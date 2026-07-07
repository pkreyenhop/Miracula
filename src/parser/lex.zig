//! lex.zig — the identifier dictionary, private-name machinery, and a
//! handful of REPL-facing helpers that outlived the character-at-a-time
//! `yylex` tokenizer it used to share a file with.
//!
//! Phase 1 step 8 (docs/ZIG_NATIVE_PLAN.md) deleted `yylex`/the offside
//! `layout` rule/`%`-`directive` handling/numeral-string-charclass scanning
//! and everything only they needed (~1,400 lines) once the native
//! `syntax/` pipeline (`Source` → `lexer` → `applyLayout` →
//! `parser.zig`/`codegen.zig`, plus `semantics/modules.zig` for
//! `%include`/`%export`/`%free`) became the sole front end. What's left is
//! genuinely still load-bearing production code that happened to live in
//! the same file: the identifier dictionary (`setupdic`/`makeId`/`findid`/
//! `keep`/`name`), the private-name machinery (`makePn`/`mkprivate`,
//! `%export`'s permanent hiding mechanism — see `mkprivate`'s own doc
//! comment), REPL-only raw token/line reading (`token`/`rdline`, used by
//! slash commands, not Miranda expression parsing), and value-building
//! helpers (`convArgs`/`strConv`) the reducer calls directly. Several of
//! these are re-exported under the same names through
//! `runtime/main_clib.zig` for callers that reach them via that module
//! instead of importing this one directly.

const std = @import("std");
const word = @import("../runtime/word.zig");
const errors = @import("../runtime/errors.zig");
const strtab = @import("../runtime/strtab.zig");
const lex_state = @import("lex_state.zig");
const ls = lex_state.ls;
const cs = @import("../compiler/compiler_state.zig").cs;
const heap_mod = @import("../runtime/heap.zig");
const Heap = heap_mod.Heap;
const rt = @import("../runtime/runtime_state.zig");
const types = @import("../compiler/types.zig");
const main_clib = @import("../runtime/main_clib.zig");
const core_state = @import("../runtime/core_state.zig");
const symbols = @import("../semantics/symbols.zig");
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)

const Word = i64;
const NIL = word.NIL;
const UNDEF = word.UNDEF;

const make = heap_mod.make;
const mallocPanic = heap_mod.mallocPanic;
const stoId = heap_mod.stoId;
const genlstatType = types.genlstatType;

/// The standard-input `FILE` handle.
fn getStdin() ?*word.FILE {
    const T = @TypeOf(main_clib.stdin);
    if (comptime @typeInfo(T) == .@"fn") {
        return main_clib.stdin();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return main_clib.stdin();
    } else {
        return main_clib.stdin;
    }
}

/// Head (`hd`) of cell `x`.
fn h(heap: *Heap, x: Word) Word {
    return heap.h(x);
}

/// Pointer to the head field of cell `x`.
fn hp(heap: *Heap, x: Word) *Word {
    return heap.hp(x);
}

/// Tail (`tl`) of cell `x`.
fn t(heap: *Heap, x: Word) Word {
    return heap.t(x);
}

/// Pointer to the tail field of cell `x`.
fn tp(heap: *Heap, x: Word) *Word {
    return heap.tp(x);
}

/// Allocate a `CONS` cell `(x . y)`.
fn cons(x: Word, y: Word) Word {
    return make(.CONS, x, y);
}

/// The interned name text of id `x`.
fn getId(heap: *Heap, x: Word) [*:0]const u8 {
    return strtab.strOf(strtab.table(), h(heap, h(heap, h(heap, x))));
}

/// Allocate a `FILEINFO` cell `(file . line)`.
fn fileinfo(file: Word, line: Word) Word {
    return make(.FILEINFO, file, line);
}

