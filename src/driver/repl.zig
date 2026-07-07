//! repl.zig — the interactive driver (read-eval-print loop).
//!
//! `commandLoop` is the top-level prompt: it reads a line, dispatches `/`/`:`
//! commands, `?`/`??` queries, `!` shell escapes, and bare expressions.
//!
//! `evaluateRepl` no longer forks a child per expression (Phase 3 step 3,
//! docs/ZIG_NATIVE_PLAN.md): it checkpoints the heap first and always
//! restores it afterward (success or interrupt alike), reproducing the old
//! fork model's actual invariant -- the forked child's reductions, being a
//! separate COW-copied address space, never persisted into the parent's
//! heap -- in-process instead. `onInterrupt`, the single SIGINT handler
//! installed for the whole session, only sets `rt.interrupt_flag`
//! (async-signal-safe by construction); `reduce()`'s main loop polls it and
//! unwinds via a normal `error.Interrupted` return, which `evaluateRepl`
//! catches, reports, and clears -- no more signal-context non-local jump for
//! this path. Float overflow (Phase 3 step 2) follows the same shape:
//! `heap.zig`'s `stoDbl`/`setdbl` return `error.FloatOverflow` on a
//! non-finite result (a *synchronous* check, never an async signal --
//! there never was a real SIGFPE delivery path here), and `evaluateRepl`
//! catches it alongside `error.Interrupted` and reports "FLOATING POINT
//! OVERFLOW" instead of killing the process. No SIGFPE handler is
//! registered any more.
//!
//! Also houses the editor-command checks and `parseLine` (the `readvals`
//! reader).

const std = @import("std");
const options = @import("version_options");
const word = @import("../runtime/word.zig");
const errors = @import("../runtime/errors.zig");
const strtab = @import("../runtime/strtab.zig");
const rt = @import("../runtime/runtime_state.zig");
const compiler_state = @import("../compiler/compiler_state.zig");
const cs = compiler_state.cs;
const abi = @import("../runtime/os.zig");
const parser_api = @import("../parser/parser_api.zig");
const lineedit = @import("lineedit.zig");

const Word = word.Word;
const NIL = word.NIL;
const h = heap_mod.h;
const t = heap_mod.t;

const lex_state = @import("../parser/lex_state.zig");
const signals_mod = @import("../io/signals.zig");
const lex = @import("../parser/lex.zig");
const heap_mod = @import("../runtime/heap.zig");
const Heap = heap_mod.Heap;
const commands = @import("commands.zig");
const trans_mod = @import("../compiler/trans.zig");
const module_loader = @import("../compiler/module_loader.zig");
const types_mod = @import("../compiler/types.zig");
const startup = @import("startup.zig");
const dump = @import("../compiler/dump.zig");
const reduce = @import("../runtime/reduce.zig");
const core_state = @import("../runtime/core_state.zig");
const version = @import("../runtime/version.zig");
const ls = lex_state.ls;

fn formatExecutionTime(ns: i128, buf: []u8) []const u8 {
    const ms = @as(f64, @floatFromInt(ns)) / 1_000_000.0;
    if (ms < 1.0) {
        return std.fmt.bufPrint(buf, "{d:.3}ms", .{ms}) catch "0ms";
    } else if (ms < 1000.0) {
        return std.fmt.bufPrint(buf, "{d:.2}ms", .{ms}) catch "0ms";
    } else {
        return std.fmt.bufPrint(buf, "{d:.3}s", .{ms / 1000.0}) catch "0s";
    }
}

fn getMonotonicNs() i128 {
    var ts: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(std.posix.CLOCK.MONOTONIC, &ts);
    return @as(i128, ts.sec) * std.time.ns_per_s + ts.nsec;
}

// State owned by reduce.zig / heap.zig — not yet accessible via @import.
inline fn getTag(heap: *Heap, x: Word) word.NodeTag {
    return heap.getTag(x);
}

