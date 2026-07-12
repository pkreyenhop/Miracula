//! module_loader.zig — source-file loading. `loadfile` drives a `.m` file
//! through the pipeline (lex → parse → type-check), reusing or refreshing its
//! `.x` dump cache, and `mkincludes` resolves the `%include` directives that
//! pull one script's definitions into another.

const std = @import("std");
const word = @import("../graph/word.zig");
const errors = @import("../runtime/errors.zig");
const strtab = @import("../graph/strtab.zig");
const rt = @import("../runtime/runtime_state.zig");
const script_store = @import("../session/script_store.zig");
const config_state = @import("../session/config_state.zig");
const repl_session = @import("../session/repl_session.zig");
const make_state = @import("../session/make_state.zig");
const compiler_state = @import("compiler_state.zig");
const cs = compiler_state.cs;
inline fn getTag(heap: *Heap, x: word.Word) word.NodeTag {
    return heap.getTag(x);
}
const abi = @import("../os.zig");
const parser_api = @import("../parser/parser_api.zig");
const setup = @import("setup.zig");

const Word = word.Word;
const NIL = word.NIL;
const Value = @import("../graph/value.zig").Value;

const lex_state = @import("../parser/lex_state.zig");
const signals_mod = @import("../io/signals.zig");
const core_state = @import("../runtime/core_state.zig");
const heap_mod = @import("../graph/heap.zig");
const dump_mod = @import("../graph/dump.zig");
const depend_mod = @import("../semantics/depend.zig");
const Heap = heap_mod.Heap;
const types_mod = @import("../semantics/infer.zig");
const trans_mod = @import("../semantics/lower.zig");
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

inline fn pnVal(heap: *Heap, x: Word) Word {
    return heap_mod.t(heap, x);
}