/// Abort if the dictionary buffer has overflowed.
fn ovflocheck() void {
    const d_ptr = @as(usize, @intFromPtr(ls().dicq));
    const start_ptr = @as(usize, @intFromPtr(ls().dic));
    if (d_ptr - start_ptr > @as(usize, @intCast(rt.rs().DICSPACE))) {
        dicovflo();
    }
}

/// Handle dictionary overflow (report and abort).
pub fn dicovflo() void {
    errors.fatal("\npanic: dictionary overflow\n", .{});
}

/// Allocate and initialise the identifier dictionary.
pub fn setupdic() void {
    const space = rt.rs().DICSPACE;
    if (ls().dic == null) {
        const dict_slice = rt.allocator.alloc(u8, @intCast(space)) catch mallocPanic("dictionary");
        ls().dic = dict_slice.ptr;

        const base_slice = rt.allocator.alloc(u8, @intCast(ls().prefixlimit)) catch mallocPanic("ls.prefixbase");
        ls().prefixbase = base_slice.ptr;
    }
    ls().dicp = @ptrCast(ls().dic.?);
    ls().dicq = @ptrCast(ls().dic.?);
    ls().prefixbase.?[0] = 0;
    ls().prefix = 0;
    symbols.syms().deinit(rt.allocator);
    symbols.syms().* = .{};
}

/// A `getchar()`-style `c_int` (may be `EOF` = -1), narrowed to a byte iff
/// it's in ASCII-byte range (Phase 2 step 5: `std.ascii`'s predicates need a
/// `u8`, and can't see the EOF sentinel directly).
inline fn charOf(ch: c_int) ?u8 {
    return if (ch >= 0 and ch <= 255) @intCast(ch) else null;
}

/// Resolve a `~`-relative path `n` against ``.
fn gethome(n: [*:0]const u8) ?[*:0]const u8 {
    if (n[0] == 0) {
        if (main_clib.getenv("HOME")) |h_dir| {
            return h_dir;
        }
        return null;
    }
    return null;
}

/// Read the next whitespace-delimited token into the dictionary buffer.
pub fn token() ?[*:0]u8 {
    var ch = main_clib.getchar();
    ls().dicq = ls().dicp; // uses top of dictionary as temporary work space
    while (ch == ' ' or ch == '\t') {
        ch = main_clib.getchar();
    }
    if (ch == '~') {
        ls().dicq[0] = @intCast(ch);
        ls().dicq += 1;
        ch = main_clib.getchar();
        while ((if (charOf(ch)) |b| std.ascii.isAlphanumeric(b) else false) or ch == '-' or ch == '_' or ch == '.') {
            ls().dicq[0] = @intCast(ch);
            ls().dicq += 1;
            ch = main_clib.getchar();
        }
        ls().dicq[0] = 0;
        if (gethome(ls().dicp + 1)) |h_dir| {
            const h_span = std.mem.span(h_dir);
            @memcpy(ls().dicp[0..h_span.len], h_span);
            ls().dicp[h_span.len] = 0;
            ls().dicq = ls().dicp + std.mem.len(ls().dicp);
        }
    }
    while (ch != main_clib.EOF and !(if (charOf(ch)) |b| std.ascii.isWhitespace(b) else false)) {
        ls().dicq[0] = @intCast(ch);
        ls().dicq += 1;
        if (ch == '%') {
            const idx = @as(usize, @intFromPtr(ls().dicq)) - @as(usize, @intFromPtr(ls().dicp));
            if (idx >= 2 and (ls().dicq - 2)[0] == '\\') {
                (ls().dicq - 2)[0] = '%';
                ls().dicq -= 1;
            } else {
                ls().dicq -= 1;
                {
                    const script_span = std.mem.span(rt.rs().current_script.?);
                    @memcpy(ls().dicq[0..script_span.len], script_span);
                    ls().dicq[script_span.len] = 0;
                }
                ls().dicq += std.mem.len(rt.rs().current_script.?);
            }
        }
        ch = main_clib.getchar();
    }
    ls().dicq[0] = 0;
    ls().dicq += 1;
    ovflocheck();
    while (ch == ' ' or ch == '\t') {
        ch = main_clib.getchar();
    }
    if (getStdin()) |stdin_file| {
        _ = main_clib.ungetc(ch, stdin_file);
    }
    if (ls().dicp[0] == 0) {
        return null;
    }
    return ls().dicp;
}