const signals = signals_mod.signals;
const resetgcstats = heap_mod.resetgcstats;
const outstats = reduce.outstats;
const token = lex.token;
const rdline = lex.rdline;
const resetLex = lex.resetLex;
/// The top-level REPL. Loads `initscript`, then reads and dispatches user input until EOF: `?`/`??` (info), `:`/`/` (commands), `!` (shell escape), `||` (comment), or an expression to evaluate.
pub fn commandLoop(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState, lexs: *lex_state.LexState, initscript: [*:0]u8) void {
    var ch: c_int = undefined;
    var lb: ?[*:0]u8 = undefined;

    if (rs.magic) {
        dump.undump(heap, core_state.s(), cs(), rs, initscript);
        if (heap.files == NIL or comp.ND != NIL or heap_mod.idVal(rs.main_id) == word.UNDEF) {
            if (heap.files != NIL and comp.ND == NIL and heap_mod.idVal(rs.main_id) == word.UNDEF) {
                word.printErr("{s}: main not defined\n", .{initscript});
            }
            errors.fatal("mira: incorrect use of \"-exec\" flag\n", .{});
        }
        rs.magic = false;
        abi.obey(heap, core, comp, rs, rs.main_id);
        abi.exit(0);
    }
    _ = signals(abi.SIGINT, @intFromPtr(&onInterrupt));
    dump.undump(heap, core_state.s(), cs(), rs, initscript);
    if (rs.verbosity != 0) {
        word.print("for help type /h\n", .{});
    }

    while (true) {
        resetgcstats();
        if (rs.verbosity != 0) {
            var prompt_buf: [256]u8 = undefined;
            const prompt = if (rs.last_elapsed_ns) |ns| blk: {
                var time_buf: [64]u8 = undefined;
                const time_str = formatExecutionTime(ns, &time_buf);
                if (rs.last_gc_count) |gc_val| {
                    if (gc_val > 0) {
                        const suffix = if (gc_val == 1) "GC" else "GCs";
                        break :blk std.fmt.bufPrint(&prompt_buf, "[{s}, {} {s}] {s}", .{ time_str, gc_val, suffix, std.mem.span(rs.promptstr) }) catch std.mem.span(rs.promptstr);
                    }
                }
                break :blk std.fmt.bufPrint(&prompt_buf, "[{s}] {s}", .{ time_str, std.mem.span(rs.promptstr) }) catch std.mem.span(rs.promptstr);
            } else std.mem.span(rs.promptstr);

            if (lineedit.active()) {
                lineedit.setPrompt(prompt);
            } else {
                word.print("{s}", .{prompt});
            }
        } else if (lineedit.active()) {
            lineedit.setPrompt("");
        }
        rs.last_elapsed_ns = null;
        rs.last_gc_count = null;
        ch = abi.getchar();
        if (rs.rechecking != 0 and heap_mod.srcUpdate(rs) != 0) {
            module_loader.loadfile(heap, core_state.s(), cs(), rs, ls(), rs.current_script.?) catch {};
        }
        while (ch == ' ' or ch == '\t') {
            ch = abi.getchar();
        }
        switch (ch) {
            '?' => {
                ch = abi.getchar();
                if (ch == '?') {
                    var x: Word = undefined;
                    var aka: ?[*:0]const u8 = null;
                    if (token() == null and rs.lastid == 0) {
                        word.print("\x07identifier needed after `??'\n", .{});
                        ch = abi.getchar();
                        continue;
                    }
                    if (abi.getchar() != '\n') {
                        commands.xschars();
                        continue;
                    }
                    if (rs.baded != 0) {
                        edWarn(rs);
                        continue;
                    }
                    if (lexs.dicp[0] != 0) {
                        x = abi.findid(heap, lexs.dicp);
                    } else {
                        word.print("??{s}\n", .{heap_mod.getId(rs.lastid)});
                        x = rs.lastid;
                    }
                    if (x == NIL or heap_mod.idType(x) == word.undef_t) {
                        commands.diagnose(if (lexs.dicp[0] != 0) lexs.dicp else heap_mod.getId(rs.lastid));
                        rs.lastid = 0;
                        continue;
                    }
                    if (heap_mod.idWho(x) == NIL) {
                        word.print("{s} -- primitive to Miranda\n", .{@as([*:0]const u8, @ptrCast(if (lexs.dicp[0] != 0) lexs.dicp else heap_mod.getId(rs.lastid)))});
                        rs.lastid = 0;
                        continue;
                    }
                    rs.lastid = x;
                    x = heap_mod.idWho(x);
                    if (getTag(heap, x) == .CONS) {
                        aka = strtab.strOf(strtab.table(), heap_mod.h(heap_mod.h(x)));
                        x = heap_mod.t(x);
                    }
                    if (aka != null) {
                        word.print("originally defined as \"{s}\"\n", .{aka.?});
                    }
                    commands.editfile(rs, strtab.strOf(strtab.table(), heap_mod.h(x)), @intCast(heap_mod.t(x)), 0);
                } else {
                    _ = abi.ungetc(ch, abi.stdin().?);
                    _ = token();
                    rs.lastid = 0;
                    if (lexs.dicp[0] == 0) {
                        if (abi.getchar() != '\n') {
                            commands.xschars();
                        } else {
                            commands.allnamescom(heap, comp, rs);
                        }
                    } else {
                        while (lexs.dicp[0] != 0) {
                            commands.finger(heap, rs, lexs.dicp);
                            _ = token();
                        }
                        ch = abi.getchar();
                    }
                }
            },
            ':', '/' => {
                _ = token();
                rs.lastid = 0;
                commands.command(heap, core_state.s(), comp, rs, lexs);
            },
            '!' => {
                lb = rdline();
                if (lb == null) continue;
                rs.lastid = 0;
                if (lb.?[0] != 0) {
                    const shell_env = abi.getenv("SHELL");
                    const shell: []const u8 = if (shell_env) |s| std.mem.span(s) else "/bin/sh";
                    // Ignore SIGINT for the duration: a Ctrl-C meant for the
                    // shell command (e.g. an interactive `!vi`) must not also
                    // kill mira itself. Restored once the child returns.
                    const oldsig = signals(abi.SIGINT, 1);
                    const argv = [_][]const u8{ shell, "-c", std.mem.span(lb.?) };
                    if (std.process.spawn(rt.io, .{
                        .argv = &argv,
                        .stdin = .inherit,
                        .stdout = .inherit,
                        .stderr = .inherit,
                    })) |spawned| {
                        var child = spawned;
                        _ = child.wait(rt.io) catch {};
                    } else |_| {
                        abi.perror("UNIX error - cannot create process");
                    }
                    _ = signals(abi.SIGINT, oldsig);
                    if (heap_mod.srcUpdate(rs) != 0) {
                        module_loader.loadfile(heap, core_state.s(), cs(), rs, ls(), rs.current_script.?) catch {};
                    }
                } else {
                    word.print("No previous shell command to substitute for \"!\"\n", .{});
                }
            },
            '|' => {
                ch = abi.getchar();
                if (ch != '|') {
                    word.print("\x07unknown command - type /h for help\n", .{});
                }
                while (ch != '\n' and ch != abi.EOF) {
                    ch = abi.getchar();
                }
            },
            '\n' => {},
            abi.EOF => {
                if (rs.verbosity != 0) {
                    word.print("\nmiranda logout\n", .{});
                }
                lineedit.deinit(); // persist history (no-op if not interactive)
                abi.exit(0);
            },
            else => {
                const start = getMonotonicNs();
                _ = abi.ungetc(ch, abi.stdin().?);
                rs.lastid = 0;
                heap_mod.tp(heap_mod.h(lexs.cook_stdin)).* = 0;
                rs.rv_expr = 0;
                lexs.c = word.EVAL;
                rs.echoing = 0;
                comp.polyshowerror = 0;
                core.commandmode = 1;
                _ = parser_api.parseCurrent() catch {};
                if (core.SYNERR != 0) {
                    core.SYNERR = 0;
                } else if (lexs.c != '\n') {
                    word.print("syntax error\n", .{});
                    while (lexs.c != '\n' and lexs.c != abi.EOF) {
                        lexs.c = abi.getchar();
                    }
                }
                core.commandmode = 0;
                rs.echoing = rs.verbosity & rs.listing;
                rs.last_elapsed_ns = getMonotonicNs() - start;
                // rs.last_gc_count is set directly by evaluateRepl now (no
                // more fork + exit-code round trip to smuggle it back).
            },
        }
    }
}

