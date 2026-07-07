//! startup.zig — process entry and one-time bootstrap.
//!
//! `mainEntry` is the program's real `main`: it parses the command line, installs
//! signal handlers, sizes and builds the heap, locates the Miranda library
//! (checking each candidate's `.version`), reads the user's `.mirarc`, and hands
//! off to `commandLoop`. Also holds the version-string formatting and the
//! library-mismatch reporting used during that search.

const std = @import("std");
const word = @import("../graph/word.zig");
const errors = @import("../runtime/errors.zig");
const strtab = @import("../graph/strtab.zig");
const cs = @import("../compiler/compiler_state.zig").cs;
const rt = @import("../runtime/runtime_state.zig");
const abi = @import("../os.zig");

const Word = word.Word;
const NIL = word.NIL;
const CONS = word.CONS;
const h = heap_mod.h;
const t = heap_mod.t;

const lex_state = @import("../parser/lex_state.zig");
const version = @import("../runtime/version.zig");
const reduce = @import("../eval/reduce_rt.zig");
const heap_mod = @import("../runtime/heap.zig");
const Heap = heap_mod.Heap;
const repl = @import("../session/repl.zig");
const commands = @import("../session/commands.zig");
const files = @import("../io/files.zig");
const setup = @import("../compiler/setup.zig");
const signals_mod = @import("../io/signals.zig");
const dump = @import("../compiler/dump.zig");
const core_state = @import("../runtime/core_state.zig");
const EDITOR: [*:0]const u8 = "vi +!";
const lineedit = @import("../session/editor.zig");
const ls = lex_state.ls;

inline fn getTag(heap: *Heap, x: Word) word.NodeTag {
    return heap.getTag(x);
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
    const heap = heap_mod.heap();
    var manonly: Word = 0;
    rt.rs().cstack = @ptrCast(&manonly);
    unlimitStack();
    rt.rs().verbosity = if (abi.isatty(0) != 0) 1 else 0;
    word.setbuf(abi.stdout(), null);

    const okhome_rc = readHomeRc();

    rt.rs().UTF8 = @intFromBool(heap_mod.utf8test());
    rt.rs().UTF8OUT = rt.rs().UTF8;

    const parsed = parseFlags(argc, argv);
    const arg_idx = parsed.arg_idx;
    manonly = parsed.manonly;
    const argc_u = @as(usize, @intCast(argc));

    const remaining_argc = argc_u - arg_idx;
    if (remaining_argc > 1 and !rt.rs().magic and !rt.rs().making) {
        errors.fatal("mira: too many args\n", .{});
    }

    resolveMiralib();

    readLibRcIfNeeded(okhome_rc);

    resolveEnvironmentSettings();

    abi.setupdic();
    rt.rs().s_in = abi.stdin();
    reduce.ev().s_out = abi.stdout();
    rt.rs().miralib = files.makeAbsolute(rt.rs().miralib.?);

    if (manonly != 0) {
        commands.manaction(rt.rs());
        abi.exit(0);
    }

    {
        const miralib_span = std.mem.span(rt.rs().miralib.?);
        @memcpy(rt.rs().PRELUDE[0..miralib_span.len], miralib_span);
        const suffix = "/prelude";
        @memcpy(rt.rs().PRELUDE[miralib_span.len..][0..suffix.len], suffix);
        rt.rs().PRELUDE[miralib_span.len + suffix.len] = 0;
    }
    {
        const miralib_span = std.mem.span(rt.rs().miralib.?);
        @memcpy(rt.rs().STDENV[0..miralib_span.len], miralib_span);
        const suffix = "/stdenv.m";
        @memcpy(rt.rs().STDENV[miralib_span.len..][0..suffix.len], suffix);
        rt.rs().STDENV[miralib_span.len + suffix.len] = 0;
    }

    setup.miraSetup();

    if (rt.rs().verbosity != 0) {
        repl.announce();
    }

    heap.files = NIL;
    dump.undump(heap, core_state.s(), cs(), rt.rs(), @as([*:0]const u8, @ptrCast(&rt.rs().PRELUDE)));
    rt.rs().okprel = true;
    abi.mkprivate(heap, heap_mod.filDefs(heap_mod.h(heap.files)));
    heap.files = NIL;

    if (!rt.rs().nostdenv) {
        dump.undump(heap, core_state.s(), cs(), rt.rs(), @as([*:0]const u8, @ptrCast(&rt.rs().STDENV)));
        while (heap.files != NIL) {
            rt.rs().primenv = heap_mod.alfasort(abi.append1(rt.rs().primenv, heap_mod.filDefs(heap_mod.h(heap.files))));
            heap.files = heap_mod.t(heap.files);
        }
        rt.rs().primenv = heap_mod.alfasort(rt.rs().primenv);
        cs().newtyps = NIL;
        heap.files = NIL;
    }

    if (!rt.rs().magic) {
        writeRc();
    }

    rt.rs().echoing = rt.rs().verbosity & rt.rs().listing;
    rt.rs().initialising = 0;

    if (rt.rs().mkexports) {
        runExportsMode(heap, argc_u, argv, arg_idx);
    }

    if (rt.rs().mksources) {
        runSourcesMode(heap, argc_u, argv, arg_idx);
    }

    if (rt.rs().making) {
        runMakeMode(heap, argc_u, argv, arg_idx);
    }

    var initscript: [*:0]const u8 = undefined;
    if (remaining_argc == 0) {
        initscript = "script.m";
    } else if (rt.rs().magic) {
        initscript = argv[arg_idx];
    } else {
        initscript = abi.addextn(1, argv[arg_idx]);
    }

    if (initscript == ls().dicp) {
        _ = abi.keep(ls().dicp);
    }

    _ = signals_mod.signals(abi.SIGTERM, @intFromPtr(&abi.exit));
    // Interactive stdin gets zigline line editing + history; piped/file stdin
    // keeps the plain read path (so the golden corpus and integration suite run
    // unchanged).
    if (abi.isatty(0) != 0) {
        lineedit.init(rt.allocator, rt.io);
    }
    repl.commandLoop(heap, core_state.s(), cs(), rt.rs(), ls(), @constCast(initscript));
    return 0;
}

