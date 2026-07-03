//! heap.zig — the graph heap: cells, allocation, garbage collection, and the
//! object-file (`.x`) dump/load format.
//!
//! Every Miranda value is a tagged cell with a head and tail (`hd`/`tl`); this
//! module owns the cell arena, the `make`/`cons`/… constructors, the mark-sweep
//! `gc`, and the typed accessors layered over the raw cells (id/type/file-record/
//! double/bignum fields). It also implements `dumpScript`/`loadScript` — the
//! serialisation that lets a compiled script be saved and reloaded. The `Heap`
//! struct holds the state; module-level free functions wrap the singleton.

const std = @import("std");
const word = @import("word.zig");
const strtab = @import("strtab.zig");
const combinator = @import("combinator.zig");
const rt = @import("runtime_state.zig");
const core = @import("core_state.zig");
const lex_state = @import("../parser/lex_state.zig");
const ls = lex_state.ls;

const compiler_state = @import("../compiler/compiler_state.zig");
const types = @import("../compiler/types.zig");
const repl = @import("../driver/repl.zig");
const files = @import("../io/files.zig");
const lex = @import("../parser/lex.zig");
const big = @import("big.zig");
const reduce = @import("reduce.zig");
const main_clib = @import("main_clib.zig");
const setup = @import("../compiler/setup.zig");
const dump = @import("../compiler/dump.zig");
const cs = compiler_state.cs;
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)

const Word = i64;
const wordsize = @sizeOf(Word) * 8;
const bits_15 = 0xffff;

/// The value field of a type/definition cell.
pub inline fn theVal(x: Word) Word {
    return t(x);
}

/// The index of type variable `x`.
inline fn gettvar(x: Word) Word {
    return t(x);
}

/// The arity recorded in a type node.
inline fn tArity(x: Word) Word {
    return h(h(t(x)));
}

/// Make a type-variable node with index `i`.
inline fn mktvar(i: Word) Word {
    return make(.TVAR, 0, i);
}
const ATOMLIMIT = word.ATOMLIMIT;
const NIL = word.NIL;
const NILS = word.NILS;

const strcmp = word.strcmp;
const fpeError = repl.fpeError;
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

/// One heap cell: a tag byte plus two `Word` fields. Atoms (index < ATOMLIMIT)
/// occupy rows too but use only `.tag`. Stored struct-of-arrays via
/// `std.MultiArrayList`, replacing the old interleaved `hd[x*2]`/`tl[x*2]` +
/// separate `tag[x]` parallel arrays (R3).
pub const Cell = struct {
    tag: word.NodeTag = .ATOM,
    hd: Word = 0,
    tl: Word = 0,
};