/// Append the Miranda source extension to name `s` (flag `b` selects the variant).
pub fn addextn(b: Word, s_input: [*:0]u8) [*:0]u8 {
    var s = s_input;
    var n: Word = @intCast(std.mem.len(s));
    if (s[0] == '<' and s[@intCast(n - 1)] == '>') {
        var miralen: usize = 0;
        if (miralen == 0) {
            miralen = std.mem.len(rt.rs().miralib.?);
        }
        {
            const miralib_span = std.mem.span(rt.rs().miralib.?);
            @memcpy(rt.rs().linebuf[0..miralib_span.len], miralib_span);
        }
        rt.rs().linebuf[miralen] = '/';
        {
            const rest_span = std.mem.span(s + 1);
            @memcpy(rt.rs().linebuf[miralen + 1 ..][0..rest_span.len], rest_span);
            rt.rs().linebuf[miralen + 1 + rest_span.len] = 0;
        }
        {
            const linebuf_span = std.mem.span(@as([*:0]const u8, @ptrCast(&rt.rs().linebuf)));
            @memcpy(ls().dicp[0..linebuf_span.len], linebuf_span);
            ls().dicp[linebuf_span.len] = 0;
        }
        s = ls().dicp;
        n = n + @as(Word, @intCast(miralen)) - 1;
        ls().dicq = ls().dicp + @as(usize, @intCast(n + 1));
        (ls().dicq - 1)[0] = 0; // overwrites '>'
        ovflocheck();
    } else if (s[0] == '"' and s[@intCast(n - 1)] == '"') {
        ls().dicq = ls().dicp;
        var p = s + 1;
        while (p[0] != 0) {
            ls().dicq[0] = p[0];
            ls().dicq += 1;
            p += 1;
        }
        (ls().dicq - 1)[0] = 0; // overwrites '"'
        s = ls().dicp;
        n = n - 2;
    }
    if (b == 0 or (n >= 2 and std.mem.eql(u8, std.mem.span(s + @as(usize, @intCast(n - 2))), ".m"))) {
        return s;
    }
    if (s == ls().dicp) {
        ls().dicq -= 1;
    } else {
        ls().dicq = ls().dicp;
        var p = s;
        while (p[0] != 0) {
            ls().dicq[0] = p[0];
            ls().dicq += 1;
            p += 1;
        }
        ls().dicq[0] = 0;
    }
    if (std.mem.eql(u8, std.mem.span(ls().dicq - 2), ".x")) {
        ls().dicq -= 2;
    } else if ((ls().dicq - 1)[0] == '.') {
        ls().dicq -= 1;
    }
    {
        const ext = ".m";
        @memcpy(ls().dicq[0..ext.len], ext);
        ls().dicq[ext.len] = 0;
    }
    ls().dicq += 3;
    ovflocheck();
    return ls().dicp;
}