/// SIGINT/SIGTERM handler for the whole session (Phase 3, docs/ZIG_NATIVE_PLAN.md):
/// async-signal-safe by construction -- the only thing it does is set the
/// flag. Everything else (reporting the interrupt, restoring the heap,
/// clearing the flag again) happens synchronously once `reduce()`'s polled
/// check propagates `error.Interrupted` up through normal Zig control flow,
/// in `evaluateRepl` below.
pub fn onInterrupt(sig: c_int) callconv(.c) void {
    _ = sig;
    rt.interrupt_flag.store(true, .release);
}

// Relocated REPL and interactive driver functions
/// Compile `x` and send its value to standard output — used to run a script's `main`.
pub fn obey(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState, x_in: Word) void {
    var x = x_in;
    const typ = types_mod.typeOf(heap, x);
    if (options.is_strict or @import("builtin").mode == .Debug) {
        heap.validate();
        trans_mod.validate(heap);
        rs.validate();
    }
    x = trans_mod.codegen(heap, x);
    if (options.is_strict or @import("builtin").mode == .Debug) {
        heap.validate();
        trans_mod.validate(heap);
        rs.validate();
    }
    if (comp.polyshowerror != 0) return;
    core.compiling = 0;
    const list_t: Word = 4;
    const char_t: Word = 3;
    const islist = typ >= word.ATOMLIMIT and getTag(heap, typ) == .AP and h(typ) == list_t;
    const out_val: Word = if (islist and t(typ) == rs.message)
        x
    else blk: {
        const inner: Word = if (islist and t(typ) == char_t)
            x
        else
            abi.make(.AP, abi.mkshow(heap, 0, 0, typ), x);
        break :blk abi.make(.CONS, abi.make(.AP, rs.standardout, inner), NIL);
    };
    abi.output(reduce.ev(), rs, out_val) catch {};
}

