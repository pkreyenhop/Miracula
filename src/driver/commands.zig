const std = @import("std");
const word = @import("../runtime/word.zig");
const strtab = @import("../runtime/strtab.zig");
const main = @import("../main.zig");
const abi = @import("../runtime/main_clib.zig");

const Word = main.Word;
const NIL = main.NIL;

// State owned by heap.zig / reduce.zig — not yet accessible via @import.
inline fn getTag(x: Word) u8 {
    return main.heap.heap.getTag(x);
}

const lex_state = @import("../parser/lex_state.zig");
const r7_lex = @import("../parser/lex.zig");
const core_state = @import("../runtime/core_state.zig");
const heap = @import("../runtime/heap.zig");
const ls = lex_state.ls;

const token = r7_lex.token;
// File-private state for the /edit command.
var mirahdr: ?[*:0]u8 = null;
var lmirahdr: ?[*:0]u8 = null;

// File-private state for allnamescom / namescom.
var leftist: bool = false;
var words: [400]Word = undefined;

// File-private state for filequote.
var filequote_mlen: usize = 0;

fn spaces(s: Word) void {
    var j = s;
    while (j > 0) : (j -= 1) {
        _ = word.putchar(' ');
    }
}

fn is(s: [:0]const u8) bool {
    return std.mem.eql(u8, std.mem.span(@as([*:0]u8, @ptrCast(ls.dicp))), s);
}

fn filequote(p: [:0]const u8) void {
    if (filequote_mlen == 0) {
        const last_slash = word.strrchr(&main.rs.PRELUDE, '/');
        if (last_slash != null) {
            filequote_mlen = @intFromPtr(last_slash.?) - @intFromPtr(&main.rs.PRELUDE) + 1;
        }
    }
    if (word.strncmp(p.ptr, &main.rs.PRELUDE, filequote_mlen) == 0) {
        word.print("<{s}>", .{p.ptr + filequote_mlen});
    } else {
        word.print("\"{s}\"", .{p.ptr});
    }
}

fn namescom(l: Word) void {
    var n = main.fil_defs(l);
    var col_local: Word = 0;
    var undefs: Word = NIL;
    var wp: usize = 0;
    const scrwd = main.twidth();
    if (main.rs.sorted == 0 and n != main.rs.primenv) {
        n = main.alfasort(n);
        main.heap.tp(l).* = n;
    }
    if (n == NIL) return;
    if (main.get_fil(l)) |gf| {
        filequote(std.mem.span(gf));
    } else {
        word.print("primitive:", .{});
    }
    word.print("\n", .{});
    while (n != NIL) {
        if (main.id_type(main.heap.h(n)) == word.wrong_t or main.id_val(main.heap.h(n)) != word.UNDEF) {
            const w = @as(Word, @intCast(word.strlen(main.get_id(main.heap.h(n)))));
            if (col_local + w < @as(Word, @intCast(scrwd))) {
                col_local += if (col_local != 0) 1 else 0;
            } else if (wp > 0 and col_local + w >= @as(Word, @intCast(scrwd))) {
                var i: Word = 0;
                var r: Word = 0;
                if (wp > 1) {
                    i = @divTrunc(@as(Word, @intCast(scrwd)) - col_local, @as(Word, @intCast(wp - 1)));
                    r = @mod(@as(Word, @intCast(scrwd)) - col_local, @as(Word, @intCast(wp - 1)));
                } else {
                    word.printErr("Internal error: i and r used uninitialized in namescom()\nPlease report it to miranda@groups.io\n", .{});
                    abi.abort();
                }
                if (i + (if (r > 0) @as(Word, 1) else 0) > 3) {
                    i = 0;
                    r = 0;
                }
                if (leftist) {
                    col_local = 0;
                    while (col_local < wp) {
                        word.print("{s}", .{main.get_id(words[@as(usize, @intCast(col_local))])});
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
                        word.print("{s}", .{main.get_id(words[@as(usize, @intCast(col_local))])});
                        col_local += 1;
                        if (col_local < wp) {
                            spaces(1 + i + if (r <= 0) @as(Word, 1) else @as(Word, 0));
                            r -= 1;
                        }
                    }
                }
                leftist = !leftist;
                wp = 0;
                col_local = 0;
                _ = word.putchar('\n');
            }
            col_local += w;
            words[wp] = main.heap.h(n);
            wp += 1;
        } else {
            undefs = main.cons(main.heap.h(n), undefs);
        }
        n = main.heap.t(n);
    }
    if (wp > 0) {
        col_local = 0;
        while (col_local < wp) {
            word.print("{s}", .{main.get_id(words[@as(usize, @intCast(col_local))])});
            col_local += 1;
            _ = word.putc(if (col_local == wp) '\n' else ' ', main.getStdout());
        }
    }
    if (undefs == NIL) return;
    undefs = main.reverse(undefs);
    abi.printlist(@constCast("SPECIFIED BUT NOT DEFINED: "), undefs);
}

