//! module_loader.zig — source-file loading. `loadfile` drives a `.m` file
//! through the pipeline (lex → parse → type-check), reusing or refreshing its
//! `.x` dump cache, and `mkincludes` resolves the `%include` directives that
//! pull one script's definitions into another.

const std = @import("std");
const word = @import("../runtime/word.zig");
const errors = @import("../runtime/errors.zig");
const strtab = @import("../runtime/strtab.zig");
const rt = @import("../runtime/runtime_state.zig");
const compiler_state = @import("compiler_state.zig");
const cs = compiler_state.cs;
inline fn getTag(heap: *Heap, x: word.Word) word.NodeTag {
    return heap.getTag(x);
}
const abi = @import("../runtime/main_clib.zig");
const parser_api = @import("../parser/parser_api.zig");
const setup = @import("setup.zig");

const Word = word.Word;
const NIL = word.NIL;

const lex_state = @import("../parser/lex_state.zig");
const signals_mod = @import("../io/signals.zig");
const core_state = @import("../runtime/core_state.zig");
const heap_mod = @import("../runtime/heap.zig");
const Heap = heap_mod.Heap;
const types_mod = @import("types.zig");
const trans_mod = @import("trans.zig");
const files = @import("../io/files.zig");
const dump = @import("dump.zig");
const ls = lex_state.ls;

// Global variables defined/exported in parser/lex.zig

// C ABI / linked symbols
const signals = signals_mod.signals;
/// POSIX `WEXITSTATUS`: the exit code from a child's wait status.
fn WEXITSTATUS(status: c_int) c_int {
    return (status >> 8) & 0xff;
}

inline fn pnVal(x: Word) Word {
    return heap_mod.t(x);
}