/// The graph heap: the cell arena plus all GC/dictionary scratch (the latter
/// folded in by shared-state Phase 2b). Cells are stored in a `MultiArrayList`
/// indexed by the raw cell id; module-level free functions wrap the singleton
/// [heap]. Accessed as `heap.X`; folded into `interp.heap` so `interp.reset()`
/// clears it.
pub const Heap = struct {
    /// Owning storage. Indexed by cell id `x` directly (row x); length BIGTOP+1.
    cells: std.MultiArrayList(Cell) = .{},
    // Cached column pointers into `cells` for fast x-indexed access. Refreshed
    // by refreshPointers() whenever `cells` is (re)allocated.
    hd: ?[*]Word = null,
    tl: ?[*]Word = null,
    tag: ?[*]word.NodeTag = null,
    SPACE: Word = 1250000,
    /// Whether cell `x - ATOMLIMIT` is currently allocated (B3: the tracing
    /// GC's precise liveness bitmap, replacing the old sign-bit-on-the-tag-
    /// byte trick). Sized to cover the full `[ATOMLIMIT, BIGTOP)` range once,
    /// in `setupheap` — `self.SPACE` only ever changes which prefix of that
    /// range `make`/`gc` currently treat as in play.
    live: std.DynamicBitSetUnmanaged = .{},
    /// Head of the free list, threaded through free cells' own `tl` field
    /// (`0` — never a valid cell index, since cells start at `ATOMLIMIT` —
    /// is the "no free cells" sentinel). `make` pops from it in O(1); `gc`
    /// rebuilds it from `live` after marking.
    free_head: Word = 0,
    allocated_dstack_size: usize = 0,

    // Heap/GC/dictionary scratch absorbed from module-level globals
    // (shared-state plan Phase 2b) so the full heap state lives in one struct
    // and `interp.reset()` covers it. Accessed as `heap.<field>` (the singleton).
    files: Word = word.NIL,
    current_file: Word = word.NIL,
    cellcount: i64 = 0,
    claims: c_long = 0,
    nogcs: c_long = 0,
    hnogcs: c_long = 0,
    dstack: ?[*]Word = null,
    stackp: ?[*]Word = null,
    collecting: c_int = 0,
    dlim: ?[*]Word = null,
    prefix: [word.pnlim]u8 = undefined,
    preflen: Word = 0,
    PNBASE: Word = 0,
    CFN: ?[*:0]const u8 = null,
    charname_buffer: [8]u8 = undefined,

    /// Refresh the cached column pointers after `cells` is (re)allocated.
    fn refreshPointers(self: *Heap) void {
        self.hd = self.cells.items(.hd).ptr;
        self.tl = self.cells.items(.tl).ptr;
        self.tag = self.cells.items(.tag).ptr;
    }

    /// Head (`hd`) of cell `x` without atom checks.
    pub inline fn hCell(self: Heap, x: Word) Word {
        return self.hd.?[@as(usize, @intCast(x))];
    }

    /// Head (`hd`) of cell `x`.
    pub fn h(self: Heap, x: Word) Word {
        if (word.isAtom(x)) return 0;
        return self.hd.?[@as(usize, @intCast(x))];
    }

    /// Pointer to the head field of cell `x` (for in-place mutation).
    pub fn hp(self: Heap, x: Word) *Word {
        std.debug.assert(x >= ATOMLIMIT);
        return &self.hd.?[@as(usize, @intCast(x))];
    }

    /// Tail (`tl`) of cell `x` without atom checks.
    pub inline fn tCell(self: Heap, x: Word) Word {
        return self.tl.?[@as(usize, @intCast(x))];
    }

    /// Tail (`tl`) of cell `x`.
    pub fn t(self: Heap, x: Word) Word {
        if (word.isAtom(x)) return 0;
        return self.tl.?[@as(usize, @intCast(x))];
    }

    /// Pointer to the tail field of cell `x` (for in-place mutation).
    pub fn tp(self: Heap, x: Word) *Word {
        std.debug.assert(x >= ATOMLIMIT);
        return &self.tl.?[@as(usize, @intCast(x))];
    }

    /// The node tag of cell `x`.
    pub fn getTag(self: Heap, x: Word) word.NodeTag {
        return self.tag.?[@intCast(x)];
    }

    /// Set the node tag of cell `x`.
    pub fn setTag(self: *Heap, x: Word, val: word.NodeTag) void {
        self.tag.?[@intCast(x)] = val;
    }

    /// Allocate a `CONS` cell `(x . y)`.
    pub fn cons(self: *Heap, x: Word, y: Word) Word {
        return self.make(.CONS, x, y);
    }

    /// The current heap top — the next free cell index.
    pub fn TOP(self: Heap) Word {
        return self.SPACE + ATOMLIMIT;
    }

    /// The high-water heap limit.
    pub fn BIGTOP(self: Heap) Word {
        _ = self;
        return rt.rs.SPACELIMIT + ATOMLIMIT;
    }

    /// The usable heap size, in cells.
    pub fn trueheapsize(self: Heap) Word {
        // Before the first-ever gc, nothing has been freed, so every claim is
        // still live -- matches what the old bump-pointer `listp` tracked.
        return if (heap.nogcs == 0) heap.claims else self.SPACE;
    }

    /// Thread cells `[from, to)` onto the front of the free list. Does not
    /// touch `live` — callers own that (freshly `resize`d bits already read
    /// `false`; `gc`'s sweep clears them explicitly before re-threading).
    fn threadFree(self: *Heap, from: Word, to: Word) void {
        var i = to;
        while (i > from) {
            i -= 1;
            self.tp(i).* = self.free_head;
            self.free_head = i;
        }
    }

    /// Allocate and initialise the heap arena.
    pub fn setupheap(self: *Heap) void {
        const bigtop_val = @as(usize, @intCast(self.BIGTOP()));
        if (self.cells.len == 0) {
            // First-time allocation: rows [0, BIGTOP]; zero the whole tag column.
            self.cells.resize(rt.allocator, bigtop_val + 1) catch mallocPanic("heap");
            self.refreshPointers();
            @memset(self.tag.?[0 .. bigtop_val + 1], .ATOM);
            // Sized once, to the full [ATOMLIMIT, BIGTOP) range -- SPACE only
            // ever changes which prefix of it `make`/`gc` currently use.
            self.live.resize(rt.allocator, bigtop_val + 1 - @as(usize, @intCast(ATOMLIMIT)), false) catch mallocPanic("heap");
        }
        self.refreshPointers();
        if (self.SPACE > rt.rs.SPACELIMIT) {
            self.SPACE = rt.rs.SPACELIMIT;
        }
        self.free_head = 0;
        self.threadFree(ATOMLIMIT, self.TOP());
    }

    /// Reset the heap to empty (between sessions).
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
        self.live.resize(rt.allocator, bigtop_val + 1 - @as(usize, @intCast(ATOMLIMIT)), false) catch mallocPanic("heap");
        self.live.setRangeValue(.{ .start = 0, .end = @intCast(self.SPACE) }, false);
        self.free_head = 0;
        self.threadFree(ATOMLIMIT, self.TOP());
    }

    pub fn makeSlow(self: *Heap, t_val: word.NodeTag, x: Word, y: Word) Word {
        if (self.SPACE != rt.rs.SPACELIMIT) {
            const old_top = self.TOP();
            if (core.s.compiling == 0) {
                self.SPACE = rt.rs.SPACELIMIT;
            } else if (heap.claims <= @divTrunc(self.SPACE, 4) and heap.nogcs > 1) {
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
            const new_top = self.TOP();
            if (new_top > old_top) {
                self.threadFree(old_top, new_top);
            }
        }
        if (self.free_head == 0) {
            self.gc();
            if (@intFromEnum(t_val) > @intFromEnum(word.NodeTag.STRCONS)) {
                self.mark(x);
            }
            if (@intFromEnum(t_val) >= @intFromEnum(word.NodeTag.INT)) {
                self.mark(y);
            }
            return self.make(t_val, x, y);
        }
        return self.make(t_val, x, y);
    }

    /// Allocate a cell with tag `t_val` and fields `(x, y)` — the core allocator.
    pub inline fn make(self: *Heap, t_val: word.NodeTag, x: Word, y: Word) Word {
        if (self.free_head == 0) {
            return self.makeSlow(t_val, x, y);
        }
        heap.claims += 1;
        const cell = self.free_head;
        const idx: usize = @intCast(cell);
        self.free_head = self.tl.?[idx];
        self.live.set(idx - ATOMLIMIT);
        self.tag.?[idx] = t_val;
        self.hd.?[idx] = x;
        self.tl.?[idx] = y;
        return cell;
    }

    /// Allocate two cells in bulk.
    pub inline fn makeTwo(self: *Heap, t1: word.NodeTag, x1: Word, y1: Word, t2: word.NodeTag, x2: Word, y2: Word, c1: *Word, c2: *Word) void {
        if (self.free_head == 0 or self.tl.?[@as(usize, @intCast(self.free_head))] == 0) {
            c1.* = self.makeSlow(t1, x1, y1);
            c2.* = self.make(t2, x2, y2);
            return;
        }
        const cell1 = self.free_head;
        const idx1: usize = @intCast(cell1);
        const cell2 = self.tl.?[idx1];
        const idx2: usize = @intCast(cell2);
        self.free_head = self.tl.?[idx2];
        
        heap.claims += 2;
        self.live.set(idx1 - ATOMLIMIT);
        self.live.set(idx2 - ATOMLIMIT);
        
        self.tag.?[idx1] = t1;
        self.hd.?[idx1] = x1;
        self.tl.?[idx1] = y1;
        
        self.tag.?[idx2] = t2;
        self.hd.?[idx2] = x2;
        self.tl.?[idx2] = y2;
        
        c1.* = cell1;
        c2.* = cell2;
    }
    fn growHeap(self: *Heap) bool {
        const old_bigtop = @as(usize, @intCast(self.BIGTOP()));
        const old_limit = rt.rs.SPACELIMIT;
        const new_limit = old_limit * 2;
        rt.rs.SPACELIMIT = new_limit;
        const new_bigtop = @as(usize, @intCast(self.BIGTOP()));

        self.cells.resize(rt.allocator, new_bigtop + 1) catch return false;
        self.refreshPointers();

        @memset(self.tag.?[old_bigtop .. new_bigtop + 1], .ATOM);

        self.live.resize(rt.allocator, new_bigtop + 1 - @as(usize, @intCast(ATOMLIMIT)), false) catch return false;

        self.SPACE = new_limit;

        _ = word.printErr("\n<<increase heap maximum from {d} to {d} cells>>\n", .{ old_limit, new_limit });
        return true;
    }

    /// Run a precise mark-sweep garbage collection: clear `live`, mark every
    /// cell reachable from a root (see `bases`/`mark`), then rebuild the free
    /// list from whatever's left unmarked (garbage, or already free).
    pub fn gc(self: *Heap) void {
        heap.collecting = 1;
        if (rt.rs.atgc != 0) {
            _ = word.printErr("\n<<gc after {d} claims>>\n", .{heap.claims});
        }
        if (heap.claims <= @divTrunc(self.SPACE, 10) and heap.nogcs > 1 and self.SPACE == rt.rs.SPACELIMIT) {
            if (heap.nogcs == self.hnogcs) {
                if (self.growHeap()) {
                    self.hnogcs = 0;
                } else {
                    _ = word.printErr("<<not enough heap space -- task abandoned>>\n", .{});
                    if (core.s.compiling == 0) {
                        outstats();
                    }
                    if (core.s.compiling != 0 and rt.rs.ideep == 0) {
                        _ = word.printErr("not enough heap to compile current script\n", .{});
                        _ = word.printErr("script = \"{s}\", heap = {d}\n", .{ rt.rs.current_script orelse @as([*:0]const u8, "(null)"), self.SPACE });
                    }
                    main_clib.exit(1);
                }
            } else {
                self.hnogcs = heap.nogcs + 1;
            }
        }
        heap.nogcs += 1;

        self.live.setRangeValue(.{ .start = 0, .end = @intCast(self.SPACE) }, false);
        self.bases();

        self.free_head = 0;
        const num_bits = self.TOP() - ATOMLIMIT;
        if (num_bits > 0) {
            const MaskInt = usize;
            const bit_size = @bitSizeOf(MaskInt);
            var mask_idx = @divTrunc(num_bits - 1, bit_size);
            while (true) {
                var mask = self.live.masks[@intCast(mask_idx)];
                if (mask_idx == @divTrunc(num_bits - 1, bit_size)) {
                    const active_bits = num_bits - mask_idx * bit_size;
                    if (active_bits < bit_size) {
                        mask |= (~@as(MaskInt, 0)) << @as(u6, @intCast(active_bits));
                    }
                }

                if (mask == ~@as(MaskInt, 0)) {
                    // All cells in this block are live. Skip.
                } else if (mask == 0) {
                    // All cells in this block are garbage. Thread them sequentially.
                    var cell_idx = (mask_idx * bit_size) + ATOMLIMIT;
                    const end_cell_idx = cell_idx + bit_size;
                    while (cell_idx < end_cell_idx) : (cell_idx += 1) {
                        self.tl.?[@intCast(cell_idx)] = self.free_head;
                        self.free_head = @intCast(cell_idx);
                    }
                } else {
                    // Mixed block. Loop from highest to lowest index to preserve order.
                    var bit_idx: i32 = bit_size - 1;
                    var cell_idx = (mask_idx * bit_size) + ATOMLIMIT + (bit_size - 1);
                    while (bit_idx >= 0) : ({ bit_idx -= 1; cell_idx -= 1; }) {
                        const is_live = (mask & (@as(MaskInt, 1) << @as(u6, @intCast(bit_idx)))) != 0;
                        if (!is_live) {
                            self.tl.?[@intCast(cell_idx)] = self.free_head;
                            self.free_head = @intCast(cell_idx);
                        }
                    }
                }

                if (mask_idx == 0) break;
                mask_idx -= 1;
            }
        }

        heap.cellcount += heap.claims;
        heap.claims = 0;
        heap.collecting = 0;
        const options = @import("version_options");
        if (options.is_strict or @import("builtin").mode == .Debug) {
            self.validate();
        }
    }

    /// Mark the GC roots: the live Words on the C stack and in registers.
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

        self.mark(reduce.ev.outfilq);
        self.mark(reduce.ev.waiting);
        if (core.s.compiling != 0 or rt.rs.rv_expr != 0 or cs.rv_script != 0) {
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
            self.mark(heap.files);
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
            const p_dstack = heap.dstack;
            const p_stackp = heap.stackp;
            if (p_dstack != null and p_stackp != null) {
                var curr = p_dstack.?;
                const end = p_stackp.?;
                while (@intFromPtr(curr) < @intFromPtr(end)) : (curr += 1) {
                    self.mark(curr[0]);
                }
            }
            if (core.s.loading != 0) {
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
            self.mark(core.s.nill);
            self.mark(rt.rs.standardout);
            self.mark(big.bn.big_one);
            self.mark(big.bn.b_rem);
            self.mark(ls.yylval);
            self.mark(ls.echostack);
            self.mark(core.s.errs);

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

        // Every currently-registered Spine's frames (see reducer/spine.zig):
        // an explicit spine's frame buffer is a separate heap allocation, not
        // a Word sitting on the C stack the scan above already covers, and
        // not reachable through any cell's hd/tl the way the old in-graph
        // pointer-reversal encoding was -- so it needs its own root pass.
        @import("reducer/spine.zig").markAllRoots(markRoot);
    }

    /// Whether `x` is a heap-cell pointer (rather than an atom/immediate).
    pub fn isptr(self: Heap, x: Word) bool {
        return x >= ATOMLIMIT and x < self.TOP();
    }

    /// Recursively mark cell `x` and its descendants as reachable (GC), by
    /// setting their bit in `live`. Iterates down `tl` chains rather than
    /// recursing (recursing on both `hd` and `tl` would stack-overflow
    /// marking a long lazy list spine); still recurses into `hd`, assumed
    /// shallower. `live.isSet` doubles as the "already visited" cycle guard
    /// pointer-reversal used to get from the tag's sign bit.
    pub fn mark(self: *Heap, x_val: Word) void {
        var x = x_val;
        while (self.isptr(x) and !self.live.isSet(@intCast(x - ATOMLIMIT))) {
            self.live.set(@intCast(x - ATOMLIMIT));
            const tag_val = @intFromEnum(self.tag.?[@intCast(x)]);
            if (tag_val > @intFromEnum(word.NodeTag.STRCONS)) {
                self.mark(self.h(x));
            }
            if (tag_val >= @intFromEnum(word.NodeTag.INT)) {
                x = self.t(x);
            } else {
                break;
            }
        }
    }

    /// Validate heap structure and invariants in Debug/Strict mode.
    pub fn validate(self: *Heap) void {
        const options = @import("version_options");
        if (@import("builtin").mode != .Debug and !options.is_strict) return;

        var x: Word = ATOMLIMIT;
        const top_limit = self.TOP();
        while (x < top_limit) : (x += 1) {
            if (!self.live.isSet(@intCast(x - ATOMLIMIT))) continue; // Free cell.

            // No "is this a valid tag" check needed anymore: NodeTag is fully
            // exhaustive (B3), so `self.tag.?[x]` can never hold anything else.
            const tag = self.tag.?[@intCast(x)];
            const tag_val = @intFromEnum(tag);

            if (tag_val > @intFromEnum(word.NodeTag.STRCONS)) {
                const hd_val = self.hd.?[@intCast(x)];
                if (hd_val >= ATOMLIMIT) {
                    if (hd_val >= top_limit) {
                        std.debug.panic("heap.validate: cell {d} (tag {s}) has out-of-bounds hd reference {d} (TOP is {d})", .{ x, @tagName(tag), hd_val, top_limit });
                    }
                }
            }
            if (tag_val >= @intFromEnum(word.NodeTag.INT)) {
                const tl_val = self.tl.?[@intCast(x)];
                if (tl_val >= ATOMLIMIT) {
                    if (tl_val >= top_limit) {
                        std.debug.panic("heap.validate: cell {d} (tag {s}) has out-of-bounds tl reference {d} (TOP is {d})", .{ x, @tagName(tag), tl_val, top_limit });
                    }
                }
            }

            // Utilize domain-specific wrappers where appropriate
            if (tag == .ID) {
                const ident = Identifier{ .word = x };
                const t_val = ident.typ();
                if (t_val >= ATOMLIMIT and t_val >= top_limit) {
                    std.debug.panic("heap.validate: Identifier {d} has invalid type reference {d}", .{ x, t_val });
                }
            }
        }
    }
};

/// Pointer to the singleton [Heap] inside `interp` (so `interp.reset()` clears
/// it). The free functions below operate on it; call sites use `heap.X`.
pub const heap = &@import("interp.zig").interp.heap;

/// Head (`hd`) of cell `x`.
///
/// Tests: heap accessors: cons/make build cells that h/t/getTag read back
pub fn h(x: Word) Word {
    return heap.h(x);
}

/// Pointer to the head field of cell `x` (for in-place mutation).
pub fn hp(x: Word) *Word {
    return heap.hp(x);
}

/// Tail (`tl`) of cell `x`.
pub fn t(x: Word) Word {
    return heap.t(x);
}

/// Pointer to the tail field of cell `x` (for in-place mutation).
pub fn tp(x: Word) *Word {
    return heap.tp(x);
}

/// Mark `x` reachable (GC). A free-function adapter to the singleton's
/// method, matching `mark`'s signature to what `reducer/spine.zig`'s
/// `markAllRoots` expects (a plain `fn (Word) void`, no bound receiver) —
/// see `Heap.bases`, the only caller.
fn markRoot(x: Word) void {
    heap.mark(x);
}

/// The node tag of cell `x`.
pub fn getTag(x: Word) word.NodeTag {
    return heap.getTag(x);
}

/// Allocate a `CONS` cell `(x . y)`.
///
/// Tests: heap accessors: cons/make build cells that h/t/getTag read back
pub fn cons(x: Word, y: Word) Word {
    return heap.cons(x, y);
}

test "heap accessors: cons/make build cells that h/t/getTag read back" {
    tu.freshInterp();
    const c = cons(word.True, word.NIL);
    try std.testing.expectEqual(word.NodeTag.CONS, getTag(c));
    try std.testing.expectEqual(@as(Word, word.True), h(c));
    try std.testing.expectEqual(@as(Word, word.NIL), t(c));
    // hp/tp expose the fields for in-place mutation.
    hp(c).* = word.False;
    tp(c).* = word.True;
    try std.testing.expectEqual(@as(Word, word.False), h(c));
    try std.testing.expectEqual(@as(Word, word.True), t(c));
    // make builds a cell with an arbitrary tag; setTag (on the singleton) rewrites it.
    const apnode = make(.AP, word.I, word.NIL);
    try std.testing.expectEqual(word.NodeTag.AP, getTag(apnode));
    heap.setTag(apnode, .CONS);
    try std.testing.expectEqual(word.NodeTag.CONS, getTag(apnode));
}

test "gc: a long-lived list survives many forced collections; garbage is reclaimed" {
    tu.freshInterp();

    // `bases()`'s conservative stack scan needs `rt.rs.cstack` as its "bottom
    // of the interesting range" boundary -- normally set once by
    // `startup.mainEntry` (real runs only). Unit tests never go through
    // that, so it's `null` here; take the address of a local, matching what
    // `mainEntry` does with its own `manonly`, so a real `gc()` cycle
    // (this test's whole point) doesn't crash finding it unset.
    var stack_anchor: Word = 0;
    const saved_cstack = rt.rs.cstack;
    rt.rs.cstack = @ptrCast(&stack_anchor);

    // Shrink the heap so allocating the workload below forces `gc()` to run
    // many times (B3's own DoD: "GC stress test stable"), then restore it --
    // `tu.freshInterp()` only sets up once per test binary, so a later test
    // must see the original size, not this one's.
    const saved_spacelimit = rt.rs.SPACELIMIT;
    const saved_space = heap.SPACE;
    defer {
        rt.rs.SPACELIMIT = saved_spacelimit;
        heap.SPACE = saved_space;
        heap.resetheap();
        rt.rs.cstack = saved_cstack;
    }
    // Set the small heap size once, *before* any allocation in this test.
    // `resetheap()` unconditionally rebuilds the free list over the entire
    // range -- calling it again mid-test, after the chain below is alive,
    // would discard the chain along with everything else (it has no way to
    // tell "still reachable" from "free"; that is `gc()`'s job, not
    // `resetheap()`'s). One resetheap, sized to comfortably hold the chain
    // (4x) while still being small enough that the churn phase below forces
    // many real collections.
    const chain_len = 500;
    rt.rs.SPACELIMIT = chain_len * 4;
    heap.resetheap();

    // A long-lived chain, kept alive only by this local `Word` (matching how
    // real roots are found: the conservative stack scan in `bases()`, not any
    // special-cased "test root" mechanism) -- if `mark`/`gc` ever lose track
    // of part of it, or if the `Spine`/GC-root registry from the B2(b) cutover
    // somehow interfered, this is exactly the kind of workload that would
    // show it: every collection below must re-discover the *entire* chain as
    // reachable, every time.
    // Store `i % 100` rather than `i` itself: `i` alone climbs past
    // `ATOMLIMIT` (447) well before `chain_len` (500), and a raw integer
    // that large stored as `hd` reads -- to `validate()`'s heuristic, which
    // cannot distinguish "a plain integer that happens to be large" from "a
    // cell reference" any other way -- exactly like an out-of-bounds pointer
    // once the heap is this small. Not a GC bug; a property of this
    // representation (the same ambiguity B2/B3's audits already flagged).
    var chain: Word = word.NIL;
    var i: Word = 0;
    while (i < chain_len) : (i += 1) {
        chain = heap.cons(@mod(i, 100), chain);
    }

    // Churn short-lived garbage through the (now mostly-full) heap: this
    // forces many `gc()` cycles, each of which must re-mark the whole chain
    // (constant O(chain_len) cost per cycle, not growing as the churn count
    // grows) while reclaiming the garbage around it. `0`/`0`, not `churn`,
    // for the same reason as above -- the churn count climbs into the
    // thousands.
    const nogcs_before = heap.nogcs;
    var churn: Word = 0;
    while (churn < chain_len * 30) : (churn += 1) {
        _ = heap.cons(0, 0);
    }

    try std.testing.expect(heap.nogcs > nogcs_before);

    // Walk the whole chain back: every value must still be exactly what was
    // stored, in the same order (built as (chain_len-1)%100, ..., 1%100, 0%100).
    var w = chain;
    var expected: Word = chain_len - 1;
    while (w != word.NIL) {
        try std.testing.expectEqual(word.NodeTag.CONS, getTag(w));
        try std.testing.expectEqual(@mod(expected, 100), h(w));
        w = t(w);
        expected -= 1;
    }
    try std.testing.expectEqual(@as(Word, -1), expected);
}

/// Allocate a `TRIES` cell `(x . y)` (a pattern-match alternative chain).
///
/// Tests: tries: builds a TRIES alternative-chain cell
///
/// Tests: tries: builds a TRIES alternative-chain cell
pub fn tries(x: Word, y: Word) Word {
    return make(.TRIES, x, y);
}

test "tries: builds a TRIES alternative-chain cell" {
    tu.freshInterp();
    const tr = tries(word.True, word.NIL);
    try std.testing.expectEqual(word.NodeTag.TRIES, getTag(tr));
    try std.testing.expectEqual(@as(Word, word.True), h(tr));
    try std.testing.expectEqual(@as(Word, word.NIL), t(tr));
}

/// The 'who' (definition-site) field of id `x`.
pub fn idWho(x: Word) Word {
    return t(h(h(x)));
}

/// The interned name text of id `x`.
pub fn getId(x: Word) [*:0]const u8 {
    return strtab.strOf(strtab.table, h(h(h(x))));
}

/// The filename of file-record `fil`, or null when absent.
///
/// The single file-name accessor: callers that want the empty string for an absent
/// name use `getFil(fil) orelse ""` (matches `strtab.strOf(strtab.table, 0)`).
pub fn getFil(fil: Word) ?[*:0]const u8 {
    const val = h(h(h(fil)));
    if (val == 0) return null;
    return strtab.strOf(strtab.table, val);
}

/// Box char `ch`: bare Latin-1, or a `UNICODE` cell for wider code points.
///
/// Tests: stoChar / getChar / isChar: bare Latin-1 and wide UNICODE chars
pub fn stoChar(ch: Word) Word {
    return if (word.fitsInByte(ch)) ch else make(.UNICODE, ch, 0);
}

/// The code point of char value `x`.
///
/// Tests: stoChar / getChar / isChar: bare Latin-1 and wide UNICODE chars
pub fn getChar(x: Word) Word {
    switch (word.classify(x)) {
        .imm => |c| return c, // bare Latin-1 code point
        .ref => if (getTag(x) == .UNICODE) return h(x), // UNICODE cell: code point in hd
        .atom => {},
    }
    std.debug.print("impossible event in getChar(x), tag[x]=={d}\n", .{heap.getTag(x)});
    main_clib.exit(1);
}

/// Whether `x` is a char value (1/0).
///
/// Tests: stoChar / getChar / isChar: bare Latin-1 and wide UNICODE chars
pub fn isChar(x: Word) bool {
    return switch (word.classify(x)) {
        .imm => true, // bare Latin-1 char
        .ref => getTag(x) == .UNICODE, // wide char cell
        .atom => false, // a combinator/named atom is not a char
    };
}

test "stoChar / getChar / isChar: bare Latin-1 and wide UNICODE chars" {
    tu.freshInterp();
    // Latin-1: stored bare as the code point itself.
    try std.testing.expectEqual(@as(Word, 65), stoChar(65));
    try std.testing.expect(isChar(65));
    try std.testing.expectEqual(@as(Word, 65), getChar(65));
    // Wide: boxed in a UNICODE cell, but still a char that decodes back.
    const emoji = stoChar(0x1F600);
    try std.testing.expectEqual(word.NodeTag.UNICODE, getTag(emoji));
    try std.testing.expect(isChar(emoji));
    try std.testing.expectEqual(@as(Word, 0x1F600), getChar(emoji));
    // A combinator atom is not a char.
    try std.testing.expect(!isChar(word.S));
}

/// The source location (`HERE`) recorded for id `x`.
pub fn getHere(x: Word) Word {
    const y = idWho(x);
    return if (getTag(y) == .CONS) t(y) else y;
}

/// The original ('also known as') name of id `x` (before any alias).
pub fn getaka(x: Word) [*:0]const u8 {
    const y = idWho(x);
    return if (getTag(y) != .CONS) getId(x) else strtab.strOf(strtab.table, h(h(y)));
}

/// Append a single element to the end of list `x`.
///
/// Tests: append1: links y onto the tail of list x
pub fn append1(x: Word, y: Word) Word {
    var x1 = x;
    if (x1 == nil()) return y;
    while (t(x1) != nil()) x1 = t(x1);
    tp(x1).* = y;
    return x;
}

test "append1: links y onto the tail of list x" {
    tu.freshInterp();
    // [True] with [False] linked on → True : False : NIL
    const x = cons(word.True, word.NIL);
    const y = cons(word.False, word.NIL);
    const r = append1(x, y);
    try std.testing.expectEqual(x, r); // mutates and returns x
    try std.testing.expectEqual(@as(Word, word.True), h(r));
    try std.testing.expectEqual(@as(Word, word.False), h(t(r)));
    try std.testing.expectEqual(@as(Word, word.NIL), t(t(r)));
    // appending onto nil just yields y
    try std.testing.expectEqual(y, append1(word.NIL, y));
}

/// Sort list `input` by cell head (merge sort).
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

/// A printable name/escape for char `ch`.
///
/// Tests: charname: escapes control chars, passes printables through
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
                const text = std.fmt.bufPrintSentinel(&heap.charname_buffer, "\\{d}", .{ch}, 0) catch unreachable;
                break :blk text.ptr;
            }
            heap.charname_buffer[0] = @intCast(ch);
            heap.charname_buffer[1] = 0;
            break :blk @as([*:0]const u8, @ptrCast(heap.charname_buffer[0..].ptr));
        },
    };
}