/// Parses and compiles the Miranda source file at `t_val`, updating the global file
/// list and environment. Sets `loading=1` for the duration; clears it on return.
/// If the file does not exist during `initialising`, panics; otherwise prints a notice.
/// Callers that want dump-or-load semantics should call `undump()` instead.
///
/// Returns `error.LoadError` if the file doesn't exist or can't be opened, and
/// `error.SyntaxError` if compilation failed (`SYNERR` ended up set -- the
/// diagnostic has already been printed by whichever `setup.syntax`/`acterror`
/// call set it). The internal pipeline stages still gate on `core.SYNERR`
/// exactly as before (Phase 3 step 5, docs/ZIG_NATIVE_PLAN.md, deliberately
/// keeps that -- it's what lets codegen continue past one bad definition and
/// collect every diagnostic in one pass); only the function's own external
/// contract becomes an honest fallible one instead of an implicit
/// caller-must-remember-to-poll-`SYNERR` convention.
pub fn loadfile(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState, lexs: *lex_state.LexState, t_val: [*:0]const u8) errors.MiraError!void {
    core.loading = 1;
    core.errs = 0;
    core.errline = 0;
    script_store.store().current_script = @constCast(t_val);
    script_store.store().oldfiles = NIL;
    dump_mod.unload(heap, comp, rs, lexs);

    if (!files.fileExists(t_val)) {
        if (rs.initialising != 0) {
            errors.fatal("panic: {s} not found\n", .{t_val});
        }
        if (repl_session.session().verbosity != 0) {
            word.print("new file {s}\n", .{t_val});
        }
        if (rs.magic) {
            errors.fatal("mira -exec {s}: no such file\n", .{t_val});
        }
        if (make_state.make().making and rs.ideep == 0) {
            word.print("mira -make {s}: no such file\n", .{t_val});
        } else {
            script_store.store().oldfiles = heap_mod.cons(heap, heap_mod.makeFil(t_val, 0, 0, NIL), NIL);
        }
        core.loading = 0;
        return error.LoadError;
    }

    if (abi.openfile(heap, @constCast(t_val)) == 0) {
        if (rs.initialising != 0) {
            errors.fatal("panic: cannot open {s}\n", .{t_val});
        }
        word.print("cannot open {s}\n", .{t_val});
        script_store.store().oldfiles = heap_mod.cons(heap, heap_mod.makeFil(t_val, 0, 0, NIL), NIL);
        core.loading = 0;
        return error.LoadError;
    }

    heap.files = heap_mod.cons(heap, heap_mod.makeFil(t_val, files.fileMtime(t_val), 1, NIL), NIL);
    heap.current_file = heap_mod.h(heap, heap.files);
    heap_mod.tp(heap, heap_mod.h(heap, lexs.fileq)).* = heap.current_file;

    if (rs.initialising != 0 and std.mem.eql(u8, std.mem.span(t_val), std.mem.span(@as([*:0]const u8, @ptrCast(&config_state.config().PRELUDE))))) {
        setup.privlib(heap);
    } else if (rs.initialising != 0 or config_state.config().nostdenv) {
        if (std.mem.eql(u8, std.mem.span(t_val), std.mem.span(@as([*:0]const u8, @ptrCast(&config_state.config().STDENV))))) {
            setup.stdlib(heap);
        }
    }

    lexs.c = ' ';
    lexs.col = 0;
    config_state.config().s_in = @ptrFromInt(@as(usize, @intCast(heap_mod.h(heap, heap_mod.h(heap, lexs.fileq)))));
    abi.adjustPrefix(@constCast(t_val));

    core.commandmode = 0;
    if (repl_session.session().verbosity != 0 or make_state.make().making) {
        word.print("compiling {s}\n", .{t_val});
    }
    lexs.nextpn = 0;
    script_store.store().embargoes = NIL;
    script_store.store().detrop = NIL;
    script_store.store().fnts = NIL;
    script_store.store().rfl = NIL;
    script_store.store().bereaved = NIL;
    script_store.store().ld_stuff = NIL;
    lexs.exportfiles = NIL;
    script_store.store().freeids = NIL;
    script_store.store().exports = NIL;
    script_store.store().includees = NIL;
    comp.FBS = NIL;

    _ = parser_api.parseCurrent(heap) catch {};

    resolveExportFileList(heap, core, rs, lexs);

    if (core.SYNERR == 0 and script_store.store().includees != NIL) {
        heap.files = abi.append1(heap.files, mkincludes(heap, core, comp, rs, lexs, script_store.store().includees));
        script_store.store().includees = NIL;
    }
    script_store.store().ld_stuff = NIL;

    if (core.SYNERR == 0) {
        if (repl_session.session().verbosity != 0 or (make_state.make().making and !make_state.make().mkexports and !make_state.make().mksources)) {
            word.print("checking types in {s}\n", .{t_val});
        }
        types_mod.checktypes(heap, core, comp, rs);
    }

    const h_val = resolveExports(heap, core, comp, rs);

    computeBereavedNames(heap, core, comp, rs);

    reportBereavedExports(heap, core, comp, rs, h_val);

    reportUnusedDefinitions(heap, core, rs);

    if (core.SYNERR == 0) {
        var x = heap_mod.filDefs(heap_mod.h(heap, heap.files));
        comp.lfrule = 0;
        while (x != NIL) : (x = heap_mod.t(heap, x)) {
            if (heap_mod.idType(heap_mod.h(heap, x)) != word.type_t) {
                comp.current_id = heap_mod.h(heap, x);
                comp.polyshowerror = 0;
                heap_mod.tp(heap, heap_mod.h(heap, x)).* = trans_mod.codegen(heap, heap_mod.idVal(heap_mod.h(heap, x)));
                if (comp.polyshowerror != 0) {
                    heap_mod.tp(heap, heap_mod.h(heap, x)).* = word.UNDEF;
                }
            }
        }
        comp.current_id = 0;
        if (comp.lfrule != 0 and (repl_session.session().verbosity != 0 or make_state.make().making)) {
            word.print("grammar optimisation: {} common left factors found\n", .{comp.lfrule});
        }
        if (rs.initialising != 0 and comp.ND != NIL) {
            errors.fatal("panic: {s} contains errors\n", .{if (config_state.config().okprel) "stdenv" else "prelude"});
        }
        if (rs.initialising != 0) {
            dump.makedump(heap, core, comp, rs);
        } else if (files.isMirandaSource(t_val) != 0) {
            if (comp.ND == NIL) {
                dump.fixexports(heap, comp, rs, lexs);
                dump.makedump(heap, core, comp, rs);
                dump.unfixexports(heap, comp, rs, lexs);
            } else {
                var obf: [abi.pnlim]u8 = undefined;
                {
                    const t_val_span = std.mem.span(t_val);
                    @memcpy(obf[0..t_val_span.len], t_val_span);
                    obf[t_val_span.len] = 0;
                    const suffix_span = std.mem.span(core.obsuffix);
                    const base = t_val_span.len - 1;
                    @memcpy(obf[base..][0..suffix_span.len], suffix_span);
                    obf[base + suffix_span.len] = 0;
                }
                _ = abi.unlink(@as([*:0]const u8, @ptrCast(&obf)));
            }
        }
        if (core.errline == 0 and core.errs != 0 and std.mem.eql(u8, std.mem.span(strtab.strOf(strtab.table(), heap_mod.h(heap, core.errs))), std.mem.span(script_store.store().current_script.?))) {
            core.errline = heap_mod.t(heap, core.errs);
        }
        comp.ND = depend_mod.alfasort(heap, comp.ND);
        core.loading = 0;
        return;
    }

    if (rs.initialising != 0) {
        errors.fatal("panic: cannot compile {s}\n", .{if (config_state.config().okprel) "stdenv" else "prelude"});
    }
    script_store.store().oldfiles = heap.files;
    dump_mod.unload(heap, comp, rs, lexs);
    if (files.isMirandaSource(t_val) != 0) {
        var obf: [abi.pnlim]u8 = undefined;
        {
            const t_val_span = std.mem.span(t_val);
            @memcpy(obf[0..t_val_span.len], t_val_span);
            obf[t_val_span.len] = 0;
            const suffix_span = std.mem.span(core.obsuffix);
            const base = t_val_span.len - 1;
            @memcpy(obf[base..][0..suffix_span.len], suffix_span);
            obf[base + suffix_span.len] = 0;
        }
        _ = abi.unlink(@as([*:0]const u8, @ptrCast(&obf)));
    }
    core.SYNERR = 0;
    core.loading = 0;
    return error.SyntaxError;
}