/// Reads the user's `$HOME/.mirarc`, if `$HOME` is set. Returns nonzero if it
/// was found and read (in which case the library-directory `.mirarc` is
/// skipped later; see [readLibRcIfNeeded]).
fn readHomeRc() Word {
    const home = abi.getenv("HOME");
    var okhome_rc: Word = 0;
    if (home != null) {
        {
            const home_span = std.mem.span(home.?);
            @memcpy(rt.rs().home_rc[0..home_span.len], home_span);
            rt.rs().home_rc[home_span.len] = 0;
        }
        if (std.mem.eql(u8, std.mem.span(@as([*:0]const u8, @ptrCast(&rt.rs().home_rc))), "/")) {
            rt.rs().home_rc[0] = 0;
        }
        {
            const dst_len = std.mem.len(@as([*:0]const u8, @ptrCast(&rt.rs().home_rc)));
            const suffix = "/.mirarc";
            @memcpy(rt.rs().home_rc[dst_len..][0..suffix.len], suffix);
            rt.rs().home_rc[dst_len + suffix.len] = 0;
        }
        okhome_rc = readRc(@as([*:0]const u8, @ptrCast(&rt.rs().home_rc)));
    }
    return okhome_rc;
}

/// The parsed result of the leading `-flag` run of `argv`: the index of the
/// first non-flag argument, and whether `-man` was given.
const ParsedFlags = struct { arg_idx: usize, manonly: Word };

/// True if the command-line argument `arg` is exactly the flag literal `lit`.
inline fn argIs(arg: [*:0]const u8, lit: []const u8) bool {
    return std.mem.eql(u8, std.mem.span(arg), lit);
}