test "charname: escapes control chars, passes printables through" {
    tu.freshInterp();
    try std.testing.expectEqualStrings("\\n", std.mem.span(charname('\n')));
    try std.testing.expectEqualStrings("\\t", std.mem.span(charname('\t')));
    try std.testing.expectEqualStrings("\\\\", std.mem.span(charname('\\')));
    try std.testing.expectEqualStrings("A", std.mem.span(charname('A')));
    try std.testing.expectEqualStrings("\\7", std.mem.span(charname(7))); // bell → \7
}

/// Print double `value` to `file`.
pub fn outReal(file: ?*word.FILE, value: f64) void {
    const magnitude = if (value < 0) -value else value;
    if (magnitude >= 1000.0 or magnitude <= 0.001) {
        _ = word.fprint(file, "{d}", .{value});
    } else {
        _ = word.fprint(file, "{d}", .{value});
    }
}

/// The `f64` stored in `DOUBLE` cell `x`.
///
/// Tests: stoDbl / getDbl / setdbl: round-trip an f64 in a DOUBLE cell
pub fn getDbl(x: Word) f64 {
    var r: fpdatum = undefined;
    if (comptime @sizeOf(Word) == 4) {
        r.bits.left = h(x);
        r.bits.right = t(x);
    } else {
        r.bits = h(x);
    }
    return r.real;
}