/// Resolves each name in `lexs.exportfiles` against `script_store.store().includees`: `+` pulls in
/// every variable defined in the current file, anything else must match exactly
/// one included fileid (ambiguous or missing matches abandon compilation).
fn resolveExportFileList(heap: *Heap, core: *core_state.CoreState, rs: *rt.RuntimeState, lexs: *lex_state.LexState) void {
    _ = rs;
    if (core.SYNERR == 0 and lexs.exportfiles != NIL) {
        var s = lexs.exportfiles;
        while (s != NIL) : (s = heap_mod.t(heap, s)) {
            if (heap_mod.h(heap, s) == word.PLUS) {
                var i = heap_mod.filDefs(heap_mod.h(heap, heap.files));
                while (i != NIL) : (i = heap_mod.t(heap, i)) {
                    if (heap_mod.isvariable(heap_mod.h(heap, i)) and !heap_mod.isfreeid(heap_mod.h(heap, i))) {
                        heap_mod.tp(heap, script_store.store().exports).* = abi.add1(heap, heap_mod.h(heap, i), heap_mod.t(heap, script_store.store().exports));
                    }
                }
            } else {
                var count: Word = 0;
                var i = script_store.store().includees;
                while (i != NIL) : (i = heap_mod.t(heap, i)) {
                    if (std.mem.eql(u8, std.mem.span(strtab.strOf(strtab.table(), heap_mod.h(heap, heap_mod.h(heap, heap_mod.h(heap, i))))), std.mem.span(strtab.strOf(strtab.table(), heap_mod.h(heap, s))))) {
                        heap_mod.hp(heap, s).* = heap_mod.h(heap, heap_mod.h(heap, heap_mod.h(heap, i)));
                        count += 1;
                    }
                }
                if (count != 1) {
                    core.SYNERR = 1;
                    word.print("illegal fileid \"{s}\" in export list ({s})\n", .{ strtab.strOf(strtab.table(), heap_mod.h(heap, s)), @as([*:0]const u8, if (count != 0) "ambiguous" else "not %included in script") });
                }
            }
        }
        if (core.SYNERR != 0) {
            abi.sayhere(heap, heap_mod.h(heap, script_store.store().exports), 1);
            word.printErr("compilation abandoned\n", .{});
        }
    }
}