/// Evaluate a typed REPL expression: compile it, then reduce and print
/// in-process, checkpointing the heap first and always restoring it
/// afterward (success or interrupt alike) -- reductions never persist
/// between REPL commands, matching the old forked-child model's own
/// invariant exactly (see this file's module doc for why).
pub fn evaluateRepl(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState, x_in: Word) void {
    var x = x_in;
    const typ = types_mod.typeOf(heap, x);
    if (options.is_strict or @import("builtin").mode == .Debug) {
        heap.validate();
        trans_mod.validate(heap);
        rs.validate();
    }
    if (typ == word.wrong_t) return;
    rs.lastexp = x;
    x = trans_mod.codegen(heap, x);
    if (options.is_strict or @import("builtin").mode == .Debug) {
        heap.validate();
        trans_mod.validate(heap);
        rs.validate();
    }
    if (comp.polyshowerror != 0) return;
    const list_t: Word = 4;
    const char_t: Word = 3;
    const islist = typ >= word.ATOMLIMIT and getTag(heap, typ) == .AP and h(typ) == list_t;
    const out_val: Word = if (islist and t(typ) == rs.message)
        x
    else blk: {
        const inner: Word = if (islist and t(typ) == char_t)
            x
        else
            abi.make(.AP, abi.mkshow(heap, 0, 0, typ), x);
        break :blk abi.make(.CONS, abi.make(.AP, rs.standardout, inner), NIL);
    };

    rt.interrupt_flag.store(false, .release); // discard any stale, pre-eval interrupt
    var snap = heap.checkpoint();
    core.compiling = 0;
    resetgcstats();
    if (abi.output(reduce.ev(), rs, out_val)) {
        _ = word.putchar('\n');
    } else |err| switch (err) {
        error.Interrupted => {
            word.printErr("<<...interrupt>>\n", .{});
            rt.interrupt_flag.store(false, .release);
        },
        error.FloatOverflow => {
            word.print("\nFLOATING POINT OVERFLOW\n", .{});
        },
    }
    outstats();
    rs.last_gc_count = heap.nogcs;
    heap.restore(&snap);
}

/// Warn that the configured editor lacks open-at-line support, disabling `??` and related features.
pub fn edWarn(rs: *rt.RuntimeState) void {
    word.print("The currently installed editor command, \"{s}\", does not\ninclude a facility for opening a file at a specified line number.  As a\nresult the `??' command and certain other features of the Miranda system\nare disabled.  See manual section 31/5 on changing the editor for more\ninformation.\n", .{rs.editor orelse @constCast("")});
}

