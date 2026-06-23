const std = @import("std");
const word = @import("word.zig");
const strtab = @import("strtab.zig");
const combinator = @import("combinator.zig");
const rt = @import("runtime_state.zig");
const core = @import("core_state.zig");
const lex_state = @import("../parser/lex_state.zig");
const ls = &lex_state.ls;

const compiler_state = @import("../compiler/compiler_state.zig");
const r7_types = @import("../compiler/types.zig");
const r7_repl = @import("../driver/repl.zig");
const r7_files = @import("../io/files.zig");
const r7_lex = @import("../parser/lex.zig");
const r7_big = @import("big.zig");
const r7_reduce = @import("reduce.zig");
const r7_word = @import("word.zig");
const main_clib = @import("main_clib.zig");
const setup = @import("../compiler/setup.zig");
const dump = @import("../compiler/dump.zig");
const cs = &compiler_state.cs;

const Word = i64;
const wordsize = @sizeOf(Word) * 8;
const bits_15 = 0xffff;

pub inline fn the_val(x: Word) Word {
    return t(x);
}

inline fn gettvar(x: Word) Word {
    return t(x);
}

inline fn t_arity(x: Word) Word {
    return h(h(t(x)));
}

inline fn mktvar(i: Word) Word {
    return make(word.TVAR, 0, i);
}
const ATOMLIMIT = word.ATOMLIMIT;
const NIL = word.NIL;
const NILS = word.NILS;
const STRCONS = word.STRCONS;
const INT = word.INT;
const DOUBLE = word.DOUBLE;
const ID = word.ID;
const UNICODE = word.UNICODE;
const CONS = word.CONS;

const strcmp = r7_word.strcmp;
const fpe_error = r7_repl.fpe_error;
const fpdatum = if (@sizeOf(Word) == 4)
    extern union {
        real: f64,
        bits: extern struct {
            left: Word,
            right: Word,
        },
    }
else if (@sizeOf(Word) == 8)
    extern union {
        real: f64,
        bits: Word,
    }
else
    @compileError("platform has unknown word size");

var charname_buffer: [8]u8 = undefined;

/// One heap cell: a tag byte plus two `Word` fields. Atoms (index < ATOMLIMIT)
/// occupy rows too but use only `.tag`. Stored struct-of-arrays via
/// `std.MultiArrayList`, replacing the old interleaved `hd[x*2]`/`tl[x*2]` +
/// separate `tag[x]` parallel arrays (R3).
pub const Cell = struct {
    tag: r7_word.NodeTag = .ATOM,
    hd: Word = 0,
    tl: Word = 0,
};

pub const Heap = struct {
    /// Owning storage. Indexed by cell id `x` directly (row x); length BIGTOP+1.
    cells: std.MultiArrayList(Cell) = .{},
    // Cached column pointers into `cells` for fast x-indexed access. Refreshed
    // by refreshPointers() whenever `cells` is (re)allocated.
    hd: ?[*]Word = null,
    tl: ?[*]Word = null,
    tag: ?[*]r7_word.NodeTag = null,
    SPACE: Word = 1250000,
    listp: Word = ATOMLIMIT - 1,
    allocated_dstack_size: usize = 0,

    /// Refresh the cached column pointers after `cells` is (re)allocated.
    fn refreshPointers(self: *Heap) void {
        self.hd = self.cells.items(.hd).ptr;
        self.tl = self.cells.items(.tl).ptr;
        self.tag = self.cells.items(.tag).ptr;
    }

    pub fn h(self: Heap, x: Word) Word {
        if (word.isAtom(x)) return 0;
        return self.hd.?[@as(usize, @intCast(x))];
    }

    pub fn hp(self: Heap, x: Word) *Word {
        std.debug.assert(x >= ATOMLIMIT);
        return &self.hd.?[@as(usize, @intCast(x))];
    }

    pub fn t(self: Heap, x: Word) Word {
        if (word.isAtom(x)) return 0;
        return self.tl.?[@as(usize, @intCast(x))];
    }

    pub fn tp(self: Heap, x: Word) *Word {
        std.debug.assert(x >= ATOMLIMIT);
        return &self.tl.?[@as(usize, @intCast(x))];
    }

    /// The raw tag byte. The stored tag is a typed `r7_word.NodeTag` (R3.2); this
    /// returns its integer value so the many `getTag(x) == word.XXX` int
    /// comparisons keep working. During GC the byte may be a negated mark.
    pub fn getTag(self: Heap, x: Word) u8 {
        return @intFromEnum(self.tag.?[@intCast(x)]);
    }

    /// Typed tag (for `switch` on `NodeTag` in dispatch, e.g. dump_ob).
    pub fn getTagEnum(self: Heap, x: Word) r7_word.NodeTag {
        return self.tag.?[@intCast(x)];
    }

    pub fn setTag(self: *Heap, x: Word, val: u8) void {
        self.tag.?[@intCast(x)] = @enumFromInt(val);
    }

    pub fn cons(self: *Heap, x: Word, y: Word) Word {
        return self.make(CONS, x, y);
    }

    pub fn TOP(self: Heap) Word {
        return self.SPACE + ATOMLIMIT;
    }

    pub fn BIGTOP(self: Heap) Word {
        _ = self;
        return rt.rs.SPACELIMIT + ATOMLIMIT;
    }

    pub fn trueheapsize(self: Heap) Word {
        return if (nogcs == 0) self.listp - ATOMLIMIT + 1 else self.SPACE;
    }

    pub fn setupheap(self: *Heap) void {
        const bigtop_val = @as(usize, @intCast(self.BIGTOP()));
        if (self.cells.len == 0) {
            // First-time allocation: rows [0, BIGTOP]; zero the whole tag column.
            self.cells.resize(rt.allocator, bigtop_val + 1) catch mallocPanic("heap");
            self.refreshPointers();
            @memset(self.tag.?[0 .. bigtop_val + 1], .ATOM);
        }
        self.refreshPointers();
        if (self.SPACE > rt.rs.SPACELIMIT) {
            self.SPACE = rt.rs.SPACELIMIT;
        }
        self.listp = ATOMLIMIT - 1;
        @memset(self.tag.?[@intCast(ATOMLIMIT)..bigtop_val], .ATOM);
    }

    pub fn resetheap(self: *Heap) void {
        if (rt.rs.SPACELIMIT < self.trueheapsize()) {
            _ = word.printErr("impossible event in resetheap\n", .{});
            main_clib.exit(1);
        }
        const bigtop_val = @as(usize, @intCast(self.BIGTOP()));
        self.cells.resize(rt.allocator, bigtop_val + 1) catch mallocPanic("heap");
        self.refreshPointers();

        self.tag.?[@intCast(bigtop_val)] = .ATOM;
        if (self.SPACE > rt.rs.SPACELIMIT) {
            self.SPACE = rt.rs.SPACELIMIT;
        }
        if (self.SPACE < 1250000 and 1250000 <= rt.rs.SPACELIMIT) {
            self.SPACE = 1250000;
            self.tag.?[@intCast(self.TOP())] = .ATOM;
        }
    }

    pub fn make(self: *Heap, t_val: u8, x: Word, y: Word) Word {
        while (true) {
            self.listp += 1;
            if (!poschar(@intFromEnum(self.tag.?[@intCast(self.listp)]))) {
                break;
            }
        }
        if (self.listp == self.TOP()) {
            if (self.SPACE != rt.rs.SPACELIMIT) {
                if (core.compiling == 0) {
                    self.SPACE = rt.rs.SPACELIMIT;
                } else if (claims <= @divTrunc(self.SPACE, 4) and nogcs > 1) {
                    var wait: Word = 0;
                    const sp = self.SPACE;
                    if (wait != 0) {
                        wait -= 1;
                    } else {
                        self.SPACE += @divTrunc(self.SPACE, 2);
                        wait = 2;
                        self.SPACE = 5000 * (1 + @divTrunc(self.SPACE - 1, 5000));
                    }
                    if (self.SPACE > rt.rs.SPACELIMIT) {
                        self.SPACE = rt.rs.SPACELIMIT;
                    }
                    if (rt.rs.atgc != 0 and self.SPACE > sp) {
                        _ = word.printErr("\n<<increase heap from {d} to {d}>>\n", .{ sp, self.SPACE });
                    }
                }
            }
            if (self.listp == self.TOP()) {
                self.gc();
                if (t_val > word.STRCONS) {
                    self.mark(x);
                }
                if (t_val >= word.INT) {
                    self.mark(y);
                }
                return self.make(t_val, x, y);
            }
        }
        claims += 1;
        self.tag.?[@intCast(self.listp)] = @enumFromInt(t_val);
        self.hp(self.listp).* = x;
        self.tp(self.listp).* = y;
        return self.listp;
    }

    pub fn gc(self: *Heap) void {
        collecting = 1;
        var idx = @as(usize, @intCast(ATOMLIMIT));
        if (rt.rs.atgc != 0) {
            _ = word.printErr("\n<<gc after {d} claims>>\n", .{claims});
        }
        if (claims <= @divTrunc(self.SPACE, 10) and nogcs > 1 and self.SPACE == rt.rs.SPACELIMIT) {
            var hnogcs: Word = 0;
            if (nogcs == hnogcs) {
                _ = word.printErr("<<not enough heap space -- task abandoned>>\n", .{});
                if (core.compiling == 0) {
                    outstats();
                }
                if (core.compiling != 0 and rt.rs.ideep == 0) {
                    _ = word.printErr("not enough heap to compile current script\n", .{});
                    _ = word.printErr("script = \"{s}\", heap = {d}\n", .{ rt.rs.current_script orelse @as([*:0]const u8, "(null)"), self.SPACE });
                }
                main_clib.exit(1);
            } else {
                hnogcs = nogcs + 1;
            }
        }
        nogcs += 1;

        while (self.tag.?[idx] != .ATOM) {
            const signed_val = @as(i8, @bitCast(@intFromEnum(self.tag.?[idx])));
            self.tag.?[idx] = @enumFromInt(@as(u8, @bitCast(-signed_val)));
            idx += 1;
        }

        self.bases();
        self.listp = ATOMLIMIT - 1;
        cellcount += claims;
        claims = 0;
        collecting = 0;
    }

    pub fn gcpatch(self: *Heap) void {
        var idx = @as(usize, @intCast(ATOMLIMIT));
        while (self.tag.?[idx] != .ATOM) : (idx += 1) {
            const signed_val = @as(i8, @bitCast(@intFromEnum(self.tag.?[idx])));
            if (signed_val < 0) {
                self.tag.?[idx] = @enumFromInt(@as(u8, @bitCast(-signed_val)));
            }
        }
    }

    pub fn bases(self: *Heap) void {
        var p: [*]Word = undefined;
        p = @ptrCast(@alignCast(&p));
        const cstack_ptr = rt.rs.cstack.?;
        if (@intFromPtr(p) < @intFromPtr(cstack_ptr)) {
            p += 1;
            while (@intFromPtr(p) < @intFromPtr(cstack_ptr)) : (p += 1) {
                self.mark(p[0]);
            }
        } else {
            p -= 1;
            while (@intFromPtr(p) > @intFromPtr(cstack_ptr)) : (p -= 1) {
                self.mark(p[0]);
            }
        }
        self.mark(cstack_ptr[0]);

        self.mark(r7_reduce.outfilq);
        self.mark(r7_reduce.waiting);
        if (core.compiling != 0 or rt.rs.rv_expr != 0 or cs.rv_script != 0) {
            self.mark(rt.rs.make_status);
            self.mark(rt.rs.primenv);
            self.mark(ls.fileq);
            self.mark(ls.idsused);
            self.mark(rt.rs.eprodnts);
            self.mark(rt.rs.nonterminals);
            self.mark(rt.rs.ntmap);
            self.mark(rt.rs.ihlist);
            self.mark(rt.rs.ntspecmap);
            self.mark(ls.gvars);
            self.mark(ls.lexvar);
            self.mark(ls.common_stdin);
            self.mark(ls.common_stdinb);
            self.mark(ls.cook_stdin);
            self.mark(ls.margstack);
            self.mark(ls.vergstack);
            self.mark(ls.litstack);
            self.mark(ls.linostack);
            self.mark(ls.prefixstack);
            self.mark(files);
            self.mark(rt.rs.oldfiles);
            self.mark(rt.rs.includees);
            self.mark(rt.rs.freeids);
            self.mark(rt.rs.exports);
            self.mark(dump.internals);
            self.mark(rt.rs.lexstates);
            self.mark(rt.rs.lexdefs);
            var i: usize = 0;
            while (i < 128) : (i += 1) {
                if (ls.namebucket[i] != 0) {
                    self.mark(ls.namebucket[i]);
                }
            }
            const p_dstack = dstack;
            const p_stackp = stackp;
            if (p_dstack != null and p_stackp != null) {
                var curr = p_dstack.?;
                const end = p_stackp.?;
                while (@intFromPtr(curr) < @intFromPtr(end)) : (curr += 1) {
                    self.mark(curr[0]);
                }
            }
            if (core.loading != 0) {
                self.mark(ls.exportfiles);
                self.mark(rt.rs.embargoes);
                self.mark(rt.rs.rfl);
                self.mark(rt.rs.detrop);
                self.mark(rt.rs.bereaved);
                self.mark(rt.rs.ld_stuff);
                self.mark(dump.tlost);
                i = 0;
                const nextpn_val = @as(usize, @intCast(ls.nextpn));
                while (i < nextpn_val) : (i += 1) {
                    self.mark(ls.pnvec.?[i]);
                }
            }
            self.mark(rt.rs.lastname);
            self.mark(rt.rs.suppressids);
            self.mark(rt.rs.lastexp);
            self.mark(core.nill);
            self.mark(rt.rs.standardout);
            self.mark(r7_big.big_one);
            self.mark(r7_big.b_rem);
            self.mark(ls.yylval);
            self.mark(ls.echostack);
            self.mark(core.errs);

            // Automatically trace all active roots in CompilerState cs singleton using compile-time reflection.
            inline for (std.meta.fields(compiler_state.CompilerState)) |field| {
                const T = field.type;
                switch (@typeInfo(T)) {
                    .int => {
                        if (T == Word) {
                            self.mark(@field(cs, field.name));
                        }
                    },
                    .array => |info| {
                        if (info.child == Word) {
                            for (@field(cs, field.name)) |elem| {
                                self.mark(elem);
                            }
                        }
                    },
                    else => {},
                }
            }
        }
    }

    pub fn isptr(self: Heap, x: Word) bool {
        return x >= ATOMLIMIT and x < self.TOP();
    }

    pub fn mark(self: *Heap, x_val: Word) void {
        var x = x_val & ~r7_word.tlptrbits;
        while (self.isptr(x) and negchar(@intFromEnum(self.tag.?[@intCast(x)]))) {
            const p1 = &self.tag.?[@intCast(x)];
            const signed_tag = @as(i8, @bitCast(@intFromEnum(p1.*)));
            const new_signed_tag = -signed_tag;
            p1.* = @enumFromInt(@as(u8, @bitCast(new_signed_tag)));

            const new_tag = @intFromEnum(p1.*);
            if (new_tag > word.STRCONS) {
                self.mark(self.h(x));
            }
            if (new_tag >= word.INT) {
                x = self.t(x) & ~r7_word.tlptrbits;
            } else {
                break;
            }
        }
    }
};