/// Finalises `script_store.store().exports`: sorts constructors ahead of the rest, embargoes
/// (previously-exported-but-now-hidden names) removed, undefined/redundant
/// names reported and folded back into `cs.ND`/dropped. Returns the export-list
/// declaration node (for error-location reporting by the caller), or `NIL`.
fn resolveExports(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState) Word {
    _ = rs;
    var h_val: Word = NIL;
    if (core.SYNERR == 0 and script_store.store().exports != NIL) {
        if (comp.ND != NIL) {
            script_store.store().exports = NIL;
        } else {
            var e = script_store.store().embargoes;
            var u: Word = NIL;
            var n: Word = NIL;
            var c_ctr: Word = NIL;
            h_val = heap_mod.h(heap, script_store.store().exports);
            script_store.store().exports = heap_mod.t(heap, script_store.store().exports);

            while (e != NIL) : (e = heap_mod.t(heap, e)) {
                if (heap_mod.idType(heap_mod.h(heap, e)) == word.undef_t) {
                    u = heap_mod.cons(heap, heap_mod.h(heap, e), u);
                    comp.ND = abi.add1(heap, heap_mod.h(heap, e), comp.ND);
                } else if (abi.member(heap, script_store.store().exports, heap_mod.h(heap, e)) == 0) {
                    n = heap_mod.cons(heap, heap_mod.h(heap, e), n);
                }
            }

            if (script_store.store().embargoes != NIL) {
                script_store.store().exports = abi.setdiff(heap, script_store.store().exports, script_store.store().embargoes);
            }
            script_store.store().exports = depend_mod.alfasort(heap, script_store.store().exports);

            e = script_store.store().exports;
            while (e != NIL) : (e = heap_mod.t(heap, e)) {
                if (heap_mod.idType(heap_mod.h(heap, e)) == word.undef_t) {
                    u = heap_mod.cons(heap, heap_mod.h(heap, e), u);
                    comp.ND = abi.add1(heap, heap_mod.h(heap, e), comp.ND);
                } else if (heap_mod.idType(heap_mod.h(heap, e)) == word.type_t and heap_mod.tClass(heap_mod.h(heap, e)) == word.algebraic_t) {
                    c_ctr = heap_mod.shunt(heap_mod.tInfo(heap_mod.h(heap, e)), c_ctr);
                }
            }

            if (script_store.store().exports == NIL) {
                word.print("warning, export list has void contents\n", .{});
            } else {
                script_store.store().exports = abi.append1(depend_mod.alfasort(heap, c_ctr), script_store.store().exports);
            }

            if (n != NIL) {
                word.print("redundant entry in export list:", .{});
                while (n != NIL) : (n = heap_mod.t(heap, n)) {
                    word.print(" -{s}", .{heap_mod.getId(heap_mod.h(heap, n))});
                }
                _ = word.putchar('\n');
            }

            if (u != NIL) {
                script_store.store().exports = NIL;
                abi.printlist(heap, @constCast("undefined names in export list: "), u);
            }

            if (u != NIL) {
                abi.sayhere(heap, h_val, 1);
                h_val = NIL;
            } else if (script_store.store().exports == NIL or n != NIL) {
                abi.outHere(heap, core, abi.stderr(), Value.fromRaw(h_val), 1);
                h_val = NIL;
            }
        }
    }
    return h_val;
}

