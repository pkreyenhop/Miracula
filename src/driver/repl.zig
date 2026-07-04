//! repl.zig — the interactive driver (read-eval-print loop).
//!
//! `commandLoop` is the top-level prompt: it reads a line, dispatches `/`/`:`
//! commands, `?`/`??` queries, `!` shell escapes, and bare expressions. Each
//! expression is type-checked, compiled, and evaluated in a forked child
//! (`process`/`evaluateRepl`) so an interrupt or fault can't take down the
//! session. Also houses the signal handlers (`reset`, `dieClean`, `fpeError`),
//! the editor-command checks, and `parseLine` (the `readvals` reader).

const std = @import("std");
const options = @import("version_options");
const word = @import("../runtime/word.zig");
const errors = @import("../runtime/errors.zig");
const strtab = @import("../runtime/strtab.zig");
const rt = @import("../runtime/runtime_state.zig");
const cs = @import("../compiler/compiler_state.zig").cs;
const abi = @import("../runtime/main_clib.zig");
const parser_api = @import("../parser/parser_api.zig");
const lineedit = @import("lineedit.zig");

const Word = word.Word;
const NIL = word.NIL;
const h = heap_mod.h;
const t = heap_mod.t;

const lex_state = @import("../parser/lex_state.zig");
const setup = @import("../compiler/setup.zig");
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

var last_elapsed_ns: ?i128 = null;
var last_gc_count: ?c_long = null;
var child_exit_status: ?u8 = null;

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
const syntax = setup.syntax;
const token = lex.token;
const rdline = lex.rdline;
const resetLex = lex.resetLex;
/// POSIX `WIFSIGNALED`: true if `status` reports a child killed by a signal.
fn WIFSIGNALED(status: c_int) bool {
    return (status & 0x7f) != 0 and (status & 0x7f) != 0x7f;
}

/// POSIX `WTERMSIG`: the signal number that terminated the child.
fn WTERMSIG(status: c_int) c_int {
    return status & 0x7f;
}

