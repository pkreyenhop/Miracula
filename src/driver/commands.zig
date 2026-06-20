const std = @import("std");
const main = @import("../main.zig");
const clib = @import("../runtime/main_clib.zig");

const Word = main.Word;
const NIL = main.NIL;

// State owned by heap.zig / reduce.zig — not yet accessible via @import.
extern var tag: [*]u8;
extern var CLASHES: Word;
extern var debug: c_int;

extern fn token() ?[*:0]u8;

// File-private state for the /edit command.
var mirahdr: ?[*:0]u8 = null;
var lmirahdr: ?[*:0]u8 = null;

// File-private state for allnamescom / namescom.
var leftist: c_int = 0;
var words: [400]Word = undefined;

// File-private state for filequote.
var filequote_mlen: usize = 0;

fn spaces(s: Word) void {
    var j = s;
    while (j > 0) : (j -= 1) {
        _ = clib.putchar(' ');
    }
}

fn is(s: [*:0]const u8) bool {
    return std.mem.eql(u8, std.mem.span(main.dicp), std.mem.span(s));
}

fn filequote(p: [*:0]const u8) void {
    if (filequote_mlen == 0) {
        const last_slash = clib.strrchr(&main.PRELUDE, '/');
        if (last_slash != null) {
            filequote_mlen = @intFromPtr(last_slash.?) - @intFromPtr(&main.PRELUDE) + 1;
        }
    }
    if (clib.strncmp(p, &main.PRELUDE, filequote_mlen) == 0) {
        _ = clib.printf("<%s>", .{.{p + filequote_mlen}});
    } else {
        _ = clib.printf("\"%s\"", .{.{p}});
    }
}

fn namescom(l: Word) void {
    var n = main.fil_defs(l);
    var col_local: Word = 0;
    var undefs: Word = NIL;
    var wp: usize = 0;
    const scrwd = main.twidth();
    if (main.sorted == 0 and n != main.primenv) {
        n = main.alfasort(n);
        main.tp(l).* = n;
    }
    if (n == NIL) return;
    if (main.get_fil(l)) |gf| {
        filequote(gf);
    } else {
        _ = clib.printf("primitive:", .{.{}});
    }
    _ = clib.printf("\n", .{.{}});
    while (n != NIL) {
        if (main.id_type(main.h(n)) == clib.wrong_t or main.id_val(main.h(n)) != clib.UNDEF) {
            const w = @as(Word, @intCast(clib.strlen(main.get_id(main.h(n)))));
            if (col_local + w < @as(Word, @intCast(scrwd))) {
                col_local += if (col_local != 0) 1 else 0;
            } else if (wp > 0 and col_local + w >= @as(Word, @intCast(scrwd))) {
                var i: Word = 0;
                var r: Word = 0;
                if (wp > 1) {
                    i = @divTrunc(@as(Word, @intCast(scrwd)) - col_local, @as(Word, @intCast(wp - 1)));
                    r = @mod(@as(Word, @intCast(scrwd)) - col_local, @as(Word, @intCast(wp - 1)));
                } else {
                    _ = clib.fprintf(main.getStderr(), "Internal error: i and r used uninitialized in namescom()\nPlease report it to miranda@groups.io\n", .{.{}});
                    clib.abort();
                }
                if (i + (if (r > 0) @as(Word, 1) else 0) > 3) {
                    i = 0;
                    r = 0;
                }
                if (leftist != 0) {
                    col_local = 0;
                    while (col_local < wp) {
                        _ = clib.printf("%s", .{.{main.get_id(words[@as(usize, @intCast(col_local))])}});
                        col_local += 1;
                        if (col_local < wp) {
                            spaces(1 + i + if (r > 0) @as(Word, 1) else @as(Word, 0));
                            r -= 1;
                        }
                    }
                } else {
                    r = @as(Word, @intCast(wp)) - 1 - r;
                    col_local = 0;
                    while (col_local < wp) {
                        _ = clib.printf("%s", .{.{main.get_id(words[@as(usize, @intCast(col_local))])}});
                        col_local += 1;
                        if (col_local < wp) {
                            spaces(1 + i + if (r <= 0) @as(Word, 1) else @as(Word, 0));
                            r -= 1;
                        }
                    }
                }
                leftist = if (leftist == 0) 1 else 0;
                wp = 0;
                col_local = 0;
                _ = clib.putchar('\n');
            }
            col_local += w;
            words[wp] = main.h(n);
            wp += 1;
        } else {
            undefs = main.cons(main.h(n), undefs);
        }
        n = main.t(n);
    }
    if (wp > 0) {
        col_local = 0;
        while (col_local < wp) {
            _ = clib.printf("%s", .{.{main.get_id(words[@as(usize, @intCast(col_local))])}});
            col_local += 1;
            _ = clib.putc(if (col_local == wp) '\n' else ' ', main.getStdout());
        }
    }
    if (undefs == NIL) return;
    undefs = main.reverse(undefs);
    clib.printlist(@constCast("SPECIFIED BUT NOT DEFINED: "), undefs);
}

