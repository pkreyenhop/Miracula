const std = @import("std");
const word = @import("../runtime/word.zig");
const main = @import("../main.zig");
const abi = @import("../runtime/main_clib.zig");
const parser_api = @import("../parser/parser_api.zig");

const Word = main.Word;
const NIL = main.NIL;
const CONS = main.CONS;
const AP = main.AP;
const h = main.heap.h;
const t = main.heap.t;

const lex_state = @import("../parser/lex_state.zig");
const ls = &lex_state.ls;

// State owned by reduce.zig / heap.zig — not yet accessible via @import.
inline fn getTag(x: Word) u8 {
    return main.heap.heap.getTag(x);
}

extern fn signals(signum: c_int, handler: usize) usize;
extern fn resetgcstats() void;
extern fn outstats() void;
extern fn syntax(s: [*:0]const u8) void;
extern fn token() ?[*:0]u8;
extern fn rdline() ?[*:0]u8;
extern fn reset_lex() void;

fn WIFSIGNALED(status: c_int) bool {
    return (status & 0x7f) != 0 and (status & 0x7f) != 0x7f;
}

fn WTERMSIG(status: c_int) c_int {
    return status & 0x7f;
}

export fn commandloop(initscript: [*:0]u8) void {
    var ch: c_int = undefined;
    var lb: ?[*:0]u8 = undefined;

    if (abi.sigsetjmp(&main.rs.env, 1) == 0) {
        if (main.rs.magic) {
            main.undump(initscript);
            if (main.files == NIL or main.cs.ND != NIL or main.id_val(main.rs.main_id) == word.UNDEF) {
                if (main.files != NIL and main.cs.ND == NIL and main.id_val(main.rs.main_id) == word.UNDEF) {
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
        if (main.rs.verbosity != 0) {
            word.print("{s}", .{main.rs.promptstr});
        }
        ch = abi.getchar();
        if (main.rs.rechecking != 0 and main.src_update() != 0) {
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
                    var aka: ?[*:0]u8 = null;
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
                        main.ed_warn();
                        continue;
                    }
                    if (ls.dicp[0] != 0) {
                        x = abi.findid(ls.dicp);
                    } else {
                        word.print("??{s}\n", .{main.get_id(main.rs.lastid)});
                        x = main.rs.lastid;
                    }
                    if (x == NIL or main.id_type(x) == word.undef_t) {
                        main.diagnose(if (ls.dicp[0] != 0) ls.dicp else main.get_id(main.rs.lastid));
                        main.rs.lastid = 0;
                        continue;
                    }
                    if (main.id_who(x) == NIL) {
                        word.print("{s} -- primitive to Miranda\n", .{@as([*:0]const u8, @ptrCast(if (ls.dicp[0] != 0) ls.dicp else main.get_id(main.rs.lastid)))});
                        main.rs.lastid = 0;
                        continue;
                    }
                    main.rs.lastid = x;
                    x = main.id_who(x);
                    if (getTag(x) == CONS) {
                        aka = @ptrFromInt(@as(usize, @intCast(main.heap.h(main.heap.h(x)))));
                        x = main.heap.t(x);
                    }
                    if (aka != null) {
                        word.print("originally defined as \"{s}\"\n", .{aka.?});
                    }
                    main.editfile(@ptrFromInt(@as(usize, @intCast(main.heap.h(x)))), @intCast(main.heap.t(x)));
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
                    if (main.src_update() != 0) {
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
                abi.exit(0);
            },
            else => {
                _ = abi.ungetc(ch, main.getStdin().?);
                main.rs.lastid = 0;
                main.heap.tp(main.heap.h(ls.cook_stdin)).* = 0;
                main.rs.rv_expr = 0;
                ls.c = word.EVAL;
                main.rs.echoing = 0;
                main.cs.polyshowerror = 0;
                main.commandmode = 1;
                _ = parser_api.parseCurrent() catch {};
                if (main.SYNERR != 0) {
                    main.SYNERR = 0;
                } else if (ls.c != '\n') {
                    word.print("syntax error\n", .{});
                    while (ls.c != '\n' and ls.c != abi.EOF) {
                        ls.c = abi.getchar();
                    }
                }
                main.commandmode = 0;
                main.rs.echoing = main.rs.verbosity & main.rs.listing;
            },
        }
    }
}

export fn process() Word {
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

export fn dieclean() void {
    word.printErr("<<...interrupt>>\n", .{});
    outstats();
    abi.exit(0);
}

export fn fpe_error(sig: c_int) void {
    if (main.compiling != 0) {
        _ = signals(sig, @intFromPtr(&fpe_error));
        syntax("floating point number out of range\n");
        main.SYNERR = 0;
        abi.siglongjmp(&main.rs.env, 1);
    } else {
        word.print("\nFLOATING POINT OVERFLOW\n", .{});
        abi.exit(1);
    }
}

// Relocated REPL and interactive driver functions
pub export fn obey(x_in: Word) void {
    var x = x_in;
    const typ = main.type_of(x);
    x = main.codegen(x);
    if (main.cs.polyshowerror != 0) return;
    main.compiling = 0;
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

pub export fn evaluate_repl(x_in: Word) void {
    var x = x_in;
    const typ = main.type_of(x);
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
        _ = signals(abi.SIGINT, @intFromPtr(&dieclean));
        main.compiling = 0;
        resetgcstats();
        abi.output(out_val);
        _ = word.putchar('\n');
        outstats();
        abi.exit(0);
    }
    // Parent returns here; heap and compiling flag are unchanged.
}

pub export fn reset() void {
    if (main.rs.echoing != 0) {
        _ = word.putchar('\n');
    }
    main.rs.s_in = main.getStdin();
    main.rs.echoing = 0;
    main.rs.listing = 0;
    main.compiling = 0;
    main.commandmode = 0;
    main.SYNERR = 0;
    main.rs.sigflag = 0;
    if (main.rs.unlinkme) |u| {
        _ = abi.unlink(u);
        main.rs.unlinkme = null;
    }
    abi.siglongjmp(&main.rs.env, 1);
}

pub fn ed_warn() void {
    word.print("The currently installed editor command, \"{s}\", does not\ninclude a facility for opening a file at a specified line number.  As a\nresult the `??' command and certain other features of the Miranda system\nare disabled.  See manual section 31/5 on changing the editor for more\ninformation.\n", .{main.rs.editor orelse @constCast("")});
}

pub fn announce() void {
    word.print("Miranda release {s}", .{main.strvers(main.version)});
    if (main.utf8test() != 0) {
        word.print(" (UTF-8)", .{});
    }
    word.print("\n", .{});
}

pub fn getln(in: ?*word.FILE, n_val: Word, s_ptr: [*]u8) c_int {
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

pub fn badeditor() c_int {
    const e = main.rs.editor orelse return 0;
    if (word.strstr(e, "+!") != null or word.strstr(e, "%d") != null or word.strstr(e, "%l") != null) {
        return 0;
    }
    return 1;
}

pub fn fixeditor() void {
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

pub export fn parseline(t_val: Word, f: ?*word.FILE, fil: Word) Word {
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
        main.commandmode = 1;
        main.rs.s_in = f;
        _ = parser_api.parseCurrent() catch {};
        main.rs.s_in = main.getStdin();
        if (main.SYNERR != 0) {
            main.SYNERR = 0;
            main.rs.lastexp = word.UNDEF;
        } else {
            t1 = main.type_of(main.rs.lastexp);
            if (t1 == word.wrong_t) {
                main.rs.lastexp = word.UNDEF;
            } else if (abi.subsumes(abi.instantiate(t1), t_val) == 0) {
                word.print("data has wrong type :: ", .{});
                abi.out_type(t1);
                word.print("\nshould be :: ", .{});
                abi.out_type(t_val);
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
                word.printErr("readvals: bad data in file \"{s}\"\n", .{abi.getstring(fil, @constCast(""))});
            } else {
                word.printErr("bad data in $+ input\n", .{});
            }
            abi.outstats();
            abi.exit(1);
        }
    }
}
