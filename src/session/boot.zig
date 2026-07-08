//! boot.zig (split from driver/startup.zig, Phase 4 step 3,
//! docs/ZIG_NATIVE_PLAN.md) — process entry, miralib resolution, the version
//! mismatch stack, and the batch CLI modes (`-exports`/`-sources`/`-make`).
//! `config.zig` holds flag parsing and `.mirarc` I/O; `mainEntry` drives both.

const std = @import("std");
const word = @import("../graph/word.zig");
const errors = @import("../runtime/errors.zig");
const strtab = @import("../graph/strtab.zig");
const cs = @import("../compiler/compiler_state.zig").cs;
const rt = @import("../runtime/runtime_state.zig");
const script_store = @import("script_store.zig");
const config_state = @import("config_state.zig");
const repl_session = @import("repl_session.zig");
const make_state = @import("make_state.zig");
const abi = @import("../os.zig");

const Word = word.Word;
const NIL = word.NIL;
const CONS = word.CONS;
const h = heap_mod.h;
const t = heap_mod.t;

const lex_state = @import("../parser/lex_state.zig");
const version = @import("../runtime/version.zig");
const reduce = @import("../eval/reduce_rt.zig");
const heap_mod = @import("../graph/heap.zig");
const depend_mod = @import("../semantics/depend.zig");
const Heap = heap_mod.Heap;
const repl = @import("repl.zig");
const commands = @import("commands.zig");
const files = @import("../io/files.zig");
const setup = @import("../compiler/setup.zig");
const signals_mod = @import("../io/signals.zig");
const dump = @import("../compiler/dump.zig");
const core_state = @import("../runtime/core_state.zig");
const lineedit = @import("editor.zig");
const config = @import("config.zig");
const ls = lex_state.ls;

inline fn getTag(heap: *Heap, x: Word) word.NodeTag {
    return heap.getTag(x);
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
    repl_session.session().verbosity = if (abi.isatty(0) != 0) 1 else 0;
    word.setbuf(abi.stdout(), null);

    const okhome_rc = config.readHomeRc();

    rt.rs().UTF8 = @intFromBool(heap_mod.utf8test());
    rt.rs().UTF8OUT = rt.rs().UTF8;

    const parsed = config.parseFlags(argc, argv);
    const arg_idx = parsed.arg_idx;
    manonly = parsed.manonly;
    const argc_u = @as(usize, @intCast(argc));

    const remaining_argc = argc_u - arg_idx;
    if (remaining_argc > 1 and !rt.rs().magic and !make_state.make().making) {
        errors.fatal("mira: too many args\n", .{});
    }

    resolveMiralib();

    config.readLibRcIfNeeded(okhome_rc);

    config.resolveEnvironmentSettings();

    abi.setupdic();
    config_state.config().s_in = abi.stdin();
    reduce.ev().s_out = abi.stdout();
    config_state.config().miralib = files.makeAbsolute(config_state.config().miralib.?);

    if (manonly != 0) {
        commands.manaction(rt.rs());
        abi.exit(0);
    }

    {
        const miralib_span = std.mem.span(config_state.config().miralib.?);
        @memcpy(config_state.config().PRELUDE[0..miralib_span.len], miralib_span);
        const suffix = "/prelude";
        @memcpy(config_state.config().PRELUDE[miralib_span.len..][0..suffix.len], suffix);
        config_state.config().PRELUDE[miralib_span.len + suffix.len] = 0;
    }
    {
        const miralib_span = std.mem.span(config_state.config().miralib.?);
        @memcpy(config_state.config().STDENV[0..miralib_span.len], miralib_span);
        const suffix = "/stdenv.m";
        @memcpy(config_state.config().STDENV[miralib_span.len..][0..suffix.len], suffix);
        config_state.config().STDENV[miralib_span.len + suffix.len] = 0;
    }

    setup.miraSetup();

    if (repl_session.session().verbosity != 0) {
        repl.announce();
    }

    heap.files = NIL;
    dump.undump(heap, core_state.s(), cs(), rt.rs(), @as([*:0]const u8, @ptrCast(&config_state.config().PRELUDE)));
    config_state.config().okprel = true;
    abi.mkprivate(heap, heap_mod.filDefs(heap_mod.h(heap, heap.files)));
    heap.files = NIL;

    if (!config_state.config().nostdenv) {
        dump.undump(heap, core_state.s(), cs(), rt.rs(), @as([*:0]const u8, @ptrCast(&config_state.config().STDENV)));
        while (heap.files != NIL) {
            rt.rs().primenv = depend_mod.alfasort(heap, abi.append1(rt.rs().primenv, heap_mod.filDefs(heap_mod.h(heap, heap.files))));
            heap.files = heap_mod.t(heap, heap.files);
        }
        rt.rs().primenv = depend_mod.alfasort(heap, rt.rs().primenv);
        cs().newtyps = NIL;
        heap.files = NIL;
    }

    if (!rt.rs().magic) {
        config.writeRc();
    }

    repl_session.session().echoing = repl_session.session().verbosity & repl_session.session().listing;
    rt.rs().initialising = 0;

    if (make_state.make().mkexports) {
        runExportsMode(heap, argc_u, argv, arg_idx);
    }

    if (make_state.make().mksources) {
        runSourcesMode(heap, argc_u, argv, arg_idx);
    }

    if (make_state.make().making) {
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

/// Locates the Miranda library directory: `-lib`/`$MIRALIB` if given, else the
/// first of the standard install locations whose `.version` file matches this
/// binary. Exits fatally if none match.
fn resolveMiralib() void {
    var badlib: bool = false;
    if (config_state.config().miralib == null) {
        if (abi.getenv("MIRALIB")) |m| {
            config_state.config().miralib = @constCast(m);
        } else if (checkVersion("/usr/lib/miralib") != 0) {
            config_state.config().miralib = @constCast("/usr/lib/miralib");
        } else if (checkVersion("/usr/local/lib/miralib") != 0) {
            config_state.config().miralib = @constCast("/usr/local/lib/miralib");
        } else if (checkVersion("miralib") != 0) {
            config_state.config().miralib = @constCast("miralib");
        } else {
            badlib = true;
        }
    }

    if (badlib) {
        word.printErr("fatal error: miralib version {s} not found\n", .{config.versionString(@intCast(version.version))});
        libFails();
        abi.exit(1);
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
        if (script_store.store().exports != NIL) {
            x = script_store.store().exports;
        } else {
            var f = heap.files;
            while (f != NIL) : (f = heap_mod.t(heap, f)) {
                x = abi.append1(heap_mod.filDefs(heap_mod.h(heap, f)), x);
            }
        }

        if (script_store.store().freeids != NIL) {
            var f = script_store.store().freeids;
            while (f != NIL) : (f = heap_mod.t(heap, f)) {
                const n = abi.findid(heap, @constCast(heap_mod.getId(heap_mod.h(heap, f))));
                heap_mod.tp(heap, n).* = heap_mod.t(heap, heap_mod.t(heap, heap_mod.h(heap, f)));
                heap_mod.tp(heap, heap_mod.h(heap, heap_mod.h(heap, n))).* = heap_mod.theVal(heap_mod.h(heap, f));
                heap_mod.hp(heap, f).* = n;
            }
            script_store.store().freeids = abi.typesfirst(heap, script_store.store().freeids);
            f = script_store.store().freeids;
            word.print("\t%free {{\n", .{});
            while (f != NIL) : (f = heap_mod.t(heap, f)) {
                _ = word.putchar('\t');
                abi.reportType(heap, heap_mod.h(heap, f));
                _ = word.putchar('\n');
            }
            word.print("\t}}\n", .{});
        }

        var item = abi.typesfirst(heap, depend_mod.alfasort(heap, x));
        while (item != NIL) : (item = heap_mod.t(heap, item)) {
            _ = word.putchar('\t');
            abi.reportType(heap, heap_mod.h(heap, item));
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
            var f = if (heap.files == NIL) script_store.store().oldfiles else heap.files;
            while (f != NIL) : (f = heap_mod.t(heap, f)) {
                const filename_str = heap_mod.getFil(heap_mod.h(heap, f)).?;
                if (abi.member(heap, x, strtab.strBits(strtab.table(), filename_str)) == 0) {
                    x = heap_mod.cons(heap, strtab.strBits(strtab.table(), filename_str), x);
                    word.print("{s}\n", .{filename_str});
                }
            }
        }
    }
    abi.exit(0);
}

/// `-make` mode: undumps each remaining argument, collecting any that have
/// errors or undefined names into `make_state.make().make_status`; reports them (see
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
        if (cs().ND != NIL or (heap.files == NIL and script_store.store().oldfiles != NIL)) {
            if (make_state.make().make_status == 1) {
                make_state.make().make_status = 0;
            }
            make_state.make().make_status = abi.strcons(heap, @as(Word, strtab.strBits(strtab.table(), s)), make_state.make().make_status);
        }
    }
    if (getTag(heap, make_state.make().make_status) == .STRCONS) {
        reportMakeFailures(heap);
    }
    abi.exit(@intCast(make_state.make().make_status));
}