pub fn command() void {
    var t_val: ?[*:0]u8 = undefined;
    var ch: c_int = undefined;
    var ch1: c_int = undefined;
    switch (ls.dicp[0]) {
        'a' => {
            if (is("a") or is("aux")) {
                if (abi.getchar() != '\n') return;
                _ = word.strcpy(&main.rs.linebuf, main.rs.miralib.?);
                _ = word.strcat(&main.rs.linebuf, "/auxfile");
                main.filecopy(@as([*:0]const u8, @ptrCast(&main.rs.linebuf)));
                return;
            }
        },
        'c' => {
            if (is("count")) {
                if (abi.getchar() != '\n') return;
                main.rs.atcount = 1;
                return;
            }
            if (is("cd")) {
                var d = token();
                if (d == null) {
                    d = @constCast(abi.getenv("HOME"));
                } else {
                    d = abi.addextn(0, d.?);
                }
                if (abi.getchar() != '\n') return;
                if (abi.chdir(d.?) == -1) {
                    word.print("cannot cd to {s}\n", .{d.?});
                } else if (main.src_update() != 0) {
                    main.undump(main.rs.current_script.?);
                }
                return;
            }
        },
        'd' => {
            if (is("dic")) {
                if (token() == null) {
                    _ = abi.getchar();
                    word.print("{} chars", .{main.rs.DICSPACE});
                    if (main.rs.DICSPACE != 100000) {
                        word.print(" (default={})", .{@as(c_long, 100000)});
                    }
                    word.print(" {} in use\n", .{@as(c_long, @intCast(@intFromPtr(ls.dicq) - @intFromPtr(ls.dic.?)))});
                    return;
                }
                if (abi.getchar() != '\n') return;
                word.print("sorry, cannot change size of dictionary while in use\n", .{});
                word.print("(/q and reinvoke with flag: mira -dic {s} ... )\n", .{@as([*:0]const u8, @ptrCast(ls.dicp))});
                return;
            }
        },
        'e' => {
            if (is("e") or is("edit")) {
                var mf: ?[*:0]u8 = null;
                if (token()) |tok| {
                    t_val = abi.addextn(1, tok);
                } else {
                    t_val = main.rs.current_script;
                }
                if (abi.getchar() != '\n') return;
                if (!main.fileExists(t_val.?)) {
                    if (lmirahdr == null) {
                        ls.dicp = ls.dicq;
                        _ = word.strcpy(ls.dicp, abi.getenv("HOME"));
                        if (word.strcmp(ls.dicp, "/") == 0) {
                            ls.dicp[0] = 0;
                        }
                        _ = word.strcat(ls.dicp, "/.mirahdr");
                        lmirahdr = ls.dicp;
                        ls.dicq = ls.dicp + word.strlen(ls.dicp) + 1;
                    }
                    if (main.fileExists(lmirahdr.?)) {
                        mf = lmirahdr;
                    }
                    if (mf == null and mirahdr == null) {
                        ls.dicp = ls.dicq;
                        _ = word.strcpy(ls.dicp, main.rs.miralib.?);
                        _ = word.strcat(ls.dicp, "/.mirahdr");
                        mirahdr = ls.dicp;
                        ls.dicq = ls.dicp + word.strlen(ls.dicp) + 1;
                    }
                    if (mf == null and main.fileExists(mirahdr.?)) {
                        mf = mirahdr;
                    }
                    if (mf != null and t_val != main.rs.current_script) {
                        word.print("open new script \"{s}\"? [ny]", .{t_val.?});
                        ch1 = abi.getchar();
                        ch = ch1;
                        while (ch != '\n' and ch != abi.EOF) {
                            ch = abi.getchar();
                        }
                        if (ch1 != 'y' and ch1 != 'Y') {
                            return;
                        }
                    }
                    if (mf != null) {
                        main.filecp(mf.?, t_val.?);
                    }
                }
                const err_line_num: c_int = if (word.strcmp(t_val.?, main.rs.current_script.?) == 0) @intCast(core_state.s.errline) else if (core_state.s.errs != 0 and word.strcmp(t_val.?, strtab.strOf(main.heap.h(core_state.s.errs))) == 0) @intCast(main.heap.t(core_state.s.errs)) else @intCast(abi.geterrlin(t_val.?));
                editfile(t_val.?, err_line_num);
                return;
            }
            if (is("editor")) {
                const hold = @as([*]u8, @ptrCast(&main.rs.linebuf[0]));
                if (main.getln(main.getStdin(), abi.pnlim - 1, hold) == 0) {
                    return;
                }
                if (hold[0] == 0) {
                    word.print("{s}\n", .{main.rs.editor orelse @constCast("")});
                    return;
                }
                var h_ptr = hold + word.strlen(hold);
                while ((h_ptr - 1)[0] == ' ' or (h_ptr - 1)[0] == '\t') {
                    h_ptr -= 1;
                    h_ptr[0] = 0;
                }
                if (hold[0] == '"' or hold[0] == '\'') {
                    word.print("please type name of editor without quotation marks\n", .{});
                    return;
                }
                word.print("change editor to: \"{s}\"? [ny]", .{@as([*:0]const u8, @ptrCast(hold))});
                ch1 = abi.getchar();
                ch = ch1;
                while (ch != '\n' and ch != abi.EOF) {
                    ch = abi.getchar();
                }
                if (ch1 != 'y' and ch1 != 'Y') {
                    word.print("editor not changed\n", .{});
                    return;
                }
                _ = word.strcpy(&main.rs.ebuf, hold);
                main.rs.editor = @as([*:0]u8, @ptrCast(&main.rs.ebuf));
                main.fixeditor();
                main.rs.echoing = main.rs.verbosity & main.rs.listing;
                main.rc_write();
                word.print("editor = {s}\n", .{main.rs.editor orelse @constCast("")});
                return;
            }
        },
        'f' => {
            if (is("f") or is("file")) {
                const t_tok = token();
                if (abi.getchar() != '\n') return;
                if (t_tok) |tok| {
                    t_val = abi.addextn(1, tok);
                    _ = abi.keep(t_val.?);
                } else {
                    t_val = null;
                }
                if (t_val != null) {
                    core_state.s.errline = 0;
                    core_state.s.errs = 0;
                }
                if (t_val != null) {
                    if (word.strcmp(t_val.?, main.rs.current_script.?) != 0 or (heap.heap.files == NIL and abi.okdump(t_val.?) != 0)) {
                        main.cs.CLASHES = NIL;
                        main.undump(t_val.?);
                        if (main.cs.CLASHES != NIL) {
                            main.loadfile(t_val.?);
                        }
                    } else {
                        main.loadfile(t_val.?);
                    }
                } else {
                    word.print("{s}{s}\n", .{main.rs.current_script.?, @as([*:0]const u8, if (heap.heap.files == NIL) " (not loaded)" else "")});
                }
                return;
            }
            if (is("files")) {
                if (abi.getchar() != '\n') return;
                var f = heap.heap.files;
                while (f != NIL) : (f = main.heap.t(f)) {
                    word.print("({s},{},{})", .{main.get_fil(main.heap.h(f)).?, main.fil_time(main.heap.h(f)), main.fil_share(main.heap.h(f))});
                    abi.printlist(@constCast(""), main.fil_defs(main.heap.h(f)));
                }
                return;
            }
            if (is("find")) {
                var i: Word = 0;
                while (token() != null) {
                    const x = abi.findid(ls.dicp);
                    i += 1;
                    if (x != NIL) {
                        const n = main.get_id(x);
                        var y = main.rs.primenv;
                        while (y != NIL) : (y = main.heap.t(y)) {
                            if (getTag(main.heap.h(y)) == word.ID) {
                                if (main.heap.h(y) == x or word.strcmp(abi.getaka(main.heap.h(y)), n) == 0) {
                                    finger(main.get_id(main.heap.h(y)));
                                }
                            }
                        }
                        var ff = heap.heap.files;
                        while (ff != NIL) : (ff = main.heap.t(ff)) {
                            var y_def = main.fil_defs(main.heap.h(ff));
                            while (y_def != NIL) : (y_def = main.heap.t(y_def)) {
                                if (getTag(main.heap.h(y_def)) == word.ID) {
                                    if (main.heap.h(y_def) == x or word.strcmp(abi.getaka(main.heap.h(y_def)), n) == 0) {
                                        finger(main.get_id(main.heap.h(y_def)));
                                    }
                                }
                            }
                        }
                    }
                }
                ch = abi.getchar();
                if (i == 0) {
                    word.print("\x07extra characters at end of command\n", .{});
                }
                return;
            }
        },
        'g' => {
            if (is("gc")) {
                if (abi.getchar() != '\n') return;
                main.rs.atgc = 1;
                return;
            }
        },
        'h' => {
            if (is("h") or is("help")) {
                if (abi.getchar() != '\n') return;
                _ = word.strcpy(&main.rs.linebuf, main.rs.miralib.?);
                _ = word.strcat(&main.rs.linebuf, "/helpfile");
                main.filecopy(@as([*:0]const u8, @ptrCast(&main.rs.linebuf)));
                return;
            }
            if (is("heap")) {
                var x: c_long = undefined;
                if (token() == null) {
                    _ = abi.getchar();
                    word.print("{} cells", .{main.rs.SPACELIMIT});
                    if (main.rs.SPACELIMIT != 2500000) {
                        word.print(" (default={})", .{@as(c_long, 2500000)});
                    }
                    word.print("\n", .{});
                    return;
                }
                if (abi.getchar() != '\n') return;
                if (abi.sscanf(ls.dicp, "%ld", .{&x}) != 1 or main.badval(x)) {
                    word.print("illegal value (heap unchanged)\n", .{});
                    return;
                }
                if (x < abi.trueheapsize()) {
                    word.print("sorry, cannot shrink heap to {} at this time\n", .{x});
                } else {
                    if (x != main.rs.SPACELIMIT) {
                        main.rs.SPACELIMIT = x;
                        abi.resetheap();
                    }
                    word.print("heaplimit = {} cells\n", .{main.rs.SPACELIMIT});
                    main.rc_write();
                }
                return;
            }
            if (is("hush")) {
                if (abi.getchar() != '\n') return;
                main.rs.echoing = 0;
                main.rs.verbosity = 0;
                return;
            }
        },
        'l' => {
            if (is("list")) {
                if (abi.getchar() != '\n') return;
                main.rs.listing = 1;
                main.rs.echoing = main.rs.verbosity & main.rs.listing;
                main.rc_write();
                return;
            }
        },
        'm' => {
            if (is("m") or is("man")) {
                if (abi.getchar() != '\n') return;
                manaction();
                return;
            }
            if (is("miralib")) {
                if (abi.getchar() != '\n') return;
                word.print("{s}\n", .{main.rs.miralib.?});
                return;
            }
        },
        'n' => {
            if (is("nocount")) {
                if (abi.getchar() != '\n') return;
                main.rs.atcount = 0;
                return;
            }
            if (is("nogc")) {
                if (abi.getchar() != '\n') return;
                main.rs.atgc = 0;
                return;
            }
            if (is("nohush")) {
                if (abi.getchar() != '\n') return;
                main.rs.echoing = main.rs.listing;
                main.rs.verbosity = 1;
                return;
            }
            if (is("nolist")) {
                if (abi.getchar() != '\n') return;
                main.rs.listing = 0;
                main.rs.echoing = 0;
                main.rc_write();
                return;
            }
            if (is("norecheck")) {
                if (abi.getchar() != '\n') return;
                main.rs.rechecking = 0;
                main.rc_write();
                return;
            }
        },
        'q' => {
            if (is("q") or is("quit")) {
                if (abi.getchar() != '\n') return;
                if (main.rs.verbosity != 0) {
                    word.print("miranda logout\n", .{});
                }
                abi.exit(0);
            }
        },
        'r' => {
            if (is("recheck")) {
                if (abi.getchar() != '\n') return;
                main.rs.rechecking = 2;
                main.rc_write();
                return;
            }
        },
        's' => {
            if (is("s") or is("settings")) {
                if (abi.getchar() != '\n') return;
                word.print("*\theap {}\n", .{main.rs.SPACELIMIT});
                word.print("*\tdic {}\n", .{main.rs.DICSPACE});
                word.print("*\teditor = {s}\n", .{main.rs.editor orelse @constCast("")});
                word.print("*\t{s}list\n", .{@as([*:0]const u8, if (main.rs.listing != 0) "" else "no")});
                word.print("*\t{s}recheck\n", .{@as([*:0]const u8, if (main.rs.rechecking != 0) "" else "no")});
                if (!main.rs.strictif) {
                    word.print("\t-nostrictif (deprecated!)\n", .{});
                }
                if (main.rs.atcount != 0) {
                    word.print("\tcount\n", .{});
                }
                if (main.rs.atgc != 0) {
                    word.print("\tgc\n", .{});
                }
                if (main.rs.UTF8 != 0) {
                    word.print("\tUTF-8 i/o\n", .{});
                }
                if (main.rs.verbosity == 0) {
                    word.print("\thush\n", .{});
                }
                if (main.rs.debug != 0) {
                    word.print("\tdebug 0{o}\n", .{main.rs.debug});
                }
                word.print("\n* items remembered between sessions\n", .{});
                return;
            }
        },
        'v' => {
            if (is("v") or is("version")) {
                if (abi.getchar() != '\n') return;
                main.v_info(0);
                return;
            }
        },
        'V' => {
            if (is("V")) {
                if (abi.getchar() != '\n') return;
                main.v_info(1);
                return;
            }
        },
        else => {},
    }
    xschars();
}

