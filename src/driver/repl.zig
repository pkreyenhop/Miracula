//! repl.zig — the interactive driver (read-eval-print loop).
//!
//! `commandLoop` is the top-level prompt: it reads a line, dispatches `/`/`:`
//! commands, `?`/`??` queries, `!` shell escapes, and bare expressions. Each
//! expression is type-checked, compiled, and evaluated in a forked child
//! (`process`/`evaluateRepl`) so an interrupt or fault can't take down the
//! session. Also houses the signal handlers (`reset`, `dieClean`, `fpeError`),
//! the editor-command checks, and `parseLine` (the `readvals` reader).

const std = @import("std");
const word = @import("../runtime/word.zig");
const strtab = @import("../runtime/strtab.zig");
const main = @import("../main.zig");
const abi = @import("../runtime/main_clib.zig");
const parser_api = @import("../parser/parser_api.zig");
const lineedit = @import("lineedit.zig");

const Word = main.Word;
const NIL = main.NIL;
const CONS = main.CONS;
const AP = main.AP;
const h = heap.h;
const t = heap.t;

const lex_state = @import("../parser/lex_state.zig");
const r7_setup = @import("../compiler/setup.zig");
const r7_signals = @import("../io/signals.zig");
const r7_lex = @import("../parser/lex.zig");
const heap = @import("../runtime/heap.zig");
const r7_reduce = @import("../runtime/reduce.zig");
const core_state = @import("../runtime/core_state.zig");
const version = @import("../runtime/version.zig");
const ls = lex_state.ls;

// State owned by reduce.zig / heap.zig — not yet accessible via @import.
inline fn getTag(x: Word) u8 {
    return heap.heap.getTag(x);
}

const signals = r7_signals.signals;
const resetgcstats = heap.resetgcstats;
const outstats = r7_reduce.outstats;
const syntax = r7_setup.syntax;
const token = r7_lex.token;
const rdline = r7_lex.rdline;
const resetLex = r7_lex.resetLex;
/// POSIX `WIFSIGNALED`: true if `status` reports a child killed by a signal.
fn WIFSIGNALED(status: c_int) bool {
    return (status & 0x7f) != 0 and (status & 0x7f) != 0x7f;
}

/// POSIX `WTERMSIG`: the signal number that terminated the child.
fn WTERMSIG(status: c_int) c_int {
    return status & 0x7f;
}

