const std = @import("std");
const main = @import("../main.zig");
const clib = @import("../runtime/main_clib.zig");

const Word = main.Word;
const NIL = main.NIL;
const CONS = main.CONS;
const h = main.heap.h;
const t = main.heap.t;

const lex_state = @import("../parser/lex_state.zig");
const ls = &lex_state.ls;

extern var tag: [*]u8;

fn badval(x: Word) bool {
    return x < 100 or x > 50000000;
}

fn unlimitStack() void {
    var rlimit: clib.struct_rlimit = undefined;
    if (clib.getrlimit(clib.RLIMIT_STACK, &rlimit) == 0) {
        rlimit.rlim_cur = rlimit.rlim_max;
        _ = clib.setrlimit(clib.RLIMIT_STACK, &rlimit);
    }
}

export fn main_entry(argc: c_int, argv: [*][*:0]u8) callconv(.c) c_int {
    var manonly: Word = 0;
    main.rs.cstack = @ptrCast(&manonly);
    unlimitStack();
    main.rs.verbosity = if (clib.isatty(0) != 0) 1 else 0;
    clib.setbuf(main.getStdout(), null);

    const home = clib.getenv("HOME");
    var okhome_rc: Word = 0;
    if (home != null) {
        _ = clib.strcpy(&main.rs.home_rc, home);
        if (clib.strcmp(&main.rs.home_rc, "/") == 0) {
            main.rs.home_rc[0] = 0;
        }
        _ = clib.strcat(&main.rs.home_rc, "/.mirarc");
        okhome_rc = main.rc_read(@as([*:0]const u8, @ptrCast(&main.rs.home_rc)));
    }

    main.rs.UTF8 = main.utf8test();
    main.rs.UTF8OUT = main.rs.UTF8;

    var arg_idx: usize = 1;
    const argc_u = @as(usize, @intCast(argc));
    while (arg_idx < argc_u and argv[arg_idx][0] == '-') {
        const arg = argv[arg_idx];
        if (clib.strcmp(arg, "-stdenv") == 0) {
            main.rs.nostdenv = true;
        } else if (clib.strcmp(arg, "-count") == 0) {
            main.rs.atcount = 1;
        } else if (clib.strcmp(arg, "-list") == 0) {
            main.rs.listing = 1;
        } else if (clib.strcmp(arg, "-nolist") == 0) {
            main.rs.listing = 0;
        } else if (clib.strcmp(arg, "-nostrictif") == 0) {
            main.rs.strictif = false;
        } else if (clib.strcmp(arg, "-gc") == 0) {
            main.rs.atgc = 1;
        } else if (clib.strcmp(arg, "-object") == 0) {
            main.rs.atobject = 1;
        } else if (clib.strcmp(arg, "-lib") == 0) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                main.missparam("lib");
            } else {
                main.rs.miralib = argv[arg_idx];
            }
        } else if (clib.strcmp(arg, "-dic") == 0) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                main.missparam("dic");
            } else {
                var val: c_long = 0;
                if (clib.sscanf(argv[arg_idx], "%ld", .{&val}) != 1 or badval(val)) {
                    main.fatal("mira: bad value after flag \"-dic\"\n", .{.{}});
                }
                main.rs.DICSPACE = val;
            }
        } else if (clib.strcmp(arg, "-heap") == 0) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                main.missparam("heap");
            } else {
                var val: c_long = 0;
                if (clib.sscanf(argv[arg_idx], "%ld", .{&val}) != 1 or badval(val)) {
                    main.fatal("mira: bad value after flag \"-heap\"\n", .{.{}});
                }
                main.rs.SPACELIMIT = val;
            }
        } else if (clib.strcmp(arg, "-editor") == 0) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                main.missparam("editor");
            } else {
                main.rs.editor = argv[arg_idx];
                main.fixeditor();
            }
        } else if (clib.strcmp(arg, "-hush") == 0) {
            main.rs.verbosity = 0;
        } else if (clib.strcmp(arg, "-nohush") == 0) {
            main.rs.verbosity = 1;
        } else if (clib.strcmp(arg, "-exp") == 0 or clib.strcmp(arg, "-log") == 0) {
            main.fatal("mira: obsolete flag \"%s\"\nuse \"-exec\" or \"-exec2\", see manual\n", .{.{arg}});
        } else if (clib.strcmp(arg, "-exec") == 0) {
            ls.ARGC = @intCast(argc - @as(c_int, @intCast(arg_idx)) - 1);
            ls.ARGV = @ptrCast(argv + arg_idx + 1);
            main.rs.magic = true;
            main.rs.verbosity = 0;
            arg_idx = argc_u;
            break;
        } else if (clib.strcmp(arg, "-exec2") == 0) {
            if (arg_idx + 1 >= argc_u) {
                main.fatal("incorrect use of -exec2 flag, missing filename\n", .{.{}});
            }
            const filename = argv[arg_idx + 1];
            var p = clib.strrchr(filename, '/');
            if (p == null) {
                p = filename;
            } else {
                p = p.? + 1;
            }
            const rt = @import("../runtime/runtime_state.zig");
            const len = clib.strlen(p.?) + 9;
            const slice = rt.allocator.allocSentinel(u8, len, 0) catch {
                clib.mallocfail(@constCast("logfile name"));
                unreachable;
            };
            const logfilname = slice.ptr;
            _ = clib.sprintf(logfilname, "miralog/%s", .{p.?});
            const fil = clib.fopen(logfilname, "a");
            if (fil != null) {
                _ = clib.dup2(clib.fileno(fil), 2);
            } else {
                _ = clib.fprintf(main.getStderr(), "could not open %s\n", .{.{logfilname}});
            }
            ls.ARGC = @intCast(argc - @as(c_int, @intCast(arg_idx)) - 1);
            ls.ARGV = @ptrCast(argv + arg_idx + 1);
            main.rs.magic = true;
            main.rs.verbosity = 0;
            arg_idx = argc_u;
            break;
        } else if (clib.strcmp(arg, "-man") == 0) {
            manonly = 1;
        } else if (clib.strcmp(arg, "-version") == 0) {
            main.v_info(0);
            clib.exit(0);
        } else if (clib.strcmp(arg, "-V") == 0) {
            main.v_info(1);
            clib.exit(0);
        } else if (clib.strcmp(arg, "-make") == 0) {
            main.rs.making = true;
            main.rs.verbosity = 0;
        } else if (clib.strcmp(arg, "-exports") == 0) {
            main.rs.making = true;
            main.rs.mkexports = true;
            main.rs.verbosity = 0;
        } else if (clib.strcmp(arg, "-sources") == 0) {
            main.rs.making = true;
            main.rs.mksources = true;
            main.rs.verbosity = 0;
        } else if (clib.strcmp(arg, "-UTF-8") == 0) {
            main.rs.UTF8 = 1;
        } else if (clib.strcmp(arg, "-noUTF-8") == 0) {
            main.rs.UTF8 = 0;
        } else {
            main.fatal("mira: unknown flag \"%s\"\n", .{.{arg}});
        }
        arg_idx += 1;
    }

    const remaining_argc = argc_u - arg_idx;
    if (remaining_argc > 1 and !main.rs.magic and !main.rs.making) {
        main.fatal("mira: too many args\n", .{.{}});
    }

    var badlib: bool = false;
    if (main.rs.miralib == null) {
        if (clib.getenv("MIRALIB")) |m| {
            main.rs.miralib = @constCast(m);
        } else if (main.checkversion("/usr/lib/miralib") != 0) {
            main.rs.miralib = @constCast("/usr/lib/miralib");
        } else if (main.checkversion("/usr/local/lib/miralib") != 0) {
            main.rs.miralib = @constCast("/usr/local/lib/miralib");
        } else if (main.checkversion("miralib") != 0) {
            main.rs.miralib = @constCast("miralib");
        } else {
            badlib = true;
        }
    }

    if (badlib) {
        _ = clib.fprintf(main.getStderr(), "fatal error: miralib version %s not found\n", .{.{main.strvers(@intCast(main.version))}});
        main.libfails();
        clib.exit(1);
    }

    if (okhome_rc == 0) {
        if (main.rs.rc_error == @as(?[*:0]const u8, @ptrCast(&main.rs.lib_rc))) {
            main.rs.rc_error = null;
        }
        _ = clib.strcpy(&main.rs.lib_rc, main.rs.miralib.?);
        _ = clib.strcat(&main.rs.lib_rc, "/.mirarc");
        _ = main.rc_read(@as([*:0]const u8, @ptrCast(&main.rs.lib_rc)));
    }

    if (main.rs.editor == null) {
        if (clib.getenv("EDITOR")) |ed| {
            main.rs.editor = @constCast(ed);
        } else {
            main.rs.editor = @constCast(main.EDITOR);
        }
        if (main.rs.editor != null) {
            _ = clib.strcpy(&main.rs.ebuf, main.rs.editor.?);
            main.rs.editor = @as([*:0]u8, @ptrCast(&main.rs.ebuf));
            main.fixeditor();
        }
    }

    if (clib.getenv("MIRAPROMPT")) |prs| {
        main.rs.promptstr = prs;
    }

    if (clib.getenv("RECHECKMIRA") != null and main.rs.rechecking == 0) {
        main.rs.rechecking = 1;
    }

    if (clib.getenv("NOSTRICTIF") != null) {
        main.rs.strictif = false;
    }

    clib.setupdic();
    main.rs.s_in = main.getStdin();
    main.s_out = main.getStdout();
    main.rs.miralib = main.mkabsolute(main.rs.miralib.?);

    if (manonly != 0) {
        main.manaction();
        clib.exit(0);
    }

    _ = clib.strcpy(&main.rs.PRELUDE, main.rs.miralib.?);
    _ = clib.strcat(&main.rs.PRELUDE, "/prelude");

    _ = clib.strcpy(&main.rs.STDENV, main.rs.miralib.?);
    _ = clib.strcat(&main.rs.STDENV, "/stdenv.m");

    main.mira_setup();

    if (main.rs.verbosity != 0) {
        main.announce();
    }

    main.files = NIL;
    main.undump(@as([*:0]const u8, @ptrCast(&main.rs.PRELUDE)));
    main.rs.okprel = true;
    clib.mkprivate(main.fil_defs(main.heap.h(main.files)));
    main.files = NIL;

    if (!main.rs.nostdenv) {
        main.undump(@as([*:0]const u8, @ptrCast(&main.rs.STDENV)));
        while (main.files != NIL) {
            main.rs.primenv = main.alfasort(clib.append1(main.rs.primenv, main.fil_defs(main.heap.h(main.files))));
            main.files = main.heap.t(main.files);
        }
        main.rs.primenv = main.alfasort(main.rs.primenv);
        main.cs.newtyps = NIL;
        main.files = NIL;
    }

    if (!main.rs.magic) {
        main.rc_write();
    }

    main.rs.echoing = main.rs.verbosity & main.rs.listing;
    main.rs.initialising = 0;

    if (main.rs.mkexports) {
        const arg_count: usize = remaining_argc;
        var s: [*:0]u8 = undefined;
        _ = clib.sigsetjmp(&main.rs.env, 1);
        var cur_argv_idx = arg_idx;
        while (cur_argv_idx < argc_u) : (cur_argv_idx += 1) {
            var x: Word = NIL;
            s = clib.addextn(1, argv[cur_argv_idx]);
            if (s == ls.dicp) {
                _ = clib.keep(ls.dicp);
            }
            main.undump(s);
            if (main.files == NIL or main.cs.ND != NIL) {
                continue;
            }
            if (arg_count != 1) {
                _ = clib.printf("%s\n", .{.{s}});
            }
            if (main.rs.exports != NIL) {
                x = main.rs.exports;
            } else {
                var f = main.files;
                while (f != NIL) : (f = main.heap.t(f)) {
                    x = clib.append1(main.fil_defs(main.heap.h(f)), x);
                }
            }

            if (main.rs.freeids != NIL) {
                var f = main.rs.freeids;
                while (f != NIL) : (f = main.heap.t(f)) {
                    const n = clib.findid(@constCast(main.get_id(main.heap.h(f))));
                    main.heap.tp(n).* = main.heap.t(main.heap.t(main.heap.h(f)));
                    main.heap.tp(main.heap.h(main.heap.h(n))).* = main.the_val(main.heap.h(f));
                    main.heap.hp(f).* = n;
                }
                main.rs.freeids = clib.typesfirst(main.rs.freeids);
                f = main.rs.freeids;
                _ = clib.printf("\t%%free {\n", .{.{}});
                while (f != NIL) : (f = main.heap.t(f)) {
                    _ = clib.putchar('\t');
                    clib.report_type(main.heap.h(f));
                    _ = clib.putchar('\n');
                }
                _ = clib.printf("\t}\n", .{.{}});
            }

            var item = clib.typesfirst(main.alfasort(x));
            while (item != NIL) : (item = main.heap.t(item)) {
                _ = clib.putchar('\t');
                clib.report_type(main.heap.h(item));
                _ = clib.putchar('\n');
            }
        }
        clib.exit(0);
    }

    if (main.rs.mksources) {
        var s: [*:0]u8 = undefined;
        var x: Word = NIL;
        _ = clib.sigsetjmp(&main.rs.env, 1);
        var cur_argv_idx = arg_idx;
        while (cur_argv_idx < argc_u) : (cur_argv_idx += 1) {
            s = clib.addextn(1, argv[cur_argv_idx]);
            if (main.fileExists(s)) {
                if (s == ls.dicp) {
                    _ = clib.keep(ls.dicp);
                }
                main.undump(s);
                var f = if (main.files == NIL) main.rs.oldfiles else main.files;
                while (f != NIL) : (f = main.heap.t(f)) {
                    const filename_str = main.get_fil(main.heap.h(f)).?;
                    if (clib.member(x, @intCast(@intFromPtr(filename_str))) == 0) {
                        x = main.cons(@intCast(@intFromPtr(filename_str)), x);
                        _ = clib.printf("%s\n", .{.{filename_str}});
                    }
                }
            }
        }
        clib.exit(0);
    }

    if (main.rs.making) {
        var s: [*:0]u8 = undefined;
        _ = clib.sigsetjmp(&main.rs.env, 1);
        var cur_argv_idx = arg_idx;
        while (cur_argv_idx < argc_u) : (cur_argv_idx += 1) {
            s = clib.addextn(1, argv[cur_argv_idx]);
            if (s == ls.dicp) {
                _ = clib.keep(ls.dicp);
            }
            main.undump(s);
            if (main.cs.ND != NIL or (main.files == NIL and main.rs.oldfiles != NIL)) {
                if (main.rs.make_status == 1) {
                    main.rs.make_status = 0;
                }
                main.rs.make_status = clib.strcons(@as(Word, @intCast(@intFromPtr(s))), main.rs.make_status);
            }
        }
        if (tag[@intCast(main.rs.make_status)] == clib.STRCONS) {
            var h_val: Word = 0;
            var maxw: Word = 0;
            _ = clib.printf("errors or undefined names found in:-\n", .{.{}});
            while (main.rs.make_status != 0) {
                h_val = clib.strcons(main.heap.h(main.rs.make_status), h_val);
                const w = @as(Word, @intCast(clib.strlen(@ptrFromInt(@as(usize, @intCast(main.heap.h(h_val)))))));
                if (w > maxw) {
                    maxw = w;
                }
                main.rs.make_status = main.heap.t(main.rs.make_status);
            }
            maxw += 1;
            const n = @divTrunc(@as(Word, 78), maxw);
            var w: Word = 0;
            while (h_val != 0) {
                w += 1;
                _ = clib.printf("%*s%s", .{.{ @as(c_int, @intCast(maxw)), @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(main.heap.h(h_val))))), @as([*:0]const u8, if ((@rem(w, n)) != 0) "" else "\n") }});
                h_val = main.heap.t(h_val);
            }
            if ((@rem(w, n)) != 0) {
                _ = clib.printf("\n", .{.{}});
            }
            main.rs.make_status = 1;
        }
        clib.exit(@intCast(main.rs.make_status));
    }

    var initscript: [*:0]const u8 = undefined;
    if (remaining_argc == 0) {
        initscript = "script.m";
    } else if (main.rs.magic) {
        initscript = argv[arg_idx];
    } else {
        initscript = clib.addextn(1, argv[arg_idx]);
    }

    if (initscript == ls.dicp) {
        _ = clib.keep(ls.dicp);
    }

    _ = main.signals(clib.SIGFPE, @intFromPtr(&main.fpe_error));
    _ = main.signals(clib.SIGTERM, @intFromPtr(&clib.exit));
    main.commandloop(@constCast(initscript));
    return 0;
}