/// Box `f64` `R_val` in a `DOUBLE` cell.
///
/// Tests: stoDbl / getDbl / setdbl: round-trip an f64 in a DOUBLE cell
pub fn stoDbl(R_val: f64) Word {
    if (!std.math.isFinite(R_val)) {
        fpeError(main_clib.SIGFPE);
    }
    var r: fpdatum = undefined;
    r.real = R_val;
    if (comptime @sizeOf(Word) == 4) {
        return make(.DOUBLE, r.bits.left, r.bits.right);
    } else {
        return make(.DOUBLE, r.bits, 0);
    }
}

/// Overwrite the `f64` in `DOUBLE` cell `x`.
///
/// Tests: stoDbl / getDbl / setdbl: round-trip an f64 in a DOUBLE cell
pub fn setdbl(x: Word, R_val: f64) void {
    if (!std.math.isFinite(R_val)) {
        fpeError(main_clib.SIGFPE);
    }
    var r: fpdatum = undefined;
    r.real = R_val;
    heap.setTag(x, .DOUBLE);
    if (comptime @sizeOf(Word) == 4) {
        hp(x).* = r.bits.left;
        tp(x).* = r.bits.right;
    } else {
        hp(x).* = r.bits;
        tp(x).* = 0;
    }
}

test "stoDbl / getDbl / setdbl: round-trip an f64 in a DOUBLE cell" {
    tu.freshInterp();
    const d = stoDbl(3.14);
    try std.testing.expectEqual(word.NodeTag.DOUBLE, getTag(d));
    try std.testing.expectEqual(@as(f64, 3.14), getDbl(d));
    setdbl(d, -2.5);
    try std.testing.expectEqual(@as(f64, -2.5), getDbl(d));
}

/// The `NIL` sentinel.
fn nil() Word {
    return 306 + 138;
}

// (Dead module duplicates of `Heap.SPACE`/`Heap.listp` removed — the live
// copies are the struct fields, accessed via `self.SPACE`/`self.listp`.)

const outstats = reduce.outstats;
const initclock = reduce.initclock;
const hashsize = word.hashsize;

/// The current heap top — the next free cell index.
fn TOP() Word {
    return heap.TOP();
}

/// The high-water heap limit.
/// The usable heap size, in cells.
pub fn trueheapsize() Word {
    return heap.trueheapsize();
}

/// Allocate and initialise the heap arena.
pub fn setupheap() void {
    heap.setupheap();
}

/// Reset the heap to empty (between sessions).
pub fn resetheap() void {
    heap.resetheap();
}

/// Report (non-fatally) a failed allocation for `x`.
pub fn mallocfail(x: [*:0]const u8) void {
    _ = word.printErr("panic: cannot find enough free space for {s}\n", .{x});
    main_clib.exit(1);
}

/// Panic and abort: outTerm of memory allocating `what`.
pub fn mallocPanic(what: [*:0]const u8) noreturn {
    mallocfail(what);
    unreachable;
}

/// Reset the per-evaluation GC counters.
pub fn resetgcstats() void {
    heap.cellcount = -heap.claims;
    heap.nogcs = 0;
    heap.hnogcs = 0;
    initclock();
}

/// Head (`hd`) of cell `x` without atom checks.
pub inline fn hCell(x: Word) Word {
    return heap.hCell(x);
}

/// Tail (`tl`) of cell `x` without atom checks.
pub inline fn tCell(x: Word) Word {
    return heap.tCell(x);
}

/// Allocate a cell with tag `t_val` and fields `(x, y)` — the core allocator.
pub inline fn make(t_val: word.NodeTag, x: Word, y: Word) Word {
    return heap.make(t_val, x, y);
}

/// Allocate two cells in bulk.
pub inline fn makeTwo(t1: word.NodeTag, x1: Word, y1: Word, t2: word.NodeTag, x2: Word, y2: Word, c1: *Word, c2: *Word) void {
    heap.makeTwo(t1, x1, y1, t2, x2, y2, c1, c2);
}

/// Run a mark-sweep garbage collection.
pub fn gc() void {
    heap.gc();
}

/// The standard-error `FILE` handle (tolerating either a fn or value form).
const fileMtime = files.fileMtime;
const unlinkObject = files.unlinkObject;
/// Intern name `p1`, returning its dictionary `ID` node (inserting if new).
pub fn stoId(p1: [*:0]const u8) Word {
    return make(.ID, cons(make(.STRCONS, strtab.strBits(strtab.table, p1), word.NIL), word.undef_t), word.UNDEF);
}

/// Read a size-prefixed tagged `Word` from dump `file`.
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

/// Write a size-prefixed tagged `Word` to dump `file`.
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

/// Set the path prefix used to relativise dumped file names.
pub fn setprefix(p: [*:0]const u8) void {
    const p_len = std.mem.len(p);
    if (p_len >= heap.prefix.len) {
        mallocfail("prefix buffer overflow");
    }
    @memcpy(heap.prefix[0..p_len], p[0..p_len]);
    heap.prefix[p_len] = 0;

    var last_slash: ?usize = null;
    var i: usize = p_len;
    while (i > 0) {
        i -= 1;
        if (heap.prefix[i] == '/') {
            last_slash = i;
            break;
        }
    }
    if (last_slash) |idx| {
        heap.prefix[idx + 1] = 0;
        heap.preflen = @intCast(idx + 1);
    } else {
        heap.prefix[0] = 0;
        heap.preflen = 0;
    }
}