/// Reports the accumulated `-make` failures (see [runMakeMode]) as a
/// column-wrapped listing of filenames, then resets `make_status` to 1.
fn reportMakeFailures(heap: *Heap) void {
    var h_val: Word = 0;
    var maxw: Word = 0;
    word.print("errors or undefined names found in:-\n", .{});
    while (make_state.make().make_status != 0) {
        h_val = abi.strcons(heap, heap_mod.h(heap, make_state.make().make_status), h_val);
        const w = @as(Word, @intCast(std.mem.len(strtab.strOf(strtab.table(), heap_mod.h(heap, h_val)))));
        if (w > maxw) {
            maxw = w;
        }
        make_state.make().make_status = heap_mod.t(heap, make_state.make().make_status);
    }
    maxw += 1;
    const n = @max(@as(Word, 1), @divTrunc(@as(Word, 78), maxw));
    var w: Word = 0;
    while (h_val != 0) {
        w += 1;
        const str = strtab.strOf(strtab.table(), heap_mod.h(heap, h_val));
        const len = std.mem.len(str);
        const spaces_needed = if (@as(usize, @intCast(maxw)) > len) @as(usize, @intCast(maxw)) - len else 0;
        var pad_idx: usize = 0;
        while (pad_idx < spaces_needed) : (pad_idx += 1) {
            word.print(" ", .{});
        }
        const next_newline = if ((@rem(w, n)) != 0) "" else "\n";
        word.print("{s}{s}", .{ str, next_newline });
        h_val = heap_mod.t(heap, h_val);
    }
    if ((@rem(w, n)) != 0) {
        word.print("\n", .{});
    }
    make_state.make().make_status = 1;
}

/// Check the `.version` file under directory `m`; returns 1 if it matches this build, else records the mismatch for `libFails`.
fn checkVersion(m: [*:0]const u8) c_int {
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
fn libFails() void {
    word.printErr("found", .{});
    var i: usize = 0;
    while (i < rt.rs().mvp) : (i += 1) {
        word.printErr("\tversion {s} at: {s}\n", .{ config.versionString(rt.rs().vstack[i]), rt.rs().mstack[i] });
    }
}