/// Parses and compiles the Miranda source file at `t_val`, updating the global file
/// list and environment. Sets `loading=1` for the duration; clears it on return.
/// If the file does not exist during `initialising`, panics; otherwise prints a notice.
/// Callers that want dump-or-load semantics should call `undump()` instead.
pub fn loadfile(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState, t_val: [*:0]const u8) void {
    core.loading = 1;
    core.errs = 0;
    core.errline = 0;
    rt.rs.current_script = @constCast(t_val);
    rt.rs.oldfiles = NIL;
    heap_mod.unload(comp);

    if (!files.fileExists(t_val)) {
        if (rt.rs.initialising != 0) {
            errors.fatal("panic: %s not found\n", .{.{t_val}});
        }
        if (rt.rs.verbosity != 0) {
            word.print("new file {s}\n", .{t_val});
        }
        if (rt.rs.magic) {
            errors.fatal("mira -exec %s: no such file\n", .{.{t_val}});
        }
        if (rt.rs.making and rt.rs.ideep == 0) {
            word.print("mira -make {s}: no such file\n", .{t_val});
        } else {
            rt.rs.oldfiles = heap_mod.cons(heap_mod.makeFil(t_val, 0, 0, NIL), NIL);
        }
        core.loading = 0;
        return;
    }

    if (abi.openfile(@constCast(t_val)) == 0) {
        if (rt.rs.initialising != 0) {
            errors.fatal("panic: cannot open %s\n", .{.{t_val}});
        }
        word.print("cannot open {s}\n", .{t_val});
        rt.rs.oldfiles = heap_mod.cons(heap_mod.makeFil(t_val, 0, 0, NIL), NIL);
        core.loading = 0;
        return;
    }

    heap.files = heap_mod.cons(heap_mod.makeFil(t_val, files.fileMtime(t_val), 1, NIL), NIL);
    heap.current_file = heap_mod.h(heap.files);
    heap_mod.tp(heap_mod.h(ls.fileq)).* = heap.current_file;

    if (rt.rs.initialising != 0 and word.strcmp(t_val, @as([*:0]const u8, @ptrCast(&rt.rs.PRELUDE))) == 0) {
        setup.privlib(heap);
    } else if (rt.rs.initialising != 0 or rt.rs.nostdenv) {
        if (word.strcmp(t_val, @as([*:0]const u8, @ptrCast(&rt.rs.STDENV))) == 0) {
            setup.stdlib(heap);
        }
    }

    ls.c = ' ';
    ls.col = 0;
    rt.rs.s_in = @ptrFromInt(@as(usize, @intCast(heap_mod.h(heap_mod.h(ls.fileq)))));
    abi.adjustPrefix(@constCast(t_val));

    core.commandmode = 0;
    if (rt.rs.verbosity != 0 or rt.rs.making) {
        word.print("compiling {s}\n", .{t_val});
    }
    ls.nextpn = 0;
    rt.rs.embargoes = NIL;
    rt.rs.detrop = NIL;
    rt.rs.fnts = NIL;
    rt.rs.rfl = NIL;
    rt.rs.bereaved = NIL;
    rt.rs.ld_stuff = NIL;
    ls.exportfiles = NIL;
    rt.rs.freeids = NIL;
    rt.rs.exports = NIL;
    rt.rs.includees = NIL;
    comp.FBS = NIL;

    _ = parser_api.parseCurrent() catch {};

    resolveExportFileList(heap, core);

    if (core.SYNERR == 0 and rt.rs.includees != NIL) {
        heap.files = abi.append1(heap.files, mkincludes(heap, core, comp, rt.rs.includees));
        rt.rs.includees = NIL;
    }
    rt.rs.ld_stuff = NIL;

    if (core.SYNERR == 0) {
        if (rt.rs.verbosity != 0 or (rt.rs.making and !rt.rs.mkexports and !rt.rs.mksources)) {
            word.print("checking types in {s}\n", .{t_val});
        }
        types_mod.checktypes(heap, core, comp);
    }

    const h_val = resolveExports(heap, core, comp);

    computeBereavedNames(heap, core, comp);

    reportBereavedExports(heap, core, comp, h_val);

    reportUnusedDefinitions(heap, core);

    if (core.SYNERR == 0) {
        var x = heap_mod.filDefs(heap_mod.h(heap.files));
        comp.lfrule = 0;
        while (x != NIL) : (x = heap_mod.t(x)) {
            if (heap_mod.idType(heap_mod.h(x)) != word.type_t) {
                comp.current_id = heap_mod.h(x);
                comp.polyshowerror = 0;
                heap_mod.tp(heap_mod.h(x)).* = trans_mod.codegen(heap, heap_mod.idVal(heap_mod.h(x)));
                if (comp.polyshowerror != 0) {
                    heap_mod.tp(heap_mod.h(x)).* = word.UNDEF;
                }
            }
        }
        comp.current_id = 0;
        if (comp.lfrule != 0 and (rt.rs.verbosity != 0 or rt.rs.making)) {
            word.print("grammar optimisation: {} common left factors found\n", .{comp.lfrule});
        }
        if (rt.rs.initialising != 0 and comp.ND != NIL) {
            errors.fatal("panic: %s contains errors\n", .{.{@as([*:0]const u8, if (rt.rs.okprel) "stdenv" else "prelude")}});
        }
        if (rt.rs.initialising != 0) {
            dump.makedump(heap, core, comp);
        } else if (files.isMirandaSource(t_val) != 0) {
            if (comp.ND == NIL) {
                dump.fixexports(heap);
                dump.makedump(heap, core, comp);
                dump.unfixexports(heap);
            } else {
                var obf: [abi.pnlim]u8 = undefined;
                _ = word.strcpy(&obf, t_val);
                const len = word.strlen(&obf);
                _ = word.strcpy(obf[len - 1 ..].ptr, core.obsuffix);
                _ = abi.unlink(@as([*:0]const u8, @ptrCast(&obf)));
            }
        }
        if (core.errline == 0 and core.errs != 0 and word.strcmp(strtab.strOf(strtab.table, heap_mod.h(core.errs)), rt.rs.current_script.?) == 0) {
            core.errline = heap_mod.t(core.errs);
        }
        comp.ND = heap_mod.alfasort(comp.ND);
        core.loading = 0;
        return;
    }

    if (rt.rs.initialising != 0) {
        errors.fatal("panic: cannot compile %s\n", .{.{@as([*:0]const u8, if (rt.rs.okprel) "stdenv" else "prelude")}});
    }
    rt.rs.oldfiles = heap.files;
    heap_mod.unload(comp);
    if (files.isMirandaSource(t_val) != 0) {
        var obf: [abi.pnlim]u8 = undefined;
        _ = word.strcpy(&obf, t_val);
        const len = word.strlen(&obf);
        _ = word.strcpy(obf[len - 1 ..].ptr, core.obsuffix);
        _ = abi.unlink(@as([*:0]const u8, @ptrCast(&obf)));
    }
    core.SYNERR = 0;
    core.loading = 0;
}