/// Rewrite path `p` relative to the dump prefix.
pub fn mkrel(p: [*:0]const u8) [*:0]const u8 {
    const p_len = std.mem.len(p);
    const prefix_len = @as(usize, @intCast(heap.preflen));
    if (prefix_len <= p_len and std.mem.eql(u8, heap.prefix[0..prefix_len], p[0..prefix_len])) {
        return @ptrCast(p + prefix_len);
    }
    if (p[0] == '/') {
        return p;
    }
    _ = word.printErr("impossible event in mkrelative\n", .{.{}});
    return p;
}

/// Whether the object file for `t_ptr` exists and is up to date.
pub fn okdump(t_ptr: [*:0]const u8) bool {
    var obf: [120]u8 = undefined;
    const t_len = std.mem.len(t_ptr);
    if (t_len >= obf.len) {
        return false;
    }
    @memcpy(obf[0..t_len], t_ptr[0..t_len]);
    obf[t_len] = 0;

    const suffix_str = std.mem.span(core.s.obsuffix);
    const suffix_len = suffix_str.len;
    if (t_len + suffix_len - 1 >= obf.len) {
        return false;
    }
    @memcpy(obf[t_len - 1 .. t_len - 1 + suffix_len], suffix_str.ptr);
    obf[t_len - 1 + suffix_len] = 0;

    const f = word.fopen(&obf, "r") orelse return false;
    defer _ = word.fclose(f);

    const ch1 = main_clib.getc(f);
    const ch2 = main_clib.getc(f);
    if (ch1 == word.XVERSION and ch2 != 0) {
        return true;
    }
    return false;
}

/// The error line number recorded in a bad object file for `t_ptr`.
pub fn geterrlin(t_ptr: [*:0]const u8) Word {
    var obf: [120]u8 = undefined;
    const t_len = std.mem.len(t_ptr);
    if (t_len >= obf.len) {
        return 0;
    }
    @memcpy(obf[0..t_len], t_ptr[0..t_len]);
    obf[t_len] = 0;

    const suffix_str = std.mem.span(core.s.obsuffix);
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
        const prefix_len = @as(usize, @intCast(heap.preflen));
        @memcpy(ls.dicp[0..prefix_len], heap.prefix[0..prefix_len]);
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
    if (main_clib.strcmp(ls.dicp, t_ptr) != 0 or mtime != fileMtime(t_ptr)) {
        return 0; // wrong dump
    }

    return el;
}

const bigtostr = big.toDecimalList;
const SIGNBIT = 0x10000000;
const MAXDIGIT = 0x7fff;

/// The next digit cell of a bignum chain.
fn rest(x: Word) Word {
    return t(x);
}

/// The raw head digit of a bignum cell.
fn digit(x: Word) Word {
    return h(x);
}

/// The head digit of a bignum cell with the sign bit masked off.
fn digit0(x: Word) Word {
    return h(x) & MAXDIGIT;
}

/// Decode a single-cell bignum to a signed `Word`.
fn getsmallint(x: Word) Word {
    return if ((h(x) & SIGNBIT) != 0) -digit0(x) else digit(x);
}

/// Box small int `x`: bare, or as an `INT` cell if it doesn't fit.
///
/// Tests: stosmallint: boxes a signed small int as an INT cell
pub fn stosmallint(x: Word) Word {
    const val = if (x < 0) SIGNBIT | @as(Word, @intCast(-x)) else x;
    return make(.INT, val, 0);
}

test "stosmallint: boxes a signed small int as an INT cell" {
    tu.freshInterp();
    const a = stosmallint(42);
    try std.testing.expectEqual(word.NodeTag.INT, getTag(a));
    try std.testing.expectEqual(@as(Word, 42), getsmallint(a));
    try std.testing.expectEqual(@as(Word, -5), getsmallint(stosmallint(-5)));
}

/// The left-hand side (head) of a definition cell `d`.
///
/// Tests: dlhs / dval: definition-cell head and value accessors
pub inline fn dlhs(d: Word) Word {
    return h(d);
}

/// The value of a definition cell `d` (`t(t(d))`).
///
/// Tests: dlhs / dval: definition-cell head and value accessors
pub inline fn dval(d: Word) Word {
    return t(t(d));
}

test "dlhs / dval: definition-cell head and value accessors" {
    tu.freshInterp();
    // a def cell d = (lhs : (mid : val))
    const d = cons(word.True, cons(word.NIL, word.False));
    try std.testing.expectEqual(@as(Word, word.True), dlhs(d));
    try std.testing.expectEqual(@as(Word, word.False), dval(d));
}

/// Reinterpret Word `val` as a C-string pointer.
fn castPtr(val: Word) [*:0]const u8 {
    return strtab.strOf(strtab.table, val);
}

/// Print cell `x` to `file` in readable form (debug/diagnostic dump).
pub fn outTerm(file: ?*word.FILE, x_val: Word) void {
    var x = x_val;
    if (x < 0 or x > TOP()) {
        _ = word.fprint(file, "<{d}>", .{x});
        return;
    }
    if (getTag(x) == .LAMBDA) {
        _ = word.fprint(file, "$(", .{.{}});
        outTerm(file, h(x));
        _ = word.putc(')', file);
        outTerm(file, t(x));
    } else {
        while (getTag(x) == .CONS) {
            outSubterm(file, h(x));
            _ = word.putc(':', file);
            x = t(x);
        }
        outSubterm(file, x);
    }
}

/// Helper for `outTerm`: print one sub-term.
pub fn outSubterm(file: ?*word.FILE, x: Word) void {
    if (x < 0 or x > TOP()) {
        _ = word.fprint(file, "<{d}>", .{x});
        return;
    }
    if (getTag(x) == .AP) {
        outSubterm(file, h(x));
        _ = word.putc(' ', file);
        outAtom(file, t(x));
    } else {
        outAtom(file, x);
    }
}