pub var heap: Heap = .{};

pub fn h(x: Word) Word {
    return heap.h(x);
}

pub fn hp(x: Word) *Word {
    return heap.hp(x);
}

pub fn t(x: Word) Word {
    return heap.t(x);
}

pub fn tp(x: Word) *Word {
    return heap.tp(x);
}

pub fn getTag(x: Word) r7_word.NodeTag {
    return @enumFromInt(heap.getTag(x));
}

pub fn cons(x: Word, y: Word) Word {
    return heap.cons(x, y);
}

pub fn tries(x: Word, y: Word) Word {
    return make(@intCast(word.TRIES), x, y);
}

fn idWho(x: Word) Word {
    return t(h(h(x)));
}

fn getId(x: Word) [*:0]const u8 {
    return strtab.strOf(h(h(h(x))));
}

pub fn sto_char(ch: Word) Word {
    return if (word.fitsInByte(ch)) ch else make(UNICODE, ch, 0);
}

pub fn get_char(x: Word) Word {
    if (word.fitsInByte(x)) return x;
    if (heap.getTag(x) == UNICODE) return h(x);
    std.debug.print("impossible event in get_char(x), tag[x]=={d}\n", .{heap.getTag(x)});
    main_clib.exit(1);
}

pub fn is_char(x: Word) c_int {
    if (word.isLatin1Char(x)) return 1;
    if (x >= 0 and heap.getTag(x) == UNICODE) return 1;
    return 0;
}

pub fn get_here(x: Word) Word {
    const y = idWho(x);
    return if (heap.getTag(y) == CONS) t(y) else y;
}

pub fn getaka(x: Word) [*:0]const u8 {
    const y = idWho(x);
    return if (heap.getTag(y) != CONS) getId(x) else strtab.strOf(h(h(y)));
}

pub fn append1(x: Word, y: Word) Word {
    var x1 = x;
    if (x1 == nil()) return y;
    while (t(x1) != nil()) x1 = t(x1);
    tp(x1).* = y;
    return x;
}

pub fn hdsort(input: Word) Word {
    var x = input;
    var a: Word = nil();
    var b: Word = nil();
    if (x == nil()) return nil();
    if (t(x) == nil()) return x;
    while (x != nil()) {
        const hold = a;
        a = cons(h(x), b);
        b = hold;
        x = t(x);
    }
    a = hdsort(a);
    b = hdsort(b);
    while (a != nil() and b != nil()) {
        if (strcmp(getId(h(h(a))), getId(h(h(b)))) < 0) {
            x = cons(h(a), x);
            a = t(a);
        } else {
            x = cons(h(b), x);
            b = t(b);
        }
    }
    if (a == nil()) a = b;
    while (a != nil()) {
        x = cons(h(a), x);
        a = t(a);
    }
    return reverse(x);
}

