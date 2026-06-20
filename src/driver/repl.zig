const std = @import("std");
const main = @import("../main.zig");
const clib = @import("../runtime/main_clib.zig");
const parser_api = @import("../parser/parser_api.zig");

const Word = main.Word;
const NIL = main.NIL;
const CONS = main.CONS;

// State owned by reduce.zig / heap.zig — not yet accessible via @import.
extern var c: Word;
extern var cook_stdin: Word;
extern var tag: [*]u8;
extern var polyshowerror: c_int;

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

    if (clib.sigsetjmp(&main.env, 1) == 0) {
        if (main.magic != 0) {
            main.undump(initscript);
            if (main.files == NIL or main.ND != NIL or main.id_val(main.main_id) == clib.UNDEF) {
                if (main.files != NIL and main.ND == NIL and main.id_val(main.main_id) == clib.UNDEF) {
                    _ = clib.fprintf(main.getStderr(), "%s: main not defined\n", .{.{initscript}});
                }
                _ = clib.fprintf(main.getStderr(), "mira: incorrect use of \"-exec\" flag\n", .{.{}});
                clib.exit(1);
            }
            main.magic = 0;
            clib.obey(main.main_id);
            clib.exit(0);
        }
        _ = signals(clib.SIGINT, @intFromPtr(&main.reset));
        main.undump(initscript);
        if (main.verbosity != 0) {
            _ = clib.printf("for help type /h\n", .{.{}});
        }
    }

    while (true) {
        resetgcstats();
        if (main.verbosity != 0) {
            _ = clib.printf("%s", .{.{main.promptstr}});
        }
        ch = clib.getchar();
        if (main.rechecking != 0 and main.src_update() != 0) {
            main.loadfile(main.current_script.?);
        }
        while (ch == ' ' or ch == '\t') {
            ch = clib.getchar();
        }
        switch (ch) {
            '?' => {
                ch = clib.getchar();
                if (ch == '?') {
                    var x: Word = undefined;
                    var aka: ?[*:0]u8 = null;
                    if (token() == null and main.lastid == 0) {
                        _ = clib.printf("\x07identifier needed after `??'\n", .{.{}});
                        ch = clib.getchar();
                        continue;
                    }
                    if (clib.getchar() != '\n') {
                        main.xschars();
                        continue;
                    }
                    if (main.baded != 0) {
                        main.ed_warn();
                        continue;
                    }
                    if (main.dicp[0] != 0) {
                        x = clib.findid(main.dicp);
                    } else {
                        _ = clib.printf("??%s\n", .{.{main.get_id(main.lastid)}});
                        x = main.lastid;
                    }
                    if (x == NIL or main.id_type(x) == clib.undef_t) {
                        main.diagnose(if (main.dicp[0] != 0) main.dicp else main.get_id(main.lastid));
                        main.lastid = 0;
                        continue;
                    }
                    if (main.id_who(x) == NIL) {
                        _ = clib.printf("%s -- primitive to Miranda\n", .{.{if (main.dicp[0] != 0) main.dicp else main.get_id(main.lastid)}});
                        main.lastid = 0;
                        continue;
                    }
                    main.lastid = x;
                    x = main.id_who(x);
                    if (tag[@intCast(x)] == CONS) {
                        aka = @ptrFromInt(@as(usize, @intCast(main.h(main.h(x)))));
                        x = main.t(x);
                    }
                    if (aka != null) {
                        _ = clib.printf("originally defined as \"%s\"\n", .{.{aka.?}});
                    }
                    main.editfile(@ptrFromInt(@as(usize, @intCast(main.h(x)))), @intCast(main.t(x)));
                } else {
                    _ = clib.ungetc(ch, main.getStdin().?);
                    _ = token();
                    main.lastid = 0;
                    if (main.dicp[0] == 0) {
                        if (clib.getchar() != '\n') {
                            main.xschars();
                        } else {
                            main.allnamescom();
                        }
                    } else {
                        while (main.dicp[0] != 0) {
                            main.finger(main.dicp);
                            _ = token();
                        }
                        ch = clib.getchar();
                    }
                }
            },
            ':', '/' => {
                _ = token();
                main.lastid = 0;
                main.command();
            },
            '!' => {
                lb = rdline();
                if (lb == null) continue;
                main.lastid = 0;
                if (lb.?[0] != 0) {
                    var shell: ?[*:0]const u8 = null;
                    var oldsig: usize = undefined;
                    var pid: c_int = undefined;
                    shell = clib.getenv("SHELL");
                    if (shell == null) {
                        shell = "/bin/sh";
                    }
                    oldsig = signals(clib.SIGINT, 1);
                    pid = clib.fork();
                    if (pid != 0) { // parent
                        if (pid == -1) {
                            clib.perror("UNIX error - cannot create process");
                        }
                        while (pid != clib.wait(null)) {}
                        _ = signals(clib.SIGINT, oldsig);
                    } else { // child
                        _ = clib.execl(shell.?, .{shell.?, "-c", lb.?});
                    }
                    if (main.src_update() != 0) {
                        main.loadfile(main.current_script.?);
                    }
                } else {
                    _ = clib.printf("No previous shell command to substitute for \"!\"\n", .{.{}});
                }
            },
            '|' => {
                ch = clib.getchar();
                if (ch != '|') {
                    _ = clib.printf("\x07unknown command - type /h for help\n", .{.{}});
                }
                while (ch != '\n' and ch != clib.EOF) {
                    ch = clib.getchar();
                }
            },
            '\n' => {},
            clib.EOF => {
                if (main.verbosity != 0) {
                    _ = clib.printf("\nmiranda logout\n", .{.{}});
                }
                clib.exit(0);
            },
            else => {
                _ = clib.ungetc(ch, main.getStdin().?);
                main.lastid = 0;
                main.tp(main.h(cook_stdin)).* = 0;
                main.rv_expr = 0;
                c = clib.EVAL;
                main.echoing = 0;
                polyshowerror = 0;
                main.commandmode = 1;
                _ = parser_api.parseCurrent() catch {};
                if (main.SYNERR != 0) {
                    main.SYNERR = 0;
                } else if (c != '\n') {
                    _ = clib.printf("syntax error\n", .{.{}});
                    while (c != '\n' and c != clib.EOF) {
                        c = clib.getchar();
                    }
                }
                main.commandmode = 0;
                main.echoing = main.verbosity & main.listing;
            },
        }
    }
}

