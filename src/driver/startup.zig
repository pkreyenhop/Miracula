//! startup.zig — process entry and one-time bootstrap.
//!
//! `mainEntry` is the program's real `main`: it parses the command line, installs
//! signal handlers, sizes and builds the heap, locates the Miranda library
//! (checking each candidate's `.version`), reads the user's `.mirarc`, and hands
//! off to `commandLoop`. Also holds the version-string formatting and the
//! library-mismatch reporting used during that search.

const std = @import("std");
const word = @import("../runtime/word.zig");
const errors = @import("../runtime/errors.zig");
const strtab = @import("../runtime/strtab.zig");
const main = @import("../main.zig");
const cs = @import("../compiler/compiler_state.zig").cs;
const rt = @import("../runtime/runtime_state.zig");
const abi = @import("../runtime/main_clib.zig");

const Word = word.Word;
const NIL = word.NIL;
const CONS = word.CONS;
const h = heap.h;
const t = heap.t;

const lex_state = @import("../parser/lex_state.zig");
const version = @import("../runtime/version.zig");
const reduce = @import("../runtime/reduce.zig");
const heap = @import("../runtime/heap.zig");
const core_state = @import("../runtime/core_state.zig");
const lineedit = @import("lineedit.zig");
const ls = lex_state.ls;