pub fn charname(ch: Word) [*:0]const u8 {
    return switch (ch) {
        '\n' => "\\n",
        '\t' => "\\t",
        '\x08' => "\\b",
        '\x0c' => "\\f",
        '\r' => "\\r",
        '\\' => "\\\\",
        '\'' => "\\'",
        '"' => "\\\"",
        else => blk: {
            if (ch < 32 or ch > 126) {
                const text = std.fmt.bufPrintZ(&charname_buffer, "\\{d}", .{ch}) catch unreachable;
                break :blk text.ptr;
            }
            charname_buffer[0] = @intCast(ch);
            charname_buffer[1] = 0;
            break :blk @as([*:0]const u8, @ptrCast(charname_buffer[0..].ptr));
        },
    };
}

pub fn outr(file: ?*word.FILE, value: f64) void {
    const magnitude = if (value < 0) -value else value;
    if (magnitude >= 1000.0 or magnitude <= 0.001) {
        _ = word.fprint(file, "{d}", .{value});
    } else {
        _ = word.fprint(file, "{d}", .{value});
    }
}

pub fn get_dbl(x: Word) f64 {
    var r: fpdatum = undefined;
    if (comptime @sizeOf(Word) == 4) {
        r.bits.left = h(x);
        r.bits.right = t(x);
    } else {
        r.bits = h(x);
    }
    return r.real;
}

pub fn sto_dbl(R_val: f64) Word {
    if (!std.math.isFinite(R_val)) {
        fpe_error(main_clib.SIGFPE);
    }
    var r: fpdatum = undefined;
    r.real = R_val;
    if (comptime @sizeOf(Word) == 4) {
        return make(DOUBLE, r.bits.left, r.bits.right);
    } else {
        return make(DOUBLE, r.bits, 0);
    }
}

pub fn setdbl(x: Word, R_val: f64) void {
    if (!std.math.isFinite(R_val)) {
        fpe_error(main_clib.SIGFPE);
    }
    var r: fpdatum = undefined;
    r.real = R_val;
    heap.setTag(x, @intCast(DOUBLE));
    if (comptime @sizeOf(Word) == 4) {
        hp(x).* = r.bits.left;
        tp(x).* = r.bits.right;
    } else {
        hp(x).* = r.bits;
        tp(x).* = 0;
    }
}

fn nil() Word {
    return 306 + 138;
}

pub export var SPACE: Word = 1250000;
pub export var listp: Word = ATOMLIMIT - 1;
pub export var files: Word = word.NIL;
pub export var current_file: Word = word.NIL;
pub export var cellcount: i64 = 0;
pub export var claims: c_long = 0;
pub export var nogcs: c_long = 0;
pub export var dstack: ?[*]Word = null;
pub export var stackp: ?[*]Word = null;
pub export var collecting: c_int = 0;

var dlim: ?[*]Word = null;

const outstats = r7_reduce.outstats;
const initclock = r7_reduce.initclock;
const hashsize = r7_word.hashsize;

fn TOP() Word {
    return heap.TOP();
}

fn BIGTOP() Word {
    return heap.BIGTOP();
}

pub fn trueheapsize() Word {
    return heap.trueheapsize();
}

pub fn setupheap() void {
    heap.setupheap();
}

pub fn resetheap() void {
    heap.resetheap();
}

pub fn mallocfail(x: [*:0]const u8) void {
    _ = word.printErr("panic: cannot find enough free space for {s}\n", .{x});
    main_clib.exit(1);
}

pub fn mallocPanic(what: [*:0]const u8) noreturn {
    mallocfail(what);
    unreachable;
}

pub fn resetgcstats() void {
    cellcount = -claims;
    nogcs = 0;
    initclock();
}

fn poschar(val: u8) bool {
    const signed_val = @as(i8, @bitCast(val));
    return signed_val > 0;
}

pub fn make(t_val: u8, x: Word, y: Word) Word {
    return heap.make(t_val, x, y);
}

pub fn gc() void {
    heap.gc();
}

pub fn gcpatch() void {
    heap.gcpatch();
}



fn getStderr() ?*word.FILE {
    const T = @TypeOf(main_clib.stderr);
    if (comptime @typeInfo(T) == .@"fn") {
        return main_clib.stderr();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return main_clib.stderr();
    } else {
        return main_clib.stderr;
    }
}

export var prefix: [r7_word.pnlim]u8 = undefined;
export var preflen: Word = 0;

const fm_time = r7_files.fm_time;
const unlinkx = r7_files.unlinkx;
pub fn sto_id(p1: [*:0]const u8) Word {
    return make(word.ID, cons(make(word.STRCONS, strtab.strBits(p1), word.NIL), word.undef_t), word.UNDEF);
}

pub fn getword(file: ?*word.FILE) Word {
    var s: i32 = 0;
    var i: usize = @sizeOf(Word);
    var x = @as(Word, @intCast(main_clib.getc(file)));
    while (i > 1) {
        i -= 1;
        s += 8;
        const next_ch = @as(Word, @intCast(main_clib.getc(file)));
        x |= next_ch << @intCast(s);
    }
    return x;
}

pub fn putword(x_val: Word, file: ?*word.FILE) void {
    var x = x_val;
    var i: usize = @sizeOf(Word);
    _ = word.putc(@intCast(x & 255), file);
    while (i > 1) {
        i -= 1;
        x >>= 8;
        _ = word.putc(@intCast(x & 255), file);
    }
}

pub fn setprefix(p: [*:0]const u8) void {
    const p_len = std.mem.len(p);
    if (p_len >= prefix.len) {
        mallocfail("prefix buffer overflow");
    }
    @memcpy(prefix[0..p_len], p[0..p_len]);
    prefix[p_len] = 0;

    var last_slash: ?usize = null;
    var i: usize = p_len;
    while (i > 0) {
        i -= 1;
        if (prefix[i] == '/') {
            last_slash = i;
            break;
        }
    }
    if (last_slash) |idx| {
        prefix[idx + 1] = 0;
        preflen = @intCast(idx + 1);
    } else {
        prefix[0] = 0;
        preflen = 0;
    }
}

pub fn mkrel(p: [*:0]const u8) [*:0]const u8 {
    const p_len = std.mem.len(p);
    const prefix_len = @as(usize, @intCast(preflen));
    if (prefix_len <= p_len and std.mem.eql(u8, prefix[0..prefix_len], p[0..prefix_len])) {
        return @ptrCast(p + prefix_len);
    }
    if (p[0] == '/') {
        return p;
    }
    _ = word.printErr("impossible event in mkrelative\n", .{.{}});
    return p;
}

pub fn okdump(t_ptr: [*:0]const u8) c_int {
    var obf: [120]u8 = undefined;
    const t_len = std.mem.len(t_ptr);
    if (t_len >= obf.len) {
        return 0;
    }
    @memcpy(obf[0..t_len], t_ptr[0..t_len]);
    obf[t_len] = 0;

    const suffix_str = std.mem.span(core.obsuffix);
    const suffix_len = suffix_str.len;
    if (t_len + suffix_len - 1 >= obf.len) {
        return 0;
    }
    @memcpy(obf[t_len - 1 .. t_len - 1 + suffix_len], suffix_str.ptr);
    obf[t_len - 1 + suffix_len] = 0;

    const f = word.fopen(&obf, "r") orelse return 0;
    defer _ = word.fclose(f);

    const ch1 = main_clib.getc(f);
    const ch2 = main_clib.getc(f);
    if (ch1 == word.XVERSION and ch2 != 0) {
        return 1;
    }
    return 0;
}

pub fn geterrlin(t_ptr: [*:0]const u8) Word {
    var obf: [120]u8 = undefined;
    const t_len = std.mem.len(t_ptr);
    if (t_len >= obf.len) {
        return 0;
    }
    @memcpy(obf[0..t_len], t_ptr[0..t_len]);
    obf[t_len] = 0;

    const suffix_str = std.mem.span(core.obsuffix);
    const suffix_len = suffix_str.len;
    if (t_len + suffix_len - 1 >= obf.len) {
        return 0;
    }
    @memcpy(obf[t_len - 1 .. t_len - 1 + suffix_len], suffix_str.ptr);
    obf[t_len - 1 + suffix_len] = 0;

    const f = word.fopen(&obf, "r") orelse return 0;
    defer _ = word.fclose(f);

    const ch1 = main_clib.getc(f);
    if (ch1 != word.XVERSION) {
        return 0;
    }

    const ch2 = main_clib.getc(f);
    if (ch2 != 0 and ch2 != 1) {
        return 0;
    }

    const el = getword(f);

    // now check this is right dump
    setprefix(t_ptr);
    var ch = main_clib.getc(f);
    ls.dicq = ls.dicp;
    if (ch != '/') {
        const prefix_len = @as(usize, @intCast(preflen));
        @memcpy(ls.dicp[0..prefix_len], prefix[0..prefix_len]);
        ls.dicp[prefix_len] = 0;
        ls.dicq = ls.dicp + prefix_len;
    }

    // locate wrt current posn
    ls.dicq[0] = @intCast(ch);
    ls.dicq += 1;

    while (true) {
        ch = main_clib.getc(f);
        ls.dicq[0] = @intCast(ch);
        ls.dicq += 1;
        if (ch == 0 or ch == main_clib.EOF) {
            break;
        }
    }

    const mtime = getword(f);
    if (main_clib.strcmp(ls.dicp, t_ptr) != 0 or mtime != fm_time(t_ptr)) {
        return 0; // wrong dump
    }

    return el;
}