pub export fn command() void {
    var t_val: ?[*:0]u8 = undefined;
    var ch: c_int = undefined;
    var ch1: c_int = undefined;
    switch (main.dicp[0]) {
        'a' => {
            if (is("a") or is("aux")) {
                if (clib.getchar() != '\n') return;
                _ = clib.strcpy(&main.linebuf, main.miralib.?);
                _ = clib.strcat(&main.linebuf, "/auxfile");
                main.filecopy(@as([*:0]const u8, @ptrCast(&main.linebuf)));
                return;
            }
        },
        'c' => {
            if (is("count")) {
                if (clib.getchar() != '\n') return;
                main.atcount = 1;
                return;
            }
            if (is("cd")) {
                var d = token();
                if (d == null) {
                    d = @constCast(clib.getenv("HOME"));
                } else {
                    d = clib.addextn(0, d.?);
                }
                if (clib.getchar() != '\n') return;
                if (clib.chdir(d.?) == -1) {
                    _ = clib.printf("cannot cd to %s\n", .{.{d.?}});
                } else if (main.src_update() != 0) {
                    main.undump(main.current_script.?);
                }
                return;
            }
        },
        'd' => {
            if (is("dic")) {
                if (token() == null) {
                    _ = clib.getchar();
                    _ = clib.printf("%ld chars", .{.{main.DICSPACE}});
                    if (main.DICSPACE != 100000) {
                        _ = clib.printf(" (default=%ld)", .{.{@as(c_long, 100000)}});
                    }
                    _ = clib.printf(" %ld in use\n", .{.{@as(c_long, @intCast(@intFromPtr(main.dicq) - @intFromPtr(main.dic.?)))}});
                    return;
                }
                if (clib.getchar() != '\n') return;
                _ = clib.printf("sorry, cannot change size of dictionary while in use\n", .{.{}});
                _ = clib.printf("(/q and reinvoke with flag: mira -dic %s ... )\n", .{.{main.dicp}});
                return;
            }
        },
        'e' => {
            if (is("e") or is("edit")) {
                var mf: ?[*:0]u8 = null;
                if (token()) |tok| {
                    t_val = clib.addextn(1, tok);
                } else {
                    t_val = main.current_script;
                }
                if (clib.getchar() != '\n') return;
                if (!main.fileExists(t_val.?)) {
                    if (lmirahdr == null) {
                        main.dicp = main.dicq;
                        _ = clib.strcpy(main.dicp, clib.getenv("HOME"));
                        if (clib.strcmp(main.dicp, "/") == 0) {
                            main.dicp[0] = 0;
                        }
                        _ = clib.strcat(main.dicp, "/.mirahdr");
                        lmirahdr = main.dicp;
                        main.dicq = main.dicp + clib.strlen(main.dicp) + 1;
                    }
                    if (main.fileExists(lmirahdr.?)) {
                        mf = lmirahdr;
                    }
                    if (mf == null and mirahdr == null) {
                        main.dicp = main.dicq;
                        _ = clib.strcpy(main.dicp, main.miralib.?);
                        _ = clib.strcat(main.dicp, "/.mirahdr");
                        mirahdr = main.dicp;
                        main.dicq = main.dicp + clib.strlen(main.dicp) + 1;
                    }
                    if (mf == null and main.fileExists(mirahdr.?)) {
                        mf = mirahdr;
                    }
                    if (mf != null and t_val != main.current_script) {
                        _ = clib.printf("open new script \"%s\"? [ny]", .{.{t_val.?}});
                        ch1 = clib.getchar();
                        ch = ch1;
                        while (ch != '\n' and ch != clib.EOF) {
                            ch = clib.getchar();
                        }
                        if (ch1 != 'y' and ch1 != 'Y') {
                            return;
                        }
                    }
                    if (mf != null) {
                        main.filecp(mf.?, t_val.?);
                    }
                }
                const err_line_num: c_int = if (clib.strcmp(t_val.?, main.current_script.?) == 0) @intCast(main.errline) else if (main.errs != 0 and clib.strcmp(t_val.?, @ptrFromInt(@as(usize, @intCast(main.h(main.errs))))) == 0) @intCast(main.t(main.errs)) else @intCast(clib.geterrlin(t_val.?));
                editfile(t_val.?, err_line_num);
                return;
            }
            if (is("editor")) {
                const hold = @as([*]u8, @ptrCast(&main.linebuf[0]));
                if (main.getln(main.getStdin(), clib.pnlim - 1, hold) == 0) {
                    return;
                }
                if (hold[0] == 0) {
                    _ = clib.printf("%s\n", .{.{main.editor orelse @constCast("")}});
                    return;
                }
                var h_ptr = hold + clib.strlen(hold);
                while ((h_ptr - 1)[0] == ' ' or (h_ptr - 1)[0] == '\t') {
                    h_ptr -= 1;
                    h_ptr[0] = 0;
                }
                if (hold[0] == '"' or hold[0] == '\'') {
                    _ = clib.printf("please type name of editor without quotation marks\n", .{.{}});
                    return;
                }
                _ = clib.printf("change editor to: \"%s\"? [ny]", .{.{hold}});
                ch1 = clib.getchar();
                ch = ch1;
                while (ch != '\n' and ch != clib.EOF) {
                    ch = clib.getchar();
                }
                if (ch1 != 'y' and ch1 != 'Y') {
                    _ = clib.printf("editor not changed\n", .{.{}});
                    return;
                }
                _ = clib.strcpy(&main.ebuf, hold);
                main.editor = @as([*:0]u8, @ptrCast(&main.ebuf));
                main.fixeditor();
                main.echoing = main.verbosity & main.listing;
                main.rc_write();
                _ = clib.printf("editor = %s\n", .{.{main.editor orelse @constCast("")}});
                return;
            }
        },
        'f' => {
            if (is("f") or is("file")) {
                const t_tok = token();
                if (clib.getchar() != '\n') return;
                if (t_tok) |tok| {
                    t_val = clib.addextn(1, tok);
                    _ = clib.keep(t_val.?);
                } else {
                    t_val = null;
                }
                if (t_val != null) {
                    main.errline = 0;
                    main.errs = 0;
                }
                if (t_val != null) {
                    if (clib.strcmp(t_val.?, main.current_script.?) != 0 or (main.files == NIL and clib.okdump(t_val.?) != 0)) {
                        CLASHES = NIL;
                        main.undump(t_val.?);
                        if (CLASHES != NIL) {
                            main.loadfile(t_val.?);
                        }
                    } else {
                        main.loadfile(t_val.?);
                    }
                } else {
                    _ = clib.printf("%s%s\n", .{.{main.current_script.?, @as([*:0]const u8, if (main.files == NIL) " (not loaded)" else "")}});
                }
                return;
            }
            if (is("files")) {
                if (clib.getchar() != '\n') return;
                var f = main.files;
                while (f != NIL) : (f = main.t(f)) {
                    _ = clib.printf("(%s,%ld,%ld)", .{.{main.get_fil(main.h(f)), main.fil_time(main.h(f)), main.fil_share(main.h(f))}});
                    clib.printlist(@constCast(""), main.fil_defs(main.h(f)));
                }
                return;
            }
            if (is("find")) {
                var i: Word = 0;
                while (token() != null) {
                    const x = clib.findid(main.dicp);
                    i += 1;
                    if (x != NIL) {
                        const n = main.get_id(x);
                        var y = main.primenv;
                        while (y != NIL) : (y = main.t(y)) {
                            if (tag[@intCast(main.h(y))] == clib.ID) {
                                if (main.h(y) == x or clib.strcmp(clib.getaka(main.h(y)), n) == 0) {
                                    finger(main.get_id(main.h(y)));
                                }
                            }
                        }
                        var ff = main.files;
                        while (ff != NIL) : (ff = main.t(ff)) {
                            var y_def = main.fil_defs(main.h(ff));
                            while (y_def != NIL) : (y_def = main.t(y_def)) {
                                if (tag[@intCast(main.h(y_def))] == clib.ID) {
                                    if (main.h(y_def) == x or clib.strcmp(clib.getaka(main.h(y_def)), n) == 0) {
                                        finger(main.get_id(main.h(y_def)));
                                    }
                                }
                            }
                        }
                    }
                }
                ch = clib.getchar();
                if (i == 0) {
                    _ = clib.printf("\x07extra characters at end of command\n", .{.{}});
                }
                return;
            }
        },
        'g' => {
            if (is("gc")) {
                if (clib.getchar() != '\n') return;
                main.atgc = 1;
                return;
            }
        },
        'h' => {
            if (is("h") or is("help")) {
                if (clib.getchar() != '\n') return;
                _ = clib.strcpy(&main.linebuf, main.miralib.?);
                _ = clib.strcat(&main.linebuf, "/helpfile");
                main.filecopy(@as([*:0]const u8, @ptrCast(&main.linebuf)));
                return;
            }
            if (is("heap")) {
                var x: c_long = undefined;
                if (token() == null) {
                    _ = clib.getchar();
                    _ = clib.printf("%ld cells", .{.{main.SPACELIMIT}});
                    if (main.SPACELIMIT != 2500000) {
                        _ = clib.printf(" (default=%ld)", .{.{@as(c_long, 2500000)}});
                    }
                    _ = clib.printf("\n", .{.{}});
                    return;
                }
                if (clib.getchar() != '\n') return;
                if (clib.sscanf(main.dicp, "%ld", .{&x}) != 1 or main.badval(x)) {
                    _ = clib.printf("illegal value (heap unchanged)\n", .{.{}});
                    return;
                }
                if (x < clib.trueheapsize()) {
                    _ = clib.printf("sorry, cannot shrink heap to %ld at this time\n", .{.{x}});
                } else {
                    if (x != main.SPACELIMIT) {
                        main.SPACELIMIT = x;
                        clib.resetheap();
                    }
                    _ = clib.printf("heaplimit = %ld cells\n", .{.{main.SPACELIMIT}});
                    main.rc_write();
                }
                return;
            }
            if (is("hush")) {
                if (clib.getchar() != '\n') return;
                main.echoing = 0;
                main.verbosity = 0;
                return;
            }
        },
        'l' => {
            if (is("list")) {
                if (clib.getchar() != '\n') return;
                main.listing = 1;
                main.echoing = main.verbosity & main.listing;
                main.rc_write();
                return;
            }
        },
        'm' => {
            if (is("m") or is("man")) {
                if (clib.getchar() != '\n') return;
                manaction();
                return;
            }
            if (is("miralib")) {
                if (clib.getchar() != '\n') return;
                _ = clib.printf("%s\n", .{.{main.miralib.?}});
                return;
            }
        },
        'n' => {
            if (is("nocount")) {
                if (clib.getchar() != '\n') return;
                main.atcount = 0;
                return;
            }
            if (is("nogc")) {
                if (clib.getchar() != '\n') return;
                main.atgc = 0;
                return;
            }
            if (is("nohush")) {
                if (clib.getchar() != '\n') return;
                main.echoing = main.listing;
                main.verbosity = 1;
                return;
            }
            if (is("nolist")) {
                if (clib.getchar() != '\n') return;
                main.listing = 0;
                main.echoing = 0;
                main.rc_write();
                return;
            }
            if (is("norecheck")) {
                if (clib.getchar() != '\n') return;
                main.rechecking = 0;
                main.rc_write();
                return;
            }
        },
        'q' => {
            if (is("q") or is("quit")) {
                if (clib.getchar() != '\n') return;
                if (main.verbosity != 0) {
                    _ = clib.printf("miranda logout\n", .{.{}});
                }
                clib.exit(0);
            }
        },
        'r' => {
            if (is("recheck")) {
                if (clib.getchar() != '\n') return;
                main.rechecking = 2;
                main.rc_write();
                return;
            }
        },
        's' => {
            if (is("s") or is("settings")) {
                if (clib.getchar() != '\n') return;
                _ = clib.printf("*\theap %ld\n", .{.{main.SPACELIMIT}});
                _ = clib.printf("*\tdic %ld\n", .{.{main.DICSPACE}});
                _ = clib.printf("*\teditor = %s\n", .{.{main.editor orelse @constCast("")}});
                _ = clib.printf("*\t%slist\n", .{.{@as([*:0]const u8, if (main.listing != 0) "" else "no")}});
                _ = clib.printf("*\t%srecheck\n", .{.{@as([*:0]const u8, if (main.rechecking != 0) "" else "no")}});
                if (main.strictif == 0) {
                    _ = clib.printf("\t-nostrictif (deprecated!)\n", .{.{}});
                }
                if (main.atcount != 0) {
                    _ = clib.printf("\tcount\n", .{.{}});
                }
                if (main.atgc != 0) {
                    _ = clib.printf("\tgc\n", .{.{}});
                }
                if (main.UTF8 != 0) {
                    _ = clib.printf("\tUTF-8 i/o\n", .{.{}});
                }
                if (main.verbosity == 0) {
                    _ = clib.printf("\thush\n", .{.{}});
                }
                if (debug != 0) {
                    _ = clib.printf("\tdebug 0%o\n", .{.{debug}});
                }
                _ = clib.printf("\n* items remembered between sessions\n", .{.{}});
                return;
            }
        },
        'v' => {
            if (is("v") or is("version")) {
                if (clib.getchar() != '\n') return;
                main.v_info(0);
                return;
            }
        },
        'V' => {
            if (is("V")) {
                if (clib.getchar() != '\n') return;
                main.v_info(1);
                return;
            }
        },
        else => {},
    }
    xschars();
}