/// Helper for `outTerm`: print one sub-term.
pub fn outAtom(file: ?*word.FILE, x_val: Word) void {
    var x = x_val;
    if (x < 0 or x > TOP()) {
        _ = word.fprint(file, "<{d}>", .{x});
        return;
    }
    const tag_val = getTag(x);
    if (tag_val == .INT) {
        if (rest(x) != 0) {
            x = bigtostr(heap, x);
            while (x != 0) {
                _ = word.putc(@intCast(h(x)), file);
                x = t(x);
            }
        } else {
            _ = word.fprint(file, "{d}", .{getsmallint(x)});
        }
        return;
    }
    if (tag_val == .DOUBLE) {
        outReal(file, getDbl(x));
        return;
    }
    if (tag_val == .ID) {
        _ = word.fprint(file, "{s}", .{getId(x)});
        return;
    }
    if (word.fitsInByte(x)) {
        _ = word.fprint(file, "'{s}'", .{charname(x)});
        return;
    }
    if (tag_val == .UNICODE) {
        _ = word.fprint(file, "'{x}'", .{h(x)});
        return;
    }
    if (tag_val == .ATOM) {
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
    if (tag_val == .TCONS or tag_val == .PAIR) {
        _ = word.fprint(file, "(", .{.{}});
        while (getTag(x) == .TCONS) {
            outTerm(file, h(x));
            _ = word.putc(',', file);
            x = t(x);
        }
        outTerm(file, h(x));
        _ = word.putc(',', file);
        outTerm(file, t(x));
        _ = word.putc(')', file);
        return;
    }
    if (tag_val == .TRIES) {
        _ = word.fprint(file, "TRIES(", .{.{}});
        outTerm(file, h(x));
        _ = word.putc(',', file);
        outTerm(file, t(x));
        _ = word.putc(')', file);
        return;
    }
    if (tag_val == .LABEL) {
        _ = word.fprint(file, "LABEL(", .{.{}});
        outTerm(file, h(x));
        _ = word.putc(',', file);
        outTerm(file, t(x));
        _ = word.putc(')', file);
        return;
    }
    if (tag_val == .SHOW) {
        _ = word.fprint(file, "SHOW(", .{.{}});
        outTerm(file, h(x));
        _ = word.putc(',', file);
        outTerm(file, t(x));
        _ = word.putc(')', file);
        return;
    }
    if (tag_val == .STARTREADVALS) {
        _ = word.fprint(file, "READVALS(", .{.{}});
        outTerm(file, h(x));
        _ = word.putc(',', file);
        outTerm(file, t(x));
        _ = word.putc(')', file);
        return;
    }
    if (tag_val == .LET) {
        _ = word.fprint(file, "(LET ", .{.{}});
        outTerm(file, dlhs(h(x)));
        _ = word.fprint(file, "=", .{.{}});
        outTerm(file, dval(h(x)));
        _ = word.fprint(file, ";IN ", .{.{}});
        outTerm(file, t(x));
        _ = word.fprint(file, ")", .{.{}});
        return;
    }
    if (tag_val == .LETREC) {
        const body = t(x);
        _ = word.fprint(file, "(LETREC ", .{.{}});
        x = h(x);
        while (x != word.NIL) {
            outTerm(file, dlhs(h(x)));
            _ = word.fprint(file, "=", .{.{}});
            outTerm(file, dval(h(x)));
            _ = word.fprint(file, ";", .{.{}});
            x = t(x);
        }
        _ = word.fprint(file, "IN ", .{.{}});
        outTerm(file, body);
        _ = word.fprint(file, ")", .{.{}});
        return;
    }
    if (tag_val == .DATAPAIR) {
        _ = word.fprint(file, "DATAPAIR({s},{d})", .{ castPtr(h(x)), t(x) });
        return;
    }
    if (tag_val == .FILEINFO) {
        _ = word.fprint(file, "FILEINFO({s},{d})", .{ castPtr(h(x)), t(x) });
        return;
    }
    if (tag_val == .CONSTRUCTOR) {
        _ = word.fprint(file, "CONSTRUCTOR({d})", .{h(x)});
        return;
    }
    if (tag_val == .STRCONS) {
        _ = word.fprint(file, "<${d}>", .{h(x)});
        return;
    }
    if (tag_val == .SHARE) {
        _ = word.fprint(file, "(SHARE:", .{.{}});
        outTerm(file, h(x));
        _ = word.fprint(file, ")", .{.{}});
        return;
    }
    if (tag_val != .CONS and tag_val != .AP and tag_val != .LAMBDA) {
        _ = word.fprint(file, "<{d}|tag={d}>", .{ x, @intFromEnum(tag_val) });
        return;
    }
    _ = word.putc(')', file);
}

const member = types.member;
const add1 = types.add1;
const name = lex.name;

/// The mtime stored in file record `fil`.
pub fn filTime(fil: Word) Word {
    return t(h(h(fil)));
}

/// The share/include flag of file record `fil`.
pub fn filShare(fil: Word) Word {
    return h(t(h(fil)));
}

/// The definitions list of file record `fil`.
pub fn filDefs(fil: Word) Word {
    return t(fil);
}

/// Build a file record `(name, mtime, share, defs)`.
pub fn makeFil(fil_name: ?[*:0]const u8, time_val: Word, share: Word, defs: Word) Word {
    const name_word = if (fil_name) |n| @as(Word, strtab.strBits(strtab.table, n)) else 0;
    return cons(cons(make(.FILEINFO, name_word, time_val), cons(share, word.NIL)), defs);
}

/// The head of private-name node `x`.
fn getPn(x: Word) Word {
    return h(x);
}

/// The value (tail) of private-name node `x`.
fn pnVal(x: Word) Word {
    return t(x);
}

/// The type field of id `x`.
pub fn idType(x: Word) Word {
    return t(h(x));
}

/// The value field of id `x`.
pub fn idVal(x: Word) Word {
    return t(x);
}

/// Pointer to the 'who' field of id `x`.
fn idWhoPtr(x: Word) *Word {
    return tp(h(h(x)));
}

/// Pointer to the type field of id `x`.
fn idTypePtr(x: Word) *Word {
    return tp(h(x));
}

/// Pointer to the value field of id `x`.
fn idValPtr(x: Word) *Word {
    return tp(x);
}

/// Pointer to the value field of private-name node `x`.
fn pnValPtr(x: Word) *Word {
    return tp(x);
}

/// The type class (algebraic/synonym/abstract/…) of type node `x`.
pub fn tClass(x: Word) Word {
    return h(t(theVal(x)));
}

/// The info field of type node `x`.
pub fn tInfo(x: Word) Word {
    return t(t(x));
}

/// Push `val` onto the GC-protected scratch stack.
fn stackpPush(val: Word) void {
    heap.stackp.?[0] = val;
    heap.stackp = heap.stackp.? + 1;
}

/// Pop the top of the GC-protected scratch stack.
fn stackpPop() Word {
    heap.stackp = heap.stackp.? - 1;
    return heap.stackp.?[0];
}

/// Peek the top of the GC-protected scratch stack.
fn stackpTop() Word {
    return (heap.stackp.? - 1)[0];
}

/// Overwrite the top of the GC-protected scratch stack.
fn stackpSetTop(val: Word) void {
    (heap.stackp.? - 1)[0] = val;
}

/// Allocate a `DATAPAIR` cell `(x . y)`.
fn datapair(x: Word, y: Word) Word {
    return make(.DATAPAIR, x, y);
}

/// Allocate a `FILEINFO` cell `(x . y)`.
fn fileinfo(x: Word, y: Word) Word {
    return make(.FILEINFO, x, y);
}

/// Allocate a `CONSTRUCTOR` cell (tag `n`, fields `x`).
pub fn constructor(n: Word, x: anytype) Word {
    const x_val: Word = switch (@TypeOf(x)) {
        Word => x,
        c_int, c_uint => @intCast(x),
        [*:0]const u8, [*:0]u8 => strtab.strBits(strtab.table, x),
        else => @compileError("Unsupported type for constructor"),
    };
    return make(.CONSTRUCTOR, n, x_val);
}

/// Allocate a `STARTREADVALS` node for the `readvals` reader.
fn readvals(x: Word, y: Word) Word {
    return make(.STARTREADVALS, x, y);
}

/// Allocate an application cell `(x y)`.
fn ap(x: Word, y: Word) Word {
    return make(.AP, x, y);
}

/// Write a 32-bit int to dump `file`.
pub fn putint(n: i32, file: ?*word.FILE) void {
    _ = word.fwrite(&n, @sizeOf(i32), 1, file);
}

/// Read a 32-bit int from dump `file`.
pub fn getint(file: ?*word.FILE) i32 {
    var r: i32 = 0;
    _ = word.fread(&r, @sizeOf(i32), 1, file);
    return r;
}

/// Write the double in cell `x` to dump `file`.
pub fn putdbl(x: Word, file: ?*word.FILE) void {
    var d = getDbl(x);
    _ = word.fwrite(&d, @sizeOf(f64), 1, file);
}

/// Read a double from dump `file` (as a `DOUBLE` node).
pub fn getdbl(file: ?*word.FILE) Word {
    var d: f64 = 0;
    _ = word.fread(&d, @sizeOf(f64), 1, file);
    return stoDbl(d);
}

/// Write the loaded files/definitions graph to dump `file`.
pub fn dumpScript(files_val: Word, file: ?*word.FILE) void {
    _ = word.putc(@intCast(wordsize), file);
    _ = word.putc(word.XVERSION, file);

    if (files_val == word.NIL) {
        _ = word.putc(0, file);
        putword(core.s.errline, file);
        var x = rt.rs.oldfiles;
        while (x != word.NIL) : (x = t(x)) {
            _ = word.fprint(file, "{s}", .{mkrel(getFil(h(x)) orelse "")});
            _ = word.putc(0, file);
            putword(filTime(h(x)), file);
        }
        return;
    }

    if (cs.ND != word.NIL) {
        _ = word.putc(1, file);
        putword(core.s.errline, file);
    }

    var f_list = files_val;
    while (f_list != word.NIL) : (f_list = t(f_list)) {
        heap.CFN = getFil(h(f_list)) orelse "";
        _ = word.fprint(file, "{s}", .{mkrel(heap.CFN.?)});
        _ = word.putc(0, file);
        putword(filTime(h(f_list)), file);
        _ = word.putc(@intCast(filShare(h(f_list))), file);
        dumpDefs(filDefs(h(f_list)), file);
    }
    _ = word.putc(0, file);
    dumpDefs(cs.algshfns, file);
    if (cs.ND == word.NIL and rt.rs.bereaved != word.NIL) {
        dumpOb(word.True, file);
    } else {
        dumpOb(cs.ND, file);
    }
    _ = word.putc(word.DEF_X, file);
    dumpOb(cs.SGC, file);
    _ = word.putc(word.DEF_X, file);
    dumpOb(rt.rs.freeids, file);
    _ = word.putc(word.DEF_X, file);
    dumpDefs(dump.internals, file);
}

/// Write a definition list to dump `file`.
pub fn dumpDefs(defs_val: Word, file: ?*word.FILE) void {
    var defs = defs_val;
    while (defs != word.NIL) : (defs = t(defs)) {
        const item = h(defs);
        if (getTag(item) == .STRCONS) {
            const v = getPn(item);
            dumpOb(pnVal(item), file);
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
            dumpOb(idVal(item), file);
            dumpOb(idType(item), file);
            dumpOb(idWho(item), file);
            _ = word.putc(word.ID_X, file);
            _ = word.fprint(file, "{s}", .{getId(item)});
            _ = word.putc(0, file);
            _ = word.putc(word.DEF_X, file);
        }
    }
    _ = word.putc(word.DEF_X, file);
}

/// Write one object (graph node) to dump `file`.
///
/// Tests: dumpOb / loadDefs: roundtrip a cons of two ints through the .x format
pub fn dumpOb(x: Word, file: ?*word.FILE) void {
    switch (heap.getTag(x)) {
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
            if (main_clib.strcmp(path, heap.CFN.?) == 0) {
                _ = word.putc(word.HERE_X, file);
            } else {
                _ = word.fprint(file, "{c}{s}", .{ @as(u8, @intCast(word.HERE_X)), mkrel(path) });
            }
            _ = word.putc(0, file);
            _ = word.putc(@intCast(line & 255), file);
            line >>= 8;
            _ = word.putc(@intCast(line & 255), file);
            if (line > 255) {
                std.debug.print("impossible line number {d} in dumpOb\n", .{t(x)});
            }
        },
        .CONSTRUCTOR => {
            dumpOb(t(x), file);
            _ = word.putc(word.CONSTRUCT_X, file);
            _ = word.putc(@intCast(h(x) & 255), file);
            _ = word.putc(@intCast(h(x) >> 8), file);
        },
        .STARTREADVALS => {
            dumpOb(t(x), file);
            _ = word.putc(word.RV_X, file);
        },
        .ID => {
            _ = word.fprint(file, "{c}{s}", .{ @as(u8, @intCast(word.ID_X)), getId(x) });
            _ = word.putc(0, file);
        },
        .STRCONS => {
            const v = getPn(x);
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
            dumpOb(h(x), file);
            dumpOb(t(x), file);
            _ = word.putc(word.AP_X, file);
        },
        .CONS => {
            dumpOb(t(x), file);
            dumpOb(h(x), file);
            _ = word.putc(word.CONS_X, file);
        },
        else => {
            std.debug.print("impossible tag {d} in dumpOb\n", .{heap.getTag(x)});
        },
    }
}

