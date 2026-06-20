const std = @import("std");
const main = @import("../main.zig");
const clib = @import("../runtime/main_clib.zig");
const parser_api = @import("../parser/parser_api.zig");
const setup = @import("setup.zig");

const Word = main.Word;
const NIL = main.NIL;

// Global variables defined/exported in parser/lex.zig
extern var fileq: Word;
extern var c: Word;
extern var col: Word;
extern var nextpn: Word;
extern var pnvec: ?[*]Word;
extern var exportfiles: Word;

// Global variables defined in other modules
extern var current_file: Word;
extern var ND: Word;
extern var CLASHES: Word;
extern var ALIASES: Word;
extern var TSUPPRESSED: Word;
extern var DETROP: Word;
extern var MISSING: Word;
extern var stackp: ?[*]Word;
extern var dstack: ?[*]Word;
extern var lfrule: c_int;
extern var polyshowerror: c_int;
extern var FBS: Word;

// C ABI / linked symbols
extern var tag: [*]u8;
extern fn signals(signum: c_int, handler: usize) usize;

fn WEXITSTATUS(status: c_int) c_int {
    return (status >> 8) & 0xff;
}

inline fn pn_val(x: Word) Word {
    return main.t(x);
}

pub fn loadfile(t_val: [*:0]const u8) void {
    var h_val: Word = NIL;
    main.loading = 1;
    main.errs = 0;
    main.errline = 0;
    main.current_script = @constCast(t_val);
    main.oldfiles = NIL;
    main.unload();

    if (!main.fileExists(t_val)) {
        if (main.initialising != 0) {
            _ = clib.fprintf(main.getStderr(), "panic: %s not found\n", .{.{t_val}});
            clib.exit(1);
        }
        if (main.verbosity != 0) {
            _ = clib.printf("new file %s\n", .{.{t_val}});
        }
        if (main.magic != 0) {
            _ = clib.fprintf(main.getStderr(), "mira -exec %s: no such file\n", .{.{t_val}});
            clib.exit(1);
        }
        if (main.making != 0 and main.ideep == 0) {
            _ = clib.printf("mira -make %s: no such file\n", .{.{t_val}});
        } else {
            main.oldfiles = main.cons(main.make_fil(t_val, 0, 0, NIL), NIL);
        }
        main.loading = 0;
        return;
    }

    if (clib.openfile(@constCast(t_val)) == 0) {
        if (main.initialising != 0) {
            _ = clib.fprintf(main.getStderr(), "panic: cannot open %s\n", .{.{t_val}});
            clib.exit(1);
        }
        _ = clib.printf("cannot open %s\n", .{.{t_val}});
        main.oldfiles = main.cons(main.make_fil(t_val, 0, 0, NIL), NIL);
        main.loading = 0;
        return;
    }

    main.files = main.cons(main.make_fil(t_val, main.fm_time(t_val), 1, NIL), NIL);
    current_file = main.h(main.files);
    main.tp(main.h(fileq)).* = current_file;

    if (main.initialising != 0 and clib.strcmp(t_val, @as([*:0]const u8, @ptrCast(&main.PRELUDE))) == 0) {
        setup.privlib();
    } else if (main.initialising != 0 or main.nostdenv == 1) {
        if (clib.strcmp(t_val, @as([*:0]const u8, @ptrCast(&main.STDENV))) == 0) {
            setup.stdlib();
        }
    }

    c = ' ';
    col = 0;
    main.s_in = @ptrFromInt(@as(usize, @intCast(main.h(main.h(fileq)))));
    clib.adjust_prefix(@constCast(t_val));

    main.commandmode = 0;
    if (main.verbosity != 0 or main.making != 0) {
        _ = clib.printf("compiling %s\n", .{.{t_val}});
    }
    nextpn = 0;
    main.embargoes = NIL;
    main.detrop = NIL;
    main.fnts = NIL;
    main.rfl = NIL;
    main.bereaved = NIL;
    main.ld_stuff = NIL;
    exportfiles = NIL;
    main.freeids = NIL;
    main.exports = NIL;
    main.includees = NIL;
    FBS = NIL;

    _ = parser_api.parseCurrent() catch {};

    if (main.SYNERR == 0 and exportfiles != NIL) {
        var s = exportfiles;
        while (s != NIL) : (s = main.t(s)) {
            if (main.h(s) == clib.PLUS) {
                var i = main.fil_defs(main.h(main.files));
                while (i != NIL) : (i = main.t(i)) {
                    if (main.isvariable(main.h(i)) and !main.isfreeid(main.h(i))) {
                        main.tp(main.exports).* = clib.add1(main.h(i), main.t(main.exports));
                    }
                }
            } else {
                var count: Word = 0;
                var i = main.includees;
                while (i != NIL) : (i = main.t(i)) {
                    if (clib.strcmp(@ptrFromInt(@as(usize, @intCast(main.h(main.h(main.h(i)))))), @ptrFromInt(@as(usize, @intCast(main.h(s))))) == 0) {
                        main.hp(s).* = main.h(main.h(main.h(i)));
                        count += 1;
                    }
                }
                if (count != 1) {
                    main.SYNERR = 1;
                    _ = clib.printf("illegal fileid \"%s\" in export list (%s)\n", .{.{@as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(main.h(s))))), @as([*:0]const u8, if (count != 0) "ambiguous" else "not %included in script")}});
                }
            }
        }
        if (main.SYNERR != 0) {
            clib.sayhere(main.h(main.exports), 1);
            _ = clib.fprintf(main.getStderr().?, "compilation abandoned\n", .{.{}});
        }
    }

    if (main.SYNERR == 0 and main.includees != NIL) {
        main.files = clib.append1(main.files, mkincludes(main.includees));
        main.includees = NIL;
    }
    main.ld_stuff = NIL;

    if (main.SYNERR == 0) {
        if (main.verbosity != 0 or (main.making != 0 and main.mkexports == 0 and main.mksources == 0)) {
            _ = clib.printf("checking types in %s\n", .{.{t_val}});
        }
        clib.checktypes();
    }

    if (main.SYNERR == 0 and main.exports != NIL) {
        if (ND != NIL) {
            main.exports = NIL;
        } else {
            var e = main.embargoes;
            var u: Word = NIL;
            var n: Word = NIL;
            var c_ctr: Word = NIL;
            h_val = main.h(main.exports);
            main.exports = main.t(main.exports);

            while (e != NIL) : (e = main.t(e)) {
                if (main.id_type(main.h(e)) == clib.undef_t) {
                    u = main.cons(main.h(e), u);
                    ND = clib.add1(main.h(e), ND);
                } else if (clib.member(main.exports, main.h(e)) == 0) {
                    n = main.cons(main.h(e), n);
                }
            }

            if (main.embargoes != NIL) {
                main.exports = clib.setdiff(main.exports, main.embargoes);
            }
            main.exports = main.alfasort(main.exports);

            e = main.exports;
            while (e != NIL) : (e = main.t(e)) {
                if (main.id_type(main.h(e)) == clib.undef_t) {
                    u = main.cons(main.h(e), u);
                    ND = clib.add1(main.h(e), ND);
                } else if (main.id_type(main.h(e)) == clib.type_t and main.t_class(main.h(e)) == clib.algebraic_t) {
                    c_ctr = main.shunt(main.t_info(main.h(e)), c_ctr);
                }
            }

            if (main.exports == NIL) {
                _ = clib.printf("warning, export list has void contents\n", .{.{}});
            } else {
                main.exports = clib.append1(main.alfasort(c_ctr), main.exports);
            }

            if (n != NIL) {
                _ = clib.printf("redundant entry in export list:", .{.{}});
                while (n != NIL) : (n = main.t(n)) {
                    _ = clib.printf(" -%s", .{.{main.get_id(main.h(n))}});
                }
                _ = clib.putchar('\n');
            }

            if (u != NIL) {
                main.exports = NIL;
                clib.printlist(@constCast("undefined names in export list: "), u);
            }

            if (u != NIL) {
                clib.sayhere(h_val, 1);
                h_val = NIL;
            } else if (main.exports == NIL or n != NIL) {
                clib.out_here(main.getStderr(), h_val, 1);
                h_val = NIL;
            }
        }
    }

    if (main.SYNERR == 0 and ND == NIL and (main.exports != NIL or main.t(main.files) != NIL)) {
        var e1 = main.exports;
        var r: Word = NIL;
        var e: Word = NIL;
        if (main.exports != NIL) {
            while (e1 != NIL) : (e1 = main.t(e1)) {
                const ty = main.id_type(main.h(e1));
                if (ty == clib.type_t) {
                    if (main.t_class(main.h(e1)) == clib.synonym_t) {
                        r = clib.UNION(r, clib.deps(main.t_info(main.h(e1))));
                    } else {
                        e = main.cons(main.h(e1), e);
                    }
                } else {
                    r = clib.UNION(r, clib.deps(ty));
                }
            }
        } else {
            e1 = main.fil_defs(main.h(main.files));
            while (e1 != NIL) : (e1 = main.t(e1)) {
                const ty = main.id_type(main.h(e1));
                if (ty == clib.type_t) {
                    if (main.t_class(main.h(e1)) == clib.synonym_t) {
                        r = clib.UNION(r, clib.deps(main.t_info(main.h(e1))));
                    } else {
                        e = main.cons(main.h(e1), e);
                    }
                } else {
                    r = clib.UNION(r, clib.deps(ty));
                }
            }
        }

        e1 = main.freeids;
        while (e1 != NIL) : (e1 = main.t(e1)) {
            const ty = main.id_type(main.h(main.h(e1)));
            if (ty == clib.type_t) {
                if (main.t_class(main.h(main.h(e1))) == clib.synonym_t) {
                    r = clib.UNION(r, clib.deps(main.t_info(main.h(main.h(e1)))));
                } else {
                    e = main.cons(main.h(main.h(e1)), e);
                }
            } else {
                r = clib.UNION(r, clib.deps(ty));
            }
        }

        while (r != NIL) : (r = main.t(r)) {
            if (clib.member(e, main.h(r)) == 0) {
                main.bereaved = main.cons(main.h(r), main.bereaved);
            }
        }
    }

    if (main.exports != NIL and main.bereaved != NIL) {
        const b = clib.intersection(main.bereaved, clib.newtyps);
        if (b != NIL) {
            _ = clib.printf("warning, export list is incomplete - missing typename: ", .{.{}});
            clib.printlist(@constCast(""), b);
        }
        if (b != NIL and h_val != NIL) {
            clib.out_here(main.getStdout(), h_val, 1);
        }
    }

    if (main.SYNERR == 0 and main.detrop != NIL) {
        const gd = main.detrop;
        while (main.detrop != NIL and tag[@intCast(main.dval(main.h(main.detrop)))] == clib.LABEL) {
            main.detrop = main.t(main.detrop);
        }
        if (main.detrop != NIL) {
            _ = clib.printf("warning, script contains unused local definitions:-\n", .{.{}});
        }
        while (main.detrop != NIL) {
            clib.out_here(main.getStdout(), main.h(main.h(main.t(main.dval(main.h(main.detrop))))), 0);
            _ = clib.putchar('\t');
            clib.out_pattern(main.getStdout(), main.dlhs(main.h(main.detrop)));
            _ = clib.putchar('\n');
            main.detrop = main.t(main.detrop);
            while (main.detrop != NIL and tag[@intCast(main.dval(main.h(main.detrop)))] == clib.LABEL) {
                main.detrop = main.t(main.detrop);
            }
        }

        var gd_mut = gd;
        while (gd_mut != NIL and tag[@intCast(main.dval(main.h(gd_mut)))] != clib.LABEL) {
            gd_mut = main.t(gd_mut);
        }
        if (gd_mut != NIL) {
            _ = clib.printf("warning, grammar contains unused nonterminals:-\n", .{.{}});
        }
        while (gd_mut != NIL) {
            clib.out_here(main.getStdout(), main.h(main.dval(main.h(gd_mut))), 0);
            _ = clib.putchar('\t');
            clib.out_pattern(main.getStdout(), main.dlhs(main.h(gd_mut)));
            _ = clib.putchar('\n');
            gd_mut = main.t(gd_mut);
            while (gd_mut != NIL and tag[@intCast(main.dval(main.h(gd_mut)))] != clib.LABEL) {
                gd_mut = main.t(gd_mut);
            }
        }
    }

    if (main.SYNERR == 0) {
        var x = main.fil_defs(main.h(main.files));
        main.lfrule = 0;
        while (x != NIL) : (x = main.t(x)) {
            if (main.id_type(main.h(x)) != clib.type_t) {
                main.current_id = main.h(x);
                polyshowerror = 0;
                main.tp(main.h(x)).* = clib.codegen(main.id_val(main.h(x)));
                if (polyshowerror != 0) {
                    main.tp(main.h(x)).* = clib.UNDEF;
                }
            }
        }
        main.current_id = 0;
        if (main.lfrule != 0 and (main.verbosity != 0 or main.making != 0)) {
            _ = clib.printf("grammar optimisation: %d common left factors found\n", .{.{main.lfrule}});
        }
        if (main.initialising != 0 and ND != NIL) {
            _ = clib.fprintf(main.getStderr(), "panic: %s contains errors\n", .{.{@as([*:0]const u8, if (main.okprel != 0) "stdenv" else "prelude")}});
            clib.exit(1);
        }
        if (main.initialising != 0) {
            main.makedump();
        } else if (main.normal(t_val) != 0) {
            main.fixexports();
            main.makedump();
            main.unfixexports();
        }
        if (main.errline == 0 and main.errs != 0 and clib.strcmp(@ptrFromInt(@as(usize, @intCast(main.h(main.errs)))), main.current_script.?) == 0) {
            main.errline = main.t(main.errs);
        }
        ND = main.alfasort(ND);
        main.loading = 0;
        return;
    }

    if (main.initialising != 0) {
        _ = clib.fprintf(main.getStderr(), "panic: cannot compile %s\n", .{.{@as([*:0]const u8, if (main.okprel != 0) "stdenv" else "prelude")}});
        clib.exit(1);
    }
    main.oldfiles = main.files;
    main.unload();
    if (main.normal(t_val) != 0 and main.SYNERR != 2) {
        main.makedump();
    }
    main.SYNERR = 0;
    main.loading = 0;
}