/// Emit `n` spaces (for listings).
/// Read a whole input line into a buffer.
pub fn rdline() ?[*:0]u8 {
    var p: [*]u8 = &ls().rdline_linebuf;
    var ch = main_clib.getchar();
    var expansion: Word = 0;
    while (ch == ' ' or ch == '\t') {
        ch = main_clib.getchar();
    }
    if (ch == '\n' or (ch == '!' and ls().rdline_linebuf[0] == 0)) {
        if (ls().rdline_linebuf[0] != 0) {
            word.print("!{s}", .{@as([*:0]const u8, @ptrCast(&ls().rdline_linebuf))});
        }
        while (ch != '\n' and ch != main_clib.EOF) {
            ch = main_clib.getchar();
        }
        return @ptrCast(&ls().rdline_linebuf);
    }
    if (ch == '!') {
        expansion = 1;
        p = @ptrCast(&ls().rdline_linebuf[std.mem.len(@as([*:0]const u8, @ptrCast(&ls().rdline_linebuf))) - 1]); // p now points at old '\n'
    } else {
        if (getStdin()) |stdin_file| {
            _ = main_clib.ungetc(ch, stdin_file);
        }
    }
    while (true) {
        ch = main_clib.getchar();
        p[0] = @intCast(ch);
        p += 1;
        if (ch == '\n' or ch == main_clib.EOF) {
            break;
        }
        const offset = @as(usize, @intFromPtr(p)) - @as(usize, @intFromPtr(&ls().rdline_linebuf));
        if (offset >= 1024) {
            p[0] = 0;
            word.printErr("sorry, !command too long (limit={} chars): {s}...\n", .{ @as(c_int, 1024), @as([*:0]const u8, @ptrCast(&ls().rdline_linebuf)) });
            while (true) {
                ch = main_clib.getchar();
                if (ch == '\n' or ch == main_clib.EOF) {
                    break;
                }
            }
            return null;
        }
        if ((p - 1)[0] == '%') {
            if (@intFromPtr(p) > @intFromPtr(&ls().rdline_linebuf[1]) and (p - 2)[0] == '\\') {
                (p - 2)[0] = '%';
                p -= 1;
            } else {
                const remaining = 1024 - (@as(usize, @intFromPtr(p - 1)) - @as(usize, @intFromPtr(&ls().rdline_linebuf)));
                {
                    const src_span = std.mem.span(rt.rs().current_script.?);
                    const limit = @min(src_span.len, remaining);
                    @memcpy((p - 1)[0..limit], src_span[0..limit]);
                    if (limit < remaining) {
                        @memset((p - 1)[limit..remaining], 0);
                    }
                }
                p = @ptrCast(&ls().rdline_linebuf[std.mem.len(@as([*:0]const u8, @ptrCast(&ls().rdline_linebuf)))]);
                expansion = 1;
            }
        }
    }
    p[0] = 0;
    if (expansion != 0) {
        word.print("!{s}", .{@as([*:0]const u8, @ptrCast(&ls().rdline_linebuf))});
    }
    return @ptrCast(&ls().rdline_linebuf);
}

/// Begin enforcing the literate-script left margin.
/// Make a grammar-variable node with index `i`.
pub fn mkgvar(heap: *Heap, i_input: Word) Word {
    var i = i_input;
    var p = &ls().gvars;
    while (i > 1) {
        if (p.* == NIL) {
            p.* = cons(stoId("gvar"), NIL);
        }
        p = tp(heap, p.*);
        i -= 1;
    }
    if (p.* == NIL) {
        p.* = cons(stoId("gvar"), NIL);
    }
    return h(heap, p.*);
}

/// Make a lexer-variable node with index `i`.
pub fn mklexvar(heap: *Heap, i: Word) Word {
    if (ls().lexvar == 0) {
        ls().lexvar = cons(stoId("ls.lexvar"), stoId("ls.lexvar"));
        tp(heap, h(heap, ls().lexvar)).* = cs().ltchar;
        tp(heap, t(heap, ls().lexvar)).* = genlstatType();
    }
    return if (i != 0) t(heap, ls().lexvar) else h(heap, ls().lexvar);
}

/// Build the command-line argument list as a Miranda list value.
pub fn convArgs() Word {
    var i = ls().ARGC;
    var x = NIL;
    if (i == 0) {
        return NIL;
    }
    i -= 1;
    while (i > 0) {
        x = cons(strConv(ls().ARGV[@intCast(i)].?), x);
        i -= 1;
    }
    x = cons(strConv(ls().ARGV[0].?), x);
    return x;
}

