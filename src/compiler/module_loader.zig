//! module_loader.zig — source-file loading. `loadfile` drives a `.m` file
//! through the pipeline (lex → parse → type-check), reusing or refreshing its
//! `.x` dump cache, and `mkincludes` resolves the `%include` directives that
//! pull one script's definitions into another.

const std = @import("std");
const word = @import("../runtime/word.zig");
const strtab = @import("../runtime/strtab.zig");
const main = @import("../main.zig");
const rt = @import("../runtime/runtime_state.zig");
const cs = @import("compiler_state.zig").cs;
inline fn getTag(x: main.Word) u8 { return heap.heap.getTag(x); }
const abi = @import("../runtime/main_clib.zig");
const parser_api = @import("../parser/parser_api.zig");
const setup = @import("setup.zig");

const Word = main.Word;
const NIL = main.NIL;

const lex_state = @import("../parser/lex_state.zig");
const r7_signals = @import("../io/signals.zig");
const core_state = @import("../runtime/core_state.zig");
const heap = @import("../runtime/heap.zig");
const ls = lex_state.ls;

// Global variables defined/exported in parser/lex.zig

// C ABI / linked symbols
const signals = r7_signals.signals;
/// POSIX `WEXITSTATUS`: the exit code from a child's wait status.
fn WEXITSTATUS(status: c_int) c_int {
    return (status >> 8) & 0xff;
}

inline fn pnVal(x: Word) Word {
    return heap.t(x);
}

