//! config.zig (split from driver/startup.zig, Phase 4 step 3,
//! docs/ZIG_NATIVE_PLAN.md) — command-line flag parsing and `.mirarc`
//! read/write. `boot.zig` drives these during `mainEntry`; nothing here
//! depends on `boot.zig` (a deliberate one-directional split: `boot.zig`
//! calls into `config.zig` for `versionString` in its miralib-not-found
//! message, not the other way around).

const std = @import("std");
const word = @import("../graph/word.zig");
const errors = @import("../runtime/errors.zig");
const rt = @import("../runtime/runtime_state.zig");
const config_state = @import("config_state.zig");
const repl_session = @import("repl_session.zig");
const make_state = @import("make_state.zig");
const abi = @import("../os.zig");

const Word = word.Word;

const lex_state = @import("../parser/lex_state.zig");
const version = @import("../runtime/version.zig");
const repl = @import("repl.zig");
const ls = lex_state.ls;
const EDITOR: [*:0]const u8 = "vi +!";

/// True if a numeric command-line flag value is outside the accepted range (100 .. 50,000,000).
fn flagOutOfRange(x: Word) bool {
    return x < 100 or x > 50000000;
}

/// The parsed result of the leading `-flag` run of `argv`: the index of the
/// first non-flag argument, and whether `-man` was given.
const ParsedFlags = struct { arg_idx: usize, manonly: Word };

/// True if the command-line argument `arg` is exactly the flag literal `lit`.
inline fn argIs(arg: [*:0]const u8, lit: []const u8) bool {
    return std.mem.eql(u8, std.mem.span(arg), lit);
}