/// Convert C-string `s` to a Miranda char list.
///
/// Tests: strConv: a C string becomes a Miranda char list
pub fn strConv(s: [*:0]const u8) Word {
    var x = NIL;
    var i = std.mem.len(s);
    while (i > 0) {
        i -= 1;
        x = cons(s[i], x);
    }
    return x;
}

test "strConv: a C string becomes a Miranda char list" {
    tu.freshInterp();
    try tu.expectStr("hello", strConv("hello"));
    try tu.expectStr("", strConv(""));
}

/// Scan a `<...>` or quoted pathname token.
/// Adjust the stored library path prefix for `f`.
pub fn adjustPrefix(f: [*:0]const u8) void {
    ls().prefixstack = cons(ls().prefix, ls().prefixstack);
    ls().prefix += @as(Word, @intCast(std.mem.len(@as([*:0]const u8, @ptrCast(ls().prefixbase.? + @as(usize, @intCast(ls().prefix))))))) + 1;
    while (@as(usize, @intCast(ls().prefix)) + std.mem.len(f) >= @as(usize, @intCast(ls().prefixlimit))) {
        const old_limit = ls().prefixlimit;
        ls().prefixlimit += 1024;
        const old_slice = ls().prefixbase.?[0..@intCast(old_limit)];
        const new_slice = rt.allocator.realloc(old_slice, @intCast(ls().prefixlimit)) catch mallocPanic("ls.prefixbase");
        ls().prefixbase = new_slice.ptr;
    }
    {
        const dest = ls().prefixbase.? + @as(usize, @intCast(ls().prefix));
        const f_span = std.mem.span(f);
        @memcpy(dest[0..f_span.len], f_span);
        dest[f_span.len] = 0;
    }
    const g: ?[*]u8 = blk: {
        const dest = ls().prefixbase.? + @as(usize, @intCast(ls().prefix));
        const dest_span = std.mem.span(@as([*:0]const u8, @ptrCast(dest)));
        break :blk if (std.mem.lastIndexOfScalar(u8, dest_span, '/')) |idx| dest + idx else null;
    };
    if (g) |gp| {
        gp[1] = 0;
    } else {
        (ls().prefixbase.? + @as(usize, @intCast(ls().prefix)))[0] = 0;
    }
}

/// Open source file `n` for reading; returns 0 on failure.
pub fn openfile(n: [*:0]const u8) c_int {
    const f = word.fopen(n, "r") orelse return 0;
    // FILE* handle stored in the cell (read back via @ptrFromInt below);
    // this is a FILE-handle-in-cell cast, not a node string — out of B1 scope.
    ls().fileq = cons(make(.STRCONS, @as(Word, @intCast(@intFromPtr(f))), NIL), ls().fileq);
    ls().insertdepth += 1;
    return 1;
}

/// Scan an identifier beginning with char `s`; returns its token id.
/// Intern token text `p` into permanent dictionary storage.
pub fn keep(p: [*:0]u8) [*:0]u8 {
    if (p == ls().dicp) {
        ls().dicp = ls().dicq;
    } else {
        {
            const p_span = std.mem.span(p);
            @memcpy(ls().dicp[0..p_span.len], p_span);
            ls().dicp[p_span.len] = 0;
        }
        const ret = ls().dicp;
        ls().dicp = ls().dicp + std.mem.len(ls().dicp) + 1;
        ls().dicq = ls().dicp;
        dicCheck();
        return ret;
    }
    return p;
}

/// Extend the dictionary buffer when it nears full.
pub fn dicCheck() void {
    ovflocheck();
}

/// Scan a decimal numeral literal.
/// Scan a name token, returning its dictionary `ID` node.
pub fn name(heap: *Heap) Word {
    _ = heap;
    const nm = std.mem.span(@as([*:0]const u8, @ptrCast(ls().dicp)));
    const existed = symbols.syms().find(nm) != null;
    const q = symbols.syms().intern(rt.allocator, nm) catch mallocPanic("symbols dictionary");
    if (!existed) _ = keep(ls().dicp);
    return q;
}

