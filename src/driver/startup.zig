//! startup.zig — process entry and one-time bootstrap.
//!
//! `mainEntry` is the program's real `main`: it parses the command line, installs
//! signal handlers, sizes and builds the heap, locates the Miranda library
//! (checking each candidate's `.version`), reads the user's `.mirarc`, and hands
//! off to `commandLoop`. Also holds the version-string formatting and the
//! library-mismatch reporting used during that search.

const std = @import("std");
const word = @import("../runtime/word.zig");
const strtab = @import("../runtime/strtab.zig");
const main = @import("../main.zig");
const abi = @import("../runtime/main_clib.zig");

const Word = main.Word;
const NIL = main.NIL;
const CONS = main.CONS;
const h = main.heap.h;
const t = main.heap.t;

const lex_state = @import("../parser/lex_state.zig");
const version = @import("../runtime/version.zig");
const reduce = @import("../runtime/reduce.zig");
const heap = @import("../runtime/heap.zig");
const core_state = @import("../runtime/core_state.zig");
const lineedit = @import("lineedit.zig");
const ls = lex_state.ls;

inline fn getTag(x: Word) u8 {
    return main.heap.heap.getTag(x);
}

/// True if a numeric command-line flag value is outside the accepted range (100 .. 50,000,000).
fn flagOutOfRange(x: Word) bool {
    return x < 100 or x > 50000000;
}

/// Raise the process stack limit to its hard maximum (deep reductions need the headroom).
fn unlimitStack() void {
    var rlimit: abi.struct_rlimit = undefined;
    if (abi.getrlimit(abi.RLIMIT_STACK, &rlimit) == 0) {
        rlimit.rlim_cur = rlimit.rlim_max;
        _ = abi.setrlimit(abi.RLIMIT_STACK, &rlimit);
    }
}