pub fn manaction() void {
    _ = abi.sprintf(&main.rs.linebuf, "\"%s/menudriver\" \"%s/manual\"", .{ main.rs.miralib.?, main.rs.miralib.? });
    _ = abi.system(&main.rs.linebuf);
}

pub fn editfile(t_val: [*:0]const u8, line: c_int) void {
    var line_val = line;
    const ebuf_local = @as([*]u8, @ptrCast(&main.rs.linebuf[0]));
    var p = ebuf_local;
    var q = main.rs.editor.?;
    var tdone: bool = false;
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
            _ = abi.sprintf(p, "%d", .{line_val});
            p += word.strlen(p);
        } else if ((p - 1)[0] == '%') {
            (p - 1)[0] = '"';
            p[0] = 0;
            const limit = @as(usize, @intCast(abi.BUFSIZE + @intFromPtr(ebuf_local) - @intFromPtr(p)));
            _ = word.strncat(p, t_val, limit);
            p += word.strlen(p);
            p[0] = '"';
            p += 1;
            p[0] = 0;
            tdone = true;
        }
    }
    p[0] = 0;
    if (!tdone) {
        p[0] = ' ';
        p += 1;
        p[0] = '"';
        p += 1;
        p[0] = 0;
        const limit = @as(usize, @intCast(abi.BUFSIZE + @intFromPtr(ebuf_local) - @intFromPtr(p)));
        _ = word.strncat(p, t_val, limit);
        p += word.strlen(p);
        p[0] = '"';
        p += 1;
        p[0] = 0;
    }
    _ = abi.system(ebuf_local);
    if (main.src_update() != 0) {
        main.loadfile(main.rs.current_script.?);
    }
}