/// Load a script graph from a dump `file`, binding params and aliases.
pub fn loadScript(file: ?*word.FILE, src: [*:0]const u8, aliases: Word, params: Word, main_flag: Word) Word {
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
            const hold = cons(idWho(old), cons(idType(old), idVal(old)));
            idTypePtr(old).* = word.alias_t;
            idValPtr(old).* = new_id;
            if (getTag(new_id) == .ID) {
                if ((idType(new_id) != word.undef_t or idVal(new_id) != word.UNDEF) and idType(new_id) != word.alias_t) {
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
            const ch = idVal(t(h(a)));
            if (getTag(ch) == .ID) {
                if (idType(ch) != word.alias_t) {
                    idTypePtr(ch).* = word.new_t;
                }
            }
        }
    }
    heap.PNBASE = ls.nextpn;
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
                core.s.errline = holde;
            }
        }
        if (ch != '/') {
            _ = main_clib.strcpy(ls.dicp, &heap.prefix);
            ls.dicq = ls.dicp + @as(usize, @intCast(heap.preflen));
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
            lex.dicovflo();
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
        heap.CFN = getId(name());
        files_list = cons(makeFil(heap.CFN, ch, s, loadDefs(file)), files_list);
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
            core.s.errline = ch;
        }
        while (true) {
            ch = main_clib.getc(file);
            if (ch == main_clib.EOF) {
                break;
            }
            ls.dicq = ls.dicp;
            if (ch != '/') {
                _ = main_clib.strcpy(ls.dicp, &heap.prefix);
                ls.dicq = ls.dicp + @as(usize, @intCast(heap.preflen));
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
                lex.dicovflo();
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
            rt.rs.oldfiles = cons(makeFil(getId(name()), ch, 0, word.NIL), rt.rs.oldfiles);
        }
        if (aliases != word.NIL) {
            unscramble(aliases);
        }
        return word.NIL;
    }
    cs.algshfns = append1(cs.algshfns, loadDefs(file));
    cs.ND = loadDefs(file);
    if (cs.ND == word.True) {
        cs.ND = word.NIL;
        cs.TORPHANS = 1;
    }
    cs.SGC = append1(cs.SGC, loadDefs(file));
    if (main_flag != 0 or rt.rs.includees == word.NIL) {
        rt.rs.freeids = loadDefs(file);
    } else {
        bindparams(loadDefs(file), hdsort(params));
    }
    if (aliases != word.NIL) {
        unscramble(aliases);
    }
    if (main_flag != 0) {
        dump.internals = loadDefs(file);
    }
    return reverse(files_list);
}

/// Bind a `%include`'s formal parameters to the actual arguments.
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
            break :blk main_clib.strcmp(f, getId(a)) < 0;
        })) {
            cs.MISSING = cons(h(t(h(formal))), cs.MISSING);
            formal = t(formal);
        }
        if (actual == word.NIL) {
            break;
        }
        if (formal == word.NIL or main_clib.strcmp(f, getId(a)) != 0) {
            cs.DETROP = cons(a, cs.DETROP);
        } else {
            const fa = if (t(t(h(formal))) == word.type_t) tArity(h(h(formal))) else -1;
            const ta = if (getTag(h(actual)) == .AP) tArity(h(actual)) else -1;
            if (fa != ta) {
                badkind = cons(cons(h(h(actual)), datapair(fa, ta)), badkind);
            }
            idValPtr(h(h(formal))).* = t(h(actual));
            formal = t(formal);
        }
        actual = t(actual);
    }

    var bk = badkind;
    while (bk != word.NIL) : (bk = t(bk)) {
        cs.DETROP = cons(h(bk), cs.DETROP);
    }
}

/// Resolve `%include` aliases in the freshly-loaded graph.
pub fn unscramble(aliases: Word) void {
    var a = aliases;
    while (a != word.NIL) : (a = t(a)) {
        const old = t(h(a));
        var hold = h(h(a));
        const new_id = idVal(old);
        hp(h(a)).* = new_id;
        idWhoPtr(old).* = h(hold);
        hold = t(hold);
        idTypePtr(old).* = h(hold);
        idValPtr(old).* = t(hold);
    }
    var al = cs.ALIASES;
    a = word.NIL;
    while (al != word.NIL) : (al = t(al)) {
        const new_id = h(h(al));
        const old = t(h(al));
        if (getTag(new_id) != .ID) {
            if (member(cs.SUPPRESSED, new_id) == 0) {
                a = cons(old, a);
            }
            continue;
        }
        if (idType(new_id) == word.new_t) {
            idTypePtr(new_id).* = word.undef_t;
        }
        if (idType(new_id) == word.undef_t) {
            a = cons(old, a);
        } else if (member(cs.CLASHES, new_id) == 0) {
            if (getTag(idWho(new_id)) != .CONS) {
                idWhoPtr(new_id).* = cons(datapair(strtab.strBits(strtab.table, getId(old)), 0), idWho(new_id));
            }
        }
    }
    cs.ALIASES = a;
}

/// Allocate the dump scratch stack (`dstack`).
pub fn dsetup() void {
    if (heap.dstack == null) {
        const slice = rt.allocator.alloc(Word, 1000) catch mallocPanic("dstack");
        heap.dstack = slice.ptr;
        heap.dlim = heap.dstack.? + 1000;
        heap.allocated_dstack_size = 1000;
    }
    heap.stackp = heap.dstack;
}

/// Grow the dump scratch stack when it overflows.
pub fn dgrow() void {
    const hold = heap.dstack.?;
    const num_elements = heap.dlim.? - hold;
    const old_slice = hold[0..heap.allocated_dstack_size];
    const new_size = num_elements * 2;
    const slice = rt.allocator.realloc(old_slice, new_size) catch mallocPanic("dstack");
    heap.dstack = slice.ptr;
    heap.dlim = heap.dstack.? + new_size;
    heap.stackp = heap.dstack.? + (heap.stackp.? - hold);
    heap.allocated_dstack_size = new_size;
}