/// Process entry point: parse flags and arguments, install signal handlers, set up the heap, locate the library, then enter `commandLoop`. Returns the exit code.
pub fn mainEntry(argc: c_int, argv: [*][*:0]u8) c_int {
    var manonly: Word = 0;
    main.rs.cstack = @ptrCast(&manonly);
    unlimitStack();
    main.rs.verbosity = if (abi.isatty(0) != 0) 1 else 0;
    word.setbuf(main.getStdout(), null);

    const home = abi.getenv("HOME");
    var okhome_rc: Word = 0;
    if (home != null) {
        _ = word.strcpy(&main.rs.home_rc, home);
        if (word.strcmp(&main.rs.home_rc, "/") == 0) {
            main.rs.home_rc[0] = 0;
        }
        _ = word.strcat(&main.rs.home_rc, "/.mirarc");
        okhome_rc = main.readRc(@as([*:0]const u8, @ptrCast(&main.rs.home_rc)));
    }

    main.rs.UTF8 = main.utf8test();
    main.rs.UTF8OUT = main.rs.UTF8;

    var arg_idx: usize = 1;
    const argc_u = @as(usize, @intCast(argc));
    while (arg_idx < argc_u and argv[arg_idx][0] == '-') {
        const arg = argv[arg_idx];
        if (word.strcmp(arg, "-stdenv") == 0) {
            main.rs.nostdenv = true;
        } else if (word.strcmp(arg, "-count") == 0) {
            main.rs.atcount = 1;
        } else if (word.strcmp(arg, "-list") == 0) {
            main.rs.listing = 1;
        } else if (word.strcmp(arg, "-nolist") == 0) {
            main.rs.listing = 0;
        } else if (word.strcmp(arg, "-nostrictif") == 0) {
            main.rs.strictif = false;
        } else if (word.strcmp(arg, "-gc") == 0) {
            main.rs.atgc = 1;
        } else if (word.strcmp(arg, "-object") == 0) {
            main.rs.atobject = 1;
        } else if (word.strcmp(arg, "-lib") == 0) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                main.missingParam("lib");
            } else {
                main.rs.miralib = argv[arg_idx];
            }
        } else if (word.strcmp(arg, "-dic") == 0) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                main.missingParam("dic");
            } else {
                var val: c_long = 0;
                if (abi.sscanf(argv[arg_idx], "%ld", .{&val}) != 1 or flagOutOfRange(val)) {
                    main.fatal("mira: bad value after flag \"-dic\"\n", .{.{}});
                }
                main.rs.DICSPACE = val;
            }
        } else if (word.strcmp(arg, "-heap") == 0) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                main.missingParam("heap");
            } else {
                var val: c_long = 0;
                if (abi.sscanf(argv[arg_idx], "%ld", .{&val}) != 1 or flagOutOfRange(val)) {
                    main.fatal("mira: bad value after flag \"-heap\"\n", .{.{}});
                }
                main.rs.SPACELIMIT = val;
            }
        } else if (word.strcmp(arg, "-editor") == 0) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                main.missingParam("editor");
            } else {
                main.rs.editor = argv[arg_idx];
                main.fixEditor();
            }
        } else if (word.strcmp(arg, "-hush") == 0) {
            main.rs.verbosity = 0;
        } else if (word.strcmp(arg, "-nohush") == 0) {
            main.rs.verbosity = 1;
        } else if (word.strcmp(arg, "-exp") == 0 or word.strcmp(arg, "-log") == 0) {
            main.fatal("mira: obsolete flag \"%s\"\nuse \"-exec\" or \"-exec2\", see manual\n", .{.{arg}});
        } else if (word.strcmp(arg, "-exec") == 0) {
            ls.ARGC = @intCast(argc - @as(c_int, @intCast(arg_idx)) - 1);
            ls.ARGV = @ptrCast(argv + arg_idx + 1);
            main.rs.magic = true;
            main.rs.verbosity = 0;
            arg_idx = argc_u;
            break;
        } else if (word.strcmp(arg, "-exec2") == 0) {
            if (arg_idx + 1 >= argc_u) {
                main.fatal("incorrect use of -exec2 flag, missing filename\n", .{.{}});
            }
            const filename = argv[arg_idx + 1];
            var p = word.strrchr(filename, '/');
            if (p == null) {
                p = filename;
            } else {
                p = p.? + 1;
            }
            const rt = @import("../runtime/runtime_state.zig");
            const len = word.strlen(p.?) + 9;
            const slice = rt.allocator.allocSentinel(u8, len, 0) catch {
                abi.mallocfail(@constCast("logfile name"));
                unreachable;
            };
            const logfilname = slice.ptr;
            _ = abi.sprintf(logfilname, "miralog/%s", .{p.?});
            const fil = word.fopen(logfilname, "a");
            if (fil != null) {
                _ = abi.dup2(word.fileno(fil), 2);
            } else {
                word.printErr("could not open {s}\n", .{logfilname});
            }
            ls.ARGC = @intCast(argc - @as(c_int, @intCast(arg_idx)) - 1);
            ls.ARGV = @ptrCast(argv + arg_idx + 1);
            main.rs.magic = true;
            main.rs.verbosity = 0;
            arg_idx = argc_u;
            break;
        } else if (word.strcmp(arg, "-man") == 0) {
            manonly = 1;
        } else if (word.strcmp(arg, "-version") == 0) {
            main.versionInfo(0);
            abi.exit(0);
        } else if (word.strcmp(arg, "-V") == 0) {
            main.versionInfo(1);
            abi.exit(0);
        } else if (word.strcmp(arg, "-make") == 0) {
            main.rs.making = true;
            main.rs.verbosity = 0;
        } else if (word.strcmp(arg, "-exports") == 0) {
            main.rs.making = true;
            main.rs.mkexports = true;
            main.rs.verbosity = 0;
        } else if (word.strcmp(arg, "-sources") == 0) {
            main.rs.making = true;
            main.rs.mksources = true;
            main.rs.verbosity = 0;
        } else if (word.strcmp(arg, "-UTF-8") == 0) {
            main.rs.UTF8 = 1;
        } else if (word.strcmp(arg, "-noUTF-8") == 0) {
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
        if (abi.getenv("MIRALIB")) |m| {
            main.rs.miralib = @constCast(m);
        } else if (main.checkVersion("/usr/lib/miralib") != 0) {
            main.rs.miralib = @constCast("/usr/lib/miralib");
        } else if (main.checkVersion("/usr/local/lib/miralib") != 0) {
            main.rs.miralib = @constCast("/usr/local/lib/miralib");
        } else if (main.checkVersion("miralib") != 0) {
            main.rs.miralib = @constCast("miralib");
        } else {
            badlib = true;
        }
    }

    if (badlib) {
        word.printErr("fatal error: miralib version {s} not found\n", .{main.versionString(@intCast(version.version))});
        main.libFails();
        abi.exit(1);
    }

    if (okhome_rc == 0) {
        if (main.rs.rc_error == @as(?[*:0]const u8, @ptrCast(&main.rs.lib_rc))) {
            main.rs.rc_error = null;
        }
        _ = word.strcpy(&main.rs.lib_rc, main.rs.miralib.?);
        _ = word.strcat(&main.rs.lib_rc, "/.mirarc");
        _ = main.readRc(@as([*:0]const u8, @ptrCast(&main.rs.lib_rc)));
    }

    if (main.rs.editor == null) {
        if (abi.getenv("EDITOR")) |ed| {
            main.rs.editor = @constCast(ed);
        } else {
            main.rs.editor = @constCast(main.EDITOR);
        }
        if (main.rs.editor != null) {
            _ = word.strcpy(&main.rs.ebuf, main.rs.editor.?);
            main.rs.editor = @as([*:0]u8, @ptrCast(&main.rs.ebuf));
            main.fixEditor();
        }
    }

    if (abi.getenv("MIRAPROMPT")) |prs| {
        main.rs.promptstr = prs;
    }

    if (abi.getenv("RECHECKMIRA") != null and main.rs.rechecking == 0) {
        main.rs.rechecking = 1;
    }

    if (abi.getenv("NOSTRICTIF") != null) {
        main.rs.strictif = false;
    }

    abi.setupdic();
    main.rs.s_in = main.getStdin();
    reduce.ev.s_out = main.getStdout();
    main.rs.miralib = main.makeAbsolute(main.rs.miralib.?);

    if (manonly != 0) {
        main.manaction();
        abi.exit(0);
    }

    _ = word.strcpy(&main.rs.PRELUDE, main.rs.miralib.?);
    _ = word.strcat(&main.rs.PRELUDE, "/prelude");

    _ = word.strcpy(&main.rs.STDENV, main.rs.miralib.?);
    _ = word.strcat(&main.rs.STDENV, "/stdenv.m");

    main.miraSetup();

    if (main.rs.verbosity != 0) {
        main.announce();
    }

    heap.heap.files = NIL;
    main.undump(@as([*:0]const u8, @ptrCast(&main.rs.PRELUDE)));
    main.rs.okprel = true;
    abi.mkprivate(main.filDefs(main.heap.h(heap.heap.files)));
    heap.heap.files = NIL;

    if (!main.rs.nostdenv) {
        main.undump(@as([*:0]const u8, @ptrCast(&main.rs.STDENV)));
        while (heap.heap.files != NIL) {
            main.rs.primenv = main.alfasort(abi.append1(main.rs.primenv, main.filDefs(main.heap.h(heap.heap.files))));
            heap.heap.files = main.heap.t(heap.heap.files);
        }
        main.rs.primenv = main.alfasort(main.rs.primenv);
        main.cs.newtyps = NIL;
        heap.heap.files = NIL;
    }

    if (!main.rs.magic) {
        main.writeRc();
    }

    main.rs.echoing = main.rs.verbosity & main.rs.listing;
    main.rs.initialising = 0;

    if (main.rs.mkexports) {
        const arg_count: usize = remaining_argc;
        var s: [*:0]u8 = undefined;
        _ = abi.sigsetjmp(&main.rs.env, 1);
        var cur_argv_idx = arg_idx;
        while (cur_argv_idx < argc_u) : (cur_argv_idx += 1) {
            var x: Word = NIL;
            s = abi.addextn(1, argv[cur_argv_idx]);
            if (s == ls.dicp) {
                _ = abi.keep(ls.dicp);
            }
            main.undump(s);
            if (heap.heap.files == NIL or main.cs.ND != NIL) {
                continue;
            }
            if (arg_count != 1) {
                word.print("{s}\n", .{s});
            }
            if (main.rs.exports != NIL) {
                x = main.rs.exports;
            } else {
                var f = heap.heap.files;
                while (f != NIL) : (f = main.heap.t(f)) {
                    x = abi.append1(main.filDefs(main.heap.h(f)), x);
                }
            }

            if (main.rs.freeids != NIL) {
                var f = main.rs.freeids;
                while (f != NIL) : (f = main.heap.t(f)) {
                    const n = abi.findid(@constCast(main.get_id(main.heap.h(f))));
                    main.heap.tp(n).* = main.heap.t(main.heap.t(main.heap.h(f)));
                    main.heap.tp(main.heap.h(main.heap.h(n))).* = main.theVal(main.heap.h(f));
                    main.heap.hp(f).* = n;
                }
                main.rs.freeids = abi.typesfirst(main.rs.freeids);
                f = main.rs.freeids;
                word.print("\t%free {{\n", .{});
                while (f != NIL) : (f = main.heap.t(f)) {
                    _ = word.putchar('\t');
                    abi.reportType(main.heap.h(f));
                    _ = word.putchar('\n');
                }
                word.print("\t}}\n", .{});
            }

            var item = abi.typesfirst(main.alfasort(x));
            while (item != NIL) : (item = main.heap.t(item)) {
                _ = word.putchar('\t');
                abi.reportType(main.heap.h(item));
                _ = word.putchar('\n');
            }
        }
        abi.exit(0);
    }

    if (main.rs.mksources) {
        var s: [*:0]u8 = undefined;
        var x: Word = NIL;
        _ = abi.sigsetjmp(&main.rs.env, 1);
        var cur_argv_idx = arg_idx;
        while (cur_argv_idx < argc_u) : (cur_argv_idx += 1) {
            s = abi.addextn(1, argv[cur_argv_idx]);
            if (main.fileExists(s)) {
                if (s == ls.dicp) {
                    _ = abi.keep(ls.dicp);
                }
                main.undump(s);
                var f = if (heap.heap.files == NIL) main.rs.oldfiles else heap.heap.files;
                while (f != NIL) : (f = main.heap.t(f)) {
                    const filename_str = main.get_fil(main.heap.h(f)).?;
                    if (abi.member(x, strtab.strBits(filename_str)) == 0) {
                        x = main.cons(strtab.strBits(filename_str), x);
                        word.print("{s}\n", .{filename_str});
                    }
                }
            }
        }
        abi.exit(0);
    }

    if (main.rs.making) {
        var s: [*:0]u8 = undefined;
        _ = abi.sigsetjmp(&main.rs.env, 1);
        var cur_argv_idx = arg_idx;
        while (cur_argv_idx < argc_u) : (cur_argv_idx += 1) {
            s = abi.addextn(1, argv[cur_argv_idx]);
            if (s == ls.dicp) {
                _ = abi.keep(ls.dicp);
            }
            main.undump(s);
            if (main.cs.ND != NIL or (heap.heap.files == NIL and main.rs.oldfiles != NIL)) {
                if (main.rs.make_status == 1) {
                    main.rs.make_status = 0;
                }
                main.rs.make_status = abi.strcons(@as(Word, strtab.strBits(s)), main.rs.make_status);
            }
        }
        if (getTag(main.rs.make_status) == word.STRCONS) {
            var h_val: Word = 0;
            var maxw: Word = 0;
            word.print("errors or undefined names found in:-\n", .{});
            while (main.rs.make_status != 0) {
                h_val = abi.strcons(main.heap.h(main.rs.make_status), h_val);
                const w = @as(Word, @intCast(word.strlen(strtab.strOf(main.heap.h(h_val)))));
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
                const str = strtab.strOf(main.heap.h(h_val));
                const len = word.strlen(str);
                const spaces_needed = if (@as(usize, @intCast(maxw)) > len) @as(usize, @intCast(maxw)) - len else 0;
                var pad_idx: usize = 0;
                while (pad_idx < spaces_needed) : (pad_idx += 1) {
                    word.print(" ", .{});
                }
                const next_newline = if ((@rem(w, n)) != 0) "" else "\n";
                word.print("{s}{s}", .{ str, next_newline });
                h_val = main.heap.t(h_val);
            }
            if ((@rem(w, n)) != 0) {
                word.print("\n", .{});
            }
            main.rs.make_status = 1;
        }
        abi.exit(@intCast(main.rs.make_status));
    }

    var initscript: [*:0]const u8 = undefined;
    if (remaining_argc == 0) {
        initscript = "script.m";
    } else if (main.rs.magic) {
        initscript = argv[arg_idx];
    } else {
        initscript = abi.addextn(1, argv[arg_idx]);
    }

    if (initscript == ls.dicp) {
        _ = abi.keep(ls.dicp);
    }

    _ = main.signals(abi.SIGFPE, @intFromPtr(&main.fpeError));
    _ = main.signals(abi.SIGTERM, @intFromPtr(&abi.exit));
    // Interactive stdin gets zigline line editing + history; piped/file stdin
    // keeps the plain read path (so the golden corpus and integration suite run
    // unchanged).
    if (abi.isatty(0) != 0) {
        const rt = @import("../runtime/runtime_state.zig");
        lineedit.init(rt.allocator, rt.io);
    }
    main.commandLoop(@constCast(initscript));
    return 0;
}