/// Computes `script_store.store().bereaved`: type names reachable from the export list (or,
/// with no explicit export list, from the whole file) plus from free ids, that
/// aren't themselves exported — candidates for the "incomplete export list"
/// warning.
fn computeBereavedNames(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState) void {
    _ = rs;
    if (core.SYNERR == 0 and comp.ND == NIL and (script_store.store().exports != NIL or heap_mod.t(heap, heap.files) != NIL)) {
        var e1 = script_store.store().exports;
        var r: Word = NIL;
        var e: Word = NIL;
        if (script_store.store().exports != NIL) {
            while (e1 != NIL) : (e1 = heap_mod.t(heap, e1)) {
                const ty = heap_mod.idType(heap_mod.h(heap, e1));
                if (ty == word.type_t) {
                    if (heap_mod.tClass(heap_mod.h(heap, e1)) == word.synonym_t) {
                        r = abi.UNION(heap, r, abi.deps(heap, heap_mod.tInfo(heap_mod.h(heap, e1))));
                    } else {
                        e = heap_mod.cons(heap, heap_mod.h(heap, e1), e);
                    }
                } else {
                    r = abi.UNION(heap, r, abi.deps(heap, ty));
                }
            }
        } else {
            e1 = heap_mod.filDefs(heap_mod.h(heap, heap.files));
            while (e1 != NIL) : (e1 = heap_mod.t(heap, e1)) {
                const ty = heap_mod.idType(heap_mod.h(heap, e1));
                if (ty == word.type_t) {
                    if (heap_mod.tClass(heap_mod.h(heap, e1)) == word.synonym_t) {
                        r = abi.UNION(heap, r, abi.deps(heap, heap_mod.tInfo(heap_mod.h(heap, e1))));
                    } else {
                        e = heap_mod.cons(heap, heap_mod.h(heap, e1), e);
                    }
                } else {
                    r = abi.UNION(heap, r, abi.deps(heap, ty));
                }
            }
        }

        e1 = script_store.store().freeids;
        while (e1 != NIL) : (e1 = heap_mod.t(heap, e1)) {
            const ty = heap_mod.idType(heap_mod.h(heap, heap_mod.h(heap, e1)));
            if (ty == word.type_t) {
                if (heap_mod.tClass(heap_mod.h(heap, heap_mod.h(heap, e1))) == word.synonym_t) {
                    r = abi.UNION(heap, r, abi.deps(heap, heap_mod.tInfo(heap_mod.h(heap, heap_mod.h(heap, e1)))));
                } else {
                    e = heap_mod.cons(heap, heap_mod.h(heap, heap_mod.h(heap, e1)), e);
                }
            } else {
                r = abi.UNION(heap, r, abi.deps(heap, ty));
            }
        }

        while (r != NIL) : (r = heap_mod.t(heap, r)) {
            if (abi.member(heap, e, heap_mod.h(heap, r)) == 0) {
                script_store.store().bereaved = heap_mod.cons(heap, heap_mod.h(heap, r), script_store.store().bereaved);
            }
        }
    }
}

/// If the export list is missing a bereaved typename, warns and (if `h_val`,
/// the export-list declaration node, is known) reports its source location.
fn reportBereavedExports(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState, h_val: Word) void {
    _ = rs;
    if (script_store.store().exports != NIL and script_store.store().bereaved != NIL) {
        const b = abi.intersection(heap, script_store.store().bereaved, comp.newtyps);
        if (b != NIL) {
            word.print("warning, export list is incomplete - missing typename: ", .{});
            abi.printlist(heap, @constCast(""), b);
        }
        if (b != NIL and h_val != NIL) {
            abi.outHere(heap, core, abi.stdout(), Value.fromRaw(h_val), 1);
        }
    }
}

/// Warns about unused local definitions (`script_store.store().detrop`) and unused grammar
/// nonterminals, both skipping past leading `LABEL`-tagged entries.
fn reportUnusedDefinitions(heap: *Heap, core: *core_state.CoreState, rs: *rt.RuntimeState) void {
    _ = rs;
    if (core.SYNERR == 0 and script_store.store().detrop != NIL) {
        const gd = script_store.store().detrop;
        while (script_store.store().detrop != NIL and getTag(heap, heap_mod.dval(heap_mod.h(heap, script_store.store().detrop))) == .LABEL) {
            script_store.store().detrop = heap_mod.t(heap, script_store.store().detrop);
        }
        if (script_store.store().detrop != NIL) {
            word.print("warning, script contains unused local definitions:-\n", .{});
        }
        while (script_store.store().detrop != NIL) {
            abi.outHere(heap, core, abi.stdout(), Value.fromRaw(heap_mod.h(heap, heap_mod.h(heap, heap_mod.t(heap, heap_mod.dval(heap_mod.h(heap, script_store.store().detrop)))))), 0);
            _ = word.putchar('\t');
            abi.outPattern(heap, abi.stdout().?, heap_mod.dlhs(heap_mod.h(heap, script_store.store().detrop)));
            _ = word.putchar('\n');
            script_store.store().detrop = heap_mod.t(heap, script_store.store().detrop);
            while (script_store.store().detrop != NIL and getTag(heap, heap_mod.dval(heap_mod.h(heap, script_store.store().detrop))) == .LABEL) {
                script_store.store().detrop = heap_mod.t(heap, script_store.store().detrop);
            }
        }

        var gd_mut = gd;
        while (gd_mut != NIL and getTag(heap, heap_mod.dval(heap_mod.h(heap, gd_mut))) != .LABEL) {
            gd_mut = heap_mod.t(heap, gd_mut);
        }
        if (gd_mut != NIL) {
            word.print("warning, grammar contains unused nonterminals:-\n", .{});
        }
        while (gd_mut != NIL) {
            abi.outHere(heap, core, abi.stdout(), Value.fromRaw(heap_mod.h(heap, heap_mod.dval(heap_mod.h(heap, gd_mut)))), 0);
            _ = word.putchar('\t');
            abi.outPattern(heap, abi.stdout().?, heap_mod.dlhs(heap_mod.h(heap, gd_mut)));
            _ = word.putchar('\n');
            gd_mut = heap_mod.t(heap, gd_mut);
            while (gd_mut != NIL and getTag(heap, heap_mod.dval(heap_mod.h(heap, gd_mut))) != .LABEL) {
                gd_mut = heap_mod.t(heap, gd_mut);
            }
        }
    }
}

