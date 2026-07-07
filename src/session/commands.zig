//! commands.zig — the REPL's `/` and `:` command dispatcher.
//!
//! `command` is the big switch behind directives like `/h` (help), `/e` (edit),
//! `/f` (files), `/l` (list), and `/man`. The rest are its helpers and the
//! name-query machinery shared with the prompt: `finger` (`?name`), `diagnose`
//! (why a name is unusable), `allnamescom` (bare `?`), and `editfile`.

const std = @import("std");
const word = @import("../graph/word.zig");
const strtab = @import("../graph/strtab.zig");
const rt = @import("../runtime/runtime_state.zig");
const compiler_state = @import("../compiler/compiler_state.zig");
const cs = compiler_state.cs;
const abi = @import("../os.zig");

const Word = word.Word;
const NIL = word.NIL;

// State owned by heap.zig / reduce.zig — not yet accessible via @import.
inline fn getTag(heap: *Heap, x: Word) word.NodeTag {
    return heap.getTag(x);
}

const lex_state = @import("../parser/lex_state.zig");
const lex = @import("../parser/lex.zig");
const core_state = @import("../runtime/core_state.zig");
const heap_mod = @import("../graph/heap.zig");
const Heap = heap_mod.Heap;
const files = @import("../io/files.zig");
const repl = @import("repl.zig");
const dump = @import("../compiler/dump.zig");
const config = @import("config.zig");
const lineedit = @import("editor.zig");
const module_loader = @import("../compiler/module_loader.zig");
const ls = lex_state.ls;

const token = lex.token;

/// Print `s` space characters (column padding for listings).
fn spaces(s: Word) void {
    var j = s;
    while (j > 0) : (j -= 1) {
        _ = word.putchar(' ');
    }
}

/// True if the just-read dictionary token equals the command keyword `s`.
fn is(lexs: *lex_state.LexState, s: [:0]const u8) bool {
    return std.mem.eql(u8, std.mem.span(@as([*:0]u8, @ptrCast(lexs.dicp))), s);
}

/// Print path `p` for messages: `<name>` when it lives under the library dir, else `"path"`.
fn filequote(rs: *rt.RuntimeState, p: [:0]const u8) void {
    const prelude_span = std.mem.span(@as([*:0]const u8, @ptrCast(&rs.PRELUDE)));
    if (rs.filequote_mlen == 0) {
        if (std.mem.lastIndexOfScalar(u8, prelude_span, '/')) |idx| {
            rs.filequote_mlen = idx + 1;
        }
    }
    const n = rs.filequote_mlen;
    const na = @min(p.len, n);
    const nb = @min(prelude_span.len, n);
    if (na == nb and std.mem.eql(u8, p[0..na], prelude_span[0..nb])) {
        word.print("<{s}>", .{p.ptr + n});
    } else {
        word.print("\"{s}\"", .{p.ptr});
    }
}