// Version-mismatch scratch, filled by checkVersion and drained by libFails.
var vstack: [4]c_int = undefined; // versions found at mismatched library dirs
var mstack: [4][*:0]const u8 = undefined; // the corresponding directory paths
var mvp: usize = 0; // count of recorded mismatches (<= 4)
var vbuf: [12]u8 = undefined; // formatting buffer for versionString

/// Load the saved `.mirarc` dump `rcfile`, fixing up types. Returns 1 on success, 0 if missing/stale/clashing.
pub fn readRc(rcfile: [*:0]const u8) Word {
    var f: ?*word.FILE = null;
    var x: Word = undefined;
    var res: Word = 0;
    f = word.fopen(rcfile, "r");
    if (f == null) return 0;
    core_state.s.loading = 1;
    res = abi.loadScript(f.?, @constCast(rcfile), NIL, NIL, 0);
    _ = word.fclose(f.?);
    if (main.cs.BAD_DUMP != 0) {
        main.unload();
        main.cs.CLASHES = NIL;
        heap.heap.stackp = heap.heap.dstack;
        core_state.s.loading = 0;
        return 0;
    }
    if (main.cs.CLASHES != NIL) {
        main.unload();
        core_state.s.loading = 0;
        return 0;
    }
    if (main.srcUpdate() != 0) {
        main.loadfile(rcfile);
    }
    core_state.s.loading = 0;
    if (main.cs.ND != NIL or heap.heap.files == NIL) return 0;
    x = main.filDefs(h(heap.heap.files));
    while (x != NIL) : (x = t(x)) {
        if (main.idType(h(x)) == word.synonym_t) {
            main.heap.tp(main.tInfo(h(x))).* = main.dump.fixtype(main.tInfo(h(x)), h(x));
        } else {
            main.heap.tp(h(h(x))).* = main.dump.fixtype(main.idType(h(x)), h(x));
        }
    }
    return 1;
}