const bigtostr = r7_big.bigtostr;
const SIGNBIT = 0x10000000;
const MAXDIGIT = 0x7fff;

fn rest(x: Word) Word {
    return t(x);
}

fn digit(x: Word) Word {
    return h(x);
}

fn digit0(x: Word) Word {
    return h(x) & MAXDIGIT;
}

fn getsmallint(x: Word) Word {
    return if ((h(x) & SIGNBIT) != 0) -digit0(x) else digit(x);
}

pub fn stosmallint(x: Word) Word {
    const val = if (x < 0) SIGNBIT | @as(Word, @intCast(-x)) else x;
    return make(word.INT, val, 0);
}

pub inline fn dlhs(d: Word) Word {
    return h(d);
}

pub inline fn dval(d: Word) Word {
    return t(t(d));
}

fn get_id(x: Word) [*:0]const u8 {
    return getId(x);
}

fn castPtr(val: Word) [*:0]const u8 {
    return strtab.strOf(val);
}

pub fn out(file: ?*word.FILE, x_val: Word) void {
    var x = x_val;
    if (x < 0 or x > TOP()) {
        _ = word.fprint(file, "<{d}>", .{x});
        return;
    }
    if (heap.getTag(x) == word.LAMBDA) {
        _ = word.fprint(file, "$(", .{.{}});
        out(file, h(x));
        _ = word.putc(')', file);
        out(file, t(x));
    } else {
        while (heap.getTag(x) == word.CONS) {
            out1(file, h(x));
            _ = word.putc(':', file);
            x = t(x);
        }
        out1(file, x);
    }
}

pub fn out1(file: ?*word.FILE, x: Word) void {
    if (x < 0 or x > TOP()) {
        _ = word.fprint(file, "<{d}>", .{x});
        return;
    }
    if (heap.getTag(x) == word.AP) {
        out1(file, h(x));
        _ = word.putc(' ', file);
        out2(file, t(x));
    } else {
        out2(file, x);
    }
}

pub fn out2(file: ?*word.FILE, x_val: Word) void {
    var x = x_val;
    if (x < 0 or x > TOP()) {
        _ = word.fprint(file, "<{d}>", .{x});
        return;
    }
    const tag_val = heap.getTag(x);
    if (tag_val == word.INT) {
        if (rest(x) != 0) {
            x = bigtostr(x);
            while (x != 0) {
                _ = word.putc(@intCast(h(x)), file);
                x = t(x);
            }
        } else {
            _ = word.fprint(file, "{d}", .{getsmallint(x)});
        }
        return;
    }
    if (tag_val == word.DOUBLE) {
        outr(file, get_dbl(x));
        return;
    }
    if (tag_val == word.ID) {
        _ = word.fprint(file, "{s}", .{get_id(x)});
        return;
    }
    if (word.fitsInByte(x)) {
        _ = word.fprint(file, "'{s}'", .{charname(x)});
        return;
    }
    if (tag_val == word.UNICODE) {
        _ = word.fprint(file, "'{x}'", .{h(x)});
        return;
    }
    if (tag_val == word.ATOM) {
        const str: [*:0]const u8 = if (x < word.CMBASE)
            @ptrCast(setup.yysterm[@intCast(x - 256)])
        else if (x == word.True)
            "True"
        else if (x == word.False)
            "False"
        else if (x == word.NIL)
            "[]"
        else if (x == word.NILS)
            "\"\""
        else
            @ptrCast(combinator.cmbnms[@intCast(x - word.CMBASE)]);
        _ = word.fprint(file, "{s}", .{str});
        return;
    }
    if (tag_val == word.TCONS or tag_val == word.PAIR) {
        _ = word.fprint(file, "(", .{.{}});
        while (heap.getTag(x) == word.TCONS) {
            out(file, h(x));
            _ = word.putc(',', file);
            x = t(x);
        }
        out(file, h(x));
        _ = word.putc(',', file);
        out(file, t(x));
        _ = word.putc(')', file);
        return;
    }
    if (tag_val == word.TRIES) {
        _ = word.fprint(file, "TRIES(", .{.{}});
        out(file, h(x));
        _ = word.putc(',', file);
        out(file, t(x));
        _ = word.putc(')', file);
        return;
    }
    if (tag_val == word.LABEL) {
        _ = word.fprint(file, "LABEL(", .{.{}});
        out(file, h(x));
        _ = word.putc(',', file);
        out(file, t(x));
        _ = word.putc(')', file);
        return;
    }
    if (tag_val == word.SHOW) {
        _ = word.fprint(file, "SHOW(", .{.{}});
        out(file, h(x));
        _ = word.putc(',', file);
        out(file, t(x));
        _ = word.putc(')', file);
        return;
    }
    if (tag_val == word.STARTREADVALS) {
        _ = word.fprint(file, "READVALS(", .{.{}});
        out(file, h(x));
        _ = word.putc(',', file);
        out(file, t(x));
        _ = word.putc(')', file);
        return;
    }
    if (tag_val == word.LET) {
        _ = word.fprint(file, "(LET ", .{.{}});
        out(file, dlhs(h(x)));
        _ = word.fprint(file, "=", .{.{}});
        out(file, dval(h(x)));
        _ = word.fprint(file, ";IN ", .{.{}});
        out(file, t(x));
        _ = word.fprint(file, ")", .{.{}});
        return;
    }
    if (tag_val == word.LETREC) {
        const body = t(x);
        _ = word.fprint(file, "(LETREC ", .{.{}});
        x = h(x);
        while (x != word.NIL) {
            out(file, dlhs(h(x)));
            _ = word.fprint(file, "=", .{.{}});
            out(file, dval(h(x)));
            _ = word.fprint(file, ";", .{.{}});
            x = t(x);
        }
        _ = word.fprint(file, "IN ", .{.{}});
        out(file, body);
        _ = word.fprint(file, ")", .{.{}});
        return;
    }
    if (tag_val == word.DATAPAIR) {
        _ = word.fprint(file, "DATAPAIR({s},{d})", .{ castPtr(h(x)), t(x) });
        return;
    }
    if (tag_val == word.FILEINFO) {
        _ = word.fprint(file, "FILEINFO({s},{d})", .{ castPtr(h(x)), t(x) });
        return;
    }
    if (tag_val == word.CONSTRUCTOR) {
        _ = word.fprint(file, "CONSTRUCTOR({d})", .{h(x)});
        return;
    }
    if (tag_val == word.STRCONS) {
        _ = word.fprint(file, "<${d}>", .{h(x)});
        return;
    }
    if (tag_val == word.SHARE) {
        _ = word.fprint(file, "(SHARE:", .{.{}});
        out(file, h(x));
        _ = word.fprint(file, ")", .{.{}});
        return;
    }
    if (tag_val != word.CONS and tag_val != word.AP and tag_val != word.LAMBDA) {
        _ = word.fprint(file, "<{d}|tag={d}>", .{ x, tag_val });
        return;
    }
    _ = word.putc(')', file);
}

var PNBASE: Word = 0;
var CFN: ?[*:0]const u8 = null;

const member = r7_types.member;
const add1 = r7_types.add1;
const name = r7_lex.name;
fn get_fil(fil: Word) [*:0]const u8 {
    return castPtr(h(h(h(fil))));
}

pub fn fil_time(fil: Word) Word {
    return t(h(h(fil)));
}

pub fn fil_share(fil: Word) Word {
    return h(t(h(fil)));
}

pub fn fil_defs(fil: Word) Word {
    return t(fil);
}

pub fn make_fil(fil_name: ?[*:0]const u8, time_val: Word, share: Word, defs: Word) Word {
    const name_word = if (fil_name) |n| @as(Word, strtab.strBits(n)) else 0;
    return cons(cons(make(word.FILEINFO, name_word, time_val), cons(share, word.NIL)), defs);
}

fn get_pn(x: Word) Word {
    return h(x);
}

fn pn_val(x: Word) Word {
    return t(x);
}

pub fn id_who(x: Word) Word {
    return t(h(h(x)));
}

pub fn id_type(x: Word) Word {
    return t(h(x));
}

pub fn id_val(x: Word) Word {
    return t(x);
}

fn id_who_ptr(x: Word) *Word {
    return tp(h(h(x)));
}

fn id_type_ptr(x: Word) *Word {
    return tp(h(x));
}

fn id_val_ptr(x: Word) *Word {
    return tp(x);
}

fn pn_val_ptr(x: Word) *Word {
    return tp(x);
}

pub fn t_class(x: Word) Word {
    return h(t(the_val(x)));
}

pub fn t_info(x: Word) Word {
    return t(t(x));
}

fn stackpPush(val: Word) void {
    stackp.?[0] = val;
    stackp = stackp.? + 1;
}

fn stackpPop() Word {
    stackp = stackp.? - 1;
    return stackp.?[0];
}

fn stackpTop() Word {
    return (stackp.? - 1)[0];
}

fn stackpSetTop(val: Word) void {
    (stackp.? - 1)[0] = val;
}

fn datapair(x: Word, y: Word) Word {
    return make(word.DATAPAIR, x, y);
}

fn fileinfo(x: Word, y: Word) Word {
    return make(word.FILEINFO, x, y);
}