/// The top-level REPL. Loads `initscript`, then reads and dispatches user input until EOF: `?`/`??` (info), `:`/`/` (commands), `!` (shell escape), `||` (comment), or an expression to evaluate.
pub fn commandLoop(initscript: [*:0]u8) void {
    var ch: c_int = undefined;
    var lb: ?[*:0]u8 = undefined;

    if (abi.sigsetjmp(&main.rs.env, 1) == 0) {
        if (main.rs.magic) {
            main.undump(initscript);
            if (heap.heap.files == NIL or main.cs.ND != NIL or main.idVal(main.rs.main_id) == word.UNDEF) {
                if (heap.heap.files != NIL and main.cs.ND == NIL and main.idVal(main.rs.main_id) == word.UNDEF) {
                    word.printErr("{s}: main not defined\n", .{initscript});
                }
                main.fatal("mira: incorrect use of \"-exec\" flag\n", .{.{}});
            }
            main.rs.magic = false;
            abi.obey(main.rs.main_id);
            abi.exit(0);
        }
        _ = signals(abi.SIGINT, @intFromPtr(&main.reset));
        main.undump(initscript);
        if (main.rs.verbosity != 0) {
            word.print("for help type /h\n", .{});
        }
    }

    while (true) {
        resetgcstats();
        if (lineedit.active) {
            // The line editor owns the prompt (it must, to redraw correctly while
            // editing); hand it the prompt instead of printing it ourselves.
            lineedit.setPrompt(if (main.rs.verbosity != 0) std.mem.span(main.rs.promptstr) else "");
        } else if (main.rs.verbosity != 0) {
            word.print("{s}", .{main.rs.promptstr});
        }
        ch = abi.getchar();
        if (main.rs.rechecking != 0 and main.srcUpdate() != 0) {
            main.loadfile(main.rs.current_script.?);
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
                    if (token() == null and main.rs.lastid == 0) {
                        word.print("\x07identifier needed after `??'\n", .{});
                        ch = abi.getchar();
                        continue;
                    }
                    if (abi.getchar() != '\n') {
                        main.xschars();
                        continue;
                    }
                    if (main.rs.baded != 0) {
                        main.edWarn();
                        continue;
                    }
                    if (ls.dicp[0] != 0) {
                        x = abi.findid(ls.dicp);
                    } else {
                        word.print("??{s}\n", .{main.get_id(main.rs.lastid)});
                        x = main.rs.lastid;
                    }
                    if (x == NIL or main.idType(x) == word.undef_t) {
                        main.diagnose(if (ls.dicp[0] != 0) ls.dicp else main.get_id(main.rs.lastid));
                        main.rs.lastid = 0;
                        continue;
                    }
                    if (main.idWho(x) == NIL) {
                        word.print("{s} -- primitive to Miranda\n", .{@as([*:0]const u8, @ptrCast(if (ls.dicp[0] != 0) ls.dicp else main.get_id(main.rs.lastid)))});
                        main.rs.lastid = 0;
                        continue;
                    }
                    main.rs.lastid = x;
                    x = main.idWho(x);
                    if (getTag(x) == CONS) {
                        aka = strtab.strOf(heap.h(heap.h(x)));
                        x = heap.t(x);
                    }
                    if (aka != null) {
                        word.print("originally defined as \"{s}\"\n", .{aka.?});
                    }
                    main.editfile(strtab.strOf(heap.h(x)), @intCast(heap.t(x)));
                } else {
                    _ = abi.ungetc(ch, main.getStdin().?);
                    _ = token();
                    main.rs.lastid = 0;
                    if (ls.dicp[0] == 0) {
                        if (abi.getchar() != '\n') {
                            main.xschars();
                        } else {
                            main.allnamescom();
                        }
                    } else {
                        while (ls.dicp[0] != 0) {
                            main.finger(ls.dicp);
                            _ = token();
                        }
                        ch = abi.getchar();
                    }
                }
            },
            ':', '/' => {
                _ = token();
                main.rs.lastid = 0;
                main.command();
            },
            '!' => {
                lb = rdline();
                if (lb == null) continue;
                main.rs.lastid = 0;
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
                    if (main.srcUpdate() != 0) {
                        main.loadfile(main.rs.current_script.?);
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
                if (main.rs.verbosity != 0) {
                    word.print("\nmiranda logout\n", .{});
                }
                lineedit.deinit(); // persist history (no-op if not interactive)
                abi.exit(0);
            },
            else => {
                _ = abi.ungetc(ch, main.getStdin().?);
                main.rs.lastid = 0;
                heap.tp(heap.h(ls.cook_stdin)).* = 0;
                main.rs.rv_expr = 0;
                ls.c = word.EVAL;
                main.rs.echoing = 0;
                main.cs.polyshowerror = 0;
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
                main.rs.echoing = main.rs.verbosity & main.rs.listing;
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
        abi.siglongjmp(&main.rs.env, 1);
    } else {
        word.print("\nFLOATING POINT OVERFLOW\n", .{});
        abi.exit(1);
    }
}

// Relocated REPL and interactive driver functions
/// Compile `x` and send its value to standard output — used to run a script's `main`.
pub fn obey(x_in: Word) void {
    var x = x_in;
    const typ = main.typeOf(x);
    x = main.codegen(x);
    if (main.cs.polyshowerror != 0) return;
    core_state.s.compiling = 0;
    const list_t: Word = 4;
    const char_t: Word = 3;
    const islist = typ >= main.ATOMLIMIT and getTag(typ) == AP and h(typ) == list_t;
    const out_val: Word = if (islist and t(typ) == main.rs.message)
        x
    else blk: {
        const inner: Word = if (islist and t(typ) == char_t)
            x
        else
            abi.make(AP, abi.mkshow(0, 0, typ), x);
        break :blk abi.make(CONS, abi.make(AP, main.rs.standardout, inner), NIL);
    };
    abi.output(out_val);
}

/// Evaluate a typed REPL expression: compile it and fork via `process`; the child prints the result and exits, leaving the parent's heap untouched.
pub fn evaluateRepl(x_in: Word) void {
    var x = x_in;
    const typ = main.typeOf(x);
    if (typ == word.wrong_t) return;
    main.rs.lastexp = x;
    x = main.codegen(x);
    if (main.cs.polyshowerror != 0) return;
    const list_t: Word = 4;
    const char_t: Word = 3;
    const islist = typ >= main.ATOMLIMIT and getTag(typ) == AP and h(typ) == list_t;
    const out_val: Word = if (islist and t(typ) == main.rs.message)
        x
    else blk: {
        const inner: Word = if (islist and t(typ) == char_t)
            x
        else
            abi.make(AP, abi.mkshow(0, 0, typ), x);
        break :blk abi.make(CONS, abi.make(AP, main.rs.standardout, inner), NIL);
    };
    if (process() != 0) {
        // Child: evaluate and print, then exit (compiling=0 only here, parent unaffected).
        _ = signals(abi.SIGINT, @intFromPtr(&dieClean));
        core_state.s.compiling = 0;
        resetgcstats();
        abi.output(out_val);
        _ = word.putchar('\n');
        outstats();
        abi.exit(0);
    }
    // Parent returns here; heap and compiling flag are unchanged.
}

/// SIGINT handler at the prompt: restore input/echo/compile state and `longjmp` back into the command loop.
pub fn reset() callconv(.c) void {
    if (main.rs.echoing != 0) {
        _ = word.putchar('\n');
    }
    main.rs.s_in = main.getStdin();
    main.rs.echoing = 0;
    main.rs.listing = 0;
    core_state.s.compiling = 0;
    core_state.s.commandmode = 0;
    core_state.s.SYNERR = 0;
    main.rs.sigflag = 0;
    if (main.rs.unlinkme) |u| {
        _ = abi.unlink(u);
        main.rs.unlinkme = null;
    }
    abi.siglongjmp(&main.rs.env, 1);
}

/// Warn that the configured editor lacks open-at-line support, disabling `??` and related features.
pub fn edWarn() void {
    word.print("The currently installed editor command, \"{s}\", does not\ninclude a facility for opening a file at a specified line number.  As a\nresult the `??' command and certain other features of the Miranda system\nare disabled.  See manual section 31/5 on changing the editor for more\ninformation.\n", .{main.rs.editor orelse @constCast("")});
}

/// Print the Miranda release banner (version, plus `(UTF-8)` when applicable).
pub fn announce() void {
    word.print("Miranda release {s}", .{main.versionString(version.version)});
    if (main.utf8test() != 0) {
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
pub fn badEditor() c_int {
    const e = main.rs.editor orelse return 0;
    if (word.strstr(e, "+!") != null or word.strstr(e, "%d") != null or word.strstr(e, "%l") != null) {
        return 0;
    }
    return 1;
}

/// Strip a trailing `+!` open-at-line marker from the editor command, in place.
pub fn fixEditor() void {
    const e = main.rs.editor orelse return;
    const len = word.strlen(e);
    var p = e + len - 1;
    while (p != e and p[0] == ' ') : (p -= 1) {}
    if (p[0] == '!') {
        p -= 1;
        while (p != e and p[0] == ' ') : (p -= 1) {}
        if (p[0] == '+') {
            p[0] = 0;
        }
    }
}

/// Read and type-check one expression of type `t_val` from file `f` (the `readvals` path). Returns its codegen, or `EOF`; re-prompts interactively and aborts on bad file data.
pub fn parseLine(t_val: Word, f: ?*word.FILE, fil: Word) Word {
    var t1: Word = undefined;
    var ch: c_int = undefined;
    main.rs.lastexp = word.UNDEF;
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
        main.rs.echoing = 0;
        core_state.s.commandmode = 1;
        main.rs.s_in = f;
        _ = parser_api.parseCurrent() catch {};
        main.rs.s_in = main.getStdin();
        if (core_state.s.SYNERR != 0) {
            core_state.s.SYNERR = 0;
            main.rs.lastexp = word.UNDEF;
        } else {
            t1 = main.typeOf(main.rs.lastexp);
            if (t1 == word.wrong_t) {
                main.rs.lastexp = word.UNDEF;
            } else if (abi.subsumes(abi.instantiate(t1), t_val) == 0) {
                word.print("data has wrong type :: ", .{});
                abi.outType(t1);
                word.print("\nshould be :: ", .{});
                abi.outType(t_val);
                _ = word.putc('\n', main.getStdout());
                main.rs.lastexp = word.UNDEF;
            }
        }
        if (main.rs.lastexp != word.UNDEF) {
            return main.codegen(main.rs.lastexp);
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