/// Parses every leading `-flag` (and its parameter, where one is expected) in
/// `argv`, applying each directly to the relevant `rt.rs()`/`ls` global. Stops at
/// the first argument that doesn't start with `-` (or at `-exec`/`-exec2`,
/// which consume the remainder of the command line for the script itself).
fn parseFlags(argc: c_int, argv: [*][*:0]u8) ParsedFlags {
    var manonly: Word = 0;
    var arg_idx: usize = 1;
    const argc_u = @as(usize, @intCast(argc));
    while (arg_idx < argc_u and argv[arg_idx][0] == '-') {
        const arg = argv[arg_idx];
        if (argIs(arg, "-stdenv")) {
            rt.rs().nostdenv = true;
        } else if (argIs(arg, "-count")) {
            rt.rs().atcount = 1;
        } else if (argIs(arg, "-list")) {
            rt.rs().listing = 1;
        } else if (argIs(arg, "-nolist")) {
            rt.rs().listing = 0;
        } else if (argIs(arg, "-nostrictif")) {
            rt.rs().strictif = false;
        } else if (argIs(arg, "-gc")) {
            rt.rs().atgc = 1;
        } else if (argIs(arg, "-object")) {
            rt.rs().atobject = 1;
        } else if (argIs(arg, "-lib")) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                missingParam("lib");
            } else {
                rt.rs().miralib = argv[arg_idx];
            }
        } else if (argIs(arg, "-dic")) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                missingParam("dic");
            } else {
                var val: c_long = 0;
                if (abi.sscanf(argv[arg_idx], "%ld", .{&val}) != 1 or flagOutOfRange(val)) {
                    errors.fatal("mira: bad value after flag \"-dic\"\n", .{});
                }
                rt.rs().DICSPACE = val;
            }
        } else if (argIs(arg, "-heap")) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                missingParam("heap");
            } else {
                var val: c_long = 0;
                if (abi.sscanf(argv[arg_idx], "%ld", .{&val}) != 1 or flagOutOfRange(val)) {
                    errors.fatal("mira: bad value after flag \"-heap\"\n", .{});
                }
                rt.rs().SPACELIMIT = val;
            }
        } else if (argIs(arg, "-editor")) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                missingParam("editor");
            } else {
                rt.rs().editor = argv[arg_idx];
                rt.rs().baded = @intFromBool(repl.badEditor(rt.rs()));
            }
        } else if (argIs(arg, "-hush")) {
            rt.rs().verbosity = 0;
        } else if (argIs(arg, "-nohush")) {
            rt.rs().verbosity = 1;
        } else if (argIs(arg, "-exp") or argIs(arg, "-log")) {
            errors.fatal("mira: obsolete flag \"{s}\"\nuse \"-exec\" or \"-exec2\", see manual\n", .{arg});
        } else if (argIs(arg, "-exec")) {
            ls().ARGC = @intCast(argc - @as(c_int, @intCast(arg_idx)) - 1);
            ls().ARGV = @ptrCast(argv + arg_idx + 1);
            rt.rs().magic = true;
            rt.rs().verbosity = 0;
            arg_idx = argc_u;
            break;
        } else if (argIs(arg, "-exec2")) {
            if (arg_idx + 1 >= argc_u) {
                errors.fatal("incorrect use of -exec2 flag, missing filename\n", .{});
            }
            const filename = argv[arg_idx + 1];
            var p: ?[*:0]u8 = blk: {
                const filename_span = std.mem.span(filename);
                break :blk if (std.mem.lastIndexOfScalar(u8, filename_span, '/')) |idx| filename + idx else null;
            };
            if (p == null) {
                p = filename;
            } else {
                p = p.? + 1;
            }
            const len = std.mem.len(p.?) + 9;
            const slice = rt.allocator.allocSentinel(u8, len, 0) catch {
                abi.mallocfail(@constCast("logfile name"));
                unreachable;
            };
            const logfilname = slice.ptr;
            _ = std.fmt.bufPrintZ(slice, "miralog/{s}", .{p.?}) catch {};
            const fil = word.fopen(logfilname, "a");
            if (fil != null) {
                _ = abi.dup2(word.fileno(fil), 2);
            } else {
                word.printErr("could not open {s}\n", .{logfilname});
            }
            ls().ARGC = @intCast(argc - @as(c_int, @intCast(arg_idx)) - 1);
            ls().ARGV = @ptrCast(argv + arg_idx + 1);
            rt.rs().magic = true;
            rt.rs().verbosity = 0;
            arg_idx = argc_u;
            break;
        } else if (argIs(arg, "-man")) {
            manonly = 1;
        } else if (argIs(arg, "-version")) {
            versionInfo(0);
            abi.exit(0);
        } else if (argIs(arg, "-V")) {
            versionInfo(1);
            abi.exit(0);
        } else if (argIs(arg, "-make")) {
            rt.rs().making = true;
            rt.rs().verbosity = 0;
        } else if (argIs(arg, "-exports")) {
            rt.rs().making = true;
            rt.rs().mkexports = true;
            rt.rs().verbosity = 0;
        } else if (argIs(arg, "-sources")) {
            rt.rs().making = true;
            rt.rs().mksources = true;
            rt.rs().verbosity = 0;
        } else if (argIs(arg, "-UTF-8")) {
            rt.rs().UTF8 = 1;
        } else if (argIs(arg, "-noUTF-8")) {
            rt.rs().UTF8 = 0;
        } else {
            errors.fatal("mira: unknown flag \"{s}\"\n", .{arg});
        }
        arg_idx += 1;
    }
    return .{ .arg_idx = arg_idx, .manonly = manonly };
}

/// Locates the Miranda library directory: `-lib`/`$MIRALIB` if given, else the
/// first of the standard install locations whose `.version` file matches this
/// binary. Exits fatally if none match.
fn resolveMiralib() void {
    var badlib: bool = false;
    if (rt.rs().miralib == null) {
        if (abi.getenv("MIRALIB")) |m| {
            rt.rs().miralib = @constCast(m);
        } else if (checkVersion("/usr/lib/miralib") != 0) {
            rt.rs().miralib = @constCast("/usr/lib/miralib");
        } else if (checkVersion("/usr/local/lib/miralib") != 0) {
            rt.rs().miralib = @constCast("/usr/local/lib/miralib");
        } else if (checkVersion("miralib") != 0) {
            rt.rs().miralib = @constCast("miralib");
        } else {
            badlib = true;
        }
    }

    if (badlib) {
        word.printErr("fatal error: miralib version {s} not found\n", .{versionString(@intCast(version.version))});
        libFails();
        abi.exit(1);
    }
}