/// Parses every leading `-flag` (and its parameter, where one is expected) in
/// `argv`, setting the corresponding `RuntimeState` fields. Returns the index
/// of the first non-flag argument and whether `-man` was seen. `-version`/`-V`
/// print and exit directly; `-exec`/`-exec2` stop flag parsing at the script
/// name (everything after belongs to the script's own argv).
pub fn parseFlags(argc: c_int, argv: [*][*:0]u8) ParsedFlags {
    var manonly: Word = 0;
    var arg_idx: usize = 1;
    const argc_u = @as(usize, @intCast(argc));
    while (arg_idx < argc_u and argv[arg_idx][0] == '-') {
        const arg = argv[arg_idx];
        if (argIs(arg, "-stdenv")) {
            config_state.config().nostdenv = true;
        } else if (argIs(arg, "-count")) {
            rt.rs().atcount = 1;
        } else if (argIs(arg, "-list")) {
            repl_session.session().listing = 1;
        } else if (argIs(arg, "-nolist")) {
            repl_session.session().listing = 0;
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
                config_state.config().miralib = argv[arg_idx];
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
                config_state.config().DICSPACE = val;
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
                config_state.config().SPACELIMIT = val;
            }
        } else if (argIs(arg, "-editor")) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                missingParam("editor");
            } else {
                config_state.config().editor = argv[arg_idx];
                config_state.config().baded = @intFromBool(repl.badEditor(rt.rs()));
            }
        } else if (argIs(arg, "-hush")) {
            repl_session.session().verbosity = 0;
        } else if (argIs(arg, "-nohush")) {
            repl_session.session().verbosity = 1;
        } else if (argIs(arg, "-exp") or argIs(arg, "-log")) {
            errors.fatal("mira: obsolete flag \"{s}\"\nuse \"-exec\" or \"-exec2\", see manual\n", .{arg});
        } else if (argIs(arg, "-exec")) {
            ls().ARGC = @intCast(argc - @as(c_int, @intCast(arg_idx)) - 1);
            ls().ARGV = @ptrCast(argv + arg_idx + 1);
            rt.rs().magic = true;
            repl_session.session().verbosity = 0;
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
            repl_session.session().verbosity = 0;
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
            make_state.make().making = true;
            repl_session.session().verbosity = 0;
        } else if (argIs(arg, "-exports")) {
            make_state.make().making = true;
            make_state.make().mkexports = true;
            repl_session.session().verbosity = 0;
        } else if (argIs(arg, "-sources")) {
            make_state.make().making = true;
            make_state.make().mksources = true;
            repl_session.session().verbosity = 0;
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

/// Reads the user's `$HOME/.mirarc`, if `$HOME` is set. Returns nonzero if it
/// was found and read (in which case the library-directory `.mirarc` is
/// skipped later; see [readLibRcIfNeeded]).
pub fn readHomeRc() Word {
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

/// Reads the library directory's `.mirarc`, but only if the user's own
/// `$HOME/.mirarc` (see [readHomeRc]) wasn't found.
pub fn readLibRcIfNeeded(okhome_rc: Word) void {
    if (okhome_rc == 0) {
        if (rt.rs().rc_error == @as(?[*:0]const u8, @ptrCast(&rt.rs().lib_rc))) {
            rt.rs().rc_error = null;
        }
        {
            const miralib_span = std.mem.span(config_state.config().miralib.?);
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
pub fn resolveEnvironmentSettings() void {
    if (config_state.config().editor == null) {
        if (abi.getenv("EDITOR")) |ed| {
            config_state.config().editor = @constCast(ed);
        } else {
            config_state.config().editor = @constCast(EDITOR);
        }
        if (config_state.config().editor != null) {
            {
                const editor_span = std.mem.span(config_state.config().editor.?);
                @memcpy(rt.rs().ebuf[0..editor_span.len], editor_span);
                rt.rs().ebuf[editor_span.len] = 0;
            }
            config_state.config().editor = @as([*:0]u8, @ptrCast(&rt.rs().ebuf));
            config_state.config().baded = @intFromBool(repl.badEditor(rt.rs()));
        }
    }

    if (abi.getenv("MIRAPROMPT")) |prs| {
        repl_session.session().promptstr = prs;
    }

    if (abi.getenv("RECHECKMIRA") != null and rt.rs().rechecking == 0) {
        rt.rs().rechecking = 1;
    }

    if (abi.getenv("NOSTRICTIF") != null) {
        rt.rs().strictif = false;
    }
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
            repl_session.session().listing = 1;
            z1 += 1;
        }
        z1 += 1;
        while (z1[0] != 0) : (z1 += 1) {
            switch (z1[0]) {
                'l' => repl_session.session().listing = 1,
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
            config_state.config().editor = @ptrCast(&rt.rs().ebuf);
            config_state.config().SPACELIMIT = h_val;
            config_state.config().DICSPACE = d_val;
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
            config_state.config().editor = @ptrCast(&rt.rs().ebuf);
            config_state.config().SPACELIMIT = h_val;
            config_state.config().DICSPACE = d_val;
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
            config_state.config().editor = @ptrCast(&rt.rs().ebuf);
            config_state.config().SPACELIMIT = h_val;
            config_state.config().DICSPACE = d_val;
            r = 1;
        }
    } else {
        rt.rs().rc_error = rcfile;
    }
    if (config_state.config().editor != null) {
        config_state.config().baded = @intFromBool(repl.badEditor(rt.rs()));
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
    if (repl_session.session().listing != 0) {
        _ = word.fprint(f, "l", .{});
    }
    if (rt.rs().rechecking == 2) {
        _ = word.fprint(f, "r", .{});
    }
    _ = word.fprint(f, " {} {} {} {s}\n", .{ config_state.config().SPACELIMIT, config_state.config().DICSPACE, version.version, config_state.config().editor orelse @constCast("") });
}

/// Abort: command-line flag `s` was given without its required parameter.
pub fn missingParam(s: [:0]const u8) noreturn {
    errors.fatal("mira: missing param after flag \"-{s}\"\n", .{s});
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
    const prev_limit = config_state.config().SPACELIMIT;
    const prev_dic = config_state.config().DICSPACE;
    const prev_editor = config_state.config().editor;
    const prev_listing = repl_session.session().listing;
    const prev_rechecking = rt.rs().rechecking;
    defer {
        config_state.config().SPACELIMIT = prev_limit;
        config_state.config().DICSPACE = prev_dic;
        config_state.config().editor = prev_editor;
        repl_session.session().listing = prev_listing;
        rt.rs().rechecking = prev_rechecking;
    }

    // Now call readRc
    const res = readRc(test_path);
    try std.testing.expectEqual(@as(Word, 1), res);
    try std.testing.expectEqual(@as(Word, 2500000), config_state.config().SPACELIMIT);
    try std.testing.expectEqual(@as(Word, 100000), config_state.config().DICSPACE);
    try std.testing.expectEqualStrings("vi +!", std.mem.span(config_state.config().editor.?));

    // Change settings and write
    config_state.config().SPACELIMIT = 3000000;
    config_state.config().DICSPACE = 150000;
    repl_session.session().listing = 1;
    rt.rs().rechecking = 2;
    config_state.config().editor = @constCast("emacs +! %");

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
    const prev_limit = config_state.config().SPACELIMIT;
    const prev_dic = config_state.config().DICSPACE;
    const prev_editor = config_state.config().editor;
    const prev_listing = repl_session.session().listing;
    defer {
        config_state.config().SPACELIMIT = prev_limit;
        config_state.config().DICSPACE = prev_dic;
        config_state.config().editor = prev_editor;
        repl_session.session().listing = prev_listing;
    }

    const res = try readRcFromContent("lhdve 2500000 100000 2067 vi\n");
    try std.testing.expectEqual(@as(Word, 1), res);
    try std.testing.expectEqual(@as(Word, 1), repl_session.session().listing);
    try std.testing.expectEqual(@as(Word, 2500000), config_state.config().SPACELIMIT);
    try std.testing.expectEqual(@as(Word, 100000), config_state.config().DICSPACE);
    try std.testing.expectEqualStrings("vi", std.mem.span(config_state.config().editor.?));
}

test "readRc: \"hdve\" with an \"r\" flag sets rechecking" {
    const prev_rechecking = rt.rs().rechecking;
    defer rt.rs().rechecking = prev_rechecking;

    const res = try readRcFromContent("hdver 2500000 100000 2067 vi\n");
    try std.testing.expectEqual(@as(Word, 1), res);
    try std.testing.expectEqual(@as(Word, 2), rt.rs().rechecking);
}

test "readRc: legacy \"ehdsv\" format (editor before the numeric fields)" {
    const prev_limit = config_state.config().SPACELIMIT;
    const prev_dic = config_state.config().DICSPACE;
    const prev_editor = config_state.config().editor;
    defer {
        config_state.config().SPACELIMIT = prev_limit;
        config_state.config().DICSPACE = prev_dic;
        config_state.config().editor = prev_editor;
    }

    // ehdsv's editor token is read via a plain %s (no getLine), so it can't
    // contain spaces -- a single-word editor name, unlike hdve's.
    const res = try readRcFromContent("ehdsv vi 2500000 100000 80 2067\n");
    try std.testing.expectEqual(@as(Word, 1), res);
    try std.testing.expectEqual(@as(Word, 2500000), config_state.config().SPACELIMIT);
    try std.testing.expectEqual(@as(Word, 100000), config_state.config().DICSPACE);
    try std.testing.expectEqualStrings("vi", std.mem.span(config_state.config().editor.?));
}

test "readRc: legacy \"ehds\" format (no version field)" {
    const prev_limit = config_state.config().SPACELIMIT;
    const prev_dic = config_state.config().DICSPACE;
    const prev_editor = config_state.config().editor;
    defer {
        config_state.config().SPACELIMIT = prev_limit;
        config_state.config().DICSPACE = prev_dic;
        config_state.config().editor = prev_editor;
    }

    const res = try readRcFromContent("ehds emacs 2500000 100000 80\n");
    try std.testing.expectEqual(@as(Word, 1), res);
    try std.testing.expectEqual(@as(Word, 2500000), config_state.config().SPACELIMIT);
    try std.testing.expectEqual(@as(Word, 100000), config_state.config().DICSPACE);
    try std.testing.expectEqualStrings("emacs", std.mem.span(config_state.config().editor.?));
}

test "readRc: unrecognised header sets rc_error and returns 0" {
    const prev_rc_error = rt.rs().rc_error;
    defer rt.rs().rc_error = prev_rc_error;
    rt.rs().rc_error = null;

    const res = try readRcFromContent("garbage 1 2 3\n");
    try std.testing.expectEqual(@as(Word, 0), res);
    try std.testing.expect(rt.rs().rc_error != null);
}