inline fn getTag(x: Word) u8 {
    return heap.heap.getTag(x);
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
    rt.rs.cstack = @ptrCast(&manonly);
    unlimitStack();
    rt.rs.verbosity = if (abi.isatty(0) != 0) 1 else 0;
    word.setbuf(main.getStdout(), null);

    const home = abi.getenv("HOME");
    var okhome_rc: Word = 0;
    if (home != null) {
        _ = word.strcpy(&rt.rs.home_rc, home);
        if (word.strcmp(&rt.rs.home_rc, "/") == 0) {
            rt.rs.home_rc[0] = 0;
        }
        _ = word.strcat(&rt.rs.home_rc, "/.mirarc");
        okhome_rc = main.readRc(@as([*:0]const u8, @ptrCast(&rt.rs.home_rc)));
    }

    rt.rs.UTF8 = heap.utf8test();
    rt.rs.UTF8OUT = rt.rs.UTF8;

    var arg_idx: usize = 1;
    const argc_u = @as(usize, @intCast(argc));
    while (arg_idx < argc_u and argv[arg_idx][0] == '-') {
        const arg = argv[arg_idx];
        if (word.strcmp(arg, "-stdenv") == 0) {
            rt.rs.nostdenv = true;
        } else if (word.strcmp(arg, "-count") == 0) {
            rt.rs.atcount = 1;
        } else if (word.strcmp(arg, "-list") == 0) {
            rt.rs.listing = 1;
        } else if (word.strcmp(arg, "-nolist") == 0) {
            rt.rs.listing = 0;
        } else if (word.strcmp(arg, "-nostrictif") == 0) {
            rt.rs.strictif = false;
        } else if (word.strcmp(arg, "-gc") == 0) {
            rt.rs.atgc = 1;
        } else if (word.strcmp(arg, "-object") == 0) {
            rt.rs.atobject = 1;
        } else if (word.strcmp(arg, "-lib") == 0) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                main.missingParam("lib");
            } else {
                rt.rs.miralib = argv[arg_idx];
            }
        } else if (word.strcmp(arg, "-dic") == 0) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                main.missingParam("dic");
            } else {
                var val: c_long = 0;
                if (abi.sscanf(argv[arg_idx], "%ld", .{&val}) != 1 or flagOutOfRange(val)) {
                    errors.fatal("mira: bad value after flag \"-dic\"\n", .{.{}});
                }
                rt.rs.DICSPACE = val;
            }
        } else if (word.strcmp(arg, "-heap") == 0) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                main.missingParam("heap");
            } else {
                var val: c_long = 0;
                if (abi.sscanf(argv[arg_idx], "%ld", .{&val}) != 1 or flagOutOfRange(val)) {
                    errors.fatal("mira: bad value after flag \"-heap\"\n", .{.{}});
                }
                rt.rs.SPACELIMIT = val;
            }
        } else if (word.strcmp(arg, "-editor") == 0) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                main.missingParam("editor");
            } else {
                rt.rs.editor = argv[arg_idx];
                main.fixEditor();
            }
        } else if (word.strcmp(arg, "-hush") == 0) {
            rt.rs.verbosity = 0;
        } else if (word.strcmp(arg, "-nohush") == 0) {
            rt.rs.verbosity = 1;
        } else if (word.strcmp(arg, "-exp") == 0 or word.strcmp(arg, "-log") == 0) {
            errors.fatal("mira: obsolete flag \"%s\"\nuse \"-exec\" or \"-exec2\", see manual\n", .{.{arg}});
        } else if (word.strcmp(arg, "-exec") == 0) {
            ls.ARGC = @intCast(argc - @as(c_int, @intCast(arg_idx)) - 1);
            ls.ARGV = @ptrCast(argv + arg_idx + 1);
            rt.rs.magic = true;
            rt.rs.verbosity = 0;
            arg_idx = argc_u;
            break;
        } else if (word.strcmp(arg, "-exec2") == 0) {
            if (arg_idx + 1 >= argc_u) {
                errors.fatal("incorrect use of -exec2 flag, missing filename\n", .{.{}});
            }
            const filename = argv[arg_idx + 1];
            var p = word.strrchr(filename, '/');
            if (p == null) {
                p = filename;
            } else {
                p = p.? + 1;
            }
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
            rt.rs.magic = true;
            rt.rs.verbosity = 0;
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
            rt.rs.making = true;
            rt.rs.verbosity = 0;
        } else if (word.strcmp(arg, "-exports") == 0) {
            rt.rs.making = true;
            rt.rs.mkexports = true;
            rt.rs.verbosity = 0;
        } else if (word.strcmp(arg, "-sources") == 0) {
            rt.rs.making = true;
            rt.rs.mksources = true;
            rt.rs.verbosity = 0;
        } else if (word.strcmp(arg, "-UTF-8") == 0) {
            rt.rs.UTF8 = 1;
        } else if (word.strcmp(arg, "-noUTF-8") == 0) {
            rt.rs.UTF8 = 0;
        } else {
            errors.fatal("mira: unknown flag \"%s\"\n", .{.{arg}});
        }
        arg_idx += 1;
    }

    const remaining_argc = argc_u - arg_idx;
    if (remaining_argc > 1 and !rt.rs.magic and !rt.rs.making) {
        errors.fatal("mira: too many args\n", .{.{}});
    }

    var badlib: bool = false;
    if (rt.rs.miralib == null) {
        if (abi.getenv("MIRALIB")) |m| {
            rt.rs.miralib = @constCast(m);
        } else if (main.checkVersion("/usr/lib/miralib") != 0) {
            rt.rs.miralib = @constCast("/usr/lib/miralib");
        } else if (main.checkVersion("/usr/local/lib/miralib") != 0) {
            rt.rs.miralib = @constCast("/usr/local/lib/miralib");
        } else if (main.checkVersion("miralib") != 0) {
            rt.rs.miralib = @constCast("miralib");
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
        if (rt.rs.rc_error == @as(?[*:0]const u8, @ptrCast(&rt.rs.lib_rc))) {
            rt.rs.rc_error = null;
        }
        _ = word.strcpy(&rt.rs.lib_rc, rt.rs.miralib.?);
        _ = word.strcat(&rt.rs.lib_rc, "/.mirarc");
        _ = main.readRc(@as([*:0]const u8, @ptrCast(&rt.rs.lib_rc)));
    }

    if (rt.rs.editor == null) {
        if (abi.getenv("EDITOR")) |ed| {
            rt.rs.editor = @constCast(ed);
        } else {
            rt.rs.editor = @constCast(main.EDITOR);
        }
        if (rt.rs.editor != null) {
            _ = word.strcpy(&rt.rs.ebuf, rt.rs.editor.?);
            rt.rs.editor = @as([*:0]u8, @ptrCast(&rt.rs.ebuf));
            main.fixEditor();
        }
    }

    if (abi.getenv("MIRAPROMPT")) |prs| {
        rt.rs.promptstr = prs;
    }

    if (abi.getenv("RECHECKMIRA") != null and rt.rs.rechecking == 0) {
        rt.rs.rechecking = 1;
    }

    if (abi.getenv("NOSTRICTIF") != null) {
        rt.rs.strictif = false;
    }

    abi.setupdic();
    rt.rs.s_in = main.getStdin();
    reduce.ev.s_out = main.getStdout();
    rt.rs.miralib = main.makeAbsolute(rt.rs.miralib.?);

    if (manonly != 0) {
        main.manaction();
        abi.exit(0);
    }

    _ = word.strcpy(&rt.rs.PRELUDE, rt.rs.miralib.?);
    _ = word.strcat(&rt.rs.PRELUDE, "/prelude");

    _ = word.strcpy(&rt.rs.STDENV, rt.rs.miralib.?);
    _ = word.strcat(&rt.rs.STDENV, "/stdenv.m");

    main.miraSetup();

    if (rt.rs.verbosity != 0) {
        main.announce();
    }

    heap.heap.files = NIL;
    main.undump(@as([*:0]const u8, @ptrCast(&rt.rs.PRELUDE)));
    rt.rs.okprel = true;
    abi.mkprivate(heap.filDefs(heap.h(heap.heap.files)));
    heap.heap.files = NIL;

    if (!rt.rs.nostdenv) {
        main.undump(@as([*:0]const u8, @ptrCast(&rt.rs.STDENV)));
        while (heap.heap.files != NIL) {
            rt.rs.primenv = heap.alfasort(abi.append1(rt.rs.primenv, heap.filDefs(heap.h(heap.heap.files))));
            heap.heap.files = heap.t(heap.heap.files);
        }
        rt.rs.primenv = heap.alfasort(rt.rs.primenv);
        cs.newtyps = NIL;
        heap.heap.files = NIL;
    }

    if (!rt.rs.magic) {
        main.writeRc();
    }

    rt.rs.echoing = rt.rs.verbosity & rt.rs.listing;
    rt.rs.initialising = 0;

    if (rt.rs.mkexports) {
        const arg_count: usize = remaining_argc;
        var s: [*:0]u8 = undefined;
        _ = abi.sigsetjmp(&rt.rs.env, 1);
        var cur_argv_idx = arg_idx;
        while (cur_argv_idx < argc_u) : (cur_argv_idx += 1) {
            var x: Word = NIL;
            s = abi.addextn(1, argv[cur_argv_idx]);
            if (s == ls.dicp) {
                _ = abi.keep(ls.dicp);
            }
            main.undump(s);
            if (heap.heap.files == NIL or cs.ND != NIL) {
                continue;
            }
            if (arg_count != 1) {
                word.print("{s}\n", .{s});
            }
            if (rt.rs.exports != NIL) {
                x = rt.rs.exports;
            } else {
                var f = heap.heap.files;
                while (f != NIL) : (f = heap.t(f)) {
                    x = abi.append1(heap.filDefs(heap.h(f)), x);
                }
            }

            if (rt.rs.freeids != NIL) {
                var f = rt.rs.freeids;
                while (f != NIL) : (f = heap.t(f)) {
                    const n = abi.findid(@constCast(main.get_id(heap.h(f))));
                    heap.tp(n).* = heap.t(heap.t(heap.h(f)));
                    heap.tp(heap.h(heap.h(n))).* = heap.theVal(heap.h(f));
                    heap.hp(f).* = n;
                }
                rt.rs.freeids = abi.typesfirst(rt.rs.freeids);
                f = rt.rs.freeids;
                word.print("\t%free {{\n", .{});
                while (f != NIL) : (f = heap.t(f)) {
                    _ = word.putchar('\t');
                    abi.reportType(heap.h(f));
                    _ = word.putchar('\n');
                }
                word.print("\t}}\n", .{});
            }

            var item = abi.typesfirst(heap.alfasort(x));
            while (item != NIL) : (item = heap.t(item)) {
                _ = word.putchar('\t');
                abi.reportType(heap.h(item));
                _ = word.putchar('\n');
            }
        }
        abi.exit(0);
    }

    if (rt.rs.mksources) {
        var s: [*:0]u8 = undefined;
        var x: Word = NIL;
        _ = abi.sigsetjmp(&rt.rs.env, 1);
        var cur_argv_idx = arg_idx;
        while (cur_argv_idx < argc_u) : (cur_argv_idx += 1) {
            s = abi.addextn(1, argv[cur_argv_idx]);
            if (main.fileExists(s)) {
                if (s == ls.dicp) {
                    _ = abi.keep(ls.dicp);
                }
                main.undump(s);
                var f = if (heap.heap.files == NIL) rt.rs.oldfiles else heap.heap.files;
                while (f != NIL) : (f = heap.t(f)) {
                    const filename_str = main.get_fil(heap.h(f)).?;
                    if (abi.member(x, strtab.strBits(filename_str)) == 0) {
                        x = heap.cons(strtab.strBits(filename_str), x);
                        word.print("{s}\n", .{filename_str});
                    }
                }
            }
        }
        abi.exit(0);
    }

    if (rt.rs.making) {
        var s: [*:0]u8 = undefined;
        _ = abi.sigsetjmp(&rt.rs.env, 1);
        var cur_argv_idx = arg_idx;
        while (cur_argv_idx < argc_u) : (cur_argv_idx += 1) {
            s = abi.addextn(1, argv[cur_argv_idx]);
            if (s == ls.dicp) {
                _ = abi.keep(ls.dicp);
            }
            main.undump(s);
            if (cs.ND != NIL or (heap.heap.files == NIL and rt.rs.oldfiles != NIL)) {
                if (rt.rs.make_status == 1) {
                    rt.rs.make_status = 0;
                }
                rt.rs.make_status = abi.strcons(@as(Word, strtab.strBits(s)), rt.rs.make_status);
            }
        }
        if (getTag(rt.rs.make_status) == word.STRCONS) {
            var h_val: Word = 0;
            var maxw: Word = 0;
            word.print("errors or undefined names found in:-\n", .{});
            while (rt.rs.make_status != 0) {
                h_val = abi.strcons(heap.h(rt.rs.make_status), h_val);
                const w = @as(Word, @intCast(word.strlen(strtab.strOf(heap.h(h_val)))));
                if (w > maxw) {
                    maxw = w;
                }
                rt.rs.make_status = heap.t(rt.rs.make_status);
            }
            maxw += 1;
            const n = @divTrunc(@as(Word, 78), maxw);
            var w: Word = 0;
            while (h_val != 0) {
                w += 1;
                const str = strtab.strOf(heap.h(h_val));
                const len = word.strlen(str);
                const spaces_needed = if (@as(usize, @intCast(maxw)) > len) @as(usize, @intCast(maxw)) - len else 0;
                var pad_idx: usize = 0;
                while (pad_idx < spaces_needed) : (pad_idx += 1) {
                    word.print(" ", .{});
                }
                const next_newline = if ((@rem(w, n)) != 0) "" else "\n";
                word.print("{s}{s}", .{ str, next_newline });
                h_val = heap.t(h_val);
            }
            if ((@rem(w, n)) != 0) {
                word.print("\n", .{});
            }
            rt.rs.make_status = 1;
        }
        abi.exit(@intCast(rt.rs.make_status));
    }

    var initscript: [*:0]const u8 = undefined;
    if (remaining_argc == 0) {
        initscript = "script.m";
    } else if (rt.rs.magic) {
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
    if (cs.BAD_DUMP != 0) {
        heap.unload();
        cs.CLASHES = NIL;
        heap.heap.stackp = heap.heap.dstack;
        core_state.s.loading = 0;
        return 0;
    }
    if (cs.CLASHES != NIL) {
        heap.unload();
        core_state.s.loading = 0;
        return 0;
    }
    if (heap.srcUpdate() != 0) {
        main.loadfile(rcfile);
    }
    core_state.s.loading = 0;
    if (cs.ND != NIL or heap.heap.files == NIL) return 0;
    x = heap.filDefs(h(heap.heap.files));
    while (x != NIL) : (x = t(x)) {
        if (heap.idType(h(x)) == word.synonym_t) {
            heap.tp(heap.tInfo(h(x))).* = main.dump.fixtype(heap.tInfo(h(x)), h(x));
        } else {
            heap.tp(h(h(x))).* = main.dump.fixtype(heap.idType(h(x)), h(x));
        }
    }
    return 1;
}

/// Write the current environment to the user's `~/.mirarc` dump.
pub fn writeRc() void {
    const home = abi.getenv("HOME");
    var f: ?*word.FILE = null;
    if (home == null or rt.rs.home_rc[0] == 0) return;
    f = word.fopen(&rt.rs.home_rc, "w");
    if (f == null) return;
    abi.setprefix(@ptrCast(&rt.rs.home_rc));
    abi.dumpScript(heap.heap.files, f.?);
    _ = word.fclose(f.?);
}

/// Abort: command-line flag `s` was given without its required parameter.
pub fn missingParam(s: [:0]const u8) noreturn {
    errors.fatal("mira: missing param after flag \"-%s\"\n", .{.{s.ptr}});
}

/// Check the `.version` file under directory `m`; returns 1 if it matches this build, else records the mismatch for `libFails`.
pub fn checkVersion(m: [*:0]const u8) c_int {
    var path_buf: [1024]u8 = undefined;
    const path = std.fmt.bufPrintSentinel(&path_buf, "{s}/.version", .{m}, 0) catch return 0;
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
///
/// Tests: versionString: formats an integer version as M.mmm
pub fn versionString(v: c_int) [*:0]const u8 {
    if (v < 0 or v > 999999) {
        return "???";
    }
    _ = abi.snprintf(&vbuf, vbuf.len, "%.3f", .{@as(f64, @floatFromInt(v)) / 1000.0});
    return @ptrCast(&vbuf);
}

test "versionString: formats an integer version as M.mmm" {
    try std.testing.expectEqualStrings("2.046", std.mem.span(versionString(2046)));
    try std.testing.expectEqualStrings("0.001", std.mem.span(versionString(1)));
    try std.testing.expectEqualStrings("???", std.mem.span(versionString(-1)));
}

/// Print the release/date line; with `full` set, also the host string and XVERSION.
pub fn versionInfo(full: c_int) void {
    word.print("{s} last revised {s}\n", .{versionString(version.version), version.vdate});
    if (full == 0) return;
    word.print("{s}", .{version.host});
    word.print("XVERSION {}\n", .{@as(c_uint, @intCast(word.XVERSION))});
}