export fn process() Word {
    var oldsig: usize = undefined;
    oldsig = signals(clib.SIGINT, 1);
    const pid = clib.fork();
    if (pid != 0) { // parent
        var status: c_int = 0;
        if (pid == -1) {
            clib.perror("UNIX error - cannot create process");
            return 0;
        }
        while (pid != clib.wait(&status)) {}
        if (WIFSIGNALED(status)) {
            const cd: [*:0]const u8 = if ((status & 0x80) != 0) " (core dumped)" else "";
            const sig = WTERMSIG(status);
            switch (sig) {
                clib.SIGBUS => _ = clib.fprintf(main.getStderr(), "\n<<...bus error%s>>\n", .{.{cd}}),
                clib.SIGSEGV => _ = clib.fprintf(main.getStderr(), "\n<<...segmentation fault%s>>\n", .{.{cd}}),
                else => _ = clib.fprintf(main.getStderr(), "\n<<...uncaught signal %d>>\n", .{.{sig}}),
            }
        }
        _ = signals(clib.SIGINT, oldsig);
        return 0;
    }
    return 1; // child
}

export fn dieclean() void {
    _ = clib.fprintf(main.getStderr(), "<<...interrupt>>\n", .{.{}});
    outstats();
    clib.exit(0);
}

export fn fpe_error(sig: c_int) void {
    if (main.compiling != 0) {
        _ = signals(sig, @intFromPtr(&fpe_error));
        syntax("floating point number out of range\n");
        main.SYNERR = 0;
        clib.siglongjmp(&main.env, 1);
    } else {
        _ = clib.printf("\nFLOATING POINT OVERFLOW\n", .{.{}});
        clib.exit(1);
    }
}