pub export fn manaction() void {
    _ = clib.sprintf(&main.linebuf, "\"%s/menudriver\" \"%s/manual\"", .{main.miralib.?, main.miralib.?});
    _ = clib.system(&main.linebuf);
}

pub export fn editfile(t_val: [*:0]const u8, line: c_int) void {
    var line_val = line;
    const ebuf_local = @as([*]u8, @ptrCast(&main.linebuf[0]));
    var p = ebuf_local;
    var q = main.editor.?;
    var tdone: c_int = 0;
    if (line_val == 0) {
        line_val = 1;
    }
    while (q[0] != 0) {
        const ch = q[0];
        q += 1;
        p[0] = ch;
        p += 1;
        if ((p - 1)[0] == '\\' and (q[0] == '!' or q[0] == '%')) {
            (p - 1)[0] = q[0];
            q += 1;
        } else if ((p - 1)[0] == '!') {
            p -= 1;
            _ = clib.sprintf(p, "%d", .{line_val});
            p += clib.strlen(p);
        } else if ((p - 1)[0] == '%') {
            (p - 1)[0] = '"';
            p[0] = 0;
            const limit = @as(usize, @intCast(clib.BUFSIZE + @intFromPtr(ebuf_local) - @intFromPtr(p)));
            _ = clib.strncat(p, t_val, limit);
            p += clib.strlen(p);
            p[0] = '"';
            p += 1;
            p[0] = 0;
            tdone = 1;
        }
    }
    p[0] = 0;
    if (tdone == 0) {
        p[0] = ' ';
        p += 1;
        p[0] = '"';
        p += 1;
        p[0] = 0;
        const limit = @as(usize, @intCast(clib.BUFSIZE + @intFromPtr(ebuf_local) - @intFromPtr(p)));
        _ = clib.strncat(p, t_val, limit);
        p += clib.strlen(p);
        p[0] = '"';
        p += 1;
        p[0] = 0;
    }
    _ = clib.system(ebuf_local);
    if (main.src_update() != 0) {
        main.loadfile(main.current_script.?);
    }
}