pub fn xschars() void {
    var ch: c_int = undefined;
    word.print("\x07extra characters at end of command\n", .{});
    while (true) {
        ch = abi.getchar();
        if (ch == '\n' or ch == abi.EOF) break;
    }
}

pub fn finger(n: [*:0]const u8) void {
    const x = abi.findid(@constCast(n));
    var line: Word = 0;
    var s: ?[*:0]const u8 = null;
    if (x != NIL and main.id_type(x) != word.undef_t) {
        if (main.id_who(x) != NIL) {
            const here_val = main.get_here(x);
            s = strtab.strOf(main.heap.h(here_val));
            line = main.heap.t(here_val);
        }
        if (main.rs.lastid == 0) {
            main.rs.lastid = x;
        }
        abi.report_type(x);
        if (main.id_who(x) == NIL) {
            word.print(" ||primitive to Miranda\n", .{});
        } else {
            const aka = abi.getaka(x);
            const aka_opt: ?[*:0]const u8 = if (word.strcmp(aka, main.get_id(x)) == 0) null else aka;
            if (main.id_val(x) == word.UNDEF and main.id_type(x) != word.wrong_t) {
                word.print(" ||(UNDEFINED) specified in ", .{});
            } else if (main.id_val(x) == word.FREE) {
                word.print(" ||(FREE) specified in ", .{});
            } else if (main.id_type(x) == word.type_t and main.t_class(x) == word.free_t) {
                word.print(" ||(free type) specified in ", .{});
            } else {
                const class_str: [*:0]const u8 = if (main.id_type(x) == word.type_t and main.t_class(x) == word.abstract_t) "(abstract type) " else if (main.id_type(x) == word.type_t and main.t_class(x) == word.algebraic_t) "(algebraic type) " else if (main.id_type(x) == word.type_t and main.t_class(x) == word.placeholder_t) "(placeholder type) " else if (main.id_type(x) == word.type_t and main.t_class(x) == word.synonym_t) "(synonym type) " else "";
                word.print(" ||{s}defined in ", .{class_str});
            }
            filequote(std.mem.span(s.?));
            if (main.rs.baded != 0 or main.rs.rechecking != 0) {
                word.print(" line {}", .{line});
            }
            if (aka_opt) |aka_s| {
                word.print(" (as \"{s}\")\n", .{aka_s});
            } else {
                _ = word.putchar('\n');
            }
        }
        if (main.rs.atobject != 0) {
            word.print("{s} = ", .{main.get_id(x)});
            abi.out(main.getStdout(), main.id_val(x));
            _ = word.putchar('\n');
        }
        return;
    }
    diagnose(n);
}