/// Resolves each name in `ls.exportfiles` against `rt.rs.includees`: `+` pulls in
/// every variable defined in the current file, anything else must match exactly
/// one included fileid (ambiguous or missing matches abandon compilation).
fn resolveExportFileList(heap: *Heap, core: *core_state.CoreState) void {
    if (core.SYNERR == 0 and ls.exportfiles != NIL) {
        var s = ls.exportfiles;
        while (s != NIL) : (s = heap_mod.t(s)) {
            if (heap_mod.h(s) == word.PLUS) {
                var i = heap_mod.filDefs(heap_mod.h(heap.files));
                while (i != NIL) : (i = heap_mod.t(i)) {
                    if (heap_mod.isvariable(heap_mod.h(i)) and !heap_mod.isfreeid(heap_mod.h(i))) {
                        heap_mod.tp(rt.rs.exports).* = abi.add1(heap, heap_mod.h(i), heap_mod.t(rt.rs.exports));
                    }
                }
            } else {
                var count: Word = 0;
                var i = rt.rs.includees;
                while (i != NIL) : (i = heap_mod.t(i)) {
                    if (word.strcmp(strtab.strOf(strtab.table, heap_mod.h(heap_mod.h(heap_mod.h(i)))), strtab.strOf(strtab.table, heap_mod.h(s))) == 0) {
                        heap_mod.hp(s).* = heap_mod.h(heap_mod.h(heap_mod.h(i)));
                        count += 1;
                    }
                }
                if (count != 1) {
                    core.SYNERR = 1;
                    word.print("illegal fileid \"{s}\" in export list ({s})\n", .{ strtab.strOf(strtab.table, heap_mod.h(s)), @as([*:0]const u8, if (count != 0) "ambiguous" else "not %included in script") });
                }
            }
        }
        if (core.SYNERR != 0) {
            abi.sayhere(heap, heap_mod.h(rt.rs.exports), 1);
            word.printErr("compilation abandoned\n", .{});
        }
    }
}

/// Finalises `rt.rs.exports`: sorts constructors ahead of the rest, embargoes
/// (previously-exported-but-now-hidden names) removed, undefined/redundant
/// names reported and folded back into `cs.ND`/dropped. Returns the export-list
/// declaration node (for error-location reporting by the caller), or `NIL`.
fn resolveExports(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState) Word {
    var h_val: Word = NIL;
    if (core.SYNERR == 0 and rt.rs.exports != NIL) {
        if (comp.ND != NIL) {
            rt.rs.exports = NIL;
        } else {
            var e = rt.rs.embargoes;
            var u: Word = NIL;
            var n: Word = NIL;
            var c_ctr: Word = NIL;
            h_val = heap_mod.h(rt.rs.exports);
            rt.rs.exports = heap_mod.t(rt.rs.exports);

            while (e != NIL) : (e = heap_mod.t(e)) {
                if (heap_mod.idType(heap_mod.h(e)) == word.undef_t) {
                    u = heap_mod.cons(heap_mod.h(e), u);
                    comp.ND = abi.add1(heap, heap_mod.h(e), comp.ND);
                } else if (abi.member(heap, rt.rs.exports, heap_mod.h(e)) == 0) {
                    n = heap_mod.cons(heap_mod.h(e), n);
                }
            }

            if (rt.rs.embargoes != NIL) {
                rt.rs.exports = abi.setdiff(heap, rt.rs.exports, rt.rs.embargoes);
            }
            rt.rs.exports = heap_mod.alfasort(rt.rs.exports);

            e = rt.rs.exports;
            while (e != NIL) : (e = heap_mod.t(e)) {
                if (heap_mod.idType(heap_mod.h(e)) == word.undef_t) {
                    u = heap_mod.cons(heap_mod.h(e), u);
                    comp.ND = abi.add1(heap, heap_mod.h(e), comp.ND);
                } else if (heap_mod.idType(heap_mod.h(e)) == word.type_t and heap_mod.tClass(heap_mod.h(e)) == word.algebraic_t) {
                    c_ctr = heap_mod.shunt(heap_mod.tInfo(heap_mod.h(e)), c_ctr);
                }
            }

            if (rt.rs.exports == NIL) {
                word.print("warning, export list has void contents\n", .{});
            } else {
                rt.rs.exports = abi.append1(heap_mod.alfasort(c_ctr), rt.rs.exports);
            }

            if (n != NIL) {
                word.print("redundant entry in export list:", .{});
                while (n != NIL) : (n = heap_mod.t(n)) {
                    word.print(" -{s}", .{heap_mod.getId(heap_mod.h(n))});
                }
                _ = word.putchar('\n');
            }

            if (u != NIL) {
                rt.rs.exports = NIL;
                abi.printlist(heap, @constCast("undefined names in export list: "), u);
            }

            if (u != NIL) {
                abi.sayhere(heap, h_val, 1);
                h_val = NIL;
            } else if (rt.rs.exports == NIL or n != NIL) {
                abi.outHere(core, abi.stderr(), h_val, 1);
                h_val = NIL;
            }
        }
    }
    return h_val;
}