/// Intern name `n` as a *fresh* `ID` node, unconditionally, shadowing any
/// existing entry for `n` in the dictionary. Thin wrapper over
/// `symbols.zig`'s `SymbolTable.createFresh` — see its doc comment for why
/// this must not be find-or-create.
///
/// The `keep()` call is unrelated to interning (`createFresh`'s `stoId` always
/// makes its own permanent copy in `strtab`): it protects the scratch
/// dictionary buffer's bytes at `n` from being overwritten by the next
/// `kollect()` before anything else needs them, exactly as it does elsewhere
/// in this file.
///
/// Tests: makeId / findid: intern then look up a dictionary name
pub fn makeId(n: [*:0]const u8) Word {
    const kept = if (ls().inprelude) keep(@constCast(n)) else n;
    return symbols.syms().createFresh(rt.allocator, std.mem.span(kept)) catch mallocPanic("symbols dictionary");
}

/// Look up name `n` in the dictionary (NIL if absent).
///
/// Tests: makeId / findid: intern then look up a dictionary name
pub fn findid(heap: *Heap, n: [*:0]const u8) Word {
    _ = heap;
    return symbols.syms().find(std.mem.span(n)) orelse NIL;
}

test "makeId / findid: intern then look up a dictionary name" {
    tu.freshInterp();
    const id = makeId("zzqunique");
    try std.testing.expectEqual(id, findid(heap_mod.heap(), "zzqunique"));
    try std.testing.expectEqual(@as(Word, NIL), findid(heap_mod.heap(), "zznotthere"));
}

/// Fill `out` with interned identifiers that are in scope (have a type) and whose
/// name starts with `prefix`. Returns the number written (capped at `out.len`).
/// Backs the REPL's tab completion; the returned pointers are into the permanent
/// dictionary storage, so they stay valid.
pub fn completeIds(heap: *Heap, prefix: []const u8, out: [][*:0]const u8) usize {
    _ = heap;
    var n: usize = 0;
    var it = symbols.syms().table.iterator();
    while (it.next()) |entry| {
        if (n >= out.len) return n;
        const idnode = entry.value_ptr.*;
        if (heap_mod.idType(idnode) == word.undef_t) continue; // not (yet) in scope
        // Safe: every SymbolTable key is `heap.getId()`'s result (via
        // `intern`), itself `[*:0]const u8` `strtab` storage -- the map's
        // `[]const u8` key type just doesn't carry that guarantee at the
        // type level.
        const id_name: [*:0]const u8 = @ptrCast(entry.key_ptr.*.ptr);
        if (std.mem.startsWith(u8, std.mem.span(id_name), prefix)) {
            out[n] = id_name;
            n += 1;
        }
    }
    return n;
}

/// Reset the private-name table.
pub fn resetPns() void {
    ls().nextpn = 0;
    if (ls().pnvec == null) {
        const slice = rt.allocator.alloc(Word, @intCast(ls().pn_lim)) catch mallocPanic("ls.pnvec");
        ls().pnvec = slice.ptr;
    }
}

/// Make a private-name node for value `val`.
pub fn makePn(val: Word) Word {
    if (ls().nextpn == ls().pn_lim) {
        const old_lim = ls().pn_lim;
        ls().pn_lim += 400;
        const old_slice = ls().pnvec.?[0..@intCast(old_lim)];
        const slice = rt.allocator.realloc(old_slice, @intCast(ls().pn_lim)) catch mallocPanic("ls.pnvec");
        ls().pnvec = slice.ptr;
    }
    ls().pnvec.?[@intCast(ls().nextpn)] = make(.STRCONS, ls().nextpn, val);
    const ret = ls().pnvec.?[@intCast(ls().nextpn)];
    ls().nextpn += 1;
    return ret;
}