// Relocated startup configuration and version verification
var vstack: [4]c_int = undefined;
var mstack: [4][*:0]const u8 = undefined;
var mvp: usize = 0;
var vbuf: [12]u8 = undefined;

pub fn rc_read(rcfile: [*:0]const u8) Word {
    var f: ?*clib.FILE = null;
    var x: Word = undefined;
    var res: Word = 0;
    f = clib.fopen(rcfile, "r");
    if (f == null) return 0;
    main.loading = 1;
    res = clib.load_script(f.?, @constCast(rcfile), NIL, NIL, 0);
    _ = clib.fclose(f.?);
    if (main.cs.BAD_DUMP != 0) {
        main.unload();
        main.cs.CLASHES = NIL;
        main.stackp = main.dstack;
        main.loading = 0;
        return 0;
    }
    if (main.cs.CLASHES != NIL) {
        main.unload();
        main.loading = 0;
        return 0;
    }
    if (main.src_update() != 0) {
        main.loadfile(rcfile);
    }
    main.loading = 0;
    if (main.cs.ND != NIL or main.files == NIL) return 0;
    x = main.fil_defs(h(main.files));
    while (x != NIL) : (x = t(x)) {
        if (main.id_type(h(x)) == clib.synonym_t) {
            main.heap.tp(main.t_info(h(x))).* = main.dump.fixtype(main.t_info(h(x)), h(x));
        } else {
            main.heap.tp(h(h(x))).* = main.dump.fixtype(main.id_type(h(x)), h(x));
        }
    }
    return 1;
}

