const std = @import("std");
const word = @import("../runtime/word.zig");
const main = @import("../main.zig");
inline fn getTag(x: main.Word) u8 { return main.heap.heap.getTag(x); }
const abi = @import("../runtime/main_clib.zig");
const parser_api = @import("../parser/parser_api.zig");
const setup = @import("setup.zig");

const Word = main.Word;
const NIL = main.NIL;

const lex_state = @import("../parser/lex_state.zig");
const ls = &lex_state.ls;

// Global variables defined/exported in parser/lex.zig

// C ABI / linked symbols
extern fn signals(signum: c_int, handler: usize) usize;

fn WEXITSTATUS(status: c_int) c_int {
    return (status >> 8) & 0xff;
}

inline fn pn_val(x: Word) Word {
    return main.heap.t(x);
}

/// Parses and compiles the Miranda source file at `t_val`, updating the global file
/// list and environment. Sets `loading=1` for the duration; clears it on return.
/// If the file does not exist during `initialising`, panics; otherwise prints a notice.
/// Callers that want dump-or-load semantics should call `undump()` instead.
pub fn loadfile(t_val: [*:0]const u8) void {
    var h_val: Word = NIL;
    main.loading = 1;
    main.errs = 0;
    main.errline = 0;
    main.rs.current_script = @constCast(t_val);
    main.rs.oldfiles = NIL;
    main.unload();

    if (!main.fileExists(t_val)) {
        if (main.rs.initialising != 0) {
            main.fatal("panic: %s not found\n", .{.{t_val}});
        }
        if (main.rs.verbosity != 0) {
            word.print("new file {s}\n", .{t_val});
        }
        if (main.rs.magic) {
            main.fatal("mira -exec %s: no such file\n", .{.{t_val}});
        }
        if (main.rs.making and main.rs.ideep == 0) {
            word.print("mira -make {s}: no such file\n", .{t_val});
        } else {
            main.rs.oldfiles = main.cons(main.make_fil(t_val, 0, 0, NIL), NIL);
        }
        main.loading = 0;
        return;
    }

    if (abi.openfile(@constCast(t_val)) == 0) {
        if (main.rs.initialising != 0) {
            main.fatal("panic: cannot open %s\n", .{.{t_val}});
        }
        word.print("cannot open {s}\n", .{t_val});
        main.rs.oldfiles = main.cons(main.make_fil(t_val, 0, 0, NIL), NIL);
        main.loading = 0;
        return;
    }

    main.files = main.cons(main.make_fil(t_val, main.fm_time(t_val), 1, NIL), NIL);
    main.current_file = main.heap.h(main.files);
    main.heap.tp(main.heap.h(ls.fileq)).* = main.current_file;

    if (main.rs.initialising != 0 and word.strcmp(t_val, @as([*:0]const u8, @ptrCast(&main.rs.PRELUDE))) == 0) {
        setup.privlib();
    } else if (main.rs.initialising != 0 or main.rs.nostdenv) {
        if (word.strcmp(t_val, @as([*:0]const u8, @ptrCast(&main.rs.STDENV))) == 0) {
            setup.stdlib();
        }
    }

    ls.c = ' ';
    ls.col = 0;
    main.rs.s_in = @ptrFromInt(@as(usize, @intCast(main.heap.h(main.heap.h(ls.fileq)))));
    abi.adjust_prefix(@constCast(t_val));

    main.commandmode = 0;
    if (main.rs.verbosity != 0 or main.rs.making) {
        word.print("compiling {s}\n", .{t_val});
    }
    ls.nextpn = 0;
    main.rs.embargoes = NIL;
    main.rs.detrop = NIL;
    main.rs.fnts = NIL;
    main.rs.rfl = NIL;
    main.rs.bereaved = NIL;
    main.rs.ld_stuff = NIL;
    ls.exportfiles = NIL;
    main.rs.freeids = NIL;
    main.rs.exports = NIL;
    main.rs.includees = NIL;
    main.cs.FBS = NIL;

    _ = parser_api.parseCurrent() catch {};

    if (main.SYNERR == 0 and ls.exportfiles != NIL) {
        var s = ls.exportfiles;
        while (s != NIL) : (s = main.heap.t(s)) {
            if (main.heap.h(s) == word.PLUS) {
                var i = main.fil_defs(main.heap.h(main.files));
                while (i != NIL) : (i = main.heap.t(i)) {
                    if (main.isvariable(main.heap.h(i)) and !main.isfreeid(main.heap.h(i))) {
                        main.heap.tp(main.rs.exports).* = abi.add1(main.heap.h(i), main.heap.t(main.rs.exports));
                    }
                }
            } else {
                var count: Word = 0;
                var i = main.rs.includees;
                while (i != NIL) : (i = main.heap.t(i)) {
                    if (word.strcmp(@as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(main.heap.h(main.heap.h(main.heap.h(i))))))), @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(main.heap.h(s)))))) == 0) {
                        main.heap.hp(s).* = main.heap.h(main.heap.h(main.heap.h(i)));
                        count += 1;
                    }
                }
                if (count != 1) {
                    main.SYNERR = 1;
                    word.print("illegal fileid \"{s}\" in export list ({s})\n", .{@as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(main.heap.h(s))))), @as([*:0]const u8, if (count != 0) "ambiguous" else "not %included in script")});
                }
            }
        }
        if (main.SYNERR != 0) {
            abi.sayhere(main.heap.h(main.rs.exports), 1);
            word.printErr("compilation abandoned\n", .{});
        }
    }

    if (main.SYNERR == 0 and main.rs.includees != NIL) {
        main.files = abi.append1(main.files, mkincludes(main.rs.includees));
        main.rs.includees = NIL;
    }
    main.rs.ld_stuff = NIL;

    if (main.SYNERR == 0) {
        if (main.rs.verbosity != 0 or (main.rs.making and !main.rs.mkexports and !main.rs.mksources)) {
            word.print("checking types in {s}\n", .{t_val});
        }
        main.checktypes();
    }

    if (main.SYNERR == 0 and main.rs.exports != NIL) {
        if (main.cs.ND != NIL) {
            main.rs.exports = NIL;
        } else {
            var e = main.rs.embargoes;
            var u: Word = NIL;
            var n: Word = NIL;
            var c_ctr: Word = NIL;
            h_val = main.heap.h(main.rs.exports);
            main.rs.exports = main.heap.t(main.rs.exports);

            while (e != NIL) : (e = main.heap.t(e)) {
                if (main.id_type(main.heap.h(e)) == word.undef_t) {
                    u = main.cons(main.heap.h(e), u);
                    main.cs.ND = abi.add1(main.heap.h(e), main.cs.ND);
                } else if (abi.member(main.rs.exports, main.heap.h(e)) == 0) {
                    n = main.cons(main.heap.h(e), n);
                }
            }

            if (main.rs.embargoes != NIL) {
                main.rs.exports = abi.setdiff(main.rs.exports, main.rs.embargoes);
            }
            main.rs.exports = main.alfasort(main.rs.exports);

            e = main.rs.exports;
            while (e != NIL) : (e = main.heap.t(e)) {
                if (main.id_type(main.heap.h(e)) == word.undef_t) {
                    u = main.cons(main.heap.h(e), u);
                    main.cs.ND = abi.add1(main.heap.h(e), main.cs.ND);
                } else if (main.id_type(main.heap.h(e)) == word.type_t and main.t_class(main.heap.h(e)) == word.algebraic_t) {
                    c_ctr = main.shunt(main.t_info(main.heap.h(e)), c_ctr);
                }
            }

            if (main.rs.exports == NIL) {
                word.print("warning, export list has void contents\n", .{});
            } else {
                main.rs.exports = abi.append1(main.alfasort(c_ctr), main.rs.exports);
            }

            if (n != NIL) {
                word.print("redundant entry in export list:", .{});
                while (n != NIL) : (n = main.heap.t(n)) {
                    word.print(" -{s}", .{main.get_id(main.heap.h(n))});
                }
                _ = word.putchar('\n');
            }

            if (u != NIL) {
                main.rs.exports = NIL;
                abi.printlist(@constCast("undefined names in export list: "), u);
            }

            if (u != NIL) {
                abi.sayhere(h_val, 1);
                h_val = NIL;
            } else if (main.rs.exports == NIL or n != NIL) {
                abi.out_here(main.getStderr(), h_val, 1);
                h_val = NIL;
            }
        }
    }

    if (main.SYNERR == 0 and main.cs.ND == NIL and (main.rs.exports != NIL or main.heap.t(main.files) != NIL)) {
        var e1 = main.rs.exports;
        var r: Word = NIL;
        var e: Word = NIL;
        if (main.rs.exports != NIL) {
            while (e1 != NIL) : (e1 = main.heap.t(e1)) {
                const ty = main.id_type(main.heap.h(e1));
                if (ty == word.type_t) {
                    if (main.t_class(main.heap.h(e1)) == word.synonym_t) {
                        r = abi.UNION(r, abi.deps(main.t_info(main.heap.h(e1))));
                    } else {
                        e = main.cons(main.heap.h(e1), e);
                    }
                } else {
                    r = abi.UNION(r, abi.deps(ty));
                }
            }
        } else {
            e1 = main.fil_defs(main.heap.h(main.files));
            while (e1 != NIL) : (e1 = main.heap.t(e1)) {
                const ty = main.id_type(main.heap.h(e1));
                if (ty == word.type_t) {
                    if (main.t_class(main.heap.h(e1)) == word.synonym_t) {
                        r = abi.UNION(r, abi.deps(main.t_info(main.heap.h(e1))));
                    } else {
                        e = main.cons(main.heap.h(e1), e);
                    }
                } else {
                    r = abi.UNION(r, abi.deps(ty));
                }
            }
        }

        e1 = main.rs.freeids;
        while (e1 != NIL) : (e1 = main.heap.t(e1)) {
            const ty = main.id_type(main.heap.h(main.heap.h(e1)));
            if (ty == word.type_t) {
                if (main.t_class(main.heap.h(main.heap.h(e1))) == word.synonym_t) {
                    r = abi.UNION(r, abi.deps(main.t_info(main.heap.h(main.heap.h(e1)))));
                } else {
                    e = main.cons(main.heap.h(main.heap.h(e1)), e);
                }
            } else {
                r = abi.UNION(r, abi.deps(ty));
            }
        }

        while (r != NIL) : (r = main.heap.t(r)) {
            if (abi.member(e, main.heap.h(r)) == 0) {
                main.rs.bereaved = main.cons(main.heap.h(r), main.rs.bereaved);
            }
        }
    }

    if (main.rs.exports != NIL and main.rs.bereaved != NIL) {
        const b = abi.intersection(main.rs.bereaved, main.cs.newtyps);
        if (b != NIL) {
            word.print("warning, export list is incomplete - missing typename: ", .{});
            abi.printlist(@constCast(""), b);
        }
        if (b != NIL and h_val != NIL) {
            abi.out_here(main.getStdout(), h_val, 1);
        }
    }

    if (main.SYNERR == 0 and main.rs.detrop != NIL) {
        const gd = main.rs.detrop;
        while (main.rs.detrop != NIL and getTag(main.dval(main.heap.h(main.rs.detrop))) == word.LABEL) {
            main.rs.detrop = main.heap.t(main.rs.detrop);
        }
        if (main.rs.detrop != NIL) {
            word.print("warning, script contains unused local definitions:-\n", .{});
        }
        while (main.rs.detrop != NIL) {
            abi.out_here(main.getStdout(), main.heap.h(main.heap.h(main.heap.t(main.dval(main.heap.h(main.rs.detrop))))), 0);
            _ = word.putchar('\t');
            abi.out_pattern(main.getStdout(), main.dlhs(main.heap.h(main.rs.detrop)));
            _ = word.putchar('\n');
            main.rs.detrop = main.heap.t(main.rs.detrop);
            while (main.rs.detrop != NIL and getTag(main.dval(main.heap.h(main.rs.detrop))) == word.LABEL) {
                main.rs.detrop = main.heap.t(main.rs.detrop);
            }
        }

        var gd_mut = gd;
        while (gd_mut != NIL and getTag(main.dval(main.heap.h(gd_mut))) != word.LABEL) {
            gd_mut = main.heap.t(gd_mut);
        }
        if (gd_mut != NIL) {
            word.print("warning, grammar contains unused nonterminals:-\n", .{});
        }
        while (gd_mut != NIL) {
            abi.out_here(main.getStdout(), main.heap.h(main.dval(main.heap.h(gd_mut))), 0);
            _ = word.putchar('\t');
            abi.out_pattern(main.getStdout(), main.dlhs(main.heap.h(gd_mut)));
            _ = word.putchar('\n');
            gd_mut = main.heap.t(gd_mut);
            while (gd_mut != NIL and getTag(main.dval(main.heap.h(gd_mut))) != word.LABEL) {
                gd_mut = main.heap.t(gd_mut);
            }
        }
    }

    if (main.SYNERR == 0) {
        var x = main.fil_defs(main.heap.h(main.files));
        main.cs.lfrule = 0;
        while (x != NIL) : (x = main.heap.t(x)) {
            if (main.id_type(main.heap.h(x)) != word.type_t) {
                main.cs.current_id = main.heap.h(x);
                main.cs.polyshowerror = 0;
                main.heap.tp(main.heap.h(x)).* = main.codegen(main.id_val(main.heap.h(x)));
                if (main.cs.polyshowerror != 0) {
                    main.heap.tp(main.heap.h(x)).* = word.UNDEF;
                }
            }
        }
        main.cs.current_id = 0;
        if (main.cs.lfrule != 0 and (main.rs.verbosity != 0 or main.rs.making)) {
            word.print("grammar optimisation: {} common left factors found\n", .{main.cs.lfrule});
        }
        if (main.rs.initialising != 0 and main.cs.ND != NIL) {
            main.fatal("panic: %s contains errors\n", .{.{@as([*:0]const u8, if (main.rs.okprel) "stdenv" else "prelude")}});
        }
        if (main.rs.initialising != 0) {
            main.makedump();
        } else if (main.normal(t_val) != 0) {
            main.fixexports();
            main.makedump();
            main.unfixexports();
        }
        if (main.errline == 0 and main.errs != 0 and word.strcmp(@as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(main.heap.h(main.errs))))), main.rs.current_script.?) == 0) {
            main.errline = main.heap.t(main.errs);
        }
        main.cs.ND = main.alfasort(main.cs.ND);
        main.loading = 0;
        return;
    }

    if (main.rs.initialising != 0) {
        main.fatal("panic: cannot compile %s\n", .{.{@as([*:0]const u8, if (main.rs.okprel) "stdenv" else "prelude")}});
    }
    main.rs.oldfiles = main.files;
    main.unload();
    if (main.normal(t_val) != 0 and main.SYNERR != 2) {
        main.makedump();
    }
    main.SYNERR = 0;
    main.loading = 0;
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
            if (main.rs.ideep > 6) {
                word.printErr("error occurs {} deep in %include files\n", .{main.rs.ideep});
            }
            if (main.rs.ideep != 0) {
                abi.exit(2);
            }
            main.SYNERR = 2;
            word.print("compilation of \"{s}\" abandoned\n", .{main.rs.current_script.?});
            return NIL;
        }
        while (pid != abi.wait(&status)) {}
        if (WEXITSTATUS(status) == 2) {
            if (main.rs.ideep != 0) {
                abi.exit(2);
            } else {
                main.SYNERR = 2;
                word.print("compilation of \"{s}\" abandoned\n", .{main.rs.current_script.?});
                return NIL;
            }
        }
    } else { // child
        _ = signals(abi.SIGINT, 0);
        main.rs.ideep += 1;
        main.rs.making = true;
        main.rs.make_status = 0;
        main.rs.echoing = 0;
        main.rs.listing = 0;
        main.rs.verbosity = 0;
        main.rs.magic = false;
        _ = abi.sigsetjmp(&main.rs.env, 1);
        while (includees_list != NIL and main.rs.make_status == 0) {
            main.undump(@ptrFromInt(@as(usize, @intCast(main.heap.h(main.heap.h(main.heap.h(includees_list)))))));
            if (main.cs.ND != NIL or (main.files == NIL and main.rs.oldfiles != NIL)) {
                main.rs.make_status = 1;
            }
            includees_list = main.heap.t(includees_list);
        }
        abi.exit(@intCast(main.rs.make_status));
    }

    main.rs.sigflag = 0;
    while (includees_list != NIL) {
        var x: Word = NIL;
        var oldsig: usize = 0;
        var f: ?*word.FILE = null;
        const fn_str = @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(main.heap.h(main.heap.h(main.heap.h(includees_list)))))));

        _ = word.strcpy(ls.dicp, fn_str);
        _ = word.strcpy(ls.dicp + word.strlen(ls.dicp) - 1, main.obsuffix);

        if (!main.rs.making) {
            oldsig = signals(abi.SIGINT, @intFromPtr(&main.sigdefer));
        }

        f = word.fopen(ls.dicp, "r");
        if (f != null) {
            x = abi.load_script(f.?, @constCast(fn_str), main.heap.h(main.heap.t(main.heap.h(includees_list))), main.heap.t(main.heap.t(main.heap.h(includees_list))), 0);
            _ = word.fclose(f.?);
        }

        main.rs.ld_stuff = main.cons(x, main.rs.ld_stuff);
        if (!main.rs.making) {
            _ = signals(abi.SIGINT, oldsig);
        }

        if (main.rs.sigflag != 0) {
            main.rs.sigflag = 0;
            if (oldsig > 1) {
                const handler: *const fn (c_int) callconv(.c) void = @ptrFromInt(oldsig);
                handler(abi.SIGINT);
            }
        }

        if (f != null and main.cs.BAD_DUMP == 0 and x != NIL and main.cs.ND == NIL and main.cs.CLASHES == NIL and main.cs.ALIASES == NIL and main.cs.TSUPPRESSED == NIL and main.cs.DETROP == NIL and main.cs.MISSING == NIL) {
            if (main.cs.TORPHANS != 0) {
                main.rs.rfl = main.shunt(x, main.rs.rfl);
            }
            var y = x;
            while (y != NIL) : (y = main.heap.t(y)) {
                const nodev = main.inodev(main.get_fil(main.heap.h(y)).?);
                main.heap.tp(main.fil_inodev(main.heap.h(y))).* = nodev;
            }

            y = x;
            while (y != NIL) : (y = main.heap.t(y)) {
                if (main.fil_share(main.heap.h(y)) != 0) {
                    var z = result;
                    while (z != NIL) : (z = main.heap.t(z)) {
                        if (main.fil_share(main.heap.h(z)) != 0 and main.same_file(main.heap.h(y), main.heap.h(z)) and main.fil_time(main.heap.h(y)) == main.fil_time(main.heap.h(z))) {
                            var p = main.fil_defs(main.heap.h(y));
                            var q = main.fil_defs(main.heap.h(z));
                            while (p != NIL and q != NIL) {
                                if (getTag(main.heap.h(p)) == word.ID) {
                                    if (main.id_type(main.heap.h(p)) == word.type_t and (getTag(main.heap.h(q)) == word.ID or getTag(pn_val(main.heap.h(q))) == word.ID)) {
                                        var w = tclashes;
                                        const orig = if (getTag(main.heap.h(q)) == word.ID) main.heap.h(q) else pn_val(main.heap.h(q));
                                        if (main.t_class(main.heap.h(p)) == word.synonym_t) {
                                            p = main.heap.t(p);
                                            q = main.heap.t(q);
                                            continue;
                                        }
                                        while (w != NIL and (word.strcmp(main.get_fil(main.heap.h(w)).?, main.get_fil(main.heap.h(z)).?) != 0 or main.heap.h(main.heap.t(main.heap.h(w))) != orig)) {
                                            w = main.heap.t(w);
                                        }
                                        if (w == NIL) {
                                            tclashes = main.cons(abi.strcons(@as(Word, @intCast(@intFromPtr(main.get_fil(main.heap.h(z)).?))), main.cons(orig, NIL)), tclashes);
                                            w = tclashes;
                                        }
                                        main.heap.tp(main.heap.t(main.heap.t(main.heap.h(w)))).* = main.cons(main.heap.h(p), main.heap.t(main.heap.t(main.heap.h(w))));
                                    } else {
                                        main.heap.tp(main.heap.h(q)).* = main.heap.h(p);
                                    }
                                } else {
                                    main.heap.tp(main.heap.h(p)).* = main.heap.h(q);
                                }
                                p = main.heap.t(p);
                                q = main.heap.t(q);
                            }
                            if (p != NIL or q != NIL) {
                                word.printErr("impossible event in mkincludes\n", .{});
                            }
                        }
                    }
                }
            }

            if (abi.member(ls.exportfiles, @intCast(@intFromPtr(fn_str))) != 0) {
                y = x;
                while (y != NIL) : (y = main.heap.t(y)) {
                    var z = main.fil_defs(main.heap.h(y));
                    while (z != NIL) : (z = main.heap.t(z)) {
                        if (main.isvariable(main.heap.h(z))) {
                            main.heap.tp(main.rs.exports).* = abi.add1(main.heap.h(z), main.heap.t(main.rs.exports));
                        }
                    }
                }
            }

            result = abi.append1(result, x);
            if (main.heap.h(main.cs.FBS) == NIL) {
                main.cs.FBS = main.heap.t(main.cs.FBS);
            } else {
                main.heap.hp(main.cs.FBS).* = main.cons(main.heap.t(main.heap.h(main.heap.h(includees_list))), main.heap.h(main.cs.FBS));
            }
            includees_list = main.heap.t(includees_list);
            continue;
        }

        if (f == null) {
            result = main.cons(main.make_fil(fn_str, main.fm_time(fn_str), 0, NIL), result);
        } else if (x == NIL and main.cs.BAD_DUMP != -2) {
            result = abi.append1(result, main.rs.oldfiles);
            main.rs.oldfiles = NIL;
        } else {
            result = abi.append1(result, x);
        }

        main.SYNERR = 1;
        word.print("unsuccessful %include directive ", .{});
        abi.sayhere(main.heap.t(main.heap.h(main.heap.h(includees_list))), 1);

        if (f == null) {
            word.print("\"{s}\" cannot be loaded\n", .{fn_str});
            main.cs.CLASHES = NIL;
            main.cs.DETROP = NIL;
            main.cs.MISSING = NIL;
        } else if (main.cs.BAD_DUMP == -2) {
            abi.printlist(@constCast("aliasing causes nameclashes: "), main.cs.CLASHES);
            main.cs.CLASHES = NIL;
        } else if (main.cs.ALIASES != NIL or main.cs.TSUPPRESSED != NIL) {
            if (main.cs.ALIASES != NIL) {
                word.print("alias fails (name{s} not found in file", .{@as([*:0]const u8, if (main.heap.t(main.cs.ALIASES) == NIL) "" else "s")});
                abi.printlist(@constCast("): "), main.cs.ALIASES);
                main.cs.ALIASES = NIL;
            }
            if (main.cs.TSUPPRESSED != NIL) {
                word.print("illegal alias (cannot suppress typename{s}):", .{@as([*:0]const u8, if (main.heap.t(main.cs.TSUPPRESSED) == NIL) "" else "s")});
                var ts = main.cs.TSUPPRESSED;
                while (ts != NIL) : (ts = main.heap.t(ts)) {
                    word.print(" -{s}", .{main.get_id(main.heap.h(ts))});
                }
                _ = word.putchar('\n');
            }
        } else if (main.cs.BAD_DUMP != 0) {
            word.print("\"{s}\" has bad data in dump file\n", .{fn_str});
        } else if (x == NIL) {
            word.print("\"{s}\" contains syntax error\n", .{fn_str});
        } else if (main.cs.ND != NIL) {
            word.print("\"{s}\" contains undefined names or type errors\n", .{fn_str});
        }

        if (main.cs.ND == NIL and main.cs.CLASHES != NIL) {
            word.print("\"{s}\" ", .{fn_str});
            abi.printlist(@constCast("causes nameclashes: "), main.cs.CLASHES);
        }

        while (main.cs.DETROP != NIL and getTag(main.heap.h(main.cs.DETROP)) == word.CONS) {
            const fa = main.heap.h(main.heap.t(main.heap.h(main.cs.DETROP)));
            const ta = main.heap.t(main.heap.t(main.heap.h(main.cs.DETROP)));
            const pn = main.get_id(main.heap.h(main.heap.h(main.cs.DETROP)));
            if (fa == -1 or ta == -1) {
                word.print("`{s}' has binding of wrong kind ", .{pn});
                word.print("(should be \"= value\" not \"== type\")\n", .{});
            } else {
                word.print("`{s}' has == binding of wrong arity ", .{pn});
                word.print("(formal has arity {}, actual has arity {})\n", .{fa, ta});
            }
            main.cs.DETROP = main.heap.t(main.cs.DETROP);
        }

        if (main.cs.DETROP != NIL) {
            word.print("illegal parameter binding (name{s} not %free in file", .{@as([*:0]const u8, if (main.heap.t(main.cs.DETROP) == NIL) "" else "s")});
            abi.printlist(@constCast("): "), main.cs.DETROP);
            main.cs.DETROP = NIL;
        }

        if (main.cs.MISSING != NIL) {
            word.print("missing parameter binding{s}: ", .{@as([*:0]const u8, if (main.heap.t(main.cs.MISSING) == NIL) "" else "s")});
        }

        while (main.cs.MISSING != NIL) {
            word.printErr("{s}{s}", .{@as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(main.heap.h(main.heap.h(main.cs.MISSING)))))), @as([*:0]const u8, if (main.heap.t(main.cs.MISSING) == NIL) ";\n" else ",")});
            main.cs.MISSING = main.heap.t(main.cs.MISSING);
        }

        word.printErr("compilation abandoned\n", .{});
        main.stackp = main.dstack;
        includees_list = main.heap.t(includees_list);
        return result;
    }

    if (tclashes != NIL) {
        word.printErr("TYPECLASH - the following type{s} multiply named:\n", .{@as([*:0]const u8, if (main.heap.t(tclashes) == NIL) " is" else "s are")});
        while (tclashes != NIL) {
            word.printErr("\'{s}\' of file \"{s}\", as: ", .{abi.getaka(main.heap.h(main.heap.t(main.heap.h(tclashes)))), @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(main.heap.h(main.heap.h(tclashes))))))});
            abi.printlist(@constCast(""), main.alfasort(main.heap.t(main.heap.t(main.heap.h(tclashes)))));
            tclashes = main.heap.t(tclashes);
        }
        word.printErr("typecheck cannot proceed - compilation abandoned\n", .{});
        main.SYNERR = 1;
        return result;
    }

    return result;
}

test "module_loader constants are consistent" {
    try std.testing.expectEqual(main.NIL, NIL);
    try std.testing.expect(NIL > 0);
}