/// Reads the library directory's `.mirarc`, but only if the user's own
/// `$HOME/.mirarc` (see [readHomeRc]) wasn't found.
fn readLibRcIfNeeded(okhome_rc: Word) void {
    if (okhome_rc == 0) {
        if (rt.rs().rc_error == @as(?[*:0]const u8, @ptrCast(&rt.rs().lib_rc))) {
            rt.rs().rc_error = null;
        }
        {
            const miralib_span = std.mem.span(rt.rs().miralib.?);
            @memcpy(rt.rs().lib_rc[0..miralib_span.len], miralib_span);
            const suffix = "/.mirarc";
            @memcpy(rt.rs().lib_rc[miralib_span.len..][0..suffix.len], suffix);
            rt.rs().lib_rc[miralib_span.len + suffix.len] = 0;
        }
        _ = readRc(@as([*:0]const u8, @ptrCast(&rt.rs().lib_rc)));
    }
}

/// Resolves the editor (`-editor`/`$EDITOR`/built-in default) and applies the
/// remaining one-shot environment-variable overrides (`$MIRAPROMPT`,
/// `$RECHECKMIRA`, `$NOSTRICTIF`).
fn resolveEnvironmentSettings() void {
    if (rt.rs().editor == null) {
        if (abi.getenv("EDITOR")) |ed| {
            rt.rs().editor = @constCast(ed);
        } else {
            rt.rs().editor = @constCast(EDITOR);
        }
        if (rt.rs().editor != null) {
            {
                const editor_span = std.mem.span(rt.rs().editor.?);
                @memcpy(rt.rs().ebuf[0..editor_span.len], editor_span);
                rt.rs().ebuf[editor_span.len] = 0;
            }
            rt.rs().editor = @as([*:0]u8, @ptrCast(&rt.rs().ebuf));
            rt.rs().baded = @intFromBool(repl.badEditor(rt.rs()));
        }
    }

    if (abi.getenv("MIRAPROMPT")) |prs| {
        rt.rs().promptstr = prs;
    }

    if (abi.getenv("RECHECKMIRA") != null and rt.rs().rechecking == 0) {
        rt.rs().rechecking = 1;
    }

    if (abi.getenv("NOSTRICTIF") != null) {
        rt.rs().strictif = false;
    }
}

/// `-exports` mode: undumps each remaining argument and reports its export
/// list (or all top-level definitions, if it has none), plus any `%free`
/// declarations. Exits the process when done.
fn runExportsMode(heap: *Heap, argc_u: usize, argv: [*][*:0]u8, arg_idx: usize) void {
    const arg_count: usize = argc_u - arg_idx;
    var s: [*:0]u8 = undefined;
    var cur_argv_idx = arg_idx;
    while (cur_argv_idx < argc_u) : (cur_argv_idx += 1) {
        var x: Word = NIL;
        s = abi.addextn(1, argv[cur_argv_idx]);
        if (s == ls().dicp) {
            _ = abi.keep(ls().dicp);
        }
        dump.undump(heap, core_state.s(), cs(), rt.rs(), s);
        if (heap.files == NIL or cs().ND != NIL) {
            continue;
        }
        if (arg_count != 1) {
            word.print("{s}\n", .{s});
        }
        if (rt.rs().exports != NIL) {
            x = rt.rs().exports;
        } else {
            var f = heap.files;
            while (f != NIL) : (f = heap_mod.t(f)) {
                x = abi.append1(heap_mod.filDefs(heap_mod.h(f)), x);
            }
        }

        if (rt.rs().freeids != NIL) {
            var f = rt.rs().freeids;
            while (f != NIL) : (f = heap_mod.t(f)) {
                const n = abi.findid(heap, @constCast(heap_mod.getId(heap_mod.h(f))));
                heap_mod.tp(n).* = heap_mod.t(heap_mod.t(heap_mod.h(f)));
                heap_mod.tp(heap_mod.h(heap_mod.h(n))).* = heap_mod.theVal(heap_mod.h(f));
                heap_mod.hp(f).* = n;
            }
            rt.rs().freeids = abi.typesfirst(heap, rt.rs().freeids);
            f = rt.rs().freeids;
            word.print("\t%free {{\n", .{});
            while (f != NIL) : (f = heap_mod.t(f)) {
                _ = word.putchar('\t');
                abi.reportType(heap, heap_mod.h(f));
                _ = word.putchar('\n');
            }
            word.print("\t}}\n", .{});
        }

        var item = abi.typesfirst(heap, heap_mod.alfasort(x));
        while (item != NIL) : (item = heap_mod.t(item)) {
            _ = word.putchar('\t');
            abi.reportType(heap, heap_mod.h(item));
            _ = word.putchar('\n');
        }
    }
    abi.exit(0);
}

