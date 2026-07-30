//! graph/heap_cells.zig — the cell arena + GC state (`Heap`/`Cell` structs
//! and the `heap()` singleton) split out of heap.zig for the Go port's
//! <1000-line file ratchet (docs/GO_PORT_PLAN.md P4). heap.zig keeps the
//! free-function accessor API and re-exports these; one-way heap -> heap_cells.

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
const big_fmt = @import("bignum_fmt.zig");
const reduce = @import("../eval/reduce_rt.zig");
const os = @import("../os.zig");
const setup = @import("../compiler/setup.zig");
const cs = compiler_state.cs;
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)
const Word = i64;
const ATOMLIMIT = word.ATOMLIMIT;
const NIL = word.NIL;
const NILS = word.NILS;
const outstats = reduce.outstats;
const initclock = reduce.initclock;
const hashsize = word.hashsize;
const bigtostr = big_fmt.toDecimalList;
const SIGNBIT = 0x10000000;
const MAXDIGIT = 0x7fff;
const isconstrname = lex.isconstrname;

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
    /// docs/GO_PORT_PLAN.md; set once during `miraSetup`, never
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
    /// interrupted or simply finishes (Phase 3, docs/GO_PORT_PLAN.md).
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
            // GO_PORT_PLAN.md Phase 1 step 6): every ID node it references
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

            // The type reference of an ID cell (equivalent to `Identifier.typ()`
            // / `idType(x)` = `t(heap(), h(heap(), x))`, written via `self`
            // methods so `validate` stays self-contained — it lives with the
            // `Heap` struct in `heap_cells.zig`, below the domain-type layer).
            if (tag == .ID) {
                const t_val = self.t(self.h(x));
                if (t_val >= ATOMLIMIT and t_val >= top_limit) {
                    std.debug.panic("heap.validate: ID cell {d} has invalid type reference {d}", .{ x, t_val });
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

/// Mark `x` reachable (GC). A free-function adapter to the singleton's
/// method, matching `mark`'s signature to what `reducer/spine.zig`'s
/// `markAllRoots` expects (a plain `fn (Word) void`, no bound receiver) —
/// see `Heap.bases`, the only caller.
fn markRoot(x: Word) void {
    heap().mark(x);
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