/// The top-level REPL. Loads `initscript`, then reads and dispatches user input until EOF: `?`/`??` (info), `:`/`/` (commands), `!` (shell escape), `||` (comment), or an expression to evaluate.
pub fn commandLoop(heap: *Heap, initscript: [*:0]u8) void {
    var ch: c_int = undefined;
    var lb: ?[*:0]u8 = undefined;

    if (abi.sigsetjmp(&rt.rs.env, 1) == 0) {
        if (rt.rs.magic) {
            dump.undump(initscript);
            if (heap.files == NIL or cs.ND != NIL or heap_mod.idVal(rt.rs.main_id) == word.UNDEF) {
                if (heap.files != NIL and cs.ND == NIL and heap_mod.idVal(rt.rs.main_id) == word.UNDEF) {
                    word.printErr("{s}: main not defined\n", .{initscript});
                }
                errors.fatal("mira: incorrect use of \"-exec\" flag\n", .{.{}});
            }
            rt.rs.magic = false;
            abi.obey(heap, rt.rs.main_id);
            abi.exit(0);
        }
        _ = signals(abi.SIGINT, @intFromPtr(&reset));
        dump.undump(initscript);
        if (rt.rs.verbosity != 0) {
            word.print("for help type /h\n", .{});
        }
    }

    while (true) {
        resetgcstats();
        if (rt.rs.verbosity != 0) {
            var prompt_buf: [256]u8 = undefined;
            const prompt = if (last_elapsed_ns) |ns| blk: {
                var time_buf: [64]u8 = undefined;
                const time_str = formatExecutionTime(ns, &time_buf);
                if (last_gc_count) |gc_val| {
                    if (gc_val > 0) {
                        const suffix = if (gc_val == 1) "GC" else "GCs";
                        break :blk std.fmt.bufPrint(&prompt_buf, "[{s}, {} {s}] {s}", .{ time_str, gc_val, suffix, std.mem.span(rt.rs.promptstr) }) catch std.mem.span(rt.rs.promptstr);
                    }
                }
                break :blk std.fmt.bufPrint(&prompt_buf, "[{s}] {s}", .{ time_str, std.mem.span(rt.rs.promptstr) }) catch std.mem.span(rt.rs.promptstr);
            } else std.mem.span(rt.rs.promptstr);

            if (lineedit.active) {
                lineedit.setPrompt(prompt);
            } else {
                word.print("{s}", .{prompt});
            }
        } else if (lineedit.active) {
            lineedit.setPrompt("");
        }
        last_elapsed_ns = null;
        last_gc_count = null;
        ch = abi.getchar();
        if (rt.rs.rechecking != 0 and heap_mod.srcUpdate() != 0) {
            module_loader.loadfile(rt.rs.current_script.?);
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
                    if (token() == null and rt.rs.lastid == 0) {
                        word.print("\x07identifier needed after `??'\n", .{});
                        ch = abi.getchar();
                        continue;
                    }
                    if (abi.getchar() != '\n') {
                        commands.xschars();
                        continue;
                    }
                    if (rt.rs.baded != 0) {
                        edWarn();
                        continue;
                    }
                    if (ls.dicp[0] != 0) {
                        x = abi.findid(ls.dicp);
                    } else {
                        word.print("??{s}\n", .{heap_mod.getId(rt.rs.lastid)});
                        x = rt.rs.lastid;
                    }
                    if (x == NIL or heap_mod.idType(x) == word.undef_t) {
                        commands.diagnose(if (ls.dicp[0] != 0) ls.dicp else heap_mod.getId(rt.rs.lastid));
                        rt.rs.lastid = 0;
                        continue;
                    }
                    if (heap_mod.idWho(x) == NIL) {
                        word.print("{s} -- primitive to Miranda\n", .{@as([*:0]const u8, @ptrCast(if (ls.dicp[0] != 0) ls.dicp else heap_mod.getId(rt.rs.lastid)))});
                        rt.rs.lastid = 0;
                        continue;
                    }
                    rt.rs.lastid = x;
                    x = heap_mod.idWho(x);
                    if (getTag(heap, x) == .CONS) {
                        aka = strtab.strOf(strtab.table, heap_mod.h(heap_mod.h(x)));
                        x = heap_mod.t(x);
                    }
                    if (aka != null) {
                        word.print("originally defined as \"{s}\"\n", .{aka.?});
                    }
                    commands.editfile(strtab.strOf(strtab.table, heap_mod.h(x)), @intCast(heap_mod.t(x)), 0);
                } else {
                    _ = abi.ungetc(ch, abi.stdin().?);
                    _ = token();
                    rt.rs.lastid = 0;
                    if (ls.dicp[0] == 0) {
                        if (abi.getchar() != '\n') {
                            commands.xschars();
                        } else {
                            commands.allnamescom();
                        }
                    } else {
                        while (ls.dicp[0] != 0) {
                            commands.finger(ls.dicp);
                            _ = token();
                        }
                        ch = abi.getchar();
                    }
                }
            },
            ':', '/' => {
                _ = token();
                rt.rs.lastid = 0;
                commands.command();
            },
            '!' => {
                lb = rdline();
                if (lb == null) continue;
                rt.rs.lastid = 0;
                if (lb.?[0] != 0) {
                    var shell: ?[*:0]const u8 = null;
                    var oldsig: usize = undefined;
                    var pid: c_int = undefined;
                    shell = abi.getenv("SHELL");
                    if (shell == null) {
                        shell = "/bin/sh";
                    }
                    oldsig = signals(abi.SIGINT, 1);
                    pid = abi.fork();
                    if (pid != 0) { // parent
                        if (pid == -1) {
                            abi.perror("UNIX error - cannot create process");
                        }
                        while (pid != abi.wait(null)) {}
                        _ = signals(abi.SIGINT, oldsig);
                    } else { // child
                        _ = abi.execl(shell.?, .{ shell.?, "-c", lb.? });
                    }
                    if (heap_mod.srcUpdate() != 0) {
                        module_loader.loadfile(rt.rs.current_script.?);
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
                if (rt.rs.verbosity != 0) {
                    word.print("\nmiranda logout\n", .{});
                }
                lineedit.deinit(); // persist history (no-op if not interactive)
                abi.exit(0);
            },
            else => {
                const start = getMonotonicNs();
                _ = abi.ungetc(ch, abi.stdin().?);
                rt.rs.lastid = 0;
                heap_mod.tp(heap_mod.h(ls.cook_stdin)).* = 0;
                rt.rs.rv_expr = 0;
                ls.c = word.EVAL;
                rt.rs.echoing = 0;
                cs.polyshowerror = 0;
                core_state.s.commandmode = 1;
                _ = parser_api.parseCurrent() catch {};
                if (core_state.s.SYNERR != 0) {
                    core_state.s.SYNERR = 0;
                } else if (ls.c != '\n') {
                    word.print("syntax error\n", .{});
                    while (ls.c != '\n' and ls.c != abi.EOF) {
                        ls.c = abi.getchar();
                    }
                }
                core_state.s.commandmode = 0;
                rt.rs.echoing = rt.rs.verbosity & rt.rs.listing;
                last_elapsed_ns = getMonotonicNs() - start;
                if (child_exit_status) |exit_code| {
                    if (exit_code == 0) {
                        last_gc_count = 0;
                    } else if (exit_code >= 2) {
                        last_gc_count = exit_code - 1;
                    } else {
                        last_gc_count = null;
                    }
                } else {
                    last_gc_count = null;
                }
            },
        }
    }
}