/// `-sources` mode: undumps each remaining argument and lists the distinct
/// source filenames it depends on. Exits the process when done.
fn runSourcesMode(heap: *Heap, argc_u: usize, argv: [*][*:0]u8, arg_idx: usize) void {
    var s: [*:0]u8 = undefined;
    var x: Word = NIL;
    var cur_argv_idx = arg_idx;
    while (cur_argv_idx < argc_u) : (cur_argv_idx += 1) {
        s = abi.addextn(1, argv[cur_argv_idx]);
        if (files.fileExists(s)) {
            if (s == ls().dicp) {
                _ = abi.keep(ls().dicp);
            }
            dump.undump(heap, core_state.s(), cs(), rt.rs(), s);
            var f = if (heap.files == NIL) rt.rs().oldfiles else heap.files;
            while (f != NIL) : (f = heap_mod.t(f)) {
                const filename_str = heap_mod.getFil(heap_mod.h(f)).?;
                if (abi.member(heap, x, strtab.strBits(strtab.table(), filename_str)) == 0) {
                    x = heap_mod.cons(strtab.strBits(strtab.table(), filename_str), x);
                    word.print("{s}\n", .{filename_str});
                }
            }
        }
    }
    abi.exit(0);
}

/// `-make` mode: undumps each remaining argument, collecting any that have
/// errors or undefined names into `rt.rs().make_status`; reports them (see
/// [reportMakeFailures]) and exits the process with the resulting status.
fn runMakeMode(heap: *Heap, argc_u: usize, argv: [*][*:0]u8, arg_idx: usize) void {
    var s: [*:0]u8 = undefined;
    var cur_argv_idx = arg_idx;
    while (cur_argv_idx < argc_u) : (cur_argv_idx += 1) {
        s = abi.addextn(1, argv[cur_argv_idx]);
        if (s == ls().dicp) {
            _ = abi.keep(ls().dicp);
        }
        dump.undump(heap, core_state.s(), cs(), rt.rs(), s);
        if (cs().ND != NIL or (heap.files == NIL and rt.rs().oldfiles != NIL)) {
            if (rt.rs().make_status == 1) {
                rt.rs().make_status = 0;
            }
            rt.rs().make_status = abi.strcons(@as(Word, strtab.strBits(strtab.table(), s)), rt.rs().make_status);
        }
    }
    if (getTag(heap, rt.rs().make_status) == .STRCONS) {
        reportMakeFailures();
    }
    abi.exit(@intCast(rt.rs().make_status));
}

/// Prints the `-make` failure list (`rt.rs().make_status`) as a padded,
/// multi-column table, then resets it to the generic nonzero status `1`.
fn reportMakeFailures() void {
    var h_val: Word = 0;
    var maxw: Word = 0;
    word.print("errors or undefined names found in:-\n", .{});
    while (rt.rs().make_status != 0) {
        h_val = abi.strcons(heap_mod.h(rt.rs().make_status), h_val);
        const w = @as(Word, @intCast(std.mem.len(strtab.strOf(strtab.table(), heap_mod.h(h_val)))));
        if (w > maxw) {
            maxw = w;
        }
        rt.rs().make_status = heap_mod.t(rt.rs().make_status);
    }
    maxw += 1;
    const n = @max(@as(Word, 1), @divTrunc(@as(Word, 78), maxw));
    var w: Word = 0;
    while (h_val != 0) {
        w += 1;
        const str = strtab.strOf(strtab.table(), heap_mod.h(h_val));
        const len = std.mem.len(str);
        const spaces_needed = if (@as(usize, @intCast(maxw)) > len) @as(usize, @intCast(maxw)) - len else 0;
        var pad_idx: usize = 0;
        while (pad_idx < spaces_needed) : (pad_idx += 1) {
            word.print(" ", .{});
        }
        const next_newline = if ((@rem(w, n)) != 0) "" else "\n";
        word.print("{s}{s}", .{ str, next_newline });
        h_val = heap_mod.t(h_val);
    }
    if ((@rem(w, n)) != 0) {
        word.print("\n", .{});
    }
    rt.rs().make_status = 1;
}