/// Allocate/store a private name `n`.
pub fn stoPn(n: Word) Word {
    if (n >= ls().pn_lim) {
        const old_lim = ls().pn_lim;
        while (ls().pn_lim <= n) {
            ls().pn_lim += 400;
        }
        const old_slice = ls().pnvec.?[0..@intCast(old_lim)];
        const slice = rt.allocator.realloc(old_slice, @intCast(ls().pn_lim)) catch mallocPanic("ls.pnvec");
        ls().pnvec = slice.ptr;
    }
    while (ls().nextpn <= n) {
        ls().pnvec.?[@intCast(ls().nextpn)] = make(.STRCONS, ls().nextpn, UNDEF);
        ls().nextpn += 1;
    }
    return ls().pnvec.?[@intCast(n)];
}

/// Re-intern id `x` under a private name (for `%export` hiding).
pub fn mkprivate(heap: *Heap, x_input: Word) void {
    var x = x_input;
    while (x != NIL) {
        // h(heap, x) is an ID node; its name's StrId lives in the STRCONS node's hd.
        // Interned bytes are immutable, so re-intern the privatised form and
        // store the new id back, rather than mutating the bytes in place.
        const id_node = h(heap, x);
        // `SymbolTable` (unlike the legacy `namebucket`) keys on a name captured
        // at insertion time, not re-derived from the node's current name at
        // lookup time. `namebucket`'s bucket-chain scan compared each
        // candidate's *live* `getId()` against the sought text, and its
        // `hash()` discards the top bit of the first byte -- exactly the bit
        // `strtab.privatize` flips -- so a privatised id landed in the *same*
        // bucket it was already chained in. That gave the legacy dictionary a
        // dual lookup for free: the *old* name no longer matches this entry's
        // (now-privatised) live name, so it's correctly invisible to plain
        // lookups, while the *privatised* text (as read back verbatim from a
        // dump's `ID_X` payload -- `dumpOb`'s `.ID` case writes whatever
        // `getId()` currently returns, and `trans.zig`'s `ap(rt.rs().concat, e)`
        // embeds bootstrap ids like "concat" directly into compiled graphs
        // that outlive this privatisation) still finds it.
        //
        // `SymbolTable.find` can't replicate that duality implicitly, so both
        // halves must be explicit: drop the old-name entry (else a later
        // re-definition of the same name -- privlib/stdlib's overlapping
        // predef names, undumped from prelude.x then stdenv.x -- finds this
        // now-privatised, still-bound node and is wrongly flagged as a name
        // clash by `loadDefs`'s `DEF_X` case), and add a new entry keyed by
        // the privatised text pointing at the same node (else a later dump
        // that references this id via its privatised spelling resolves to
        // nothing and misreports "UNDEFINED NAME").
        const old_name = std.mem.span(getId(heap, id_node));
        _ = symbols.syms().table.remove(old_name);
        const strcons = h(heap, h(heap, id_node));
        hp(heap, strcons).* = strtab.privatize(strtab.table(), h(heap, strcons));
        const new_name = std.mem.span(getId(heap, id_node));
        symbols.syms().table.put(rt.allocator, new_name, id_node) catch mallocPanic("symbols dictionary");
        x = t(heap, x);
    }
    ls().inprelude = false;
}