pub fn constructor(n: Word, x: anytype) Word {
    const x_val: Word = switch (@TypeOf(x)) {
        Word => x,
        c_int, c_uint => @intCast(x),
        [*:0]const u8, [*:0]u8 => strtab.strBits(x),
        else => @compileError("Unsupported type for constructor"),
    };
    return make(word.CONSTRUCTOR, n, x_val);
}

fn readvals(x: Word, y: Word) Word {
    return make(word.STARTREADVALS, x, y);
}

fn ap(x: Word, y: Word) Word {
    return make(word.AP, x, y);
}

pub fn putint(n: i32, file: ?*word.FILE) void {
    _ = word.fwrite(&n, @sizeOf(i32), 1, file);
}

pub fn getint(file: ?*word.FILE) i32 {
    var r: i32 = 0;
    _ = word.fread(&r, @sizeOf(i32), 1, file);
    return r;
}

pub fn putdbl(x: Word, file: ?*word.FILE) void {
    var d = get_dbl(x);
    _ = word.fwrite(&d, @sizeOf(f64), 1, file);
}

pub fn getdbl(file: ?*word.FILE) Word {
    var d: f64 = 0;
    _ = word.fread(&d, @sizeOf(f64), 1, file);
    return sto_dbl(d);
}

pub fn dump_script(files_val: Word, file: ?*word.FILE) void {
    _ = word.putc(@intCast(wordsize), file);
    _ = word.putc(word.XVERSION, file);

    if (files_val == word.NIL) {
        _ = word.putc(0, file);
        putword(core.errline, file);
        var x = rt.rs.oldfiles;
        while (x != word.NIL) : (x = t(x)) {
            _ = word.fprint(file, "{s}", .{mkrel(get_fil(h(x)))});
            _ = word.putc(0, file);
            putword(fil_time(h(x)), file);
        }
        return;
    }

    if (cs.ND != word.NIL) {
        _ = word.putc(1, file);
        putword(core.errline, file);
    }

    var f_list = files_val;
    while (f_list != word.NIL) : (f_list = t(f_list)) {
        CFN = get_fil(h(f_list));
        _ = word.fprint(file, "{s}", .{mkrel(CFN.?)});
        _ = word.putc(0, file);
        putword(fil_time(h(f_list)), file);
        _ = word.putc(@intCast(fil_share(h(f_list))), file);
        dump_defs(fil_defs(h(f_list)), file);
    }
    _ = word.putc(0, file);
    dump_defs(cs.algshfns, file);
    if (cs.ND == word.NIL and rt.rs.bereaved != word.NIL) {
        dump_ob(word.True, file);
    } else {
        dump_ob(cs.ND, file);
    }
    _ = word.putc(word.DEF_X, file);
    dump_ob(cs.SGC, file);
    _ = word.putc(word.DEF_X, file);
    dump_ob(rt.rs.freeids, file);
    _ = word.putc(word.DEF_X, file);
    dump_defs(dump.internals, file);
}

pub fn dump_defs(defs_val: Word, file: ?*word.FILE) void {
    var defs = defs_val;
    while (defs != word.NIL) : (defs = t(defs)) {
        const item = h(defs);
        if (heap.getTag(item) == word.STRCONS) {
            const v = get_pn(item);
            dump_ob(pn_val(item), file);
            if (v > bits_15) {
                _ = word.putc(word.PN1_X, file);
                putint(@intCast(v), file);
            } else {
                _ = word.putc(word.PN_X, file);
                _ = word.putc(@intCast(v & 255), file);
                _ = word.putc(@intCast(v >> 8), file);
            }
            _ = word.putc(word.DEF_X, file);
        } else {
            dump_ob(id_val(item), file);
            dump_ob(id_type(item), file);
            dump_ob(id_who(item), file);
            _ = word.putc(word.ID_X, file);
            _ = word.fprint(file, "{s}", .{get_id(item)});
            _ = word.putc(0, file);
            _ = word.putc(word.DEF_X, file);
        }
    }
    _ = word.putc(word.DEF_X, file);
}

pub fn dump_ob(x: Word, file: ?*word.FILE) void {
    switch (heap.getTagEnum(x)) {
        .ATOM => {
            if (x < 128) {
                _ = word.putc(@intCast(x), file);
            } else if (x >= 384) {
                _ = word.putc(@intCast(x - 256), file);
            } else {
                _ = word.putc(word.CHAR_X, file);
                _ = word.putc(@intCast(x - 128), file);
            }
        },
        .TVAR => {
            _ = word.putc(word.TVAR_X, file);
            _ = word.putc(@intCast(gettvar(x)), file);
            if (gettvar(x) > 255) {
                std.debug.print("panic, tvar too large\n", .{});
            }
        },
        .INT => {
            var curr = x;
            const d = digit(curr);
            if (rest(curr) == 0 and (d & MAXDIGIT) <= 127) {
                var signed_d = d;
                if ((d & SIGNBIT) != 0) {
                    signed_d = -@as(Word, @intCast(d & MAXDIGIT));
                }
                _ = word.putc(word.SHORT_X, file);
                _ = word.putc(@intCast(signed_d), file);
                return;
            }
            _ = word.putc(word.INT_X, file);
            putint(@intCast(d), file);
            curr = rest(curr);
            while (curr != 0) {
                putint(@intCast(digit(curr)), file);
                curr = rest(curr);
            }
            putint(-1, file);
        },
        .DOUBLE => {
            _ = word.putc(word.DBL_X, file);
            putdbl(x, file);
        },
        .UNICODE => {
            _ = word.putc(word.UNICODE_X, file);
            putint(@intCast(h(x)), file);
        },
        .DATAPAIR => {
            _ = word.fprint(file, "{c}{s}", .{ @as(u8, @intCast(word.AKA_X)), castPtr(h(x)) });
            _ = word.putc(0, file);
        },
        .FILEINFO => {
            var line = t(x);
            const path = castPtr(h(x));
            if (main_clib.strcmp(path, CFN.?) == 0) {
                _ = word.putc(word.HERE_X, file);
            } else {
                _ = word.fprint(file, "{c}{s}", .{ @as(u8, @intCast(word.HERE_X)), mkrel(path) });
            }
            _ = word.putc(0, file);
            _ = word.putc(@intCast(line & 255), file);
            line >>= 8;
            _ = word.putc(@intCast(line & 255), file);
            if (line > 255) {
                std.debug.print("impossible line number {d} in dump_ob\n", .{t(x)});
            }
        },
        .CONSTRUCTOR => {
            dump_ob(t(x), file);
            _ = word.putc(word.CONSTRUCT_X, file);
            _ = word.putc(@intCast(h(x) & 255), file);
            _ = word.putc(@intCast(h(x) >> 8), file);
        },
        .STARTREADVALS => {
            dump_ob(t(x), file);
            _ = word.putc(word.RV_X, file);
        },
        .ID => {
            _ = word.fprint(file, "{c}{s}", .{ @as(u8, @intCast(word.ID_X)), get_id(x) });
            _ = word.putc(0, file);
        },
        .STRCONS => {
            const v = get_pn(x);
            if (v > bits_15) {
                _ = word.putc(word.PN1_X, file);
                putint(@intCast(v), file);
            } else {
                _ = word.putc(word.PN_X, file);
                _ = word.putc(@intCast(v & 255), file);
                _ = word.putc(@intCast(v >> 8), file);
            }
        },
        .AP => {
            dump_ob(h(x), file);
            dump_ob(t(x), file);
            _ = word.putc(word.AP_X, file);
        },
        .CONS => {
            dump_ob(t(x), file);
            dump_ob(h(x), file);
            _ = word.putc(word.CONS_X, file);
        },
        else => {
            std.debug.print("impossible tag {d} in dump_ob\n", .{heap.getTag(x)});
        },
    }
}