/// Fork a child for evaluation. In the parent, wait and report any fatal signal; returns 0 in the parent and 1 in the child.
pub fn process() Word {
    var oldsig: usize = undefined;
    oldsig = signals(abi.SIGINT, 1);
    const pid = abi.fork();
    if (pid != 0) { // parent
        var status: c_int = 0;
        if (pid == -1) {
            abi.perror("UNIX error - cannot create process");
            return 0;
        }
        while (pid != abi.wait(&status)) {}
        if (WIFSIGNALED(status)) {
            const cd: [*:0]const u8 = if ((status & 0x80) != 0) " (core dumped)" else "";
            const sig = WTERMSIG(status);
            switch (sig) {
                abi.SIGBUS => word.printErr("\n<<...bus error{s}>>\n", .{cd}),
                abi.SIGSEGV => word.printErr("\n<<...segmentation fault{s}>>\n", .{cd}),
                else => word.printErr("\n<<...uncaught signal {}>>\n", .{sig}),
            }
        }
        _ = signals(abi.SIGINT, oldsig);
        if (std.posix.W.IFEXITED(@bitCast(status))) {
            child_exit_status = std.posix.W.EXITSTATUS(@bitCast(status));
        } else {
            child_exit_status = null;
        }
        return 0;
    }
    return 1; // child
}

/// SIGINT handler during evaluation: print the interrupt notice, dump stats, and exit.
pub fn dieClean() callconv(.c) void {
    word.printErr("<<...interrupt>>\n", .{});
    outstats();
    abi.exit(0);
}

/// SIGFPE handler: treat as a syntax error while compiling, otherwise a fatal floating-point overflow.
pub fn fpeError(sig: c_int) callconv(.c) void {
    if (core_state.s.compiling != 0) {
        _ = signals(sig, @intFromPtr(&fpeError));
        syntax("floating point number out of range\n");
        core_state.s.SYNERR = 0;
        abi.siglongjmp(&rt.rs.env, 1);
    } else {
        word.print("\nFLOATING POINT OVERFLOW\n", .{});
        abi.exit(1);
    }
}

// Relocated REPL and interactive driver functions
/// Compile `x` and send its value to standard output — used to run a script's `main`.
pub fn obey(heap: *Heap, x_in: Word) void {
    var x = x_in;
    const typ = types_mod.typeOf(x);
    if (options.is_strict or @import("builtin").mode == .Debug) {
        heap.validate();
        trans_mod.validate();
        rt.rs.validate();
    }
    x = trans_mod.codegen(x);
    if (options.is_strict or @import("builtin").mode == .Debug) {
        heap.validate();
        trans_mod.validate();
        rt.rs.validate();
    }
    if (cs.polyshowerror != 0) return;
    core_state.s.compiling = 0;
    const list_t: Word = 4;
    const char_t: Word = 3;
    const islist = typ >= word.ATOMLIMIT and getTag(heap, typ) == .AP and h(typ) == list_t;
    const out_val: Word = if (islist and t(typ) == rt.rs.message)
        x
    else blk: {
        const inner: Word = if (islist and t(typ) == char_t)
            x
        else
            abi.make(.AP, abi.mkshow(0, 0, typ), x);
        break :blk abi.make(.CONS, abi.make(.AP, rt.rs.standardout, inner), NIL);
    };
    abi.output(out_val);
}