/// Scan a string literal.
/// Reset the lexer's per-line scanning state.
pub fn resetLex(heap: *Heap) void {
    if (core_state.s().commandmode == 0) {
        if (core_state.s().errs == 0) {
            core_state.s().errs = fileinfo(strtab.strBits(strtab.table(), heap_mod.getFil(heap.current_file) orelse ""), ls().line_no);
        }
        const err_script_raw = @as(?[*:0]const u8, strtab.strOf(strtab.table(), h(heap, core_state.s().errs)));
        const err_script = err_script_raw orelse "test.m";
        const is_current = if (err_script_raw) |es|
            (if (rt.rs().current_script) |script| std.mem.eql(u8, std.mem.span(es), std.mem.span(script)) else false)
        else
            true;
        if (!@import("builtin").is_test) {
            if (t(heap, core_state.s().errs) == 0 and is_current) {
                word.printErr("error occurs at end of ", .{});
            } else {
                word.printErr("error found near line {} of ", .{t(heap, core_state.s().errs)});
            }
            word.printErr("{s}file \"{s}\"\ncompilation abandoned\n", .{ if (is_current) @as([*:0]const u8, "") else "%insert ", err_script });
        }
        if (is_current) {
            core_state.s().errline = if (t(heap, core_state.s().errs) == 0) ls().lastline else t(heap, core_state.s().errs);
            core_state.s().errs = 0;
        } else {
            if (ls().linostack != NIL) {
                while (t(heap, ls().linostack) != NIL) {
                    ls().linostack = t(heap, ls().linostack);
                }
                core_state.s().errline = h(heap, ls().linostack);
            } else {
                core_state.s().errline = ls().lastline;
            }
        }
    }
    resetState(heap);
}

/// Reset the full lexer state (between sessions).
pub fn resetState(heap: *Heap) void {
    if (core_state.s().commandmode != 0) {
        while (ls().c != '\n' and ls().c != main_clib.EOF) {
            if (rt.rs().s_in) |sin| {
                ls().c = main_clib.getc(sin);
            } else {
                ls().c = main_clib.EOF;
            }
        }
    }
    while (ls().fileq != NIL) {
        const file_ptr: ?*word.FILE = @ptrFromInt(@as(usize, @intCast(h(heap, h(heap, ls().fileq)))));
        _ = word.fclose(file_ptr);
        ls().fileq = t(heap, ls().fileq);
    }
    ls().insertdepth = -1;
    rt.rs().s_in = getStdin();
    ls().echostack = NIL;
    ls().idsused = NIL;
    ls().prefixstack = NIL;
    ls().litstack = NIL;
    ls().linostack = NIL;
    ls().vergstack = NIL;
    ls().margstack = NIL;
    ls().prefix = 0;
    ls().prefixbase.?[0] = 0;
    rt.rs().echoing = rt.rs().verbosity & rt.rs().listing;
    ls().brct = 0;
    ls().inbnf = 0;
    ls().sreds = 0;
    ls().inlex = 0;
    ls().inexplist = 0;
    core_state.s().commandmode = 0;
    ls().lverge = 0;
    ls().col = 0;
    ls().lmargin = 0;
    ls().atnl = 1;
    cs().rv_script = 0;
    cs().algshfns = NIL;
    cs().newtyps = NIL;
    cs().showchain = NIL;
    cs().SGC = NIL;
    cs().TABSTRS = NIL;
    ls().c = ' ';
    ls().line_no = 0;
    ls().litmain = 0;
    ls().literate = 0;
    core_state.s().errs = 0;
    core_state.s().errline = 0;
}

/// Hash identifier text into a dictionary bucket index.
/// Whether name `input` is a constructor name — begins uppercase (1/0).
///
/// Tests: identifier classification matches Miranda lexer rules
pub fn isconstrname(input: [*:0]const u8) bool {
    var s = input;
    if (s[0] == '$') s += 1;
    return std.ascii.isUpper(s[0]);
}

/// Whether char `ch` is valid within an identifier (1/0).
///
/// Tests: identifier classification matches Miranda lexer rules
pub fn okid(ch: c_int) bool {
    return ((ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or
        ch == '_' or
        ch == '\'');
}

test "identifier classification matches Miranda lexer rules" {
    try std.testing.expect(isconstrname("Name"));
    try std.testing.expect(isconstrname("$Name"));
    try std.testing.expect(!(isconstrname("name")));
    try std.testing.expect(okid('a'));
    try std.testing.expect(okid('\''));
    try std.testing.expect(!(okid('-')));
}