/// Load the saved `.mirarc` dump `rcfile`. Returns 1 on success, 0 on failure.
pub fn readRc(rcfile: [*:0]const u8) Word {
    var z: [20]u8 = undefined;
    @memset(&z, 0);
    var h_val: c_long = 0;
    var d_val: c_long = 0;
    var v_val: c_long = 0;
    var s_val: c_long = 0;
    var r: Word = 0;

    const in = word.fopen(rcfile, "r") orelse return 0;
    defer _ = word.fclose(in);

    if (abi.fscanf(in, "%19s", .{@as([*c]u8, @ptrCast(&z))}) != 1) {
        return 0;
    }
    const z_ptr: [*:0]const u8 = @ptrCast(&z);
    const z_slice = std.mem.span(z_ptr);
    if (std.mem.startsWith(u8, z_slice, "hdve") or std.mem.eql(u8, z_slice, "lhdve")) {
        var z1 = @as([*]u8, @ptrCast(&z)) + 3;
        if (z[0] == 'l') {
            rt.rs().listing = 1;
            z1 += 1;
        }
        z1 += 1;
        while (z1[0] != 0) : (z1 += 1) {
            switch (z1[0]) {
                'l' => rt.rs().listing = 1,
                's' => {},
                'r' => rt.rs().rechecking = 2,
                else => rt.rs().rc_error = rcfile,
            }
        }

        const read_ok = blk: {
            if (abi.fscanf(in, "%ld%ld%ld%*c", .{ &h_val, &d_val, &v_val }) != 3) break :blk false;
            if (repl.getLine(in, rt.rs().ebuf.len - 1, @ptrCast(&rt.rs().ebuf)) == 0) break :blk false;
            if (flagOutOfRange(h_val) or flagOutOfRange(d_val) or flagOutOfRange(v_val)) break :blk false;
            break :blk true;
        };
        if (!read_ok) {
            rt.rs().rc_error = rcfile;
        } else {
            var len = std.mem.len(@as([*:0]const u8, @ptrCast(&rt.rs().ebuf)));
            if (len > 0 and rt.rs().ebuf[len - 1] == '\n') {
                rt.rs().ebuf[len - 1] = 0;
                len -= 1;
            }
            rt.rs().editor = @ptrCast(&rt.rs().ebuf);
            rt.rs().SPACELIMIT = h_val;
            rt.rs().DICSPACE = d_val;
            r = 1;
        }
    } else if (std.mem.eql(u8, z_slice, "ehdsv")) {
        const read_ok = blk: {
            if (abi.fscanf(in, "%19s%ld%ld%ld%ld", .{ &rt.rs().ebuf, &h_val, &d_val, &s_val, &v_val }) != 5) break :blk false;
            if (flagOutOfRange(h_val) or flagOutOfRange(d_val) or flagOutOfRange(v_val)) break :blk false;
            break :blk true;
        };
        if (!read_ok) {
            rt.rs().rc_error = rcfile;
        } else {
            rt.rs().editor = @ptrCast(&rt.rs().ebuf);
            rt.rs().SPACELIMIT = h_val;
            rt.rs().DICSPACE = d_val;
            r = 1;
        }
    } else if (std.mem.eql(u8, z_slice, "ehds")) {
        const read_ok = blk: {
            if (abi.fscanf(in, "%1023s%ld%ld%ld", .{ &rt.rs().ebuf, &h_val, &d_val, &s_val }) != 4) break :blk false;
            if (flagOutOfRange(h_val) or flagOutOfRange(d_val)) break :blk false;
            break :blk true;
        };
        if (!read_ok) {
            rt.rs().rc_error = rcfile;
        } else {
            rt.rs().editor = @ptrCast(&rt.rs().ebuf);
            rt.rs().SPACELIMIT = h_val;
            rt.rs().DICSPACE = d_val;
            r = 1;
        }
    } else {
        rt.rs().rc_error = rcfile;
    }
    if (rt.rs().editor != null) {
        rt.rs().baded = @intFromBool(repl.badEditor(rt.rs()));
    }
    return r;
}

/// Write the current environment to the user's `~/.mirarc` config file.
pub fn writeRc() void {
    if (rt.rs().home_rc[0] == 0) return;
    const f = word.fopen(&rt.rs().home_rc, "w") orelse {
        word.printErr("warning: cannot write to \"{s}\"\n", .{std.mem.span(@as([*:0]const u8, @ptrCast(&rt.rs().home_rc)))});
        return;
    };
    defer _ = word.fclose(f);

    _ = word.fprint(f, "hdve", .{});
    if (rt.rs().listing != 0) {
        _ = word.fprint(f, "l", .{});
    }
    if (rt.rs().rechecking == 2) {
        _ = word.fprint(f, "r", .{});
    }
    _ = word.fprint(f, " {} {} {} {s}\n", .{ rt.rs().SPACELIMIT, rt.rs().DICSPACE, version.version, rt.rs().editor orelse @constCast("") });
}