/// Computes `rt.rs.bereaved`: type names reachable from the export list (or,
/// with no explicit export list, from the whole file) plus from free ids, that
/// aren't themselves exported — candidates for the "incomplete export list"
/// warning.
fn computeBereavedNames(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState) void {
    if (core.SYNERR == 0 and comp.ND == NIL and (rt.rs.exports != NIL or heap_mod.t(heap.files) != NIL)) {
        var e1 = rt.rs.exports;
        var r: Word = NIL;
        var e: Word = NIL;
        if (rt.rs.exports != NIL) {
            while (e1 != NIL) : (e1 = heap_mod.t(e1)) {
                const ty = heap_mod.idType(heap_mod.h(e1));
                if (ty == word.type_t) {
                    if (heap_mod.tClass(heap_mod.h(e1)) == word.synonym_t) {
                        r = abi.UNION(heap, r, abi.deps(heap, heap_mod.tInfo(heap_mod.h(e1))));
                    } else {
                        e = heap_mod.cons(heap_mod.h(e1), e);
                    }
                } else {
                    r = abi.UNION(heap, r, abi.deps(heap, ty));
                }
            }
        } else {
            e1 = heap_mod.filDefs(heap_mod.h(heap.files));
            while (e1 != NIL) : (e1 = heap_mod.t(e1)) {
                const ty = heap_mod.idType(heap_mod.h(e1));
                if (ty == word.type_t) {
                    if (heap_mod.tClass(heap_mod.h(e1)) == word.synonym_t) {
                        r = abi.UNION(heap, r, abi.deps(heap, heap_mod.tInfo(heap_mod.h(e1))));
                    } else {
                        e = heap_mod.cons(heap_mod.h(e1), e);
                    }
                } else {
                    r = abi.UNION(heap, r, abi.deps(heap, ty));
                }
            }
        }

        e1 = rt.rs.freeids;
        while (e1 != NIL) : (e1 = heap_mod.t(e1)) {
            const ty = heap_mod.idType(heap_mod.h(heap_mod.h(e1)));
            if (ty == word.type_t) {
                if (heap_mod.tClass(heap_mod.h(heap_mod.h(e1))) == word.synonym_t) {
                    r = abi.UNION(heap, r, abi.deps(heap, heap_mod.tInfo(heap_mod.h(heap_mod.h(e1)))));
                } else {
                    e = heap_mod.cons(heap_mod.h(heap_mod.h(e1)), e);
                }
            } else {
                r = abi.UNION(heap, r, abi.deps(heap, ty));
            }
        }

        while (r != NIL) : (r = heap_mod.t(r)) {
            if (abi.member(heap, e, heap_mod.h(r)) == 0) {
                rt.rs.bereaved = heap_mod.cons(heap_mod.h(r), rt.rs.bereaved);
            }
        }
    }
}