pub fn mkincludes(includees_val: Word) Word {
    var includees_list = includees_val;
    var result: Word = NIL;
    var tclashes: Word = NIL;
    includees_list = main.reverse(includees_list);
    const pid = clib.fork();
    if (pid != 0) { // parent
        var status: c_int = 0;
        if (pid == -1) {
            clib.perror("UNIX error - cannot create process");
            if (main.ideep > 6) {
                _ = clib.fprintf(main.getStderr(), "error occurs %d deep in %%include files\n", .{.{main.ideep}});
            }
            if (main.ideep != 0) {
                clib.exit(2);
            }
            main.SYNERR = 2;
            _ = clib.printf("compilation of \"%s\" abandoned\n", .{.{main.current_script.?}});
            return NIL;
        }
        while (pid != clib.wait(&status)) {}
        if (WEXITSTATUS(status) == 2) {
            if (main.ideep != 0) {
                clib.exit(2);
            } else {
                main.SYNERR = 2;
                _ = clib.printf("compilation of \"%s\" abandoned\n", .{.{main.current_script.?}});
                return NIL;
            }
        }
    } else { // child
        _ = signals(clib.SIGINT, 0);
        main.ideep += 1;
        main.making = 1;
        main.make_status = 0;
        main.echoing = 0;
        main.listing = 0;
        main.verbosity = 0;
        main.magic = 0;
        _ = clib.sigsetjmp(&main.env, 1);
        while (includees_list != NIL and main.make_status == 0) {
            main.undump(@ptrFromInt(@as(usize, @intCast(main.h(main.h(main.h(includees_list)))))));
            if (ND != NIL or (main.files == NIL and main.oldfiles != NIL)) {
                main.make_status = 1;
            }
            includees_list = main.t(includees_list);
        }
        clib.exit(@intCast(main.make_status));
    }

    main.sigflag = 0;
    while (includees_list != NIL) {
        var x: Word = NIL;
        var oldsig: usize = 0;
        var f: ?*clib.FILE = null;
        const fn_str = @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(main.h(main.h(main.h(includees_list)))))));

        _ = clib.strcpy(main.dicp, fn_str);
        _ = clib.strcpy(main.dicp + clib.strlen(main.dicp) - 1, main.obsuffix);

        if (main.making == 0) {
            oldsig = signals(clib.SIGINT, @intFromPtr(&main.sigdefer));
        }

        f = clib.fopen(main.dicp, "r");
        if (f != null) {
            x = clib.load_script(f.?, @constCast(fn_str), main.h(main.t(main.h(includees_list))), main.t(main.t(main.h(includees_list))), 0);
            _ = clib.fclose(f.?);
        }

        main.ld_stuff = main.cons(x, main.ld_stuff);
        if (main.making == 0) {
            _ = signals(clib.SIGINT, oldsig);
        }

        if (main.sigflag != 0) {
            main.sigflag = 0;
            if (oldsig > 1) {
                const handler: *const fn (c_int) callconv(.c) void = @ptrFromInt(oldsig);
                handler(clib.SIGINT);
            }
        }

        if (f != null and clib.BAD_DUMP == 0 and x != NIL and ND == NIL and CLASHES == NIL and ALIASES == NIL and TSUPPRESSED == NIL and DETROP == NIL and MISSING == NIL) {
            if (clib.TORPHANS != 0) {
                main.rfl = main.shunt(x, main.rfl);
            }
            var y = x;
            while (y != NIL) : (y = main.t(y)) {
                const nodev = main.inodev(main.get_fil(main.h(y)).?);
                main.tp(main.fil_inodev(main.h(y))).* = nodev;
            }

            y = x;
            while (y != NIL) : (y = main.t(y)) {
                if (main.fil_share(main.h(y)) != 0) {
                    var z = result;
                    while (z != NIL) : (z = main.t(z)) {
                        if (main.fil_share(main.h(z)) != 0 and main.same_file(main.h(y), main.h(z)) and main.fil_time(main.h(y)) == main.fil_time(main.h(z))) {
                            var p = main.fil_defs(main.h(y));
                            var q = main.fil_defs(main.h(z));
                            while (p != NIL and q != NIL) {
                                if (tag[@intCast(main.h(p))] == clib.ID) {
                                    if (main.id_type(main.h(p)) == clib.type_t and (tag[@intCast(main.h(q))] == clib.ID or tag[@intCast(pn_val(main.h(q)))] == clib.ID)) {
                                        var w = tclashes;
                                        const orig = if (tag[@intCast(main.h(q))] == clib.ID) main.h(q) else pn_val(main.h(q));
                                        if (main.t_class(main.h(p)) == clib.synonym_t) {
                                            p = main.t(p);
                                            q = main.t(q);
                                            continue;
                                        }
                                        while (w != NIL and (clib.strcmp(main.get_fil(main.h(w)).?, main.get_fil(main.h(z)).?) != 0 or main.h(main.t(main.h(w))) != orig)) {
                                            w = main.t(w);
                                        }
                                        if (w == NIL) {
                                            tclashes = main.cons(clib.strcons(@as(Word, @intCast(@intFromPtr(main.get_fil(main.h(z)).?))), main.cons(orig, NIL)), tclashes);
                                            w = tclashes;
                                        }
                                        main.tp(main.t(main.t(main.h(w)))).* = main.cons(main.h(p), main.t(main.t(main.h(w))));
                                    } else {
                                        main.tp(main.h(q)).* = main.h(p);
                                    }
                                } else {
                                    main.tp(main.h(p)).* = main.h(q);
                                }
                                p = main.t(p);
                                q = main.t(q);
                            }
                            if (p != NIL or q != NIL) {
                                _ = clib.fprintf(main.getStderr(), "impossible event in mkincludes\n", .{.{}});
                            }
                        }
                    }
                }
            }

            if (clib.member(exportfiles, @intCast(@intFromPtr(fn_str))) != 0) {
                y = x;
                while (y != NIL) : (y = main.t(y)) {
                    var z = main.fil_defs(main.h(y));
                    while (z != NIL) : (z = main.t(z)) {
                        if (main.isvariable(main.h(z))) {
                            main.tp(main.exports).* = clib.add1(main.h(z), main.t(main.exports));
                        }
                    }
                }
            }

            result = clib.append1(result, x);
            if (main.h(FBS) == NIL) {
                FBS = main.t(FBS);
            } else {
                main.hp(FBS).* = main.cons(main.t(main.h(main.h(includees_list))), main.h(FBS));
            }
            includees_list = main.t(includees_list);
            continue;
        }

        if (f == null) {
            result = main.cons(main.make_fil(fn_str, main.fm_time(fn_str), 0, NIL), result);
        } else if (x == NIL and clib.BAD_DUMP != -2) {
            result = clib.append1(result, main.oldfiles);
            main.oldfiles = NIL;
        } else {
            result = clib.append1(result, x);
        }

        main.SYNERR = 1;
        _ = clib.printf("unsuccessful %%include directive ", .{.{}});
        clib.sayhere(main.t(main.h(main.h(includees_list))), 1);

        if (f == null) {
            _ = clib.printf("\"%s\" cannot be loaded\n", .{.{fn_str}});
            CLASHES = NIL;
            DETROP = NIL;
            MISSING = NIL;
        } else if (clib.BAD_DUMP == -2) {
            clib.printlist(@constCast("aliasing causes nameclashes: "), CLASHES);
            CLASHES = NIL;
        } else if (ALIASES != NIL or TSUPPRESSED != NIL) {
            if (ALIASES != NIL) {
                _ = clib.printf("alias fails (name%s not found in file", .{.{@as([*:0]const u8, if (main.t(ALIASES) == NIL) "" else "s")}});
                clib.printlist(@constCast("): "), ALIASES);
                ALIASES = NIL;
            }
            if (TSUPPRESSED != NIL) {
                _ = clib.printf("illegal alias (cannot suppress typename%s):", .{.{@as([*:0]const u8, if (main.t(TSUPPRESSED) == NIL) "" else "s")}});
                var ts = TSUPPRESSED;
                while (ts != NIL) : (ts = main.t(ts)) {
                    _ = clib.printf(" -%s", .{.{main.get_id(main.h(ts))}});
                }
                _ = clib.putchar('\n');
            }
        } else if (clib.BAD_DUMP != 0) {
            _ = clib.printf("\"%s\" has bad data in dump file\n", .{.{fn_str}});
        } else if (x == NIL) {
            _ = clib.printf("\"%s\" contains syntax error\n", .{.{fn_str}});
        } else if (ND != NIL) {
            _ = clib.printf("\"%s\" contains undefined names or type errors\n", .{.{fn_str}});
        }

        if (ND == NIL and CLASHES != NIL) {
            _ = clib.printf("\"%s\" ", .{.{fn_str}});
            clib.printlist(@constCast("causes nameclashes: "), CLASHES);
        }

        while (DETROP != NIL and tag[@intCast(main.h(DETROP))] == clib.CONS) {
            const fa = main.h(main.t(main.h(DETROP)));
            const ta = main.t(main.t(main.h(DETROP)));
            const pn = main.get_id(main.h(main.h(DETROP)));
            if (fa == -1 or ta == -1) {
                _ = clib.printf("`%s' has binding of wrong kind ", .{.{pn}});
                _ = clib.printf(if (fa == -1) "(should be \"= value\" not \"== type\")\n" else "(should be \"== type\" not \"= value\")\n", .{.{}});
            } else {
                _ = clib.printf("`%s' has == binding of wrong arity ", .{.{pn}});
                _ = clib.printf("(formal has arity %ld, actual has arity %ld)\n", .{.{fa, ta}});
            }
            DETROP = main.t(DETROP);
        }

        if (DETROP != NIL) {
            _ = clib.printf("illegal parameter binding (name%s not %%free in file", .{.{@as([*:0]const u8, if (main.t(DETROP) == NIL) "" else "s")}});
            clib.printlist(@constCast("): "), DETROP);
            DETROP = NIL;
        }

        if (MISSING != NIL) {
            _ = clib.printf("missing parameter binding%s: ", .{.{@as([*:0]const u8, if (main.t(MISSING) == NIL) "" else "s")}});
        }

        while (MISSING != NIL) {
            _ = clib.fprintf(main.getStderr().?, "%s%s", .{.{@as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(main.h(main.h(MISSING)))))), @as([*:0]const u8, if (main.t(MISSING) == NIL) ";\n" else ",")}});
            MISSING = main.t(MISSING);
        }

        _ = clib.fprintf(main.getStderr().?, "compilation abandoned\n", .{.{}});
        stackp = dstack;
        includees_list = main.t(includees_list);
        return result;
    }

    if (tclashes != NIL) {
        _ = clib.fprintf(main.getStderr().?, "TYPECLASH - the following type%s multiply named:\n", .{.{@as([*:0]const u8, if (main.t(tclashes) == NIL) " is" else "s are")}});
        while (tclashes != NIL) {
            _ = clib.fprintf(main.getStderr().?, "\'%s\' of file \"%s\", as: ", .{.{clib.getaka(main.h(main.t(main.h(tclashes)))), @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(main.h(main.h(tclashes))))))}});
            clib.printlist(@constCast(""), main.alfasort(main.t(main.t(main.h(tclashes)))));
            tclashes = main.t(tclashes);
        }
        _ = clib.fprintf(main.getStderr().?, "typecheck cannot proceed - compilation abandoned\n", .{.{}});
        main.SYNERR = 1;
        return result;
    }

    return result;
}

test "module_loader constants are consistent" {
    try std.testing.expectEqual(main.NIL, NIL);
    try std.testing.expect(NIL > 0);
}