/// Evaluate a typed REPL expression: compile it and fork via `process`; the child prints the result and exits, leaving the parent's heap untouched.
pub fn evaluateRepl(heap: *Heap, x_in: Word) void {
    var x = x_in;
    const typ = types_mod.typeOf(x);
    if (options.is_strict or @import("builtin").mode == .Debug) {
        heap.validate();
        trans_mod.validate();
        rt.rs.validate();
    }
    if (typ == word.wrong_t) return;
    rt.rs.lastexp = x;
    x = trans_mod.codegen(x);
    if (options.is_strict or @import("builtin").mode == .Debug) {
        heap.validate();
        trans_mod.validate();
        rt.rs.validate();
    }
    if (cs.polyshowerror != 0) return;
    const list_t: Word = 4;
    const char_t: Word = 3;
    const islist = typ >= word.ATOMLIMIT and getTag(heap, typ) == .AP and h(typ) == list_t;
    const out_val: Word = if (islist and t(typ) == rt.rs.message)
        x
    else blk: {
        const inner: Word = if (islist and t(typ) == char_t)
            x
        else
            abi.make(.AP, abi.mkshow(0, 0, typ), x);
        break :blk abi.make(.CONS, abi.make(.AP, rt.rs.standardout, inner), NIL);
    };
    if (process() != 0) {
        // Child: evaluate and print, then exit (compiling=0 only here, parent unaffected).
        _ = signals(abi.SIGINT, @intFromPtr(&dieClean));
        core_state.s.compiling = 0;
        resetgcstats();
        abi.output(out_val);
        _ = word.putchar('\n');
        outstats();
        const exit_code: c_int = if (heap.nogcs == 0) 0 else @as(c_int, @intCast(@min(heap.nogcs, 253))) + 1;
        abi.exit(exit_code);
    }
    // Parent returns here; heap and compiling flag are unchanged.
}

/// SIGINT handler at the prompt: restore input/echo/compile state and `longjmp` back into the command loop.
pub fn reset() callconv(.c) void {
    if (rt.rs.echoing != 0) {
        _ = word.putchar('\n');
    }
    rt.rs.s_in = abi.stdin();
    rt.rs.echoing = 0;
    rt.rs.listing = 0;
    core_state.s.compiling = 0;
    core_state.s.commandmode = 0;
    core_state.s.SYNERR = 0;
    rt.rs.sigflag = 0;
    if (rt.rs.unlinkme) |u| {
        _ = abi.unlink(u);
        rt.rs.unlinkme = null;
    }
    last_elapsed_ns = null;
    last_gc_count = null;
    abi.siglongjmp(&rt.rs.env, 1);
}

/// Warn that the configured editor lacks open-at-line support, disabling `??` and related features.
pub fn edWarn() void {
    word.print("The currently installed editor command, \"{s}\", does not\ninclude a facility for opening a file at a specified line number.  As a\nresult the `??' command and certain other features of the Miranda system\nare disabled.  See manual section 31/5 on changing the editor for more\ninformation.\n", .{rt.rs.editor orelse @constCast("")});
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
pub fn getLine(in: ?*word.FILE, n_val: Word, s_ptr: [*]u8) c_int {
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
pub fn badEditor() bool {
    const e = rt.rs.editor orelse return false;
    if (word.strstr(e, "+!") != null or word.strstr(e, "%d") != null or word.strstr(e, "%l") != null) {
        return false;
    }
    return true;
}

/// Read and type-check one expression of type `t_val` from file `f` (the `readvals` path). Returns its codegen, or `EOF`; re-prompts interactively and aborts on bad file data.
pub fn parseLine(t_val: Word, f: ?*word.FILE, fil: Word) Word {
    var t1: Word = undefined;
    var ch: c_int = undefined;
    rt.rs.lastexp = word.UNDEF;
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
        ls.c = word.VALUE;
        rt.rs.echoing = 0;
        core_state.s.commandmode = 1;
        rt.rs.s_in = f;
        _ = parser_api.parseCurrent() catch {};
        rt.rs.s_in = abi.stdin();
        if (core_state.s.SYNERR != 0) {
            core_state.s.SYNERR = 0;
            rt.rs.lastexp = word.UNDEF;
        } else {
            t1 = types_mod.typeOf(rt.rs.lastexp);
            if (t1 == word.wrong_t) {
                rt.rs.lastexp = word.UNDEF;
            } else if (abi.subsumes(abi.instantiate(t1), t_val) == 0) {
                word.print("data has wrong type :: ", .{});
                abi.outType(t1);
                word.print("\nshould be :: ", .{});
                abi.outType(t_val);
                _ = word.putc('\n', abi.stdout());
                rt.rs.lastexp = word.UNDEF;
            }
        }
        if (rt.rs.lastexp != word.UNDEF) {
            return trans_mod.codegen(rt.rs.lastexp);
        }
        if (abi.isatty(word.fileno(f)) != 0) {
            word.print("please re-enter data:\n", .{});
        } else {
            if (fil != 0) {
                word.printErr("readvals: bad data in file \"{s}\"\n", .{abi.getstring(fil, @constCast("")) orelse "?"});
            } else {
                word.printErr("bad data in $+ input\n", .{});
            }
            abi.outstats();
            abi.exit(1);
        }
    }
}