/// Print the Miranda release banner (version, plus `(UTF-8)` when applicable).
pub fn announce() void {
    word.print("Miranda release {s}", .{startup.versionString(version.version)});
    if (heap_mod.utf8test()) {
        word.print(" (UTF-8)", .{});
    }
    word.print("\n", .{});
}

/// Read up to `n_val-1` bytes (or through a newline) from `in` into `s_ptr`. Returns 0 on immediate EOF, else 1.
pub fn getLine(in: ?*word.Stream, n_val: Word, s_ptr: [*]u8) c_int {
    var s = s_ptr;
    var n = n_val;
    var ch: c_int = undefined;
    while (n > 1) : (n -= 1) {
        ch = abi.getc(in);
        if (ch == abi.EOF) break;
        s[0] = @intCast(ch);
        s += 1;
        if (ch == '\n') break;
    }
    s[0] = 0;
    return if (ch == abi.EOF) 0 else 1;
}

/// 1 if the editor command lacks an open-at-line placeholder (`+!`, `%d`, or `%l`).
pub fn badEditor(rs: *rt.RuntimeState) bool {
    const e = std.mem.span(rs.editor orelse return false);
    if (std.mem.indexOf(u8, e, "+!") != null or std.mem.indexOf(u8, e, "%d") != null or std.mem.indexOf(u8, e, "%l") != null) {
        return false;
    }
    return true;
}

/// Read and type-check one expression of type `t_val` from file `f` (the `readvals` path). Returns its codegen, or `EOF`; re-prompts interactively and aborts on bad file data.
pub fn parseLine(heap: *Heap, core: *core_state.CoreState, rs: *rt.RuntimeState, lexs: *lex_state.LexState, t_val: Word, f: ?*word.Stream, fil: Word) Word {
    var t1: Word = undefined;
    var ch: c_int = undefined;
    rs.lastexp = word.UNDEF;
    while (true) {
        ch = abi.getc(f);
        while (ch == ' ' or ch == '\t' or ch == '\n') {
            ch = abi.getc(f);
        }
        if (ch == '|') {
            ch = abi.getc(f);
            if (ch == '|') {
                ch = abi.getc(f);
                while (ch != '\n' and ch != abi.EOF) {
                    ch = abi.getc(f);
                }
                if (ch != abi.EOF) {
                    continue;
                }
            } else {
                _ = abi.ungetc(ch, f);
            }
        }
        if (ch == abi.EOF) {
            return abi.EOF;
        }
        _ = abi.ungetc(ch, f);
        lexs.c = word.VALUE;
        rs.echoing = 0;
        core.commandmode = 1;
        rs.s_in = f;
        _ = parser_api.parseCurrent() catch {};
        rs.s_in = abi.stdin();
        if (core.SYNERR != 0) {
            core.SYNERR = 0;
            rs.lastexp = word.UNDEF;
        } else {
            t1 = types_mod.typeOf(heap, rs.lastexp);
            if (t1 == word.wrong_t) {
                rs.lastexp = word.UNDEF;
            } else if (abi.subsumes(heap, abi.instantiate(heap, t1), t_val) == 0) {
                word.print("data has wrong type :: ", .{});
                abi.outType(heap, t1);
                word.print("\nshould be :: ", .{});
                abi.outType(heap, t_val);
                _ = word.putc('\n', abi.stdout());
                rs.lastexp = word.UNDEF;
            }
        }
        if (rs.lastexp != word.UNDEF) {
            return trans_mod.codegen(heap, rs.lastexp);
        }
        if (abi.isatty(word.fileno(f)) != 0) {
            word.print("please re-enter data:\n", .{});
        } else {
            if (fil != 0) {
                word.printErr("readvals: bad data in file \"{s}\"\n", .{(abi.getstring(fil, @constCast("")) catch null) orelse "?"});
            } else {
                word.printErr("bad data in $+ input\n", .{});
            }
            abi.outstats();
            abi.exit(1);
        }
    }
}