pub export fn xschars() void {
    var ch: c_int = undefined;
    _ = clib.printf("\x07extra characters at end of command\n", .{.{}});
    while (true) {
        ch = clib.getchar();
        if (ch == '\n' or ch == clib.EOF) break;
    }
}

pub export fn finger(n: [*:0]const u8) void {
    const x = clib.findid(@constCast(n));
    var line: Word = 0;
    var s: ?[*:0]u8 = null;
    if (x != NIL and main.id_type(x) != clib.undef_t) {
        if (main.id_who(x) != NIL) {
            const here_val = main.get_here(x);
            s = @ptrFromInt(@as(usize, @intCast(main.h(here_val))));
            line = main.t(here_val);
        }
        if (main.lastid == 0) {
            main.lastid = x;
        }
        clib.report_type(x);
        if (main.id_who(x) == NIL) {
            _ = clib.printf(" ||primitive to Miranda\n", .{.{}});
        } else {
            const aka = clib.getaka(x);
            const aka_opt: ?[*:0]const u8 = if (clib.strcmp(aka, main.get_id(x)) == 0) null else aka;
            if (main.id_val(x) == clib.UNDEF and main.id_type(x) != clib.wrong_t) {
                _ = clib.printf(" ||(UNDEFINED) specified in ", .{.{}});
            } else if (main.id_val(x) == clib.FREE) {
                _ = clib.printf(" ||(FREE) specified in ", .{.{}});
            } else if (main.id_type(x) == clib.type_t and main.t_class(x) == clib.free_t) {
                _ = clib.printf(" ||(free type) specified in ", .{.{}});
            } else {
                const class_str: [*:0]const u8 = if (main.id_type(x) == clib.type_t and main.t_class(x) == clib.abstract_t) "(abstract type) " else if (main.id_type(x) == clib.type_t and main.t_class(x) == clib.algebraic_t) "(algebraic type) " else if (main.id_type(x) == clib.type_t and main.t_class(x) == clib.placeholder_t) "(placeholder type) " else if (main.id_type(x) == clib.type_t and main.t_class(x) == clib.synonym_t) "(synonym type) " else "";
                _ = clib.printf(" ||%sdefined in ", .{.{class_str}});
            }
            filequote(s.?);
            if (main.baded != 0 or main.rechecking != 0) {
                _ = clib.printf(" line %ld", .{.{line}});
            }
            if (aka_opt) |aka_s| {
                _ = clib.printf(" (as \"%s\")\n", .{.{aka_s}});
            } else {
                _ = clib.putchar('\n');
            }
        }
        if (main.atobject != 0) {
            _ = clib.printf("%s = ", .{.{main.get_id(x)}});
            clib.out(main.getStdout(), main.id_val(x));
            _ = clib.putchar('\n');
        }
        return;
    }
    diagnose(n);
}