/// List the identifiers defined in `l` in aligned columns.
fn namescom(heap: *Heap, rs: *rt.RuntimeState, l: Word) void {
    var n = heap_mod.filDefs(l);
    var col_local: Word = 0;
    var undefs: Word = NIL;
    var wp: usize = 0;
    const scrwd = files.termWidth();
    if (rs.sorted == 0 and n != rs.primenv) {
        n = heap_mod.alfasort(n);
        heap_mod.tp(l).* = n;
    }
    if (n == NIL) return;
    if (heap_mod.getFil(l)) |gf| {
        filequote(rs, std.mem.span(gf));
    } else {
        word.print("primitive:", .{});
    }
    word.print("\n", .{});
    while (n != NIL) {
        if (heap_mod.idType(heap_mod.h(n)) == word.wrong_t or heap_mod.idVal(heap_mod.h(n)) != word.UNDEF) {
            const w = @as(Word, @intCast(std.mem.len(heap_mod.getId(heap_mod.h(n)))));
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
                if (rs.leftist) {
                    col_local = 0;
                    while (col_local < wp) {
                        word.print("{s}", .{heap_mod.getId(rs.words[@as(usize, @intCast(col_local))])});
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
                        word.print("{s}", .{heap_mod.getId(rs.words[@as(usize, @intCast(col_local))])});
                        col_local += 1;
                        if (col_local < wp) {
                            spaces(1 + i + if (r <= 0) @as(Word, 1) else @as(Word, 0));
                            r -= 1;
                        }
                    }
                }
                rs.leftist = !rs.leftist;
                wp = 0;
                col_local = 0;
                _ = word.putchar('\n');
            }
            col_local += w;
            rs.words[wp] = heap_mod.h(n);
            wp += 1;
        } else {
            undefs = heap_mod.cons(heap_mod.h(n), undefs);
        }
        n = heap_mod.t(n);
    }
    if (wp > 0) {
        col_local = 0;
        while (col_local < wp) {
            word.print("{s}", .{heap_mod.getId(rs.words[@as(usize, @intCast(col_local))])});
            col_local += 1;
            _ = word.putc(if (col_local == wp) '\n' else ' ', abi.stdout());
        }
    }
    if (undefs == NIL) return;
    undefs = heap_mod.reverse(undefs);
    abi.printlist(heap, @constCast("SPECIFIED BUT NOT DEFINED: "), undefs);
}