/// Load a definition list from a dump `file`.
///
/// Tests: dumpOb / loadDefs: roundtrip a cons of two ints through the .x format
pub fn loadDefs(file: ?*word.FILE) Word {
    var ch = main_clib.getc(file);
    var defs: Word = word.NIL;
    while (ch != main_clib.EOF) {
        if (heap.stackp == heap.dlim) {
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
                stackpPush(make(.INT, val, 0));
                var x = &tp(stackpTop()).*;
                var next = getint(file);
                while (next != -1) {
                    x.* = make(.INT, next, 0);
                    x = &tp(x.*).*;
                    next = getint(file);
                }
            },
            word.DBL_X => {
                stackpPush(getdbl(file));
            },
            word.UNICODE_X => {
                stackpPush(make(.UNICODE, getint(file), 0));
            },
            word.PN_X => {
                var val = main_clib.getc(file);
                val = val | (main_clib.getc(file) << 8);
                const idx = heap.PNBASE + val;
                stackpPush(if (idx < ls.nextpn) ls.pnvec.?[@intCast(idx)] else lex.stoPn(idx));
            },
            word.PN1_X => {
                const idx = heap.PNBASE + getint(file);
                stackpPush(if (idx < ls.nextpn) ls.pnvec.?[@intCast(idx)] else lex.stoPn(idx));
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
                    lex.dicovflo();
                }
                stackpPush(name());
                const top = stackpTop();
                if (idType(top) == word.new_t) {
                    cs.CLASHES = add1(top, cs.CLASHES);
                    stackpSetTop(word.NIL);
                } else if (idType(top) == word.alias_t) {
                    stackpSetTop(idVal(top));
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
                    lex.dicovflo();
                }
                stackpPush(datapair(strtab.strBits(strtab.table, getId(name())), 0));
            },
            word.HERE_X => {
                ls.dicq = ls.dicp;
                var next = main_clib.getc(file);
                if (next == 0) {
                    next = main_clib.getc(file);
                    next = next | (main_clib.getc(file) << 8);
                    stackpPush(fileinfo(strtab.strBits(strtab.table, heap.CFN.?), next));
                } else {
                    if (next != '/') {
                        _ = main_clib.strcpy(ls.dicp, &heap.prefix);
                        ls.dicq = ls.dicp + @as(usize, @intCast(heap.preflen));
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
                        lex.dicovflo();
                    }
                    var line = main_clib.getc(file);
                    line = line | (main_clib.getc(file) << 8);
                    stackpPush(fileinfo(strtab.strBits(strtab.table, getId(name())), line));
                }
            },
            word.DEF_X => {
                const diff = heap.stackp.? - heap.dstack.?;
                switch (diff) {
                    0 => {
                        return reverse(defs);
                    },
                    1 => {
                        return stackpPop();
                    },
                    2 => {
                        const ch_val = stackpPop();
                        pnValPtr(ch_val).* = stackpPop();
                        defs = cons(ch_val, defs);
                    },
                    4 => {
                        const top = stackpTop();
                        if (getTag(top) != .ID) {
                            if (top == word.NIL) {
                                heap.stackp = heap.stackp.? - 4;
                                ch = main_clib.getc(file);
                                continue;
                            }
                            const ch_val = stackpPop();
                            cs.SUPPRESSED = cons(ch_val, cs.SUPPRESSED);
                            _ = stackpPop(); // who
                            const who_val = stackpTop();
                            const akap = if (getTag(who_val) == .CONS) h(who_val) else word.NIL;
                            const type_val = stackpPop(); // type
                            pnValPtr(ch_val).* = stackpPop();

                            if (type_val == word.type_t and tClass(ch_val) != word.synonym_t) {
                                var a = cs.ALIASES;
                                while (a != word.NIL and idVal(t(h(a))) != ch_val) : (a = t(a)) {}
                                if (a != word.NIL) {
                                    cs.TSUPPRESSED = cons(t(h(a)), cs.TSUPPRESSED);
                                }
                            } else if (pnVal(ch_val) == word.UNDEF) {
                                var akap_val = akap;
                                if (akap_val == word.NIL) {
                                    var a = cs.ALIASES;
                                    while (a != word.NIL) : (a = t(a)) {
                                        if (idVal(t(h(a))) == ch_val) {
                                            akap_val = datapair(strtab.strBits(strtab.table, getId(t(h(a)))), 0);
                                            break;
                                        }
                                    }
                                }
                                pnValPtr(ch_val).* = ap(akap_val, fileinfo(strtab.strBits(strtab.table, heap.CFN.?), 0));
                            }
                            defs = cons(ch_val, defs);
                            ch = main_clib.getc(file);
                            continue;
                        }
                        const top_val = stackpTop();
                        if (idType(top_val) != word.new_t and (idType(top_val) != word.undef_t or idVal(top_val) != word.UNDEF)) {
                            if (idType(top_val) == word.alias_t) {
                                var a = cs.ALIASES;
                                while (a != word.NIL and t(h(a)) != top_val) : (a = t(a)) {}
                                if (a == word.NIL) {
                                    std.debug.print("impossible event in cyclic alias ({s})\n", .{getId(top_val)});
                                    heap.stackp = heap.stackp.? - 4;
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
                            heap.stackp = heap.stackp.? - 4;
                        } else {
                            defs = cons(stackpPop(), defs);
                            idWhoPtr(h(defs)).* = stackpPop();
                            idTypePtr(h(defs)).* = stackpPop();
                            idValPtr(h(defs)).* = stackpPop();
                        }
                    },
                    else => {
                        std.debug.print("unexpected stack diff in loadDefs\n", .{});
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
/// The `(dev . ino)` filesystem identity of file record `fil`.
pub fn filInodev(fil: Word) Word {
    return t(t(h(fil)));
}

/// Whether two file records name the same inode.
pub fn sameFile(x: Word, y: Word) bool {
    const ix = filInodev(x);
    const iy = filInodev(y);
    return h(ix) == h(iy) and t(ix) == t(iy);
}

/// Whether `x` is a bad/error sentinel value.
///
/// Tests: badval: flags values outside the plausible heap range
pub fn badval(x: Word) bool {
    return x < 100 or x > 50000000;
}

test "badval: flags values outside the plausible heap range" {
    try std.testing.expect(badval(50)); // below the floor
    try std.testing.expect(badval(60_000_000)); // above the ceiling
    try std.testing.expect(!badval(1000)); // a plausible cell id
}

/// Whether id `x` is a `%free` identifier.
pub fn isfreeid(x: Word) bool {
    return idType(x) == word.undef_t and idVal(x) == word.UNDEF;
}

const isconstrname = lex.isconstrname;
/// Whether `x` names a data constructor.
pub fn isconstructor(x: Word) bool {
    return getTag(x) == .ID and isconstrname(getId(x));
}

/// Whether `x` names an ordinary variable.
pub fn isvariable(x: Word) bool {
    return getTag(x) == .ID and !isconstrname(getId(x));
}

/// Add id `x` to the current file's definition environment.
pub fn addtoenv(x: Word) void {
    tp(h(heap.files)).* = cons(x, t(h(heap.files)));
}

/// Reverse list `input`.
///
/// Tests: reverse: reverses a list
pub fn reverse(input: Word) Word {
    var x = input;
    var y: Word = NIL;
    while (x != NIL) {
        y = cons(h(x), y);
        x = t(x);
    }
    return y;
}

test "reverse: reverses a list" {
    tu.freshInterp();
    const l = cons(word.I, cons(word.K, cons(word.S, word.NIL)));
    const r = reverse(l);
    try std.testing.expectEqual(@as(Word, word.S), h(r));
    try std.testing.expectEqual(@as(Word, word.K), h(t(r)));
    try std.testing.expectEqual(@as(Word, word.I), h(t(t(r))));
    try std.testing.expectEqual(@as(Word, word.NIL), t(t(t(r))));
    try std.testing.expectEqual(@as(Word, word.NIL), reverse(word.NIL));
}

/// Reverse `x` onto the front of `y` (shunt / reverse-append).
///
/// Tests: shunt: reverses x onto the front of y
pub fn shunt(input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    while (x != NIL) {
        y = cons(h(x), y);
        x = t(x);
    }
    return y;
}

test "shunt: reverses x onto the front of y" {
    tu.freshInterp();
    const x = cons(word.I, cons(word.K, word.NIL));
    const y = cons(word.S, word.NIL);
    const r = shunt(x, y); // reverse [I,K] onto [S] → [K,I,S]
    try std.testing.expectEqual(@as(Word, word.K), h(r));
    try std.testing.expectEqual(@as(Word, word.I), h(t(r)));
    try std.testing.expectEqual(@as(Word, word.S), h(t(t(r))));
    try std.testing.expectEqual(@as(Word, word.NIL), t(t(t(r))));
}

/// The length of list `input`.
///
/// Tests: size: counts the cells of a flat list
pub fn size(input: Word) Word {
    var x = input;
    var s: Word = 0;
    while (getTag(x) == .CONS or getTag(x) == .AP) {
        s += 1 + size(h(x));
        x = t(x);
    }
    return s;
}

test "size: counts the cells of a flat list" {
    tu.freshInterp();
    try std.testing.expectEqual(@as(Word, 0), size(word.NIL));
    const l = cons(stosmallint(1), cons(stosmallint(2), cons(stosmallint(3), word.NIL)));
    try std.testing.expectEqual(@as(Word, 3), size(l));
}

/// Sort a list of identifiers alphabetically by name.
pub fn alfasort(x_val: Word) Word {
    var x = x_val;
    var a = NIL;
    var b = NIL;
    var hold = NIL;
    if (x == NIL) {
        return NIL;
    }
    if (t(x) == NIL) {
        return if (getTag(h(x)) != .ID) NIL else x;
    }
    while (x != NIL) {
        if (getTag(h(x)) == .ID) {
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

/// Detect whether the current locale is UTF-8 (1/0).
pub fn utf8test() bool {
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
            return true;
        }
    }
    return false;
}

/// Clear the values of all ids defined in `d_val` (on unload).
pub fn unsetids(d_val: Word) void {
    var d = d_val;
    while (d != NIL and d != 0) : (d = t(d)) {
        const item = h(d);
        if (getTag(item) == .ID) {
            tp(item).* = word.UNDEF;
            tp(h(h(item))).* = NIL;
            tp(h(item)).* = word.undef_t;
        }
    }
}

/// Unload the current script: clear its definitions from the environment.
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
    while (heap.files != NIL and heap.files != 0) : (heap.files = t(heap.files)) {
        const fil = h(heap.files);
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

/// Whether any loaded source file has changed on disk since load (1/0).
pub fn srcUpdate() c_int {
    var ft: Word = undefined;
    var f = if (heap.files == NIL) rt.rs.oldfiles else heap.files;
    while (f != NIL) {
        const _fil_path: [*:0]const u8 = strtab.strOf(strtab.table, h(h(h(h(f)))));
        if ((fileMtime(_fil_path)) != filTime(h(f))) {
            ft = fileMtime(_fil_path);
            if (ft == 0) {
                unlinkObject(_fil_path);
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
/// Created by `makeFil()`; its structure is `(FILEINFO name mtime) . defs`.
pub const FileNode = struct {
    word: Word,

    /// The modification time recorded in the heap for this file (seconds since epoch).
    pub fn time(self: FileNode) Word {
        return filTime(self.word);
    }
    /// Share flag: 1 for system/shared files (prelude, stdlib), 0 for user scripts.
    pub fn share(self: FileNode) Word {
        return filShare(self.word);
    }
    /// The definitions list (environment entries compiled from this file).
    pub fn defs(self: FileNode) Word {
        return filDefs(self.word);
    }
    /// A `(dev . ino)` cons cell identifying this file's filesystem inode.
    pub fn inodeId(self: FileNode) Word {
        return filInodev(self.word);
    }
    /// True if this file and `other` refer to the same filesystem inode.
    pub fn sameAs(self: FileNode, other: FileNode) bool {
        return sameFile(self.word, other.word);
    }
};

/// A heap node that represents a Miranda identifier (name/binding).
/// Created by `makeId()`; has tag ID and carries type, value, and provenance.
pub const Identifier = struct {
    word: Word,

    /// The declared type of this identifier (a type node Word).
    pub fn typ(self: Identifier) Word {
        return idType(self.word);
    }
    /// The current reduction value of this identifier (combinator or UNDEF).
    pub fn val(self: Identifier) Word {
        return idVal(self.word);
    }
    /// Provenance: a cons list of datapairs recording where this name was defined.
    pub fn who(self: Identifier) Word {
        return idWho(self.word);
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
        return tClass(self.word);
    }
    /// Auxiliary info: parameter list for synonyms, constructor list for algebraics.
    pub fn info(self: TypeRef) Word {
        return tInfo(self.word);
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

test "dumpOb / loadDefs: roundtrip a cons of two ints through the .x format" {
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
    dumpOb(list, f_write);
    _ = word.fclose(f_write.?);

    // 5. Open the temp file for reading
    const f_read = word.fopen(filename, "r");
    try std.testing.expect(f_read != null);

    // 6. Load it back using loadDefs (which pushes it onto stackp)
    const old_stackp = heap.stackp;
    _ = loadDefs(f_read);
    _ = word.fclose(f_read.?);

    // Clean up temp file
    _ = main_clib.unlink(filename);

    // 7. Verify structural equality
    try std.testing.expect(@intFromPtr(heap.stackp.?) > @intFromPtr(old_stackp.?));
    const loaded = stackpTop();

    try std.testing.expectEqual(word.NodeTag.CONS, heap.getTag(loaded));
    const loaded_h = h(loaded);
    const loaded_t = t(loaded);

    try std.testing.expectEqual(word.NodeTag.INT, heap.getTag(loaded_h));
    try std.testing.expectEqual(@as(Word, 42), getsmallint(loaded_h));
    try std.testing.expectEqual(word.NodeTag.INT, heap.getTag(loaded_t));
    try std.testing.expectEqual(@as(Word, 100), getsmallint(loaded_t));
}