pub export fn diagnose(n: [*:0]const u8) void {
    var i: usize = 0;
    if (clib.isalpha(@intCast(n[0])) != 0) {
        while (n[i] != 0 and clib.okid(n[i]) != 0) {
            i += 1;
        }
    }
    if (n[i] != 0) {
        _ = clib.printf("\"%s\" -- not an identifier\n", .{.{n}});
        return;
    }
    const presym = [_][*:0]const u8{
        "abstype", "div", "if", "mod", "otherwise", "readvals", "show", "type", "where", "with",
    };
    const presym_n = [_]c_int{ 21, 8, 15, 8, 15, 31, 23, 22, 15, 21 };
    inline for (presym, presym_n) |sym, sym_n| {
        if (clib.strcmp(n, sym) == 0) {
            _ = clib.printf("%s -- keyword (see manual, section %d)\n", .{.{n, sym_n}});
            return;
        }
    }
    _ = clib.printf("identifier \"%s\" not in scope\n", .{.{n}});
}

pub export fn allnamescom() void {
    var s: Word = undefined;
    var x = main.ND;
    var y = main.ND;
    var z: Word = 0;
    leftist = 0;
    namescom(main.make_fil(if (main.nostdenv != 0) null else @as([*:0]const u8, @ptrCast(&main.STDENV)), 0, 0, main.primenv));
    if (main.files == NIL) return;
    s = main.t(main.files);
    while (s != NIL) : (s = main.t(s)) {
        namescom(main.h(s));
    }
    namescom(main.h(main.files));
    main.sorted = 1;

    while (x != NIL and main.id_type(main.h(x)) == clib.undef_t) {
        x = main.t(x);
    }
    while (y != NIL and main.id_type(main.h(y)) != clib.undef_t) {
        y = main.t(y);
    }
    if (x != NIL) {
        _ = clib.printf("WARNING, SCRIPT CONTAINS TYPE ERRORS: ", .{.{}});
        while (x != NIL) : (x = main.t(x)) {
            if (main.id_type(main.h(x)) != clib.undef_t) {
                if (z == 0) {
                    z = 1;
                } else {
                    _ = clib.putchar(',');
                }
                clib.out(main.getStdout(), main.h(x));
            }
        }
        _ = clib.printf(";\n", .{.{}});
    }
    if (y != NIL) {
        _ = clib.printf("%s UNDEFINED NAMES: ", .{.{@as([*:0]const u8, if (z != 0) "AND" else "WARNING, SCRIPT CONTAINS")}});
        z = 0;
        while (y != NIL) : (y = main.t(y)) {
            if (main.id_type(main.h(y)) == clib.undef_t) {
                if (z == 0) {
                    z = 1;
                } else {
                    _ = clib.putchar(',');
                }
                clib.out(main.getStdout(), main.h(y));
            }
        }
        _ = clib.printf(";\n", .{.{}});
    }
}