/// Parses and compiles the Miranda source file at `t_val`, updating the global file
/// list and environment. Sets `loading=1` for the duration; clears it on return.
/// If the file does not exist during `initialising`, panics; otherwise prints a notice.
/// Callers that want dump-or-load semantics should call `undump()` instead.
pub fn loadfile(t_val: [*:0]const u8) void {
    var h_val: Word = NIL;
    core_state.s.loading = 1;
    core_state.s.errs = 0;
    core_state.s.errline = 0;
    rt.rs.current_script = @constCast(t_val);
    rt.rs.oldfiles = NIL;
    main.unload();

    if (!main.fileExists(t_val)) {
        if (rt.rs.initialising != 0) {
            main.fatal("panic: %s not found\n", .{.{t_val}});
        }
        if (rt.rs.verbosity != 0) {
            word.print("new file {s}\n", .{t_val});
        }
        if (rt.rs.magic) {
            main.fatal("mira -exec %s: no such file\n", .{.{t_val}});
        }
        if (rt.rs.making and rt.rs.ideep == 0) {
            word.print("mira -make {s}: no such file\n", .{t_val});
        } else {
            rt.rs.oldfiles = main.cons(main.makeFil(t_val, 0, 0, NIL), NIL);
        }
        core_state.s.loading = 0;
        return;
    }

    if (abi.openfile(@constCast(t_val)) == 0) {
        if (rt.rs.initialising != 0) {
            main.fatal("panic: cannot open %s\n", .{.{t_val}});
        }
        word.print("cannot open {s}\n", .{t_val});
        rt.rs.oldfiles = main.cons(main.makeFil(t_val, 0, 0, NIL), NIL);
        core_state.s.loading = 0;
        return;
    }

    heap.heap.files = main.cons(main.makeFil(t_val, main.fileMtime(t_val), 1, NIL), NIL);
    heap.heap.current_file = heap.h(heap.heap.files);
    heap.tp(heap.h(ls.fileq)).* = heap.heap.current_file;

    if (rt.rs.initialising != 0 and word.strcmp(t_val, @as([*:0]const u8, @ptrCast(&rt.rs.PRELUDE))) == 0) {
        setup.privlib();
    } else if (rt.rs.initialising != 0 or rt.rs.nostdenv) {
        if (word.strcmp(t_val, @as([*:0]const u8, @ptrCast(&rt.rs.STDENV))) == 0) {
            setup.stdlib();
        }
    }

    ls.c = ' ';
    ls.col = 0;
    rt.rs.s_in = @ptrFromInt(@as(usize, @intCast(heap.h(heap.h(ls.fileq)))));
    abi.adjustPrefix(@constCast(t_val));

    core_state.s.commandmode = 0;
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
    cs.FBS = NIL;

    _ = parser_api.parseCurrent() catch {};

    if (core_state.s.SYNERR == 0 and ls.exportfiles != NIL) {
        var s = ls.exportfiles;
        while (s != NIL) : (s = heap.t(s)) {
            if (heap.h(s) == word.PLUS) {
                var i = main.filDefs(heap.h(heap.heap.files));
                while (i != NIL) : (i = heap.t(i)) {
                    if (main.isvariable(heap.h(i)) and !main.isfreeid(heap.h(i))) {
                        heap.tp(rt.rs.exports).* = abi.add1(heap.h(i), heap.t(rt.rs.exports));
                    }
                }
            } else {
                var count: Word = 0;
                var i = rt.rs.includees;
                while (i != NIL) : (i = heap.t(i)) {
                    if (word.strcmp(strtab.strOf(heap.h(heap.h(heap.h(i)))), strtab.strOf(heap.h(s))) == 0) {
                        heap.hp(s).* = heap.h(heap.h(heap.h(i)));
                        count += 1;
                    }
                }
                if (count != 1) {
                    core_state.s.SYNERR = 1;
                    word.print("illegal fileid \"{s}\" in export list ({s})\n", .{strtab.strOf(heap.h(s)), @as([*:0]const u8, if (count != 0) "ambiguous" else "not %included in script")});
                }
            }
        }
        if (core_state.s.SYNERR != 0) {
            abi.sayhere(heap.h(rt.rs.exports), 1);
            word.printErr("compilation abandoned\n", .{});
        }
    }

    if (core_state.s.SYNERR == 0 and rt.rs.includees != NIL) {
        heap.heap.files = abi.append1(heap.heap.files, mkincludes(rt.rs.includees));
        rt.rs.includees = NIL;
    }
    rt.rs.ld_stuff = NIL;

    if (core_state.s.SYNERR == 0) {
        if (rt.rs.verbosity != 0 or (rt.rs.making and !rt.rs.mkexports and !rt.rs.mksources)) {
            word.print("checking types in {s}\n", .{t_val});
        }
        main.checktypes();
    }

    if (core_state.s.SYNERR == 0 and rt.rs.exports != NIL) {
        if (cs.ND != NIL) {
            rt.rs.exports = NIL;
        } else {
            var e = rt.rs.embargoes;
            var u: Word = NIL;
            var n: Word = NIL;
            var c_ctr: Word = NIL;
            h_val = heap.h(rt.rs.exports);
            rt.rs.exports = heap.t(rt.rs.exports);

            while (e != NIL) : (e = heap.t(e)) {
                if (main.idType(heap.h(e)) == word.undef_t) {
                    u = main.cons(heap.h(e), u);
                    cs.ND = abi.add1(heap.h(e), cs.ND);
                } else if (abi.member(rt.rs.exports, heap.h(e)) == 0) {
                    n = main.cons(heap.h(e), n);
                }
            }

            if (rt.rs.embargoes != NIL) {
                rt.rs.exports = abi.setdiff(rt.rs.exports, rt.rs.embargoes);
            }
            rt.rs.exports = main.alfasort(rt.rs.exports);

            e = rt.rs.exports;
            while (e != NIL) : (e = heap.t(e)) {
                if (main.idType(heap.h(e)) == word.undef_t) {
                    u = main.cons(heap.h(e), u);
                    cs.ND = abi.add1(heap.h(e), cs.ND);
                } else if (main.idType(heap.h(e)) == word.type_t and main.tClass(heap.h(e)) == word.algebraic_t) {
                    c_ctr = main.shunt(main.tInfo(heap.h(e)), c_ctr);
                }
            }

            if (rt.rs.exports == NIL) {
                word.print("warning, export list has void contents\n", .{});
            } else {
                rt.rs.exports = abi.append1(main.alfasort(c_ctr), rt.rs.exports);
            }

            if (n != NIL) {
                word.print("redundant entry in export list:", .{});
                while (n != NIL) : (n = heap.t(n)) {
                    word.print(" -{s}", .{main.get_id(heap.h(n))});
                }
                _ = word.putchar('\n');
            }

            if (u != NIL) {
                rt.rs.exports = NIL;
                abi.printlist(@constCast("undefined names in export list: "), u);
            }

            if (u != NIL) {
                abi.sayhere(h_val, 1);
                h_val = NIL;
            } else if (rt.rs.exports == NIL or n != NIL) {
                abi.outHere(main.getStderr(), h_val, 1);
                h_val = NIL;
            }
        }
    }

    if (core_state.s.SYNERR == 0 and cs.ND == NIL and (rt.rs.exports != NIL or heap.t(heap.heap.files) != NIL)) {
        var e1 = rt.rs.exports;
        var r: Word = NIL;
        var e: Word = NIL;
        if (rt.rs.exports != NIL) {
            while (e1 != NIL) : (e1 = heap.t(e1)) {
                const ty = main.idType(heap.h(e1));
                if (ty == word.type_t) {
                    if (main.tClass(heap.h(e1)) == word.synonym_t) {
                        r = abi.UNION(r, abi.deps(main.tInfo(heap.h(e1))));
                    } else {
                        e = main.cons(heap.h(e1), e);
                    }
                } else {
                    r = abi.UNION(r, abi.deps(ty));
                }
            }
        } else {
            e1 = main.filDefs(heap.h(heap.heap.files));
            while (e1 != NIL) : (e1 = heap.t(e1)) {
                const ty = main.idType(heap.h(e1));
                if (ty == word.type_t) {
                    if (main.tClass(heap.h(e1)) == word.synonym_t) {
                        r = abi.UNION(r, abi.deps(main.tInfo(heap.h(e1))));
                    } else {
                        e = main.cons(heap.h(e1), e);
                    }
                } else {
                    r = abi.UNION(r, abi.deps(ty));
                }
            }
        }

        e1 = rt.rs.freeids;
        while (e1 != NIL) : (e1 = heap.t(e1)) {
            const ty = main.idType(heap.h(heap.h(e1)));
            if (ty == word.type_t) {
                if (main.tClass(heap.h(heap.h(e1))) == word.synonym_t) {
                    r = abi.UNION(r, abi.deps(main.tInfo(heap.h(heap.h(e1)))));
                } else {
                    e = main.cons(heap.h(heap.h(e1)), e);
                }
            } else {
                r = abi.UNION(r, abi.deps(ty));
            }
        }

        while (r != NIL) : (r = heap.t(r)) {
            if (abi.member(e, heap.h(r)) == 0) {
                rt.rs.bereaved = main.cons(heap.h(r), rt.rs.bereaved);
            }
        }
    }

    if (rt.rs.exports != NIL and rt.rs.bereaved != NIL) {
        const b = abi.intersection(rt.rs.bereaved, cs.newtyps);
        if (b != NIL) {
            word.print("warning, export list is incomplete - missing typename: ", .{});
            abi.printlist(@constCast(""), b);
        }
        if (b != NIL and h_val != NIL) {
            abi.outHere(main.getStdout(), h_val, 1);
        }
    }

    if (core_state.s.SYNERR == 0 and rt.rs.detrop != NIL) {
        const gd = rt.rs.detrop;
        while (rt.rs.detrop != NIL and getTag(main.dval(heap.h(rt.rs.detrop))) == word.LABEL) {
            rt.rs.detrop = heap.t(rt.rs.detrop);
        }
        if (rt.rs.detrop != NIL) {
            word.print("warning, script contains unused local definitions:-\n", .{});
        }
        while (rt.rs.detrop != NIL) {
            abi.outHere(main.getStdout(), heap.h(heap.h(heap.t(main.dval(heap.h(rt.rs.detrop))))), 0);
            _ = word.putchar('\t');
            abi.outPattern(main.getStdout().?, main.dlhs(heap.h(rt.rs.detrop)));
            _ = word.putchar('\n');
            rt.rs.detrop = heap.t(rt.rs.detrop);
            while (rt.rs.detrop != NIL and getTag(main.dval(heap.h(rt.rs.detrop))) == word.LABEL) {
                rt.rs.detrop = heap.t(rt.rs.detrop);
            }
        }

        var gd_mut = gd;
        while (gd_mut != NIL and getTag(main.dval(heap.h(gd_mut))) != word.LABEL) {
            gd_mut = heap.t(gd_mut);
        }
        if (gd_mut != NIL) {
            word.print("warning, grammar contains unused nonterminals:-\n", .{});
        }
        while (gd_mut != NIL) {
            abi.outHere(main.getStdout(), heap.h(main.dval(heap.h(gd_mut))), 0);
            _ = word.putchar('\t');
            abi.outPattern(main.getStdout().?, main.dlhs(heap.h(gd_mut)));
            _ = word.putchar('\n');
            gd_mut = heap.t(gd_mut);
            while (gd_mut != NIL and getTag(main.dval(heap.h(gd_mut))) != word.LABEL) {
                gd_mut = heap.t(gd_mut);
            }
        }
    }

    if (core_state.s.SYNERR == 0) {
        var x = main.filDefs(heap.h(heap.heap.files));
        cs.lfrule = 0;
        while (x != NIL) : (x = heap.t(x)) {
            if (main.idType(heap.h(x)) != word.type_t) {
                cs.current_id = heap.h(x);
                cs.polyshowerror = 0;
                heap.tp(heap.h(x)).* = main.codegen(main.idVal(heap.h(x)));
                if (cs.polyshowerror != 0) {
                    heap.tp(heap.h(x)).* = word.UNDEF;
                }
            }
        }
        cs.current_id = 0;
        if (cs.lfrule != 0 and (rt.rs.verbosity != 0 or rt.rs.making)) {
            word.print("grammar optimisation: {} common left factors found\n", .{cs.lfrule});
        }
        if (rt.rs.initialising != 0 and cs.ND != NIL) {
            main.fatal("panic: %s contains errors\n", .{.{@as([*:0]const u8, if (rt.rs.okprel) "stdenv" else "prelude")}});
        }
        if (rt.rs.initialising != 0) {
            main.makedump();
        } else if (main.isMirandaSource(t_val) != 0) {
            main.fixexports();
            main.makedump();
            main.unfixexports();
        }
        if (core_state.s.errline == 0 and core_state.s.errs != 0 and word.strcmp(strtab.strOf(heap.h(core_state.s.errs)), rt.rs.current_script.?) == 0) {
            core_state.s.errline = heap.t(core_state.s.errs);
        }
        cs.ND = main.alfasort(cs.ND);
        core_state.s.loading = 0;
        return;
    }

    if (rt.rs.initialising != 0) {
        main.fatal("panic: cannot compile %s\n", .{.{@as([*:0]const u8, if (rt.rs.okprel) "stdenv" else "prelude")}});
    }
    rt.rs.oldfiles = heap.heap.files;
    main.unload();
    if (main.isMirandaSource(t_val) != 0 and core_state.s.SYNERR != 2) {
        main.makedump();
    }
    core_state.s.SYNERR = 0;
    core_state.s.loading = 0;
}