pub fn rc_write() void {
    const home = clib.getenv("HOME");
    var f: ?*clib.FILE = null;
    if (home == null or main.rs.home_rc[0] == 0) return;
    f = clib.fopen(&main.rs.home_rc, "w");
    if (f == null) return;
    clib.setprefix(@ptrCast(&main.rs.home_rc));
    clib.dump_script(main.files, f.?);
    _ = clib.fclose(f.?);
}

pub fn missparam(s: [:0]const u8) noreturn {
    main.fatal("mira: missing param after flag \"-%s\"\n", .{.{s.ptr}});
}

pub fn checkversion(m: [*:0]const u8) c_int {
    var path_buf: [1024]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, "{s}/.version", .{m}) catch return 0;
    const f = clib.fopen(path.ptr, "r");
    var v1: c_uint = 0;
    var read_ok: bool = false;
    var r: c_int = 0;
    if (f != null) {
        if (clib.fscanf(f, "%u", .{&v1}) == 1) {
            r = if (v1 == main.version) 1 else 0;
            read_ok = true;
        }
        _ = clib.fclose(f);
    }
    if (read_ok and r == 0) {
        if (mvp < 4) {
            mstack[mvp] = m;
            vstack[mvp] = @intCast(v1);
            mvp += 1;
        }
    }
    return r;
}

pub fn libfails() void {
    const stderr = main.getStderr().?;
    _ = clib.fprintf(stderr, "found", .{.{}});
    var i: usize = 0;
    while (i < mvp) : (i += 1) {
        _ = clib.fprintf(stderr, "\tversion %s at: %s\n", .{.{ strvers(vstack[i]), mstack[i] }});
    }
}

pub fn strvers(v: c_int) [*:0]const u8 {
    if (v < 0 or v > 999999) {
        return "???";
    }
    _ = clib.snprintf(&vbuf, vbuf.len, "%.3f", .{@as(f64, @floatFromInt(v)) / 1000.0});
    return @ptrCast(&vbuf);
}

pub fn v_info(full: c_int) void {
    _ = clib.printf("%s last revised %s\n", .{.{ strvers(main.version), main.vdate }});
    if (full == 0) return;
    _ = clib.printf("%s", .{.{main.host}});
    _ = clib.printf("XVERSION %u\n", .{.{@as(c_uint, @intCast(clib.XVERSION))}});
}