pub fn load_script(file: ?*word.FILE, src: [*:0]const u8, aliases: Word, params: Word, main_flag: Word) Word {
    cs.TORPHANS = 0;
    cs.BAD_DUMP = 0;
    cs.CLASHES = word.NIL;
    dsetup();
    setprefix(src);
    if (main_clib.getc(file) != wordsize or main_clib.getc(file) != word.XVERSION) {
        cs.BAD_DUMP = -1;
        return word.NIL;
    }
    if (aliases != word.NIL) {
        var a = aliases;
        cs.ALIASES = aliases;
        while (a != word.NIL) : (a = t(a)) {
            const old = t(h(a));
            const new_id = h(h(a));
            const hold = cons(id_who(old), cons(id_type(old), id_val(old)));
            id_type_ptr(old).* = word.alias_t;
            id_val_ptr(old).* = new_id;
            if (heap.getTag(new_id) == word.ID) {
                if ((id_type(new_id) != word.undef_t or id_val(new_id) != word.UNDEF) and id_type(new_id) != word.alias_t) {
                    cs.CLASHES = add1(new_id, cs.CLASHES);
                }
            }
            hp(h(a)).* = hold;
        }
        if (cs.CLASHES != word.NIL) {
            cs.BAD_DUMP = -2;
            unscramble(aliases);
            return word.NIL;
        }
        a = aliases;
        while (a != word.NIL) : (a = t(a)) {
            const ch = id_val(t(h(a)));
            if (heap.getTag(ch) == word.ID) {
                if (id_type(ch) != word.alias_t) {
                    id_type_ptr(ch).* = word.new_t;
                }
            }
        }
    }
    PNBASE = ls.nextpn;
    cs.SUPPRESSED = word.NIL;
    cs.TSUPPRESSED = word.NIL;

    var files_list: Word = word.NIL;
    var ch: Word = main_clib.getc(file);
    while (ch != 0 and ch != main_clib.EOF and cs.BAD_DUMP == 0) {
        var s: Word = 0;
        var holde: Word = 0;
        ls.dicq = ls.dicp;
        if (files_list == word.NIL and ch == 1) {
            holde = getword(file);
            ch = main_clib.getc(file);
            if (main_flag != 0) {
                core.errline = holde;
            }
        }
        if (ch != '/') {
            _ = main_clib.strcpy(ls.dicp, &prefix);
            ls.dicq = ls.dicp + @as(usize, @intCast(preflen));
        }
        ls.dicq[0] = @intCast(ch);
        ls.dicq += 1;
        while (true) {
            ch = main_clib.getc(file);
            ls.dicq[0] = @intCast(ch);
            ls.dicq += 1;
            if (ch == 0 or ch == main_clib.EOF) {
                break;
            }
        }
        if (@intFromPtr(ls.dicq) - @intFromPtr(ls.dicp) > rt.rs.DICSPACE) {
            r7_lex.dicovflo();
        }
        ch = getword(file);
        s = main_clib.getc(file);
        if (files_list == word.NIL) {
            if (main_clib.strcmp(ls.dicp, src) != 0) {
                cs.BAD_DUMP = 1;
                if (aliases != word.NIL) {
                    unscramble(aliases);
                }
                return word.NIL;
            }
        }
        CFN = get_id(name());
        files_list = cons(make_fil(CFN, ch, s, load_defs(file)), files_list);
        ch = main_clib.getc(file);
    }
    if (ch == main_clib.EOF or cs.BAD_DUMP != 0) {
        if (cs.BAD_DUMP == 0) {
            cs.BAD_DUMP = 2;
        }
        if (aliases != word.NIL) {
            unscramble(aliases);
        }
        return files_list;
    }
    if (files_list == word.NIL) {
        ch = getword(file);
        if (main_flag != 0) {
            core.errline = ch;
        }
        while (true) {
            ch = main_clib.getc(file);
            if (ch == main_clib.EOF) {
                break;
            }
            ls.dicq = ls.dicp;
            if (ch != '/') {
                _ = main_clib.strcpy(ls.dicp, &prefix);
                ls.dicq = ls.dicp + @as(usize, @intCast(preflen));
            }
            ls.dicq[0] = @intCast(ch);
            ls.dicq += 1;
            while (true) {
                ch = main_clib.getc(file);
                ls.dicq[0] = @intCast(ch);
                ls.dicq += 1;
                if (ch == 0 or ch == main_clib.EOF) {
                    break;
                }
            }
            if (@intFromPtr(ls.dicq) - @intFromPtr(ls.dicp) > rt.rs.DICSPACE) {
                r7_lex.dicovflo();
            }
            ch = getword(file);
            if (rt.rs.oldfiles == word.NIL) {
                if (main_clib.strcmp(ls.dicp, src) != 0) {
                    cs.BAD_DUMP = 1;
                    if (aliases != word.NIL) {
                        unscramble(aliases);
                    }
                    return word.NIL;
                }
            }
            rt.rs.oldfiles = cons(make_fil(get_id(name()), ch, 0, word.NIL), rt.rs.oldfiles);
        }
        if (aliases != word.NIL) {
            unscramble(aliases);
        }
        return word.NIL;
    }
    cs.algshfns = append1(cs.algshfns, load_defs(file));
    cs.ND = load_defs(file);
    if (cs.ND == word.True) {
        cs.ND = word.NIL;
        cs.TORPHANS = 1;
    }
    cs.SGC = append1(cs.SGC, load_defs(file));
    if (main_flag != 0 or rt.rs.includees == word.NIL) {
        rt.rs.freeids = load_defs(file);
    } else {
        bindparams(load_defs(file), hdsort(params));
    }
    if (aliases != word.NIL) {
        unscramble(aliases);
    }
    if (main_flag != 0) {
        dump.internals = load_defs(file);
    }
    return reverse(files_list);
}

pub fn bindparams(formal_val: Word, actual_val: Word) void {
    var formal = formal_val;
    var actual = actual_val;
    var badkind: Word = word.NIL;
    cs.DETROP = word.NIL;
    cs.MISSING = word.NIL;
    cs.FBS = cons(formal, cs.FBS);

    while (true) {
        var a: Word = 0;
        var f: [*:0]const u8 = undefined;
        while (formal != word.NIL and (actual == word.NIL or blk: {
            f = castPtr(h(h(t(h(formal)))));
            a = h(h(actual));
            break :blk main_clib.strcmp(f, get_id(a)) < 0;
        })) {
            cs.MISSING = cons(h(t(h(formal))), cs.MISSING);
            formal = t(formal);
        }
        if (actual == word.NIL) {
            break;
        }
        if (formal == word.NIL or main_clib.strcmp(f, get_id(a)) != 0) {
            cs.DETROP = cons(a, cs.DETROP);
        } else {
            const fa = if (t(t(h(formal))) == word.type_t) t_arity(h(h(formal))) else -1;
            const ta = if (heap.getTag(h(actual)) == word.AP) t_arity(h(actual)) else -1;
            if (fa != ta) {
                badkind = cons(cons(h(h(actual)), datapair(fa, ta)), badkind);
            }
            id_val_ptr(h(h(formal))).* = t(h(actual));
            formal = t(formal);
        }
        actual = t(actual);
    }

    var bk = badkind;
    while (bk != word.NIL) : (bk = t(bk)) {
        cs.DETROP = cons(h(bk), cs.DETROP);
    }
}

pub fn unscramble(aliases: Word) void {
    var a = aliases;
    while (a != word.NIL) : (a = t(a)) {
        const old = t(h(a));
        var hold = h(h(a));
        const new_id = id_val(old);
        hp(h(a)).* = new_id;
        id_who_ptr(old).* = h(hold);
        hold = t(hold);
        id_type_ptr(old).* = h(hold);
        id_val_ptr(old).* = t(hold);
    }
    var al = cs.ALIASES;
    a = word.NIL;
    while (al != word.NIL) : (al = t(al)) {
        const new_id = h(h(al));
        const old = t(h(al));
        if (heap.getTag(new_id) != word.ID) {
            if (member(cs.SUPPRESSED, new_id) == 0) {
                a = cons(old, a);
            }
            continue;
        }
        if (id_type(new_id) == word.new_t) {
            id_type_ptr(new_id).* = word.undef_t;
        }
        if (id_type(new_id) == word.undef_t) {
            a = cons(old, a);
        } else if (member(cs.CLASHES, new_id) == 0) {
            if (heap.getTag(id_who(new_id)) != word.CONS) {
                id_who_ptr(new_id).* = cons(datapair(strtab.strBits(get_id(old)), 0), id_who(new_id));
            }
        }
    }
    cs.ALIASES = a;
}

pub fn dsetup() void {
    if (dstack == null) {
        const slice = rt.allocator.alloc(Word, 1000) catch mallocPanic("dstack");
        dstack = slice.ptr;
        dlim = dstack.? + 1000;
        heap.allocated_dstack_size = 1000;
    }
    stackp = dstack;
}

pub fn dgrow() void {
    const hold = dstack.?;
    const num_elements = dlim.? - hold;
    const old_slice = hold[0..heap.allocated_dstack_size];
    const new_size = num_elements * 2;
    const slice = rt.allocator.realloc(old_slice, new_size) catch mallocPanic("dstack");
    dstack = slice.ptr;
    dlim = dstack.? + new_size;
    stackp = dstack.? + (stackp.? - hold);
    heap.allocated_dstack_size = new_size;
}