/// If the export list is missing a bereaved typename, warns and (if `h_val`,
/// the export-list declaration node, is known) reports its source location.
fn reportBereavedExports(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState, h_val: Word) void {
    if (rt.rs.exports != NIL and rt.rs.bereaved != NIL) {
        const b = abi.intersection(heap, rt.rs.bereaved, comp.newtyps);
        if (b != NIL) {
            word.print("warning, export list is incomplete - missing typename: ", .{});
            abi.printlist(heap, @constCast(""), b);
        }
        if (b != NIL and h_val != NIL) {
            abi.outHere(core, abi.stdout(), h_val, 1);
        }
    }
}

/// Warns about unused local definitions (`rt.rs.detrop`) and unused grammar
/// nonterminals, both skipping past leading `LABEL`-tagged entries.
fn reportUnusedDefinitions(heap: *Heap, core: *core_state.CoreState) void {
    if (core.SYNERR == 0 and rt.rs.detrop != NIL) {
        const gd = rt.rs.detrop;
        while (rt.rs.detrop != NIL and getTag(heap, heap_mod.dval(heap_mod.h(rt.rs.detrop))) == .LABEL) {
            rt.rs.detrop = heap_mod.t(rt.rs.detrop);
        }
        if (rt.rs.detrop != NIL) {
            word.print("warning, script contains unused local definitions:-\n", .{});
        }
        while (rt.rs.detrop != NIL) {
            abi.outHere(core, abi.stdout(), heap_mod.h(heap_mod.h(heap_mod.t(heap_mod.dval(heap_mod.h(rt.rs.detrop))))), 0);
            _ = word.putchar('\t');
            abi.outPattern(heap, abi.stdout().?, heap_mod.dlhs(heap_mod.h(rt.rs.detrop)));
            _ = word.putchar('\n');
            rt.rs.detrop = heap_mod.t(rt.rs.detrop);
            while (rt.rs.detrop != NIL and getTag(heap, heap_mod.dval(heap_mod.h(rt.rs.detrop))) == .LABEL) {
                rt.rs.detrop = heap_mod.t(rt.rs.detrop);
            }
        }

        var gd_mut = gd;
        while (gd_mut != NIL and getTag(heap, heap_mod.dval(heap_mod.h(gd_mut))) != .LABEL) {
            gd_mut = heap_mod.t(gd_mut);
        }
        if (gd_mut != NIL) {
            word.print("warning, grammar contains unused nonterminals:-\n", .{});
        }
        while (gd_mut != NIL) {
            abi.outHere(core, abi.stdout(), heap_mod.h(heap_mod.dval(heap_mod.h(gd_mut))), 0);
            _ = word.putchar('\t');
            abi.outPattern(heap, abi.stdout().?, heap_mod.dlhs(heap_mod.h(gd_mut)));
            _ = word.putchar('\n');
            gd_mut = heap_mod.t(gd_mut);
            while (gd_mut != NIL and getTag(heap, heap_mod.dval(heap_mod.h(gd_mut))) != .LABEL) {
                gd_mut = heap_mod.t(gd_mut);
            }
        }
    }
}