/// Resolves a list of `%include` file nodes (`includees_val`) into a heap list
/// of loaded file nodes, detecting and reporting clashes. Returns the resolved list.
pub fn mkincludes(includees_val: Word) Word {
    var includees_list = includees_val;
    var result: Word = NIL;
    var tclashes: Word = NIL;
    includees_list = main.reverse(includees_list);
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
            core_state.s.SYNERR = 2;
            word.print("compilation of \"{s}\" abandoned\n", .{rt.rs.current_script.?});
            return NIL;
        }
        while (pid != abi.wait(&status)) {}
        if (WEXITSTATUS(status) == 2) {
            if (rt.rs.ideep != 0) {
                abi.exit(2);
            } else {
                core_state.s.SYNERR = 2;
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
            main.undump(strtab.strOf(heap.h(heap.h(heap.h(includees_list)))));
            if (cs.ND != NIL or (heap.heap.files == NIL and rt.rs.oldfiles != NIL)) {
                rt.rs.make_status = 1;
            }
            includees_list = heap.t(includees_list);
        }
        abi.exit(@intCast(rt.rs.make_status));
    }

    rt.rs.sigflag = 0;
    while (includees_list != NIL) {
        var x: Word = NIL;
        var oldsig: usize = 0;
        var f: ?*word.FILE = null;
        const fn_str = strtab.strOf(heap.h(heap.h(heap.h(includees_list))));

        _ = word.strcpy(ls.dicp, fn_str);
        _ = word.strcpy(ls.dicp + word.strlen(ls.dicp) - 1, core_state.s.obsuffix);

        if (!rt.rs.making) {
            oldsig = signals(abi.SIGINT, @intFromPtr(&main.sigdefer));
        }

        f = word.fopen(ls.dicp, "r");
        if (f != null) {
            x = abi.loadScript(f.?, @constCast(fn_str), heap.h(heap.t(heap.h(includees_list))), heap.t(heap.t(heap.h(includees_list))), 0);
            _ = word.fclose(f.?);
        }

        rt.rs.ld_stuff = main.cons(x, rt.rs.ld_stuff);
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

        if (f != null and cs.BAD_DUMP == 0 and x != NIL and cs.ND == NIL and cs.CLASHES == NIL and cs.ALIASES == NIL and cs.TSUPPRESSED == NIL and cs.DETROP == NIL and cs.MISSING == NIL) {
            if (cs.TORPHANS != 0) {
                rt.rs.rfl = main.shunt(x, rt.rs.rfl);
            }
            var y = x;
            while (y != NIL) : (y = heap.t(y)) {
                const nodev = main.inodeId(main.get_fil(heap.h(y)).?);
                heap.tp(main.filInodev(heap.h(y))).* = nodev;
            }

            y = x;
            while (y != NIL) : (y = heap.t(y)) {
                if (main.filShare(heap.h(y)) != 0) {
                    var z = result;
                    while (z != NIL) : (z = heap.t(z)) {
                        if (main.filShare(heap.h(z)) != 0 and main.sameFile(heap.h(y), heap.h(z)) and main.filTime(heap.h(y)) == main.filTime(heap.h(z))) {
                            var p = main.filDefs(heap.h(y));
                            var q = main.filDefs(heap.h(z));
                            while (p != NIL and q != NIL) {
                                if (getTag(heap.h(p)) == word.ID) {
                                    if (main.idType(heap.h(p)) == word.type_t and (getTag(heap.h(q)) == word.ID or getTag(pnVal(heap.h(q))) == word.ID)) {
                                        var w = tclashes;
                                        const orig = if (getTag(heap.h(q)) == word.ID) heap.h(q) else pnVal(heap.h(q));
                                        if (main.tClass(heap.h(p)) == word.synonym_t) {
                                            p = heap.t(p);
                                            q = heap.t(q);
                                            continue;
                                        }
                                        while (w != NIL and (word.strcmp(main.get_fil(heap.h(w)).?, main.get_fil(heap.h(z)).?) != 0 or heap.h(heap.t(heap.h(w))) != orig)) {
                                            w = heap.t(w);
                                        }
                                        if (w == NIL) {
                                            tclashes = main.cons(abi.strcons(@as(Word, strtab.strBits(main.get_fil(heap.h(z)).?)), main.cons(orig, NIL)), tclashes);
                                            w = tclashes;
                                        }
                                        heap.tp(heap.t(heap.t(heap.h(w)))).* = main.cons(heap.h(p), heap.t(heap.t(heap.h(w))));
                                    } else {
                                        heap.tp(heap.h(q)).* = heap.h(p);
                                    }
                                } else {
                                    heap.tp(heap.h(p)).* = heap.h(q);
                                }
                                p = heap.t(p);
                                q = heap.t(q);
                            }
                            if (p != NIL or q != NIL) {
                                word.printErr("impossible event in mkincludes\n", .{});
                            }
                        }
                    }
                }
            }

            if (abi.member(ls.exportfiles, strtab.strBits(fn_str)) != 0) {
                y = x;
                while (y != NIL) : (y = heap.t(y)) {
                    var z = main.filDefs(heap.h(y));
                    while (z != NIL) : (z = heap.t(z)) {
                        if (main.isvariable(heap.h(z))) {
                            heap.tp(rt.rs.exports).* = abi.add1(heap.h(z), heap.t(rt.rs.exports));
                        }
                    }
                }
            }

            result = abi.append1(result, x);
            if (heap.h(cs.FBS) == NIL) {
                cs.FBS = heap.t(cs.FBS);
            } else {
                heap.hp(cs.FBS).* = main.cons(heap.t(heap.h(heap.h(includees_list))), heap.h(cs.FBS));
            }
            includees_list = heap.t(includees_list);
            continue;
        }

        if (f == null) {
            result = main.cons(main.makeFil(fn_str, main.fileMtime(fn_str), 0, NIL), result);
        } else if (x == NIL and cs.BAD_DUMP != -2) {
            result = abi.append1(result, rt.rs.oldfiles);
            rt.rs.oldfiles = NIL;
        } else {
            result = abi.append1(result, x);
        }

        core_state.s.SYNERR = 1;
        word.print("unsuccessful %include directive ", .{});
        abi.sayhere(heap.t(heap.h(heap.h(includees_list))), 1);

        if (f == null) {
            word.print("\"{s}\" cannot be loaded\n", .{fn_str});
            cs.CLASHES = NIL;
            cs.DETROP = NIL;
            cs.MISSING = NIL;
        } else if (cs.BAD_DUMP == -2) {
            abi.printlist(@constCast("aliasing causes nameclashes: "), cs.CLASHES);
            cs.CLASHES = NIL;
        } else if (cs.ALIASES != NIL or cs.TSUPPRESSED != NIL) {
            if (cs.ALIASES != NIL) {
                word.print("alias fails (name{s} not found in file", .{@as([*:0]const u8, if (heap.t(cs.ALIASES) == NIL) "" else "s")});
                abi.printlist(@constCast("): "), cs.ALIASES);
                cs.ALIASES = NIL;
            }
            if (cs.TSUPPRESSED != NIL) {
                word.print("illegal alias (cannot suppress typename{s}):", .{@as([*:0]const u8, if (heap.t(cs.TSUPPRESSED) == NIL) "" else "s")});
                var ts = cs.TSUPPRESSED;
                while (ts != NIL) : (ts = heap.t(ts)) {
                    word.print(" -{s}", .{main.get_id(heap.h(ts))});
                }
                _ = word.putchar('\n');
            }
        } else if (cs.BAD_DUMP != 0) {
            word.print("\"{s}\" has bad data in dump file\n", .{fn_str});
        } else if (x == NIL) {
            word.print("\"{s}\" contains syntax error\n", .{fn_str});
        } else if (cs.ND != NIL) {
            word.print("\"{s}\" contains undefined names or type errors\n", .{fn_str});
        }

        if (cs.ND == NIL and cs.CLASHES != NIL) {
            word.print("\"{s}\" ", .{fn_str});
            abi.printlist(@constCast("causes nameclashes: "), cs.CLASHES);
        }

        while (cs.DETROP != NIL and getTag(heap.h(cs.DETROP)) == word.CONS) {
            const fa = heap.h(heap.t(heap.h(cs.DETROP)));
            const ta = heap.t(heap.t(heap.h(cs.DETROP)));
            const pn = main.get_id(heap.h(heap.h(cs.DETROP)));
            if (fa == -1 or ta == -1) {
                word.print("`{s}' has binding of wrong kind ", .{pn});
                word.print("(should be \"= value\" not \"== type\")\n", .{});
            } else {
                word.print("`{s}' has == binding of wrong arity ", .{pn});
                word.print("(formal has arity {}, actual has arity {})\n", .{fa, ta});
            }
            cs.DETROP = heap.t(cs.DETROP);
        }

        if (cs.DETROP != NIL) {
            word.print("illegal parameter binding (name{s} not %free in file", .{@as([*:0]const u8, if (heap.t(cs.DETROP) == NIL) "" else "s")});
            abi.printlist(@constCast("): "), cs.DETROP);
            cs.DETROP = NIL;
        }

        if (cs.MISSING != NIL) {
            word.print("missing parameter binding{s}: ", .{@as([*:0]const u8, if (heap.t(cs.MISSING) == NIL) "" else "s")});
        }

        while (cs.MISSING != NIL) {
            word.printErr("{s}{s}", .{strtab.strOf(heap.h(heap.h(cs.MISSING))), @as([*:0]const u8, if (heap.t(cs.MISSING) == NIL) ";\n" else ",")});
            cs.MISSING = heap.t(cs.MISSING);
        }

        word.printErr("compilation abandoned\n", .{});
        heap.heap.stackp = heap.heap.dstack;
        includees_list = heap.t(includees_list);
        return result;
    }

    if (tclashes != NIL) {
        word.printErr("TYPECLASH - the following type{s} multiply named:\n", .{@as([*:0]const u8, if (heap.t(tclashes) == NIL) " is" else "s are")});
        while (tclashes != NIL) {
            word.printErr("\'{s}\' of file \"{s}\", as: ", .{abi.getaka(heap.h(heap.t(heap.h(tclashes)))), strtab.strOf(heap.h(heap.h(tclashes)))});
            abi.printlist(@constCast(""), main.alfasort(heap.t(heap.t(heap.h(tclashes)))));
            tclashes = heap.t(tclashes);
        }
        word.printErr("typecheck cannot proceed - compilation abandoned\n", .{});
        core_state.s.SYNERR = 1;
        return result;
    }

    return result;
}

test "module_loader constants are consistent" {
    try std.testing.expectEqual(main.NIL, NIL);
    try std.testing.expect(NIL > 0);
}