pub fn load_defs(file: ?*word.FILE) Word {
    var ch = main_clib.getc(file);
    var defs: Word = word.NIL;
    while (ch != main_clib.EOF) {
        if (stackp == dlim) {
            dgrow();
        }
        switch (ch) {
            word.CHAR_X => {
                stackpPush(main_clib.getc(file) + 128);
            },
            word.TVAR_X => {
                stackpPush(mktvar(main_clib.getc(file)));
            },
            word.SHORT_X => {
                var val = main_clib.getc(file);
                if ((val & 128) != 0) {
                    val = val | (~@as(c_int, 127));
                }
                stackpPush(stosmallint(val));
            },
            word.INT_X => {
                const val = getint(file);
                stackpPush(make(word.INT, val, 0));
                var x = &tp(stackpTop()).*;
                var next = getint(file);
                while (next != -1) {
                    x.* = make(word.INT, next, 0);
                    x = &tp(x.*).*;
                    next = getint(file);
                }
            },
            word.DBL_X => {
                stackpPush(getdbl(file));
            },
            word.UNICODE_X => {
                stackpPush(make(word.UNICODE, getint(file), 0));
            },
            word.PN_X => {
                var val = main_clib.getc(file);
                val = val | (main_clib.getc(file) << 8);
                const idx = PNBASE + val;
                stackpPush(if (idx < ls.nextpn) ls.pnvec.?[@intCast(idx)] else r7_lex.sto_pn(idx));
            },
            word.PN1_X => {
                const idx = PNBASE + getint(file);
                stackpPush(if (idx < ls.nextpn) ls.pnvec.?[@intCast(idx)] else r7_lex.sto_pn(idx));
            },
            word.CONSTRUCT_X => {
                var val = main_clib.getc(file);
                val = val | (main_clib.getc(file) << 8);
                stackpSetTop(constructor(val, stackpTop()));
            },
            word.RV_X => {
                stackpSetTop(readvals(0, stackpTop()));
                cs.rv_script = 1;
            },
            word.ID_X => {
                ls.dicq = ls.dicp;
                while (true) {
                    const next = main_clib.getc(file);
                    ls.dicq[0] = @intCast(next);
                    ls.dicq += 1;
                    if (next == 0 or next == main_clib.EOF) {
                        break;
                    }
                }
                if (@intFromPtr(ls.dicq) - @intFromPtr(ls.dicp) > rt.rs.DICSPACE) {
                    r7_lex.dicovflo();
                }
                stackpPush(name());
                const top = stackpTop();
                if (id_type(top) == word.new_t) {
                    cs.CLASHES = add1(top, cs.CLASHES);
                    stackpSetTop(word.NIL);
                } else if (id_type(top) == word.alias_t) {
                    stackpSetTop(id_val(top));
                }
            },
            word.AKA_X => {
                ls.dicq = ls.dicp;
                while (true) {
                    const next = main_clib.getc(file);
                    ls.dicq[0] = @intCast(next);
                    ls.dicq += 1;
                    if (next == 0 or next == main_clib.EOF) {
                        break;
                    }
                }
                if (@intFromPtr(ls.dicq) - @intFromPtr(ls.dicp) > rt.rs.DICSPACE) {
                    r7_lex.dicovflo();
                }
                stackpPush(datapair(strtab.strBits(get_id(name())), 0));
            },
            word.HERE_X => {
                ls.dicq = ls.dicp;
                var next = main_clib.getc(file);
                if (next == 0) {
                    next = main_clib.getc(file);
                    next = next | (main_clib.getc(file) << 8);
                    stackpPush(fileinfo(strtab.strBits(CFN.?), next));
                } else {
                    if (next != '/') {
                        _ = main_clib.strcpy(ls.dicp, &prefix);
                        ls.dicq = ls.dicp + @as(usize, @intCast(preflen));
                    }
                    ls.dicq[0] = @intCast(next);
                    ls.dicq += 1;
                    while (true) {
                        const val = main_clib.getc(file);
                        ls.dicq[0] = @intCast(val);
                        ls.dicq += 1;
                        if (val == 0 or val == main_clib.EOF) {
                            break;
                        }
                    }
                    if (@intFromPtr(ls.dicq) - @intFromPtr(ls.dicp) > rt.rs.DICSPACE) {
                        r7_lex.dicovflo();
                    }
                    var line = main_clib.getc(file);
                    line = line | (main_clib.getc(file) << 8);
                    stackpPush(fileinfo(strtab.strBits(get_id(name())), line));
                }
            },
            word.DEF_X => {
                const diff = stackp.? - dstack.?;
                switch (diff) {
                    0 => {
                        return reverse(defs);
                    },
                    1 => {
                        return stackpPop();
                    },
                    2 => {
                        const ch_val = stackpPop();
                        pn_val_ptr(ch_val).* = stackpPop();
                        defs = cons(ch_val, defs);
                    },
                    4 => {
                        const top = stackpTop();
                        if (heap.getTag(top) != word.ID) {
                            if (top == word.NIL) {
                                stackp = stackp.? - 4;
                                ch = main_clib.getc(file);
                                continue;
                            }
                            const ch_val = stackpPop();
                            cs.SUPPRESSED = cons(ch_val, cs.SUPPRESSED);
                            _ = stackpPop(); // who
                            const who_val = stackpTop();
                            const akap = if (heap.getTag(who_val) == word.CONS) h(who_val) else word.NIL;
                            const type_val = stackpPop(); // type
                            pn_val_ptr(ch_val).* = stackpPop();

                            if (type_val == word.type_t and t_class(ch_val) != word.synonym_t) {
                                var a = cs.ALIASES;
                                while (a != word.NIL and id_val(t(h(a))) != ch_val) : (a = t(a)) {}
                                if (a != word.NIL) {
                                    cs.TSUPPRESSED = cons(t(h(a)), cs.TSUPPRESSED);
                                }
                            } else if (pn_val(ch_val) == word.UNDEF) {
                                var akap_val = akap;
                                if (akap_val == word.NIL) {
                                    var a = cs.ALIASES;
                                    while (a != word.NIL) : (a = t(a)) {
                                        if (id_val(t(h(a))) == ch_val) {
                                            akap_val = datapair(strtab.strBits(get_id(t(h(a)))), 0);
                                            break;
                                        }
                                    }
                                }
                                pn_val_ptr(ch_val).* = ap(akap_val, fileinfo(strtab.strBits(CFN.?), 0));
                            }
                            defs = cons(ch_val, defs);
                            ch = main_clib.getc(file);
                            continue;
                        }
                        const top_val = stackpTop();
                        if (id_type(top_val) != word.new_t and (id_type(top_val) != word.undef_t or id_val(top_val) != word.UNDEF)) {
                            if (id_type(top_val) == word.alias_t) {
                                var a = cs.ALIASES;
                                while (a != word.NIL and t(h(a)) != top_val) : (a = t(a)) {}
                                if (a == word.NIL) {
                                    std.debug.print("impossible event in cyclic alias ({s})\n", .{get_id(top_val)});
                                    stackp = stackp.? - 4;
                                    ch = main_clib.getc(file);
                                    continue;
                                }
                                defs = cons(stackpPop(), defs);
                                hp(h(h(a))).* = stackpPop(); // who
                                hp(t(h(h(a)))).* = stackpPop(); // type
                                tp(t(h(h(a)))).* = stackpPop(); // value
                                ch = main_clib.getc(file);
                                continue;
                            }
                            cs.CLASHES = add1(top_val, cs.CLASHES);
                            stackp = stackp.? - 4;
                        } else {
                            defs = cons(stackpPop(), defs);
                            id_who_ptr(h(defs)).* = stackpPop();
                            id_type_ptr(h(defs)).* = stackpPop();
                            id_val_ptr(h(defs)).* = stackpPop();
                        }
                    },
                    else => {
                        std.debug.print("unexpected stack diff in load_defs\n", .{});
                    },
                }
            },
            word.AP_X => {
                const ch_val = stackpPop();
                const top = stackpTop();
                if (top == word.READ and ch_val == 0) {
                    stackpSetTop(ls.common_stdin);
                } else if (top == word.READBIN and ch_val == 0) {
                    stackpSetTop(ls.common_stdinb);
                } else {
                    stackpSetTop(ap(top, ch_val));
                }
            },
            word.CONS_X => {
                const ch_val = stackpPop();
                stackpSetTop(cons(ch_val, stackpTop()));
            },
            else => {
                stackpPush(if (ch > 127) ch + 256 else ch);
            },
        }
        ch = main_clib.getc(file);
    }
    cs.BAD_DUMP = 4;
    return defs;
}

// Relocated heap/node domain metadata accessors and lifecycle utilities
pub fn fil_inodev(fil: Word) Word {
    return t(t(h(fil)));
}

pub fn same_file(x: Word, y: Word) bool {
    const ix = fil_inodev(x);
    const iy = fil_inodev(y);
    return h(ix) == h(iy) and t(ix) == t(iy);
}

pub fn badval(x: Word) bool {
    return x < 100 or x > 50000000;
}

pub fn isfreeid(x: Word) bool {
    return id_type(x) == word.undef_t and id_val(x) == word.UNDEF;
}

const isconstrname = r7_lex.isconstrname;
pub fn isconstructor(x: Word) bool {
    return heap.getTag(x) == word.ID and isconstrname(getId(x)) != 0;
}

pub fn isvariable(x: Word) bool {
    return heap.getTag(x) == word.ID and isconstrname(getId(x)) == 0;
}

pub fn addtoenv(x: Word) void {
    tp(h(files)).* = cons(x, t(h(files)));
}

pub fn reverse(input: Word) Word {
    var x = input;
    var y: Word = NIL;
    while (x != NIL) {
        y = cons(h(x), y);
        x = t(x);
    }
    return y;
}

pub fn shunt(input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    while (x != NIL) {
        y = cons(h(x), y);
        x = t(x);
    }
    return y;
}

pub fn size(input: Word) Word {
    var x = input;
    var s: Word = 0;
    while (heap.getTag(x) == CONS or heap.getTag(x) == word.AP) {
        s += 1 + size(h(x));
        x = t(x);
    }
    return s;
}