/// Resolves a list of `%include` file nodes (`includees_val`) into a heap list
/// of loaded file nodes, detecting and reporting clashes. Returns the resolved list.
pub fn mkincludes(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState, includees_val: Word) Word {
    var includees_list = includees_val;
    var result: Word = NIL;
    var tclashes: Word = NIL;
    includees_list = heap_mod.reverse(includees_list);
    const pid = abi.fork();
    if (pid != 0) { // parent
        var status: c_int = 0;
        if (pid == -1) {
            abi.perror("UNIX error - cannot create process");
            if (rt.rs.ideep > 6) {
                word.printErr("error occurs {} deep in %include files\n", .{rt.rs.ideep});
            }
            if (rt.rs.ideep != 0) {
                abi.exit(2);
            }
            core.SYNERR = 2;
            word.print("compilation of \"{s}\" abandoned\n", .{rt.rs.current_script.?});
            return NIL;
        }
        while (pid != abi.wait(&status)) {}
        if (WEXITSTATUS(status) == 2) {
            if (rt.rs.ideep != 0) {
                abi.exit(2);
            } else {
                core.SYNERR = 2;
                word.print("compilation of \"{s}\" abandoned\n", .{rt.rs.current_script.?});
                return NIL;
            }
        }
    } else { // child
        _ = signals(abi.SIGINT, 0);
        rt.rs.ideep += 1;
        rt.rs.making = true;
        rt.rs.make_status = 0;
        rt.rs.echoing = 0;
        rt.rs.listing = 0;
        rt.rs.verbosity = 0;
        rt.rs.magic = false;
        _ = abi.sigsetjmp(&rt.rs.env, 1);
        while (includees_list != NIL and rt.rs.make_status == 0) {
            dump.undump(heap, core, comp, strtab.strOf(strtab.table, heap_mod.h(heap_mod.h(heap_mod.h(includees_list)))));
            if (comp.ND != NIL or (heap.files == NIL and rt.rs.oldfiles != NIL)) {
                rt.rs.make_status = 1;
            }
            includees_list = heap_mod.t(includees_list);
        }
        abi.exit(@intCast(rt.rs.make_status));
    }

    rt.rs.sigflag = 0;
    while (includees_list != NIL) {
        var x: Word = NIL;
        var oldsig: usize = 0;
        var f: ?*word.FILE = null;
        const fn_str = strtab.strOf(strtab.table, heap_mod.h(heap_mod.h(heap_mod.h(includees_list))));

        _ = word.strcpy(ls.dicp, fn_str);
        _ = word.strcpy(ls.dicp + word.strlen(ls.dicp) - 1, core.obsuffix);

        if (!rt.rs.making) {
            oldsig = signals(abi.SIGINT, @intFromPtr(&dump.sigdefer));
        }

        f = word.fopen(ls.dicp, "r");
        if (f != null) {
            x = abi.loadScript(core, comp, f.?, @constCast(fn_str), heap_mod.h(heap_mod.t(heap_mod.h(includees_list))), heap_mod.t(heap_mod.t(heap_mod.h(includees_list))), 0);
            _ = word.fclose(f.?);
        }

        rt.rs.ld_stuff = heap_mod.cons(x, rt.rs.ld_stuff);
        if (!rt.rs.making) {
            _ = signals(abi.SIGINT, oldsig);
        }

        if (rt.rs.sigflag != 0) {
            rt.rs.sigflag = 0;
            if (oldsig > 1) {
                const handler: *const fn (c_int) callconv(.c) void = @ptrFromInt(oldsig);
                handler(abi.SIGINT);
            }
        }

        if (f != null and comp.BAD_DUMP == 0 and x != NIL and comp.ND == NIL and comp.CLASHES == NIL and comp.ALIASES == NIL and comp.TSUPPRESSED == NIL and comp.DETROP == NIL and comp.MISSING == NIL) {
            if (comp.TORPHANS != 0) {
                rt.rs.rfl = heap_mod.shunt(x, rt.rs.rfl);
            }
            var y = x;
            while (y != NIL) : (y = heap_mod.t(y)) {
                const nodev = files.inodeId(heap_mod.getFil(heap_mod.h(y)).?);
                heap_mod.tp(heap_mod.filInodev(heap_mod.h(y))).* = nodev;
            }

            y = x;
            while (y != NIL) : (y = heap_mod.t(y)) {
                if (heap_mod.filShare(heap_mod.h(y)) != 0) {
                    var z = result;
                    while (z != NIL) : (z = heap_mod.t(z)) {
                        if (heap_mod.filShare(heap_mod.h(z)) != 0 and files.sameFile(heap_mod.h(y), heap_mod.h(z)) and heap_mod.filTime(heap_mod.h(y)) == heap_mod.filTime(heap_mod.h(z))) {
                            var p = heap_mod.filDefs(heap_mod.h(y));
                            var q = heap_mod.filDefs(heap_mod.h(z));
                            while (p != NIL and q != NIL) {
                                if (getTag(heap, heap_mod.h(p)) == .ID) {
                                    if (heap_mod.idType(heap_mod.h(p)) == word.type_t and (getTag(heap, heap_mod.h(q)) == .ID or getTag(heap, pnVal(heap_mod.h(q))) == .ID)) {
                                        var w = tclashes;
                                        const orig = if (getTag(heap, heap_mod.h(q)) == .ID) heap_mod.h(q) else pnVal(heap_mod.h(q));
                                        if (heap_mod.tClass(heap_mod.h(p)) == word.synonym_t) {
                                            p = heap_mod.t(p);
                                            q = heap_mod.t(q);
                                            continue;
                                        }
                                        while (w != NIL and (word.strcmp(heap_mod.getFil(heap_mod.h(w)).?, heap_mod.getFil(heap_mod.h(z)).?) != 0 or heap_mod.h(heap_mod.t(heap_mod.h(w))) != orig)) {
                                            w = heap_mod.t(w);
                                        }
                                        if (w == NIL) {
                                            tclashes = heap_mod.cons(abi.strcons(@as(Word, strtab.strBits(strtab.table, heap_mod.getFil(heap_mod.h(z)).?)), heap_mod.cons(orig, NIL)), tclashes);
                                            w = tclashes;
                                        }
                                        heap_mod.tp(heap_mod.t(heap_mod.t(heap_mod.h(w)))).* = heap_mod.cons(heap_mod.h(p), heap_mod.t(heap_mod.t(heap_mod.h(w))));
                                    } else {
                                        heap_mod.tp(heap_mod.h(q)).* = heap_mod.h(p);
                                    }
                                } else {
                                    heap_mod.tp(heap_mod.h(p)).* = heap_mod.h(q);
                                }
                                p = heap_mod.t(p);
                                q = heap_mod.t(q);
                            }
                            if (p != NIL or q != NIL) {
                                word.printErr("impossible event in mkincludes\n", .{});
                            }
                        }
                    }
                }
            }

            if (abi.member(heap, ls.exportfiles, strtab.strBits(strtab.table, fn_str)) != 0) {
                y = x;
                while (y != NIL) : (y = heap_mod.t(y)) {
                    var z = heap_mod.filDefs(heap_mod.h(y));
                    while (z != NIL) : (z = heap_mod.t(z)) {
                        if (heap_mod.isvariable(heap_mod.h(z))) {
                            heap_mod.tp(rt.rs.exports).* = abi.add1(heap, heap_mod.h(z), heap_mod.t(rt.rs.exports));
                        }
                    }
                }
            }

            result = abi.append1(result, x);
            if (heap_mod.h(comp.FBS) == NIL) {
                comp.FBS = heap_mod.t(comp.FBS);
            } else {
                heap_mod.hp(comp.FBS).* = heap_mod.cons(heap_mod.t(heap_mod.h(heap_mod.h(includees_list))), heap_mod.h(comp.FBS));
            }
            includees_list = heap_mod.t(includees_list);
            continue;
        }

        if (f == null) {
            result = heap_mod.cons(heap_mod.makeFil(fn_str, files.fileMtime(fn_str), 0, NIL), result);
        } else if (x == NIL and comp.BAD_DUMP != -2) {
            result = abi.append1(result, rt.rs.oldfiles);
            rt.rs.oldfiles = NIL;
        } else {
            result = abi.append1(result, x);
        }

        core.SYNERR = 1;
        word.print("unsuccessful %include directive ", .{});
        abi.sayhere(heap, heap_mod.t(heap_mod.h(heap_mod.h(includees_list))), 1);

        if (f == null) {
            word.print("\"{s}\" cannot be loaded\n", .{fn_str});
            comp.CLASHES = NIL;
            comp.DETROP = NIL;
            comp.MISSING = NIL;
        } else if (comp.BAD_DUMP == -2) {
            abi.printlist(heap, @constCast("aliasing causes nameclashes: "), comp.CLASHES);
            comp.CLASHES = NIL;
        } else if (comp.ALIASES != NIL or comp.TSUPPRESSED != NIL) {
            if (comp.ALIASES != NIL) {
                word.print("alias fails (name{s} not found in file", .{@as([*:0]const u8, if (heap_mod.t(comp.ALIASES) == NIL) "" else "s")});
                abi.printlist(heap, @constCast("): "), comp.ALIASES);
                comp.ALIASES = NIL;
            }
            if (comp.TSUPPRESSED != NIL) {
                word.print("illegal alias (cannot suppress typename{s}):", .{@as([*:0]const u8, if (heap_mod.t(comp.TSUPPRESSED) == NIL) "" else "s")});
                var ts = comp.TSUPPRESSED;
                while (ts != NIL) : (ts = heap_mod.t(ts)) {
                    word.print(" -{s}", .{heap_mod.getId(heap_mod.h(ts))});
                }
                _ = word.putchar('\n');
            }
        } else if (comp.BAD_DUMP != 0) {
            word.print("\"{s}\" has bad data in dump file\n", .{fn_str});
        } else if (x == NIL) {
            word.print("\"{s}\" contains syntax error\n", .{fn_str});
        } else if (comp.ND != NIL) {
            word.print("\"{s}\" contains undefined names or type errors\n", .{fn_str});
        }

        if (comp.ND == NIL and comp.CLASHES != NIL) {
            word.print("\"{s}\" ", .{fn_str});
            abi.printlist(heap, @constCast("causes nameclashes: "), comp.CLASHES);
        }

        while (comp.DETROP != NIL and getTag(heap, heap_mod.h(comp.DETROP)) == .CONS) {
            const fa = heap_mod.h(heap_mod.t(heap_mod.h(comp.DETROP)));
            const ta = heap_mod.t(heap_mod.t(heap_mod.h(comp.DETROP)));
            const pn = heap_mod.getId(heap_mod.h(heap_mod.h(comp.DETROP)));
            if (fa == -1 or ta == -1) {
                word.print("`{s}' has binding of wrong kind ", .{pn});
                word.print("(should be \"= value\" not \"== type\")\n", .{});
            } else {
                word.print("`{s}' has == binding of wrong arity ", .{pn});
                word.print("(formal has arity {}, actual has arity {})\n", .{ fa, ta });
            }
            comp.DETROP = heap_mod.t(comp.DETROP);
        }

        if (comp.DETROP != NIL) {
            word.print("illegal parameter binding (name{s} not %free in file", .{@as([*:0]const u8, if (heap_mod.t(comp.DETROP) == NIL) "" else "s")});
            abi.printlist(heap, @constCast("): "), comp.DETROP);
            comp.DETROP = NIL;
        }

        if (comp.MISSING != NIL) {
            word.print("missing parameter binding{s}: ", .{@as([*:0]const u8, if (heap_mod.t(comp.MISSING) == NIL) "" else "s")});
        }

        while (comp.MISSING != NIL) {
            word.printErr("{s}{s}", .{ strtab.strOf(strtab.table, heap_mod.h(heap_mod.h(comp.MISSING))), @as([*:0]const u8, if (heap_mod.t(comp.MISSING) == NIL) ";\n" else ",") });
            comp.MISSING = heap_mod.t(comp.MISSING);
        }

        word.printErr("compilation abandoned\n", .{});
        heap.stackp = heap.dstack;
        includees_list = heap_mod.t(includees_list);
        return result;
    }

    if (tclashes != NIL) {
        word.printErr("TYPECLASH - the following type{s} multiply named:\n", .{@as([*:0]const u8, if (heap_mod.t(tclashes) == NIL) " is" else "s are")});
        while (tclashes != NIL) {
            word.printErr("\'{s}\' of file \"{s}\", as: ", .{ abi.getaka(heap_mod.h(heap_mod.t(heap_mod.h(tclashes)))), strtab.strOf(strtab.table, heap_mod.h(heap_mod.h(tclashes))) });
            abi.printlist(heap, @constCast(""), heap_mod.alfasort(heap_mod.t(heap_mod.t(heap_mod.h(tclashes)))));
            tclashes = heap_mod.t(tclashes);
        }
        word.printErr("typecheck cannot proceed - compilation abandoned\n", .{});
        core.SYNERR = 1;
        return result;
    }

    return result;
}

test "module_loader constants are consistent" {
    try std.testing.expectEqual(word.NIL, NIL);
    try std.testing.expect(NIL > 0);
}