/// Abort: command-line flag `s` was given without its required parameter.
pub fn missingParam(s: [:0]const u8) noreturn {
    errors.fatal("mira: missing param after flag \"-{s}\"\n", .{s});
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
        if (rt.rs().mvp < 4) {
            rt.rs().mstack[rt.rs().mvp] = m;
            rt.rs().vstack[rt.rs().mvp] = @intCast(v1);
            rt.rs().mvp += 1;
        }
    }
    return r;
}

/// Report the library version mismatches collected by `checkVersion`.
pub fn libFails() void {
    word.printErr("found", .{});
    var i: usize = 0;
    while (i < rt.rs().mvp) : (i += 1) {
        word.printErr("\tversion {s} at: {s}\n", .{ versionString(rt.rs().vstack[i]), rt.rs().mstack[i] });
    }
}

/// Format integer version `v` as an `M.mmm` string (`???` if out of range).
///
/// Tests: versionString: formats an integer version as M.mmm
pub fn versionString(v: c_int) [*:0]const u8 {
    if (v < 0 or v > 999999) {
        return "???";
    }
    // Was `abi.snprintf(..., "%.3f", ...)` -- os.zig's formatC engine
    // discards the precision for every float specifier (confirmed this
    // session while converting runtime/reducer/ready.zig's showfloat/
    // showscaled; see formatMiraFixed's doc comment there), always doing
    // Zig's own round-trip `{d}` regardless -- a real, pre-existing,
    // trailing-zero-dropping bug the old two-case test happened not to
    // exercise (2046/1000 and 1/1000 both round-trip without trailing
    // zeros anyway). Fixed with Zig's own fixed-precision formatting.
    const buf: []u8 = &rt.rs().vbuf;
    _ = std.fmt.bufPrintZ(buf, "{d:.3}", .{@as(f64, @floatFromInt(v)) / 1000.0}) catch {};
    return @ptrCast(&rt.rs().vbuf);
}

test "versionString: formats an integer version as M.mmm" {
    try std.testing.expectEqualStrings("2.046", std.mem.span(versionString(2046)));
    try std.testing.expectEqualStrings("0.001", std.mem.span(versionString(1)));
    // Regression: a value whose fixed-3-decimal form has trailing zeros --
    // the exact case the old %.3f-that-ignored-precision bug dropped.
    try std.testing.expectEqualStrings("2.000", std.mem.span(versionString(2000)));
    try std.testing.expectEqualStrings("???", std.mem.span(versionString(-1)));
}

/// Print the release/date line; with `full` set, also the host string and XVERSION.
pub fn versionInfo(full: c_int) void {
    word.print("{s} last revised {s}\n", .{ versionString(version.version), version.vdate });
    if (full == 0) return;
    word.print("{s}", .{version.host});
    word.print("XVERSION {}\n", .{@as(c_uint, @intCast(word.XVERSION))});
}

test "readRc and writeRc roundtrip text config" {
    const test_filename = "test_mirarc_temp";
    const test_path: [*:0]const u8 = test_filename;

    // Create the test .mirarc file with content
    {
        const f = word.fopen(test_path, "w") orelse return error.OpenFileFailed;
        defer _ = word.fclose(f);
        _ = word.fprint(f, "hdve 2500000 100000 2067 vi +!\n", .{});
    }
    defer _ = abi.unlink(test_path);

    // Save previous values
    const prev_limit = rt.rs().SPACELIMIT;
    const prev_dic = rt.rs().DICSPACE;
    const prev_editor = rt.rs().editor;
    const prev_listing = rt.rs().listing;
    const prev_rechecking = rt.rs().rechecking;
    defer {
        rt.rs().SPACELIMIT = prev_limit;
        rt.rs().DICSPACE = prev_dic;
        rt.rs().editor = prev_editor;
        rt.rs().listing = prev_listing;
        rt.rs().rechecking = prev_rechecking;
    }

    // Now call readRc
    const res = readRc(test_path);
    try std.testing.expectEqual(@as(Word, 1), res);
    try std.testing.expectEqual(@as(Word, 2500000), rt.rs().SPACELIMIT);
    try std.testing.expectEqual(@as(Word, 100000), rt.rs().DICSPACE);
    try std.testing.expectEqualStrings("vi +!", std.mem.span(rt.rs().editor.?));

    // Change settings and write
    rt.rs().SPACELIMIT = 3000000;
    rt.rs().DICSPACE = 150000;
    rt.rs().listing = 1;
    rt.rs().rechecking = 2;
    rt.rs().editor = @constCast("emacs +! %");

    // Set rt.rs().home_rc to our path so writeRc writes to it
    {
        const test_path_span = std.mem.span(test_path);
        @memcpy(rt.rs().home_rc[0..test_path_span.len], test_path_span);
        rt.rs().home_rc[test_path_span.len] = 0;
    }

    writeRc();

    // Verify file content
    {
        const f = word.fopen(test_path, "r") orelse return error.OpenFileFailed;
        defer _ = word.fclose(f);
        var buf: [256]u8 = undefined;
        @memset(&buf, 0);
        _ = repl.getLine(f, buf.len - 1, &buf);
        const file_content = std.mem.sliceTo(&buf, 0);
        try std.testing.expectEqualStrings("hdvelr 3000000 150000 2067 emacs +! %\n", file_content);
    }
}