pub fn alfasort(x_val: Word) Word {
    var x = x_val;
    var a = NIL;
    var b = NIL;
    var hold = NIL;
    if (x == NIL) {
        return NIL;
    }
    if (t(x) == NIL) {
        return if (heap.getTag(h(x)) != word.ID) NIL else x;
    }
    while (x != NIL) {
        if (heap.getTag(h(x)) == word.ID) {
            hold = a;
            a = cons(h(x), b);
            b = hold;
        }
        x = t(x);
    }
    a = alfasort(a);
    b = alfasort(b);
    x = NIL;
    while (a != NIL and b != NIL) {
        if (strcmp(getId(h(a)), getId(h(b))) < 0) {
            x = cons(h(a), x);
            a = t(a);
        } else {
            x = cons(h(b), x);
            b = t(b);
        }
    }
    if (a == NIL) {
        a = b;
    }
    while (a != NIL) {
        x = cons(h(a), x);
        a = t(a);
    }
    return reverse(x);
}

pub fn utf8test() c_int {
    var lang = main_clib.getenv("LC_CTYPE");
    if (lang == null) {
        lang = main_clib.getenv("LANG");
    }
    if (lang) |l| {
        if (main_clib.strstr(l, "UTF-8") != null or
            main_clib.strstr(l, "UTF8") != null or
            main_clib.strstr(l, "utf-8") != null or
            main_clib.strstr(l, "utf8") != null)
        {
            return 1;
        }
    }
    return 0;
}

pub fn unsetids(d_val: Word) void {
    var d = d_val;
    while (d != NIL and d != 0) : (d = t(d)) {
        const item = h(d);
        if (heap.getTag(item) == word.ID) {
            tp(item).* = word.UNDEF;
            tp(h(h(item))).* = NIL;
        }
    }
}

pub fn unload() void {
    rt.rs.sorted = 0;
    cs.speclocs = NIL;
    ls.nextpn = 0;
    cs.rv_script = 0;
    cs.algshfns = NIL;
    unsetids(cs.newtyps);
    cs.newtyps = NIL;
    unsetids(rt.rs.freeids);
    rt.rs.freeids = NIL;
    rt.rs.includees = NIL;
    cs.SGC = NIL;
    cs.TABSTRS = NIL;
    cs.ND = NIL;
    unsetids(dump.internals);
    dump.internals = NIL;
    while (files != NIL and files != 0) : (files = t(files)) {
        const fil = h(files);
        unsetids(t(fil));
        tp(fil).* = NIL;
    }
    var ld = rt.rs.ld_stuff;
    while (ld != NIL and ld != 0) : (ld = t(ld)) {
        var x = h(ld);
        while (x != NIL and x != 0) : (x = t(x)) {
            unsetids(t(h(x)));
        }
    }
    rt.rs.ld_stuff = NIL;
}

pub fn src_update() c_int {
    var ft: Word = undefined;
    var f = if (files == NIL) rt.rs.oldfiles else files;
    while (f != NIL) {
        const _fil_path: [*:0]const u8 = strtab.strOf(h(h(h(h(f)))));
        if ((fm_time(_fil_path)) != fil_time(h(f))) {
            ft = fm_time(_fil_path);
            if (ft == 0) {
                unlinkx(_fil_path);
            }
            return 1;
        }
        f = t(f);
    }
    return 0;
}

// ── Domain types (C2) ────────────────────────────────────────────────────────
// These single-field structs carry semantic intent at API boundaries.
// The underlying Word value is accessible via `.word` for sites that still
// call the procedural accessors. New code should prefer the method style.

/// A heap node that represents a loaded Miranda source file.
/// Created by `make_fil()`; its structure is `(FILEINFO name mtime) . defs`.
pub const FileNode = struct {
    word: Word,

    /// The modification time recorded in the heap for this file (seconds since epoch).
    pub fn time(self: FileNode) Word {
        return fil_time(self.word);
    }
    /// Share flag: 1 for system/shared files (prelude, stdlib), 0 for user scripts.
    pub fn share(self: FileNode) Word {
        return fil_share(self.word);
    }
    /// The definitions list (environment entries compiled from this file).
    pub fn defs(self: FileNode) Word {
        return fil_defs(self.word);
    }
    /// A `(dev . ino)` cons cell identifying this file's filesystem inode.
    pub fn inodev(self: FileNode) Word {
        return fil_inodev(self.word);
    }
    /// True if this file and `other` refer to the same filesystem inode.
    pub fn sameAs(self: FileNode, other: FileNode) bool {
        return same_file(self.word, other.word);
    }
};

/// A heap node that represents a Miranda identifier (name/binding).
/// Created by `make_id()`; has tag ID and carries type, value, and provenance.
pub const Identifier = struct {
    word: Word,

    /// The declared type of this identifier (a type node Word).
    pub fn typ(self: Identifier) Word {
        return id_type(self.word);
    }
    /// The current reduction value of this identifier (combinator or UNDEF).
    pub fn val(self: Identifier) Word {
        return id_val(self.word);
    }
    /// Provenance: a cons list of datapairs recording where this name was defined.
    pub fn who(self: Identifier) Word {
        return id_who(self.word);
    }
    /// True if this identifier names a constructor (starts with upper-case or is an operator).
    pub fn isConstructor(self: Identifier) bool {
        return isconstructor(self.word);
    }
    /// True if this identifier names a type variable (lower-case, not a constructor).
    pub fn isVariable(self: Identifier) bool {
        return isvariable(self.word);
    }
    /// True if this identifier has no definition yet (undef_t type and UNDEF value).
    pub fn isFreeId(self: Identifier) bool {
        return isfreeid(self.word);
    }
    /// Prepends this identifier to the current file's environment definition list.
    pub fn addToEnv(self: Identifier) void {
        addtoenv(self.word);
    }
};

/// A heap node that represents a Miranda type expression or type constructor.
/// Carries a class (synonym_t, algebraic_t, etc.) and auxiliary info.
pub const TypeRef = struct {
    word: Word,

    /// The type class tag (e.g. `c_abi.synonym_t`, `algebraic_t`, `abstract_t`).
    pub fn class(self: TypeRef) Word {
        return t_class(self.word);
    }
    /// Auxiliary info: parameter list for synonyms, constructor list for algebraics.
    pub fn info(self: TypeRef) Word {
        return t_info(self.word);
    }
};

/// Generic typed wrapper for any heap node where the specific domain is not yet refined.
/// Used as a placeholder at typed boundaries until the call site is fully migrated.
pub const NodeRef = struct {
    word: Word,
};

test "domain type wrappers preserve their word value" {
    const w: Word = 42;
    try std.testing.expectEqual(w, (FileNode{ .word = w }).word);
    try std.testing.expectEqual(w, (Identifier{ .word = w }).word);
    try std.testing.expectEqual(w, (TypeRef{ .word = w }).word);
    try std.testing.expectEqual(w, (NodeRef{ .word = w }).word);
}

test "domain type methods are callable at comptime (signature check)" {
    // Verify each method can be resolved — the heap accessors they delegate to
    // are pub fn and require a live heap, so we only check that the call
    // compiles; the actual values are tested via the procedural accessor tests.
    const FileNodeTimeFn = @TypeOf(FileNode.time);
    const IdentifierTypFn = @TypeOf(Identifier.typ);
    const TypeRefClassFn = @TypeOf(TypeRef.class);
    try std.testing.expect(FileNodeTimeFn == fn (FileNode) Word);
    try std.testing.expect(IdentifierTypFn == fn (Identifier) Word);
    try std.testing.expect(TypeRefClassFn == fn (TypeRef) Word);
}

test "sto_char returns atoms for Latin-1 values" {
    try std.testing.expectEqual(@as(Word, 65), sto_char(65));
    try std.testing.expectEqual(@as(c_int, 1), is_char(65));
}

test "heap dump roundtrip" {
    // 1. Initialize heap and stack
    rt.rs.SPACELIMIT = 10000;
    setupheap();
    dsetup();
    
    // 2. Build a representative structure: a cons pair of two small integers
    const item1 = stosmallint(42);
    const item2 = stosmallint(100);
    const list = cons(item1, item2);
    
    // 3. Open a temp file for writing
    const filename = "test_roundtrip.dump";
    const f_write = word.fopen(filename, "w");
    try std.testing.expect(f_write != null);
    
    // 4. Dump the object structure
    dump_ob(list, f_write);
    _ = word.fclose(f_write.?);
    
    // 5. Open the temp file for reading
    const f_read = word.fopen(filename, "r");
    try std.testing.expect(f_read != null);
    
    // 6. Load it back using load_defs (which pushes it onto stackp)
    const old_stackp = stackp;
    _ = load_defs(f_read);
    _ = word.fclose(f_read.?);
    
    // Clean up temp file
    _ = main_clib.unlink(filename);
    
    // 7. Verify structural equality
    try std.testing.expect(@intFromPtr(stackp.?) > @intFromPtr(old_stackp.?));
    const loaded = stackpTop();
    
    try std.testing.expectEqual(word.CONS, heap.getTag(loaded));
    const loaded_h = h(loaded);
    const loaded_t = t(loaded);
    
    try std.testing.expectEqual(word.INT, heap.getTag(loaded_h));
    try std.testing.expectEqual(@as(Word, 42), getsmallint(loaded_h));
    try std.testing.expectEqual(word.INT, heap.getTag(loaded_t));
    try std.testing.expectEqual(@as(Word, 100), getsmallint(loaded_t));
}

fn negchar(val: u8) bool {
    const signed_val = @as(i8, @bitCast(val));
    return signed_val < 0;
}