/// Write the current environment to the user's `~/.mirarc` dump.
pub fn writeRc() void {
    const home = abi.getenv("HOME");
    var f: ?*word.FILE = null;
    if (home == null or main.rs.home_rc[0] == 0) return;
    f = word.fopen(&main.rs.home_rc, "w");
    if (f == null) return;
    abi.setprefix(@ptrCast(&main.rs.home_rc));
    abi.dumpScript(heap.heap.files, f.?);
    _ = word.fclose(f.?);
}

/// Abort: command-line flag `s` was given without its required parameter.
pub fn missingParam(s: [:0]const u8) noreturn {
    main.fatal("mira: missing param after flag \"-%s\"\n", .{.{s.ptr}});
}

/// Check the `.version` file under directory `m`; returns 1 if it matches this build, else records the mismatch for `libFails`.
pub fn checkVersion(m: [*:0]const u8) c_int {
    var path_buf: [1024]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, "{s}/.version", .{m}) catch return 0;
    const f = word.fopen(path.ptr, "r");
    var v1: c_uint = 0;
    var read_ok: bool = false;
    var r: c_int = 0;
    if (f != null) {
        if (abi.fscanf(f, "%u", .{&v1}) == 1) {
            r = if (v1 == version.version) 1 else 0;
            read_ok = true;
        }
        _ = word.fclose(f);
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

/// Report the library version mismatches collected by `checkVersion`.
pub fn libFails() void {
    word.printErr("found", .{});
    var i: usize = 0;
    while (i < mvp) : (i += 1) {
        word.printErr("\tversion {s} at: {s}\n", .{versionString(vstack[i]), mstack[i]});
    }
}

/// Format integer version `v` as an `M.mmm` string (`???` if out of range).
pub fn versionString(v: c_int) [*:0]const u8 {
    if (v < 0 or v > 999999) {
        return "???";
    }
    _ = abi.snprintf(&vbuf, vbuf.len, "%.3f", .{@as(f64, @floatFromInt(v)) / 1000.0});
    return @ptrCast(&vbuf);
}

/// Print the release/date line; with `full` set, also the host string and XVERSION.
pub fn versionInfo(full: c_int) void {
    word.print("{s} last revised {s}\n", .{versionString(version.version), version.vdate});
    if (full == 0) return;
    word.print("{s}", .{version.host});
    word.print("XVERSION {}\n", .{@as(c_uint, @intCast(word.XVERSION))});
}