/// Write `content` to a fresh temp `.mirarc`-style file, call `readRc` on it,
/// and return the result -- shared by the legacy-format tests below.
fn readRcFromContent(content: [*:0]const u8) !Word {
    const test_path: [*:0]const u8 = "test_mirarc_legacy_temp";
    {
        const f = word.fopen(test_path, "w") orelse return error.OpenFileFailed;
        defer _ = word.fclose(f);
        _ = word.fprint(f, "{s}", .{content});
    }
    defer _ = abi.unlink(test_path);
    return readRc(test_path);
}

test "readRc: \"lhdve\" sets the listing flag in addition to hdve's fields" {
    const prev_limit = rt.rs().SPACELIMIT;
    const prev_dic = rt.rs().DICSPACE;
    const prev_editor = rt.rs().editor;
    const prev_listing = rt.rs().listing;
    defer {
        rt.rs().SPACELIMIT = prev_limit;
        rt.rs().DICSPACE = prev_dic;
        rt.rs().editor = prev_editor;
        rt.rs().listing = prev_listing;
    }

    const res = try readRcFromContent("lhdve 2500000 100000 2067 vi\n");
    try std.testing.expectEqual(@as(Word, 1), res);
    try std.testing.expectEqual(@as(Word, 1), rt.rs().listing);
    try std.testing.expectEqual(@as(Word, 2500000), rt.rs().SPACELIMIT);
    try std.testing.expectEqual(@as(Word, 100000), rt.rs().DICSPACE);
    try std.testing.expectEqualStrings("vi", std.mem.span(rt.rs().editor.?));
}

test "readRc: \"hdve\" with an \"r\" flag sets rechecking" {
    const prev_rechecking = rt.rs().rechecking;
    defer rt.rs().rechecking = prev_rechecking;

    const res = try readRcFromContent("hdver 2500000 100000 2067 vi\n");
    try std.testing.expectEqual(@as(Word, 1), res);
    try std.testing.expectEqual(@as(Word, 2), rt.rs().rechecking);
}

test "readRc: legacy \"ehdsv\" format (editor before the numeric fields)" {
    const prev_limit = rt.rs().SPACELIMIT;
    const prev_dic = rt.rs().DICSPACE;
    const prev_editor = rt.rs().editor;
    defer {
        rt.rs().SPACELIMIT = prev_limit;
        rt.rs().DICSPACE = prev_dic;
        rt.rs().editor = prev_editor;
    }

    // ehdsv's editor token is read via a plain %s (no getLine), so it can't
    // contain spaces -- a single-word editor name, unlike hdve's.
    const res = try readRcFromContent("ehdsv vi 2500000 100000 80 2067\n");
    try std.testing.expectEqual(@as(Word, 1), res);
    try std.testing.expectEqual(@as(Word, 2500000), rt.rs().SPACELIMIT);
    try std.testing.expectEqual(@as(Word, 100000), rt.rs().DICSPACE);
    try std.testing.expectEqualStrings("vi", std.mem.span(rt.rs().editor.?));
}

test "readRc: legacy \"ehds\" format (no version field)" {
    const prev_limit = rt.rs().SPACELIMIT;
    const prev_dic = rt.rs().DICSPACE;
    const prev_editor = rt.rs().editor;
    defer {
        rt.rs().SPACELIMIT = prev_limit;
        rt.rs().DICSPACE = prev_dic;
        rt.rs().editor = prev_editor;
    }

    const res = try readRcFromContent("ehds emacs 2500000 100000 80\n");
    try std.testing.expectEqual(@as(Word, 1), res);
    try std.testing.expectEqual(@as(Word, 2500000), rt.rs().SPACELIMIT);
    try std.testing.expectEqual(@as(Word, 100000), rt.rs().DICSPACE);
    try std.testing.expectEqualStrings("emacs", std.mem.span(rt.rs().editor.?));
}

test "readRc: unrecognised header sets rc_error and returns 0" {
    const prev_rc_error = rt.rs().rc_error;
    defer rt.rs().rc_error = prev_rc_error;
    rt.rs().rc_error = null;

    const res = try readRcFromContent("garbage 1 2 3\n");
    try std.testing.expectEqual(@as(Word, 0), res);
    try std.testing.expect(rt.rs().rc_error != null);
}