/// Dispatch a `/` or `:` REPL command — the main command switch (`/h`, `/e`, `/f`, `/l`, `/man`, ...).
/// Handle the `'f'` REPL command (extracted from `command`).
fn cmdFiles(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState, lexs: *lex_state.LexState) bool {
    var t_val: ?[*:0]u8 = undefined;
    var ch: c_int = undefined;
    if (is(lexs, "f") or is(lexs, "file")) {
        const t_tok = token();
        if (abi.getchar() != '\n') return true;
        if (t_tok) |tok| {
            t_val = abi.addextn(1, tok);
            _ = abi.keep(t_val.?);
        } else {
            t_val = null;
        }
        if (t_val != null) {
            core.errline = 0;
            core.errs = 0;
        }
        if (t_val != null) {
            if (!std.mem.eql(u8, std.mem.span(t_val.?), std.mem.span(rs.current_script.?)) or (heap.files == NIL and abi.okdump(core, t_val.?))) {
                comp.CLASHES = NIL;
                dump.undump(heap, core, comp, rs, t_val.?);
                if (comp.CLASHES != NIL) {
                    module_loader.loadfile(heap, core, comp, rs, ls(), t_val.?) catch {};
                }
            } else {
                module_loader.loadfile(heap, core, comp, rs, ls(), t_val.?) catch {};
            }
        } else {
            word.print("{s}{s}\n", .{ rs.current_script.?, @as([*:0]const u8, if (heap.files == NIL) " (not loaded)" else "") });
        }
        return true;
    }
    if (is(lexs, "files")) {
        if (abi.getchar() != '\n') return true;
        var f = heap.files;
        while (f != NIL) : (f = heap_mod.t(f)) {
            word.print("({s},{},{})", .{ heap_mod.getFil(heap_mod.h(f)).?, heap_mod.filTime(heap_mod.h(f)), heap_mod.filShare(heap_mod.h(f)) });
            abi.printlist(heap, @constCast(""), heap_mod.filDefs(heap_mod.h(f)));
        }
        return true;
    }
    if (is(lexs, "find")) {
        var i: Word = 0;
        while (token() != null) {
            const x = abi.findid(heap, lexs.dicp);
            i += 1;
            if (x != NIL) {
                const n = heap_mod.getId(x);
                var y = rs.primenv;
                while (y != NIL) : (y = heap_mod.t(y)) {
                    if (getTag(heap, heap_mod.h(y)) == .ID) {
                        if (heap_mod.h(y) == x or std.mem.eql(u8, std.mem.span(abi.getaka(heap_mod.h(y))), std.mem.span(n))) {
                            finger(heap, rs, heap_mod.getId(heap_mod.h(y)));
                        }
                    }
                }
                var ff = heap.files;
                while (ff != NIL) : (ff = heap_mod.t(ff)) {
                    var y_def = heap_mod.filDefs(heap_mod.h(ff));
                    while (y_def != NIL) : (y_def = heap_mod.t(y_def)) {
                        if (getTag(heap, heap_mod.h(y_def)) == .ID) {
                            if (heap_mod.h(y_def) == x or std.mem.eql(u8, std.mem.span(abi.getaka(heap_mod.h(y_def))), std.mem.span(n))) {
                                finger(heap, rs, heap_mod.getId(heap_mod.h(y_def)));
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
        return true;
    }
    return false;
}

/// Handle the `'e'` REPL command (extracted from `command`).
fn cmdEdit(core: *core_state.CoreState, rs: *rt.RuntimeState, lexs: *lex_state.LexState) bool {
    var t_val: ?[*:0]u8 = undefined;
    var ch: c_int = undefined;
    var ch1: c_int = undefined;
    if (is(lexs, "e") or is(lexs, "edit")) {
        var mf: ?[*:0]u8 = null;
        if (token()) |tok| {
            t_val = abi.addextn(1, tok);
        } else {
            t_val = rs.current_script;
        }
        if (abi.getchar() != '\n') return true;
        if (!files.fileExists(t_val.?)) {
            if (rs.lmirahdr == null) {
                lexs.dicp = lexs.dicq;
                {
                    // HOME unset -> treat as "" (the old strcpy(dicp, null) left
                    // dicp's stale buffer contents untouched, which was never
                    // actually safe to read back as a C string).
                    const home_span = if (abi.getenv("HOME")) |home| std.mem.span(home) else "";
                    @memcpy(lexs.dicp[0..home_span.len], home_span);
                    lexs.dicp[home_span.len] = 0;
                }
                if (std.mem.eql(u8, std.mem.span(lexs.dicp), "/")) {
                    lexs.dicp[0] = 0;
                }
                {
                    const suffix = "/.mirahdr";
                    const dst_len = std.mem.len(lexs.dicp);
                    @memcpy(lexs.dicp[dst_len..][0..suffix.len], suffix);
                    lexs.dicp[dst_len + suffix.len] = 0;
                }
                rs.lmirahdr = lexs.dicp;
                lexs.dicq = lexs.dicp + std.mem.len(lexs.dicp) + 1;
            }
            if (files.fileExists(rs.lmirahdr.?)) {
                mf = rs.lmirahdr;
            }
            if (mf == null and rs.mirahdr == null) {
                lexs.dicp = lexs.dicq;
                {
                    const miralib_span = std.mem.span(rs.miralib.?);
                    @memcpy(lexs.dicp[0..miralib_span.len], miralib_span);
                    lexs.dicp[miralib_span.len] = 0;
                    const suffix = "/.mirahdr";
                    @memcpy(lexs.dicp[miralib_span.len..][0..suffix.len], suffix);
                    lexs.dicp[miralib_span.len + suffix.len] = 0;
                }
                rs.mirahdr = lexs.dicp;
                lexs.dicq = lexs.dicp + std.mem.len(lexs.dicp) + 1;
            }
            if (mf == null and files.fileExists(rs.mirahdr.?)) {
                mf = rs.mirahdr;
            }
            if (mf != null and t_val != rs.current_script) {
                var prompt_buf: [256]u8 = undefined;
                const prompt = std.fmt.bufPrint(&prompt_buf, "open new script \"{s}\"? [ny]", .{t_val.?}) catch "open new script? [ny]";
                if (lineedit.active()) {
                    lineedit.setPrompt(prompt);
                } else {
                    word.print("{s}", .{prompt});
                }
                ch1 = abi.getchar();
                ch = ch1;
                while (ch != '\n' and ch != abi.EOF) {
                    ch = abi.getchar();
                }
                if (ch1 != 'y' and ch1 != 'Y') {
                    return true;
                }
            }
            if (mf != null) {
                files.copyFile(mf.?, t_val.?);
            }
        }
        const err_line_num: c_int = if (std.mem.eql(u8, std.mem.span(t_val.?), std.mem.span(rs.current_script.?))) @intCast(core.errline) else if (core.errs != 0 and std.mem.eql(u8, std.mem.span(t_val.?), std.mem.span(strtab.strOf(strtab.table(), heap_mod.h(core.errs))))) @intCast(heap_mod.t(core.errs)) else @intCast(abi.geterrlin(core, lexs, t_val.?));
        const err_col_num: c_int = if (std.mem.eql(u8, std.mem.span(t_val.?), std.mem.span(rs.current_script.?))) @intCast(core.errcol) else 0;
        editfile(rs, t_val.?, err_line_num, err_col_num);
        return true;
    }
    if (is(lexs, "editor")) {
        const hold = @as([*]u8, @ptrCast(&rs.linebuf[0]));
        if (repl.getLine(abi.stdin(), abi.pnlim - 1, hold) == 0) {
            return true;
        }
        if (hold[0] == 0) {
            word.print("{s}\n", .{rs.editor orelse @constCast("")});
            return true;
        }
        var h_ptr = hold + std.mem.len(@as([*:0]const u8, @ptrCast(hold)));
        while (h_ptr != hold and ((h_ptr - 1)[0] == ' ' or (h_ptr - 1)[0] == '\t' or (h_ptr - 1)[0] == '\n' or (h_ptr - 1)[0] == '\r')) {
            h_ptr -= 1;
            h_ptr[0] = 0;
        }
        if (hold[0] == '"' or hold[0] == '\'') {
            word.print("please type name of editor without quotation marks\n", .{});
            return true;
        }
        var prompt_buf: [256]u8 = undefined;
        const prompt = std.fmt.bufPrint(&prompt_buf, "change editor to: \"{s}\"? [ny]", .{std.mem.span(@as([*:0]const u8, @ptrCast(hold)))}) catch "change editor to? [ny]";
        if (lineedit.active()) {
            lineedit.setPrompt(prompt);
        } else {
            word.print("{s}", .{prompt});
        }
        ch1 = abi.getchar();
        ch = ch1;
        while (ch != '\n' and ch != abi.EOF) {
            ch = abi.getchar();
        }
        if (ch1 != 'y' and ch1 != 'Y') {
            word.print("editor not changed\n", .{});
            return true;
        }
        {
            const hold_span = std.mem.span(@as([*:0]const u8, @ptrCast(hold)));
            @memcpy(rs.ebuf[0..hold_span.len], hold_span);
            rs.ebuf[hold_span.len] = 0;
        }
        rs.editor = @as([*:0]u8, @ptrCast(&rs.ebuf));
        rs.baded = @intFromBool(repl.badEditor(rs));
        rs.echoing = rs.verbosity & rs.listing;
        config.writeRc();
        word.print("editor = {s}\n", .{rs.editor orelse @constCast("")});
        return true;
    }
    return false;
}

pub fn command(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState, lexs: *lex_state.LexState) void {
    switch (lexs.dicp[0]) {
        'a' => {
            if (is(lexs, "a") or is(lexs, "aux")) {
                if (abi.getchar() != '\n') return;
                {
                    const miralib_span = std.mem.span(rs.miralib.?);
                    @memcpy(rs.linebuf[0..miralib_span.len], miralib_span);
                    const suffix = "/auxfile";
                    @memcpy(rs.linebuf[miralib_span.len..][0..suffix.len], suffix);
                    rs.linebuf[miralib_span.len + suffix.len] = 0;
                }
                files.fileCopy(@as([*:0]const u8, @ptrCast(&rs.linebuf)));
                return;
            }
        },
        'c' => {
            if (is(lexs, "count")) {
                if (abi.getchar() != '\n') return;
                rs.atcount = 1;
                return;
            }
            if (is(lexs, "cd")) {
                var d = token();
                if (d == null) {
                    d = @constCast(abi.getenv("HOME"));
                } else {
                    d = abi.addextn(0, d.?);
                }
                if (abi.getchar() != '\n') return;
                if (abi.chdir(d.?) == -1) {
                    word.print("cannot cd to {s}\n", .{d.?});
                } else if (heap_mod.srcUpdate(rs) != 0) {
                    dump.undump(heap, core, cs(), rs, rs.current_script.?);
                }
                return;
            }
        },
        'd' => {
            if (is(lexs, "dic")) {
                if (token() == null) {
                    _ = abi.getchar();
                    word.print("{} chars", .{rs.DICSPACE});
                    if (rs.DICSPACE != 100000) {
                        word.print(" (default={})", .{@as(c_long, 100000)});
                    }
                    word.print(" {} in use\n", .{@as(c_long, @intCast(@intFromPtr(lexs.dicq) - @intFromPtr(lexs.dic.?)))});
                    return;
                }
                if (abi.getchar() != '\n') return;
                word.print("sorry, cannot change size of dictionary while in use\n", .{});
                word.print("(/q and reinvoke with flag: mira -dic {s} ... )\n", .{@as([*:0]const u8, @ptrCast(lexs.dicp))});
                return;
            }
        },
        'e' => {
            if (cmdEdit(core, rs, lexs)) return;
        },
        'f' => {
            if (cmdFiles(heap, core, comp, rs, lexs)) return;
        },
        'g' => {
            if (is(lexs, "gc")) {
                if (abi.getchar() != '\n') return;
                rs.atgc = 1;
                return;
            }
        },
        'h' => {
            if (is(lexs, "h") or is(lexs, "help")) {
                if (abi.getchar() != '\n') return;
                {
                    const miralib_span = std.mem.span(rs.miralib.?);
                    @memcpy(rs.linebuf[0..miralib_span.len], miralib_span);
                    const suffix = "/helpfile";
                    @memcpy(rs.linebuf[miralib_span.len..][0..suffix.len], suffix);
                    rs.linebuf[miralib_span.len + suffix.len] = 0;
                }
                files.fileCopy(@as([*:0]const u8, @ptrCast(&rs.linebuf)));
                return;
            }
            if (is(lexs, "heap")) {
                var x: c_long = undefined;
                if (token() == null) {
                    _ = abi.getchar();
                    word.print("{} cells", .{rs.SPACELIMIT});
                    if (rs.SPACELIMIT != 2500000) {
                        word.print(" (default={})", .{@as(c_long, 2500000)});
                    }
                    word.print("\n", .{});
                    return;
                }
                if (abi.getchar() != '\n') return;
                if (abi.sscanf(lexs.dicp, "%ld", .{&x}) != 1 or heap_mod.badval(x)) {
                    word.print("illegal value (heap unchanged)\n", .{});
                    return;
                }
                if (x < abi.trueheapsize()) {
                    word.print("sorry, cannot shrink heap to {} at this time\n", .{x});
                } else {
                    if (x != rs.SPACELIMIT) {
                        rs.SPACELIMIT = x;
                        abi.resetheap();
                    }
                    word.print("heaplimit = {} cells\n", .{rs.SPACELIMIT});
                    config.writeRc();
                }
                return;
            }
            if (is(lexs, "hush")) {
                if (abi.getchar() != '\n') return;
                rs.echoing = 0;
                rs.verbosity = 0;
                return;
            }
        },
        'l' => {
            if (is(lexs, "list")) {
                if (abi.getchar() != '\n') return;
                rs.listing = 1;
                rs.echoing = rs.verbosity & rs.listing;
                config.writeRc();
                return;
            }
        },
        'm' => {
            if (is(lexs, "m") or is(lexs, "man")) {
                if (abi.getchar() != '\n') return;
                manaction(rs);
                return;
            }
            if (is(lexs, "miralib")) {
                if (abi.getchar() != '\n') return;
                word.print("{s}\n", .{rs.miralib.?});
                return;
            }
        },
        'n' => {
            if (is(lexs, "nocount")) {
                if (abi.getchar() != '\n') return;
                rs.atcount = 0;
                return;
            }
            if (is(lexs, "nogc")) {
                if (abi.getchar() != '\n') return;
                rs.atgc = 0;
                return;
            }
            if (is(lexs, "nohush")) {
                if (abi.getchar() != '\n') return;
                rs.echoing = rs.listing;
                rs.verbosity = 1;
                return;
            }
            if (is(lexs, "nolist")) {
                if (abi.getchar() != '\n') return;
                rs.listing = 0;
                rs.echoing = 0;
                config.writeRc();
                return;
            }
            if (is(lexs, "norecheck")) {
                if (abi.getchar() != '\n') return;
                rs.rechecking = 0;
                config.writeRc();
                return;
            }
        },
        'q' => {
            if (is(lexs, "q") or is(lexs, "quit")) {
                if (abi.getchar() != '\n') return;
                if (rs.verbosity != 0) {
                    word.print("miranda logout\n", .{});
                }
                abi.exit(0);
            }
        },
        'r' => {
            if (is(lexs, "recheck")) {
                if (abi.getchar() != '\n') return;
                rs.rechecking = 2;
                config.writeRc();
                return;
            }
        },
        's' => {
            if (is(lexs, "s") or is(lexs, "settings")) {
                if (abi.getchar() != '\n') return;
                word.print("*\theap {}\n", .{rs.SPACELIMIT});
                word.print("*\tdic {}\n", .{rs.DICSPACE});
                word.print("*\teditor = {s}\n", .{rs.editor orelse @constCast("")});
                word.print("*\t{s}list\n", .{@as([*:0]const u8, if (rs.listing != 0) "" else "no")});
                word.print("*\t{s}recheck\n", .{@as([*:0]const u8, if (rs.rechecking != 0) "" else "no")});
                if (!rs.strictif) {
                    word.print("\t-nostrictif (deprecated!)\n", .{});
                }
                if (rs.atcount != 0) {
                    word.print("\tcount\n", .{});
                }
                if (rs.atgc != 0) {
                    word.print("\tgc\n", .{});
                }
                if (rs.UTF8 != 0) {
                    word.print("\tUTF-8 i/o\n", .{});
                }
                if (rs.verbosity == 0) {
                    word.print("\thush\n", .{});
                }
                if (rs.debug != 0) {
                    word.print("\tdebug 0{o}\n", .{rs.debug});
                }
                word.print("\n* items remembered between sessions\n", .{});
                return;
            }
        },
        'v' => {
            if (is(lexs, "v") or is(lexs, "version")) {
                if (abi.getchar() != '\n') return;
                config.versionInfo(0);
                return;
            }
        },
        'V' => {
            if (is(lexs, "V")) {
                if (abi.getchar() != '\n') return;
                config.versionInfo(1);
                return;
            }
        },
        else => {},
    }
    xschars();
}

/// Run the `/man` command: launch the manual via the library's `menudriver`.
pub fn manaction(rs: *rt.RuntimeState) void {
    _ = std.fmt.bufPrintZ(&rs.linebuf, "\"{s}/menudriver\" \"{s}/manual\"", .{ rs.miralib.?, rs.miralib.? }) catch {};
    _ = abi.system(&rs.linebuf);
}

/// Open `t_val` at `line` in the user's editor, substituting into the editor-command template.
pub fn editfile(rs: *rt.RuntimeState, t_val: [*:0]const u8, line: c_int, col: c_int) void {
    var line_val = line;
    const col_val = if (col == 0) @as(c_int, 1) else col;
    const ebuf_local = @as([*]u8, @ptrCast(&rs.linebuf[0]));
    var p = ebuf_local;
    var q = rs.editor.?;
    var tdone: bool = false;
    var temp_editor: [512]u8 = undefined;
    if (line_val == 0) {
        _ = std.fmt.bufPrintZ(&temp_editor, "{s}", .{q}) catch {};
        const len = std.mem.len(@as([*:0]const u8, @ptrCast(&temp_editor)));
        if (len > 0) {
            var tp_ptr = @as([*]u8, @ptrCast(&temp_editor)) + len - 1;
            while (tp_ptr != &temp_editor and tp_ptr[0] == ' ') : (tp_ptr -= 1) {}
            if (tp_ptr[0] == '!') {
                tp_ptr -= 1;
                while (tp_ptr != &temp_editor and tp_ptr[0] == ' ') : (tp_ptr -= 1) {}
                if (tp_ptr[0] == '+') {
                    tp_ptr[0] = 0;
                }
            }
        }
        q = @ptrCast(&temp_editor);
        line_val = 1;
    }
    while (q[0] != 0) {
        const ch = q[0];
        q += 1;
        p[0] = ch;
        p += 1;
        if ((p - 1)[0] == '\\' and (q[0] == '!' or q[0] == '%' or q[0] == '&')) {
            (p - 1)[0] = q[0];
            q += 1;
        } else if ((p - 1)[0] == '!') {
            p -= 1;
            _ = std.fmt.bufPrintZ(p[0..16], "{d}", .{line_val}) catch "";
            p += std.mem.len(@as([*:0]const u8, @ptrCast(p)));
        } else if ((p - 1)[0] == '&') {
            p -= 1;
            _ = std.fmt.bufPrintZ(p[0..16], "{d}", .{col_val}) catch "";
            p += std.mem.len(@as([*:0]const u8, @ptrCast(p)));
        } else if ((p - 1)[0] == '%') {
            (p - 1)[0] = '"';
            p[0] = 0;
            const limit = @as(usize, @intCast(abi.BUFSIZE + @intFromPtr(ebuf_local) - @intFromPtr(p)));
            {
                const dst_len = std.mem.len(@as([*:0]const u8, @ptrCast(p)));
                const src_span = std.mem.span(t_val);
                const lim = @min(src_span.len, limit);
                @memcpy(p[dst_len..][0..lim], src_span[0..lim]);
                p[dst_len + lim] = 0;
            }
            p += std.mem.len(@as([*:0]const u8, @ptrCast(p)));
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
        {
            const dst_len = std.mem.len(@as([*:0]const u8, @ptrCast(p)));
            const src_span = std.mem.span(t_val);
            const lim = @min(src_span.len, limit);
            @memcpy(p[dst_len..][0..lim], src_span[0..lim]);
            p[dst_len + lim] = 0;
        }
        p += std.mem.len(@as([*:0]const u8, @ptrCast(p)));
        p[0] = '"';
        p += 1;
        p[0] = 0;
    }
    _ = abi.system(ebuf_local);
    if (heap_mod.srcUpdate(rs) != 0) {
        module_loader.loadfile(heap_mod.heap(), core_state.s(), cs(), rs, ls(), rs.current_script.?) catch {};
    }
}

/// Warn about and consume extra characters after a command, through end of line.
pub fn xschars() void {
    var ch: c_int = undefined;
    word.print("\x07extra characters at end of command\n", .{});
    while (true) {
        ch = abi.getchar();
        if (ch == '\n' or ch == abi.EOF) break;
    }
}

/// Print the type and definition location of name `n` (the `?name` query).
pub fn finger(heap: *Heap, rs: *rt.RuntimeState, n: [*:0]const u8) void {
    const x = abi.findid(heap, @constCast(n));
    var line: Word = 0;
    var s: ?[*:0]const u8 = null;
    if (x != NIL and heap_mod.idType(x) != word.undef_t) {
        if (heap_mod.idWho(x) != NIL) {
            const here_val = heap_mod.getHere(x);
            s = strtab.strOf(strtab.table(), heap_mod.h(here_val));
            line = heap_mod.t(here_val);
        }
        if (rs.lastid == 0) {
            rs.lastid = x;
        }
        abi.reportType(heap, x);
        if (heap_mod.idWho(x) == NIL) {
            word.print(" ||primitive to Miranda\n", .{});
        } else {
            const aka = abi.getaka(x);
            const aka_opt: ?[*:0]const u8 = if (std.mem.eql(u8, std.mem.span(aka), std.mem.span(heap_mod.getId(x)))) null else aka;
            if (heap_mod.idVal(x) == word.UNDEF and heap_mod.idType(x) != word.wrong_t) {
                word.print(" ||(UNDEFINED) specified in ", .{});
            } else if (heap_mod.idVal(x) == word.FREE) {
                word.print(" ||(FREE) specified in ", .{});
            } else if (heap_mod.idType(x) == word.type_t and heap_mod.tClass(x) == word.free_t) {
                word.print(" ||(free type) specified in ", .{});
            } else {
                const class_str: [*:0]const u8 = if (heap_mod.idType(x) == word.type_t and heap_mod.tClass(x) == word.abstract_t) "(abstract type) " else if (heap_mod.idType(x) == word.type_t and heap_mod.tClass(x) == word.algebraic_t) "(algebraic type) " else if (heap_mod.idType(x) == word.type_t and heap_mod.tClass(x) == word.placeholder_t) "(placeholder type) " else if (heap_mod.idType(x) == word.type_t and heap_mod.tClass(x) == word.synonym_t) "(synonym type) " else "";
                word.print(" ||{s}defined in ", .{class_str});
            }
            filequote(rs, std.mem.span(s.?));
            if (rs.baded != 0 or rs.rechecking != 0) {
                word.print(" line {}", .{line});
            }
            if (aka_opt) |aka_s| {
                word.print(" (as \"{s}\")\n", .{aka_s});
            } else {
                _ = word.putchar('\n');
            }
        }
        if (rs.atobject != 0) {
            word.print("{s} = ", .{heap_mod.getId(x)});
            abi.out(abi.stdout(), heap_mod.idVal(x));
            _ = word.putchar('\n');
        }
        return;
    }
    diagnose(n);
}

/// Explain why name `n` is unusable: not an identifier, a reserved keyword, or simply not in scope.
pub fn diagnose(n: [*:0]const u8) void {
    var i: usize = 0;
    if (std.ascii.isAlphabetic(n[0])) {
        while (n[i] != 0 and abi.okid(n[i])) {
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
        if (std.mem.eql(u8, std.mem.span(n), std.mem.span(sym))) {
            word.print("{s} -- keyword (see manual, section {})\n", .{ n, sym_n });
            return;
        }
    }
    word.print("identifier \"{s}\" not in scope\n", .{n});
}

/// List every name currently in scope (the bare `?` command).
pub fn allnamescom(heap: *Heap, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState) void {
    var s: Word = undefined;
    var x = comp.ND;
    var y = comp.ND;
    var z: Word = 0;
    rs.leftist = false;
    namescom(heap, rs, heap_mod.makeFil(if (rs.nostdenv) null else @as([*:0]const u8, @ptrCast(&rs.STDENV)), 0, 0, rs.primenv));
    if (heap.files == NIL) return;
    s = heap_mod.t(heap.files);
    while (s != NIL) : (s = heap_mod.t(s)) {
        namescom(heap, rs, heap_mod.h(s));
    }
    namescom(heap, rs, heap_mod.h(heap.files));
    rs.sorted = 1;

    while (x != NIL and heap_mod.idType(heap_mod.h(x)) == word.undef_t) {
        x = heap_mod.t(x);
    }
    while (y != NIL and heap_mod.idType(heap_mod.h(y)) != word.undef_t) {
        y = heap_mod.t(y);
    }
    if (x != NIL) {
        word.print("WARNING, SCRIPT CONTAINS TYPE ERRORS: ", .{});
        while (x != NIL) : (x = heap_mod.t(x)) {
            if (heap_mod.idType(heap_mod.h(x)) != word.undef_t) {
                if (z == 0) {
                    z = 1;
                } else {
                    _ = word.putchar(',');
                }
                abi.out(abi.stdout(), heap_mod.h(x));
            }
        }
        word.print(";\n", .{});
    }
    if (y != NIL) {
        word.print("{s} UNDEFINED NAMES: ", .{@as([*:0]const u8, if (z != 0) "AND" else "WARNING, SCRIPT CONTAINS")});
        z = 0;
        while (y != NIL) : (y = heap_mod.t(y)) {
            if (heap_mod.idType(heap_mod.h(y)) == word.undef_t) {
                if (z == 0) {
                    z = 1;
                } else {
                    _ = word.putchar(',');
                }
                abi.out(abi.stdout(), heap_mod.h(y));
            }
        }
        word.print(";\n", .{});
    }
}
