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
const rt = @import("../runtime/runtime_state.zig");
const script_store = @import("../session/script_store.zig");
const config_state = @import("../session/config_state.zig");
const core = @import("../runtime/core_state.zig");
const lex_state = @import("../parser/lex_state.zig");
const ls = lex_state.ls;

const compiler_state = @import("../compiler/compiler_state.zig");
const make_state = @import("../session/make_state.zig");
const bnf_state = @import("../session/bnf_state.zig");
const repl_session = @import("../session/repl_session.zig");
const lex = @import("../parser/lex.zig");
const symbols = @import("../semantics/symbols.zig");
const big = @import("bignum.zig");
const reduce = @import("../eval/reduce_rt.zig");
const os = @import("../os.zig");
const setup = @import("../compiler/setup.zig");
const cs = compiler_state.cs;
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)

const Word = i64;

/// The value field of a type/definition cell.
pub inline fn theVal(x: Word) Word {
    return t(x);
}

/// The arity recorded in a type node.
pub inline fn tArity(x: Word) Word {
    return h(h(t(x)));
}
const ATOMLIMIT = word.ATOMLIMIT;
const NIL = word.NIL;
const NILS = word.NILS;

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
    /// Heap address of the `nil` combinator (Phase 4 step 4,
    /// docs/ZIG_NATIVE_PLAN.md; set once during `miraSetup`, never
    /// mutated after — moved off `CoreState`, whose "core state" was
    /// meant for cross-cutting error/mode flags, not heap-node identity
    /// already covered by this struct's other setup-time fields like
    /// `files`/`CFN`).
    nill: Word = 0,
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
        return config_state.config().SPACELIMIT + ATOMLIMIT;
    }

    /// The usable heap size, in cells.
    pub fn trueheapsize(self: Heap) Word {
        // Before the first-ever gc, nothing has been freed, so every claim is
        // still live -- matches what the old bump-pointer `listp` tracked.
        return if (heap().nogcs == 0) heap().claims else self.SPACE;
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
        if (self.SPACE > config_state.config().SPACELIMIT) {
            self.SPACE = config_state.config().SPACELIMIT;
        }
        self.free_head = 0;
        self.threadFree(ATOMLIMIT, self.TOP());
    }

    /// Reset the heap to empty (between sessions).
    pub fn resetheap(self: *Heap) void {
        if (config_state.config().SPACELIMIT < self.trueheapsize()) {
            _ = word.printErr("impossible event in resetheap\n", .{});
            os.exit(1);
        }
        const bigtop_val = @as(usize, @intCast(self.BIGTOP()));
        self.cells.resize(rt.allocator, bigtop_val + 1) catch mallocPanic("heap");
        self.refreshPointers();

        self.tag.?[@intCast(bigtop_val)] = .ATOM;
        if (self.SPACE > config_state.config().SPACELIMIT) {
            self.SPACE = config_state.config().SPACELIMIT;
        }
        if (self.SPACE < 1250000 and 1250000 <= config_state.config().SPACELIMIT) {
            self.SPACE = 1250000;
            self.tag.?[@intCast(self.TOP())] = .ATOM;
        }
        self.live.resize(rt.allocator, bigtop_val + 1 - @as(usize, @intCast(ATOMLIMIT)), false) catch mallocPanic("heap");
        self.live.setRangeValue(.{ .start = 0, .end = @intCast(self.SPACE) }, false);
        self.free_head = 0;
        self.threadFree(ATOMLIMIT, self.TOP());
    }

    /// A snapshot of the heap's mutable state, taken before an in-process
    /// evaluation whose reductions must not persist if the evaluation is
    /// interrupted or simply finishes (Phase 3, docs/ZIG_NATIVE_PLAN.md).
    ///
    /// Replaces fork-per-eval: the old design forked a child to do the
    /// reduction, and the child's heap mutations (being a separate,
    /// COW-copied address space) simply died with it when it exited --
    /// `evaluateRepl`'s own doc comment already said as much ("leaving the
    /// parent's heap untouched"). `checkpoint`/`restore` reproduce that same
    /// invariant in-process: every REPL expression evaluation is checkpointed
    /// first and *always* restored afterward (success, interrupt, or
    /// otherwise), matching the fork model exactly rather than only undoing
    /// mutations on the interrupted path.
    pub const Checkpoint = struct {
        space: Word,
        hd: []Word,
        tl: []Word,
        tag: []word.NodeTag,
        live: std.DynamicBitSetUnmanaged,
        free_head: Word,
        cellcount: i64,
        claims: c_long,
        nogcs: c_long,
        hnogcs: c_long,
        files: Word,
        current_file: Word,
    };

    /// Snapshot the heap's mutable state. Only the currently-in-play
    /// `[ATOMLIMIT, TOP())` cell range is copied (not the full
    /// `SPACELIMIT`-sized backing arrays), bounding the cost to the heap's
    /// actual working set.
    ///
    /// Tests: Heap.checkpoint/restore: undoes cell mutations and new allocations made after the snapshot
    pub fn checkpoint(self: *Heap) Checkpoint {
        const n: usize = @intCast(self.SPACE);
        const start: usize = @intCast(ATOMLIMIT);
        return .{
            .space = self.SPACE,
            .hd = rt.allocator.dupe(Word, self.hd.?[start..][0..n]) catch mallocPanic("checkpoint"),
            .tl = rt.allocator.dupe(Word, self.tl.?[start..][0..n]) catch mallocPanic("checkpoint"),
            .tag = rt.allocator.dupe(word.NodeTag, self.tag.?[start..][0..n]) catch mallocPanic("checkpoint"),
            .live = self.live.clone(rt.allocator) catch mallocPanic("checkpoint"),
            .free_head = self.free_head,
            .cellcount = self.cellcount,
            .claims = self.claims,
            .nogcs = self.nogcs,
            .hnogcs = self.hnogcs,
            .files = self.files,
            .current_file = self.current_file,
        };
    }

    /// Restore the heap to a previous `checkpoint`, discarding any
    /// allocations, in-place rewrites, or GCs made since. Consumes `snap`
    /// (its backing memory is freed here; do not reuse it afterward).
    pub fn restore(self: *Heap, snap: *Checkpoint) void {
        const n: usize = @intCast(snap.space);
        const start: usize = @intCast(ATOMLIMIT);
        self.SPACE = snap.space;
        @memcpy(self.hd.?[start..][0..n], snap.hd);
        @memcpy(self.tl.?[start..][0..n], snap.tl);
        @memcpy(self.tag.?[start..][0..n], snap.tag);
        rt.allocator.free(snap.hd);
        rt.allocator.free(snap.tl);
        rt.allocator.free(snap.tag);
        self.live.deinit(rt.allocator);
        self.live = snap.live;
        self.free_head = snap.free_head;
        self.cellcount = snap.cellcount;
        self.claims = snap.claims;
        self.nogcs = snap.nogcs;
        self.hnogcs = snap.hnogcs;
        self.files = snap.files;
        self.current_file = snap.current_file;
    }

    pub fn makeSlow(self: *Heap, t_val: word.NodeTag, x: Word, y: Word) Word {
        if (self.SPACE != config_state.config().SPACELIMIT) {
            const old_top = self.TOP();
            if (core.s().compiling == 0) {
                self.SPACE = config_state.config().SPACELIMIT;
            } else if (heap().claims <= @divTrunc(self.SPACE, 4) and heap().nogcs > 1) {
                var wait: Word = 0;
                const sp = self.SPACE;
                if (wait != 0) {
                    wait -= 1;
                } else {
                    self.SPACE += @divTrunc(self.SPACE, 2);
                    wait = 2;
                    self.SPACE = 5000 * (1 + @divTrunc(self.SPACE - 1, 5000));
                }
                if (self.SPACE > config_state.config().SPACELIMIT) {
                    self.SPACE = config_state.config().SPACELIMIT;
                }
                if (rt.rs().atgc != 0 and self.SPACE > sp) {
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
        heap().claims += 1;
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

        heap().claims += 2;
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
        const old_limit = config_state.config().SPACELIMIT;
        const new_limit = old_limit * 2;
        config_state.config().SPACELIMIT = new_limit;
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
        heap().collecting = 1;
        if (rt.rs().atgc != 0) {
            _ = word.printErr("\n<<gc after {d} claims>>\n", .{heap().claims});
        }
        if (heap().claims <= @divTrunc(self.SPACE, 10) and heap().nogcs > 1 and self.SPACE == config_state.config().SPACELIMIT) {
            if (heap().nogcs == self.hnogcs) {
                if (self.growHeap()) {
                    self.hnogcs = 0;
                } else {
                    _ = word.printErr("<<not enough heap space -- task abandoned>>\n", .{});
                    if (core.s().compiling == 0) {
                        outstats();
                    }
                    if (core.s().compiling != 0 and rt.rs().ideep == 0) {
                        _ = word.printErr("not enough heap to compile current script\n", .{});
                        _ = word.printErr("script = \"{s}\", heap = {d}\n", .{ script_store.store().current_script orelse @as([*:0]const u8, "(null)"), self.SPACE });
                    }
                    os.exit(1);
                }
            } else {
                self.hnogcs = heap().nogcs + 1;
            }
        }
        heap().nogcs += 1;

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
                    while (bit_idx >= 0) : ({
                        bit_idx -= 1;
                        cell_idx -= 1;
                    }) {
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

        heap().cellcount += heap().claims;
        heap().claims = 0;
        heap().collecting = 0;
        const options = @import("version_options");
        if (options.is_strict or @import("builtin").mode == .Debug) {
            self.validate();
        }
    }

    /// Mark the GC roots: the live Words on the C stack and in registers.
    pub fn bases(self: *Heap) void {
        var p: [*]Word = undefined;
        p = @ptrCast(@alignCast(&p));
        const cstack_ptr = rt.rs().cstack.?;
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

        self.mark(reduce.ev().outfilq);
        self.mark(reduce.ev().waiting);
        if (core.s().compiling != 0 or rt.rs().rv_expr != 0 or cs().rv_script != 0) {
            self.mark(make_state.make().make_status);
            self.mark(rt.rs().primenv);
            self.mark(ls().fileq);
            self.mark(ls().idsused);
            self.mark(bnf_state.bnf().eprodnts);
            self.mark(bnf_state.bnf().nonterminals);
            self.mark(bnf_state.bnf().ntmap);
            self.mark(bnf_state.bnf().ihlist);
            self.mark(bnf_state.bnf().ntspecmap);
            self.mark(ls().gvars);
            self.mark(ls().lexvar);
            self.mark(ls().common_stdin);
            self.mark(ls().common_stdinb);
            self.mark(ls().cook_stdin);
            self.mark(ls().margstack);
            self.mark(ls().vergstack);
            self.mark(ls().litstack);
            self.mark(ls().linostack);
            self.mark(ls().prefixstack);
            self.mark(heap().files);
            self.mark(script_store.store().oldfiles);
            self.mark(script_store.store().includees);
            self.mark(script_store.store().freeids);
            self.mark(script_store.store().exports);
            self.mark(cs().internals);
            self.mark(bnf_state.bnf().lexstates);
            self.mark(bnf_state.bnf().lexdefs);
            // The identifier dictionary (semantics/symbols.zig's SymbolTable,
            // replacing LexState.namebucket's hash-bucket array -- see
            // ZIG_NATIVE_PLAN.md Phase 1 step 6): every ID node it references
            // must stay reachable, exactly as every namebucket entry used to.
            var syms_it = symbols.syms().table.valueIterator();
            while (syms_it.next()) |id| {
                self.mark(id.*);
            }
            const p_dstack = heap().dstack;
            const p_stackp = heap().stackp;
            if (p_dstack != null and p_stackp != null) {
                var curr = p_dstack.?;
                const end = p_stackp.?;
                while (@intFromPtr(curr) < @intFromPtr(end)) : (curr += 1) {
                    self.mark(curr[0]);
                }
            }
            if (core.s().loading != 0) {
                self.mark(ls().exportfiles);
                self.mark(script_store.store().embargoes);
                self.mark(script_store.store().rfl);
                self.mark(script_store.store().detrop);
                self.mark(script_store.store().bereaved);
                self.mark(script_store.store().ld_stuff);
                self.mark(cs().tlost);
                var i: usize = 0;
                const nextpn_val = @as(usize, @intCast(ls().nextpn));
                while (i < nextpn_val) : (i += 1) {
                    self.mark(ls().pnvec.?[i]);
                }
            }
            self.mark(script_store.store().lastname);
            self.mark(script_store.store().suppressids);
            self.mark(repl_session.session().lastexp);
            self.mark(self.nill);
            self.mark(rt.rs().standardout);
            self.mark(big.bn().big_one);
            self.mark(big.bn().b_rem);
            self.mark(ls().yylval);
            self.mark(ls().echostack);
            self.mark(core.s().errs);

            // Automatically trace all active roots in CompilerState cs singleton using compile-time reflection.
            inline for (std.meta.fields(compiler_state.CompilerState)) |field| {
                const T = field.type;
                switch (@typeInfo(T)) {
                    .int => {
                        if (T == Word) {
                            self.mark(@field(cs(), field.name));
                        }
                    },
                    .array => |info| {
                        if (info.child == Word) {
                            for (@field(cs(), field.name)) |elem| {
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
        @import("../eval/spine.zig").markAllRoots(reduce.ev().gc_roots_head, markRoot);
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

/// Pointer to the singleton [Heap] inside `current_interp` (so `interp.reset()`
/// clears it). The free functions below operate on it; call sites use `heap.heap().X`.
pub inline fn heap() *Heap {
    return &@import("../session/interp.zig").current_interp.heap;
}

/// Head (`hd`) of cell `x`.
///
/// Tests: heap accessors: cons/make build cells that h/t/getTag read back
pub fn h(x: Word) Word {
    return heap().h(x);
}

/// Pointer to the head field of cell `x` (for in-place mutation).
pub fn hp(x: Word) *Word {
    return heap().hp(x);
}

/// Tail (`tl`) of cell `x`.
pub fn t(x: Word) Word {
    return heap().t(x);
}

/// Pointer to the tail field of cell `x` (for in-place mutation).
pub fn tp(x: Word) *Word {
    return heap().tp(x);
}

/// Mark `x` reachable (GC). A free-function adapter to the singleton's
/// method, matching `mark`'s signature to what `reducer/spine.zig`'s
/// `markAllRoots` expects (a plain `fn (Word) void`, no bound receiver) —
/// see `Heap.bases`, the only caller.
fn markRoot(x: Word) void {
    heap().mark(x);
}

/// The node tag of cell `x`.
pub fn getTag(x: Word) word.NodeTag {
    return heap().getTag(x);
}

/// Allocate a `CONS` cell `(x . y)`.
///
/// Tests: heap accessors: cons/make build cells that h/t/getTag read back
pub fn cons(x: Word, y: Word) Word {
    return heap().cons(x, y);
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
    heap().setTag(apnode, .CONS);
    try std.testing.expectEqual(word.NodeTag.CONS, getTag(apnode));
}

test "gc: a long-lived list survives many forced collections; garbage is reclaimed" {
    tu.freshInterp();

    // `bases()`'s conservative stack scan needs `rt.rs().cstack` as its "bottom
    // of the interesting range" boundary -- normally set once by
    // `startup.mainEntry` (real runs only). Unit tests never go through
    // that, so it's `null` here; take the address of a local, matching what
    // `mainEntry` does with its own `manonly`, so a real `gc()` cycle
    // (this test's whole point) doesn't crash finding it unset.
    var stack_anchor: Word = 0;
    const saved_cstack = rt.rs().cstack;
    rt.rs().cstack = @ptrCast(&stack_anchor);

    // Shrink the heap so allocating the workload below forces `gc()` to run
    // many times (B3's own DoD: "GC stress test stable"), then restore it --
    // `tu.freshInterp()` only sets up once per test binary, so a later test
    // must see the original size, not this one's.
    const saved_spacelimit = config_state.config().SPACELIMIT;
    const saved_space = heap().SPACE;
    defer {
        config_state.config().SPACELIMIT = saved_spacelimit;
        heap().SPACE = saved_space;
        heap().resetheap();
        rt.rs().cstack = saved_cstack;
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
    config_state.config().SPACELIMIT = chain_len * 4;
    heap().resetheap();

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
        chain = heap().cons(@mod(i, 100), chain);
    }

    // Churn short-lived garbage through the (now mostly-full) heap: this
    // forces many `gc()` cycles, each of which must re-mark the whole chain
    // (constant O(chain_len) cost per cycle, not growing as the churn count
    // grows) while reclaiming the garbage around it. `0`/`0`, not `churn`,
    // for the same reason as above -- the churn count climbs into the
    // thousands.
    const nogcs_before = heap().nogcs;
    var churn: Word = 0;
    while (churn < chain_len * 30) : (churn += 1) {
        _ = heap().cons(0, 0);
    }

    try std.testing.expect(heap().nogcs > nogcs_before);

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

test "Heap.checkpoint/restore: undoes cell mutations and new allocations made after the snapshot" {
    tu.freshInterp();

    var stack_anchor: Word = 0;
    const saved_cstack = rt.rs().cstack;
    rt.rs().cstack = @ptrCast(&stack_anchor);
    defer rt.rs().cstack = saved_cstack;

    // A cell that exists *before* the checkpoint: restore must put its
    // fields back exactly, even though it gets mutated in place below.
    const before = heap().cons(1, 2);
    try std.testing.expectEqual(@as(Word, 1), h(before));
    try std.testing.expectEqual(@as(Word, 2), t(before));

    const top_before = heap().TOP();
    const free_head_before = heap().free_head;
    const cellcount_before = heap().cellcount;
    const claims_before = heap().claims;

    var snap = heap().checkpoint();

    // Mutate the pre-checkpoint cell in place and allocate a chain past it
    // (forcing `TOP`/`free_head`/`claims`/`cellcount` to move) before
    // restoring -- the snapshot itself is inert data, not a GC root; it does
    // not need a live mark/sweep pass to exercise (that's `gc()`'s own test,
    // above).
    hp(before).* = 99;
    tp(before).* = 98;
    var i: Word = 0;
    while (i < 50) : (i += 1) {
        _ = heap().cons(0, 0);
    }

    heap().restore(&snap);

    try std.testing.expectEqual(@as(Word, 1), h(before));
    try std.testing.expectEqual(@as(Word, 2), t(before));
    try std.testing.expectEqual(top_before, heap().TOP());
    try std.testing.expectEqual(free_head_before, heap().free_head);
    try std.testing.expectEqual(cellcount_before, heap().cellcount);
    try std.testing.expectEqual(claims_before, heap().claims);
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
    return strtab.strOf(strtab.table(), h(h(h(x))));
}

/// The filename of file-record `fil`, or null when absent.
///
/// The single file-name accessor: callers that want the empty string for an absent
/// name use `getFil(fil) orelse ""` (matches `strtab.strOf(strtab.table(), 0)`).
pub fn getFil(fil: Word) ?[*:0]const u8 {
    const val = h(h(h(fil)));
    if (val == 0) return null;
    return strtab.strOf(strtab.table(), val);
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
    std.debug.print("impossible event in getChar(x), tag[x]=={d}\n", .{heap().getTag(x)});
    os.exit(1);
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
    return if (getTag(y) != .CONS) getId(x) else strtab.strOf(strtab.table(), h(h(y)));
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
        if (std.mem.order(u8, std.mem.span(getId(h(h(a)))), std.mem.span(getId(h(h(b))))) == .lt) {
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
pub fn stoDbl(R_val: f64) word.ReduceError!Word {
    if (!std.math.isFinite(R_val)) {
        return error.FloatOverflow;
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
pub fn setdbl(x: Word, R_val: f64) word.ReduceError!void {
    if (!std.math.isFinite(R_val)) {
        return error.FloatOverflow;
    }
    var r: fpdatum = undefined;
    r.real = R_val;
    heap().setTag(x, .DOUBLE);
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
    const d = try stoDbl(3.14);
    try std.testing.expectEqual(word.NodeTag.DOUBLE, getTag(d));
    try std.testing.expectEqual(@as(f64, 3.14), getDbl(d));
    try setdbl(d, -2.5);
    try std.testing.expectEqual(@as(f64, -2.5), getDbl(d));
}

test "stoDbl / setdbl: non-finite result returns error.FloatOverflow" {
    tu.freshInterp();
    try std.testing.expectError(error.FloatOverflow, stoDbl(std.math.inf(f64)));
    const d = try stoDbl(1.0);
    try std.testing.expectError(error.FloatOverflow, setdbl(d, -std.math.inf(f64)));
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
pub fn TOP() Word {
    return heap().TOP();
}

/// The high-water heap limit.
/// The usable heap size, in cells.
pub fn trueheapsize() Word {
    return heap().trueheapsize();
}

/// Allocate and initialise the heap arena.
pub fn setupheap() void {
    heap().setupheap();
}

/// Reset the heap to empty (between sessions).
pub fn resetheap() void {
    heap().resetheap();
}

/// Report (non-fatally) a failed allocation for `x`.
pub fn mallocfail(x: [*:0]const u8) void {
    _ = word.printErr("panic: cannot find enough free space for {s}\n", .{x});
    os.exit(1);
}

/// Panic and abort: outTerm of memory allocating `what`.
pub fn mallocPanic(what: [*:0]const u8) noreturn {
    mallocfail(what);
    unreachable;
}

/// Reset the per-evaluation GC counters.
pub fn resetgcstats() void {
    heap().cellcount = -heap().claims;
    heap().nogcs = 0;
    heap().hnogcs = 0;
    initclock();
}

/// Head (`hd`) of cell `x` without atom checks.
pub inline fn hCell(x: Word) Word {
    return heap().hCell(x);
}

/// Tail (`tl`) of cell `x` without atom checks.
pub inline fn tCell(x: Word) Word {
    return heap().tCell(x);
}

/// Allocate a cell with tag `t_val` and fields `(x, y)` — the core allocator.
pub inline fn make(t_val: word.NodeTag, x: Word, y: Word) Word {
    return heap().make(t_val, x, y);
}

/// Allocate two cells in bulk.
pub inline fn makeTwo(t1: word.NodeTag, x1: Word, y1: Word, t2: word.NodeTag, x2: Word, y2: Word, c1: *Word, c2: *Word) void {
    heap.makeTwo(t1, x1, y1, t2, x2, y2, c1, c2);
}

/// Run a mark-sweep garbage collection.
pub fn gc() void {
    heap.gc();
}

/// Intern name `p1`, returning its dictionary `ID` node (inserting if new).
pub fn stoId(p1: [*:0]const u8) Word {
    return make(.ID, cons(make(.STRCONS, strtab.strBits(strtab.table(), p1), word.NIL), word.undef_t), word.UNDEF);
}


const bigtostr = big.toDecimalList;
const SIGNBIT = 0x10000000;
const MAXDIGIT = 0x7fff;

/// The next digit cell of a bignum chain.
pub fn rest(x: Word) Word {
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
pub fn getsmallint(x: Word) Word {
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
    const name_word = if (fil_name) |n| @as(Word, strtab.strBits(strtab.table(), n)) else 0;
    return cons(cons(make(.FILEINFO, name_word, time_val), cons(share, word.NIL)), defs);
}

/// The type field of id `x`.
pub fn idType(x: Word) Word {
    return t(h(x));
}

/// The value field of id `x`.
pub fn idVal(x: Word) Word {
    return t(x);
}

/// The type class (algebraic/synonym/abstract/…) of type node `x`.
pub fn tClass(x: Word) Word {
    return h(t(theVal(x)));
}

/// The info field of type node `x`.
pub fn tInfo(x: Word) Word {
    return t(t(x));
}

/// Allocate a `CONSTRUCTOR` cell (tag `n`, fields `x`).
pub fn constructor(self: *Heap, n: Word, x: anytype) Word {
    const x_val: Word = switch (@TypeOf(x)) {
        Word => x,
        c_int, c_uint => @intCast(x),
        [*:0]const u8, [*:0]u8 => strtab.strBits(strtab.table(), x),
        else => @compileError("Unsupported type for constructor"),
    };
    return self.make(.CONSTRUCTOR, n, x_val);
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
pub fn isconstructor(self: Heap, x: Word) bool {
    return self.getTag(x) == .ID and isconstrname(getId(x));
}

/// Whether `x` names an ordinary variable.
pub fn isvariable(x: Word) bool {
    return getTag(x) == .ID and !isconstrname(getId(x));
}

/// Add id `x` to the current file's definition environment.
pub fn addtoenv(self: *Heap, x: Word) void {
    self.tp(self.h(self.files)).* = self.cons(x, self.t(self.h(self.files)));
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

/// Detect whether the current locale is UTF-8 (1/0).
pub fn utf8test() bool {
    var lang = os.getenv("LC_CTYPE");
    if (lang == null) {
        lang = os.getenv("LANG");
    }
    if (lang) |l| {
        if (os.strstr(l, "UTF-8") != null or
            os.strstr(l, "UTF8") != null or
            os.strstr(l, "utf-8") != null or
            os.strstr(l, "utf8") != null)
        {
            return true;
        }
    }
    return false;
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