/// Resolves a list of `%include` file nodes (`includees_val`) into a heap list
/// of loaded file nodes, detecting and reporting clashes. Returns the resolved list.
pub fn mkincludes(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState, lexs: *lex_state.LexState, includees_val: Word) Word {
    var includees_list = includees_val;
    var result: Word = NIL;
    var tclashes: Word = NIL;
    includees_list = heap_mod.reverse(includees_list);
    const pid = abi.fork();
    if (pid != 0) { // parent
        var status: c_int = 0;
        if (pid == -1) {
            abi.perror("UNIX error - cannot create process");
            if (rs.ideep > 6) {
                word.printErr("error occurs {} deep in %include files\n", .{rs.ideep});
            }
            if (rs.ideep != 0) {
                abi.exit(2);
            }
            core.SYNERR = 2;
            word.print("compilation of \"{s}\" abandoned\n", .{script_store.store().current_script.?});
            return NIL;
        }
        while (pid != abi.wait(&status)) {}
        if (WEXITSTATUS(status) == 2) {
            if (rs.ideep != 0) {
                abi.exit(2);
            } else {
                core.SYNERR = 2;
                word.print("compilation of \"{s}\" abandoned\n", .{script_store.store().current_script.?});
                return NIL;
            }
        }
    } else { // child
        _ = signals(abi.SIGINT, 0);
        rs.ideep += 1;
        make_state.make().making = true;
        make_state.make().make_status = 0;
        repl_session.session().echoing = 0;
        repl_session.session().listing = 0;
        repl_session.session().verbosity = 0;
        rs.magic = false;
        while (includees_list != NIL and make_state.make().make_status == 0) {
            dump.undump(heap, core, comp, rs, strtab.strOf(strtab.table(), heap_mod.h(heap, heap_mod.h(heap, heap_mod.h(heap, includees_list)))));
            if (comp.ND != NIL or (heap.files == NIL and script_store.store().oldfiles != NIL)) {
                make_state.make().make_status = 1;
            }
            includees_list = heap_mod.t(heap, includees_list);
        }
        abi.exit(@intCast(make_state.make().make_status));
    }

    while (includees_list != NIL) {
        var x: Word = NIL;
        var f: ?*word.Stream = null;
        const fn_str = strtab.strOf(strtab.table(), heap_mod.h(heap, heap_mod.h(heap, heap_mod.h(heap, includees_list))));

        {
            const fn_span = std.mem.span(fn_str);
            @memcpy(lexs.dicp[0..fn_span.len], fn_span);
            lexs.dicp[fn_span.len] = 0;
            const suffix_span = std.mem.span(core.obsuffix);
            const base = fn_span.len - 1;
            @memcpy(lexs.dicp[base..][0..suffix_span.len], suffix_span);
            lexs.dicp[base + suffix_span.len] = 0;
        }

        f = word.fopen(lexs.dicp, "r");
        if (f != null) {
            x = abi.loadScript(heap, core, comp, rs, lexs, f.?, @constCast(fn_str), heap_mod.h(heap, heap_mod.t(heap, heap_mod.h(heap, includees_list))), heap_mod.t(heap, heap_mod.t(heap, heap_mod.h(heap, includees_list))), 0);
            _ = word.fclose(f.?);
        }

        script_store.store().ld_stuff = heap_mod.cons(heap, x, script_store.store().ld_stuff);

        if (f != null and comp.BAD_DUMP == 0 and x != NIL and comp.ND == NIL and comp.CLASHES == NIL and comp.ALIASES == NIL and comp.TSUPPRESSED == NIL and comp.DETROP == NIL and comp.MISSING == NIL) {
            if (comp.TORPHANS != 0) {
                script_store.store().rfl = heap_mod.shunt(x, script_store.store().rfl);
            }
            var y = x;
            while (y != NIL) : (y = heap_mod.t(heap, y)) {
                const nodev = files.inodeId(heap, heap_mod.getFil(heap_mod.h(heap, y)).?);
                heap_mod.tp(heap, heap_mod.filInodev(heap_mod.h(heap, y))).* = nodev;
            }

            y = x;
            while (y != NIL) : (y = heap_mod.t(heap, y)) {
                if (heap_mod.filShare(heap_mod.h(heap, y)) != 0) {
                    var z = result;
                    while (z != NIL) : (z = heap_mod.t(heap, z)) {
                        if (heap_mod.filShare(heap_mod.h(heap, z)) != 0 and files.sameFile(heap, heap_mod.h(heap, y), heap_mod.h(heap, z)) and heap_mod.filTime(heap_mod.h(heap, y)) == heap_mod.filTime(heap_mod.h(heap, z))) {
                            var p = heap_mod.filDefs(heap_mod.h(heap, y));
                            var q = heap_mod.filDefs(heap_mod.h(heap, z));
                            while (p != NIL and q != NIL) {
                                if (getTag(heap, heap_mod.h(heap, p)) == .ID) {
                                    if (heap_mod.idType(heap_mod.h(heap, p)) == word.type_t and (getTag(heap, heap_mod.h(heap, q)) == .ID or getTag(heap, pnVal(heap, heap_mod.h(heap, q))) == .ID)) {
                                        var w = tclashes;
                                        const orig = if (getTag(heap, heap_mod.h(heap, q)) == .ID) heap_mod.h(heap, q) else pnVal(heap, heap_mod.h(heap, q));
                                        if (heap_mod.tClass(heap_mod.h(heap, p)) == word.synonym_t) {
                                            p = heap_mod.t(heap, p);
                                            q = heap_mod.t(heap, q);
                                            continue;
                                        }
                                        while (w != NIL and (!std.mem.eql(u8, std.mem.span(heap_mod.getFil(heap_mod.h(heap, w)).?), std.mem.span(heap_mod.getFil(heap_mod.h(heap, z)).?)) or heap_mod.h(heap, heap_mod.t(heap, heap_mod.h(heap, w))) != orig)) {
                                            w = heap_mod.t(heap, w);
                                        }
                                        if (w == NIL) {
                                            tclashes = heap_mod.cons(heap, abi.strcons(heap, @as(Word, strtab.strBits(strtab.table(), heap_mod.getFil(heap_mod.h(heap, z)).?)), heap_mod.cons(heap, orig, NIL)), tclashes);
                                            w = tclashes;
                                        }
                                        heap_mod.tp(heap, heap_mod.t(heap, heap_mod.t(heap, heap_mod.h(heap, w)))).* = heap_mod.cons(heap, heap_mod.h(heap, p), heap_mod.t(heap, heap_mod.t(heap, heap_mod.h(heap, w))));
                                    } else {
                                        heap_mod.tp(heap, heap_mod.h(heap, q)).* = heap_mod.h(heap, p);
                                    }
                                } else {
                                    heap_mod.tp(heap, heap_mod.h(heap, p)).* = heap_mod.h(heap, q);
                                }
                                p = heap_mod.t(heap, p);
                                q = heap_mod.t(heap, q);
                            }
                            if (p != NIL or q != NIL) {
                                word.printErr("impossible event in mkincludes\n", .{});
                            }
                        }
                    }
                }
            }

            if (abi.member(heap, lexs.exportfiles, strtab.strBits(strtab.table(), fn_str)) != 0) {
                y = x;
                while (y != NIL) : (y = heap_mod.t(heap, y)) {
                    var z = heap_mod.filDefs(heap_mod.h(heap, y));
                    while (z != NIL) : (z = heap_mod.t(heap, z)) {
                        if (heap_mod.isvariable(heap_mod.h(heap, z))) {
                            heap_mod.tp(heap, script_store.store().exports).* = abi.add1(heap, heap_mod.h(heap, z), heap_mod.t(heap, script_store.store().exports));
                        }
                    }
                }
            }

            result = abi.append1(result, x);
            if (heap_mod.h(heap, comp.FBS) == NIL) {
                comp.FBS = heap_mod.t(heap, comp.FBS);
            } else {
                heap_mod.hp(heap, comp.FBS).* = heap_mod.cons(heap, heap_mod.t(heap, heap_mod.h(heap, heap_mod.h(heap, includees_list))), heap_mod.h(heap, comp.FBS));
            }
            includees_list = heap_mod.t(heap, includees_list);
            continue;
        }

        if (f == null) {
            result = heap_mod.cons(heap, heap_mod.makeFil(fn_str, files.fileMtime(fn_str), 0, NIL), result);
        } else if (x == NIL and comp.BAD_DUMP != -2) {
            result = abi.append1(result, script_store.store().oldfiles);
            script_store.store().oldfiles = NIL;
        } else {
            result = abi.append1(result, x);
        }

        core.SYNERR = 1;
        word.print("unsuccessful %include directive ", .{});
        abi.sayhere(heap, heap_mod.t(heap, heap_mod.h(heap, heap_mod.h(heap, includees_list))), 1);

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
                word.print("alias fails (name{s} not found in file", .{@as([*:0]const u8, if (heap_mod.t(heap, comp.ALIASES) == NIL) "" else "s")});
                abi.printlist(heap, @constCast("): "), comp.ALIASES);
                comp.ALIASES = NIL;
            }
            if (comp.TSUPPRESSED != NIL) {
                word.print("illegal alias (cannot suppress typename{s}):", .{@as([*:0]const u8, if (heap_mod.t(heap, comp.TSUPPRESSED) == NIL) "" else "s")});
                var ts = comp.TSUPPRESSED;
                while (ts != NIL) : (ts = heap_mod.t(heap, ts)) {
                    word.print(" -{s}", .{heap_mod.getId(heap_mod.h(heap, ts))});
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

        while (comp.DETROP != NIL and getTag(heap, heap_mod.h(heap, comp.DETROP)) == .CONS) {
            const fa = heap_mod.h(heap, heap_mod.t(heap, heap_mod.h(heap, comp.DETROP)));
            const ta = heap_mod.t(heap, heap_mod.t(heap, heap_mod.h(heap, comp.DETROP)));
            const pn = heap_mod.getId(heap_mod.h(heap, heap_mod.h(heap, comp.DETROP)));
            if (fa == -1 or ta == -1) {
                word.print("`{s}' has binding of wrong kind ", .{pn});
                word.print("(should be \"= value\" not \"== type\")\n", .{});
            } else {
                word.print("`{s}' has == binding of wrong arity ", .{pn});
                word.print("(formal has arity {}, actual has arity {})\n", .{ fa, ta });
            }
            comp.DETROP = heap_mod.t(heap, comp.DETROP);
        }

        if (comp.DETROP != NIL) {
            word.print("illegal parameter binding (name{s} not %free in file", .{@as([*:0]const u8, if (heap_mod.t(heap, comp.DETROP) == NIL) "" else "s")});
            abi.printlist(heap, @constCast("): "), comp.DETROP);
            comp.DETROP = NIL;
        }

        if (comp.MISSING != NIL) {
            word.print("missing parameter binding{s}: ", .{@as([*:0]const u8, if (heap_mod.t(heap, comp.MISSING) == NIL) "" else "s")});
        }

        while (comp.MISSING != NIL) {
            word.printErr("{s}{s}", .{ strtab.strOf(strtab.table(), heap_mod.h(heap, heap_mod.h(heap, comp.MISSING))), @as([*:0]const u8, if (heap_mod.t(heap, comp.MISSING) == NIL) ";\n" else ",") });
            comp.MISSING = heap_mod.t(heap, comp.MISSING);
        }

        word.printErr("compilation abandoned\n", .{});
        heap.stackp = heap.dstack;
        includees_list = heap_mod.t(heap, includees_list);
        return result;
    }

    if (tclashes != NIL) {
        word.printErr("TYPECLASH - the following type{s} multiply named:\n", .{@as([*:0]const u8, if (heap_mod.t(heap, tclashes) == NIL) " is" else "s are")});
        while (tclashes != NIL) {
            word.printErr("\'{s}\' of file \"{s}\", as: ", .{ abi.getaka(heap_mod.h(heap, heap_mod.t(heap, heap_mod.h(heap, tclashes)))), strtab.strOf(strtab.table(), heap_mod.h(heap, heap_mod.h(heap, tclashes))) });
            abi.printlist(heap, @constCast(""), depend_mod.alfasort(heap, heap_mod.t(heap, heap_mod.t(heap, heap_mod.h(heap, tclashes)))));
            tclashes = heap_mod.t(heap, tclashes);
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