pub fn diagnose(n: [*:0]const u8) void {
    var i: usize = 0;
    if (word.isalpha(n[0])) {
        while (n[i] != 0 and abi.okid(n[i]) != 0) {
            i += 1;
        }
    }
    if (n[i] != 0) {
        word.print("\"{s}\" -- not an identifier\n", .{n});
        return;
    }
    const presym = [_][*:0]const u8{
        "abstype", "div", "if", "mod", "otherwise", "readvals", "show", "type", "where", "with",
    };
    const presym_n = [_]i32{ 21, 8, 15, 8, 15, 31, 23, 22, 15, 21 };
    inline for (presym, presym_n) |sym, sym_n| {
        if (word.strcmp(n, sym) == 0) {
            word.print("{s} -- keyword (see manual, section {})\n", .{n, sym_n});
            return;
        }
    }
    word.print("identifier \"{s}\" not in scope\n", .{n});
}

pub fn allnamescom() void {
    var s: Word = undefined;
    var x = main.cs.ND;
    var y = main.cs.ND;
    var z: Word = 0;
    leftist = false;
    namescom(main.make_fil(if (main.rs.nostdenv) null else @as([*:0]const u8, @ptrCast(&main.rs.STDENV)), 0, 0, main.rs.primenv));
    if (heap.heap.files == NIL) return;
    s = main.heap.t(heap.heap.files);
    while (s != NIL) : (s = main.heap.t(s)) {
        namescom(main.heap.h(s));
    }
    namescom(main.heap.h(heap.heap.files));
    main.rs.sorted = 1;

    while (x != NIL and main.id_type(main.heap.h(x)) == word.undef_t) {
        x = main.heap.t(x);
    }
    while (y != NIL and main.id_type(main.heap.h(y)) != word.undef_t) {
        y = main.heap.t(y);
    }
    if (x != NIL) {
        word.print("WARNING, SCRIPT CONTAINS TYPE ERRORS: ", .{});
        while (x != NIL) : (x = main.heap.t(x)) {
            if (main.id_type(main.heap.h(x)) != word.undef_t) {
                if (z == 0) {
                    z = 1;
                } else {
                    _ = word.putchar(',');
                }
                abi.out(main.getStdout(), main.heap.h(x));
            }
        }
        word.print(";\n", .{});
    }
    if (y != NIL) {
        word.print("{s} UNDEFINED NAMES: ", .{@as([*:0]const u8, if (z != 0) "AND" else "WARNING, SCRIPT CONTAINS")});
        z = 0;
        while (y != NIL) : (y = main.heap.t(y)) {
            if (main.id_type(main.heap.h(y)) == word.undef_t) {
                if (z == 0) {
                    z = 1;
                } else {
                    _ = word.putchar(',');
                }
                abi.out(main.getStdout(), main.heap.h(y));
            }
        }
        word.print(";\n", .{});
    }
}
