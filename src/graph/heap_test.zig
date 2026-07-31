//! graph/heap_test.zig — inline test suite for heap.zig, moved to a
//! companion file for the Go port's <1000-line file ratchet
//! (docs/GO_PORT_PLAN.md P4). Same tests/names; reaches heap.zig through its
//! public API. Aggregated into the test build one-way (no import cycle).

const std = @import("std");
const word = @import("word.zig");
const strtab = @import("strtab.zig");
const combinator = @import("combinator.zig");
const rt = @import("../runtime/runtime_state.zig");
const config_state = @import("../session/config_state.zig");
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)
const Word = i64;
const ATOMLIMIT = word.ATOMLIMIT;
const NIL = word.NIL;

const heap_mod = @import("heap.zig");
const FileNode = heap_mod.FileNode;
const Heap = heap_mod.Heap;
const Identifier = heap_mod.Identifier;
const NodeRef = heap_mod.NodeRef;
const TOP = heap_mod.TOP;
const TypeRef = heap_mod.TypeRef;
const append1 = heap_mod.append1;
const badval = heap_mod.badval;
const cons = heap_mod.cons;
const constructor = heap_mod.constructor;
const dlhs = heap_mod.dlhs;
const dval = heap_mod.dval;
const filDefs = heap_mod.filDefs;
const filInodev = heap_mod.filInodev;
const filShare = heap_mod.filShare;
const filTime = heap_mod.filTime;
const gc = heap_mod.gc;
const getChar = heap_mod.getChar;
const getDbl = heap_mod.getDbl;
const getHere = heap_mod.getHere;
const getId = heap_mod.getId;
const getTag = heap_mod.getTag;
const getaka = heap_mod.getaka;
const getsmallint = heap_mod.getsmallint;
const h = heap_mod.h;
const hdsort = heap_mod.hdsort;
const heap = heap_mod.heap;
const hp = heap_mod.hp;
const idType = heap_mod.idType;
const idVal = heap_mod.idVal;
const idWho = heap_mod.idWho;
const isChar = heap_mod.isChar;
const isconstructor = heap_mod.isconstructor;
const isfreeid = heap_mod.isfreeid;
const isvariable = heap_mod.isvariable;
const make = heap_mod.make;
const makeFil = heap_mod.makeFil;
const nil = heap_mod.nil;
const resetheap = heap_mod.resetheap;
const reverse = heap_mod.reverse;
const sameFile = heap_mod.sameFile;
const setdbl = heap_mod.setdbl;
const shunt = heap_mod.shunt;
const size = heap_mod.size;
const stoChar = heap_mod.stoChar;
const stoDbl = heap_mod.stoDbl;
const stoId = heap_mod.stoId;
const stosmallint = heap_mod.stosmallint;
const t = heap_mod.t;
const tp = heap_mod.tp;
const tries = heap_mod.tries;

test "heap accessors: cons/make build cells that h/t/getTag read back" {
    tu.freshInterp();
    const heap_val = heap();
    const c = cons(heap_val, word.True, word.NIL);
    try std.testing.expectEqual(word.NodeTag.CONS, getTag(heap_val, c));
    try std.testing.expectEqual(@as(Word, word.True), h(heap_val, c));
    try std.testing.expectEqual(@as(Word, word.NIL), t(heap_val, c));
    // hp/tp expose the fields for in-place mutation.
    hp(heap_val, c).* = word.False;
    tp(heap_val, c).* = word.True;
    try std.testing.expectEqual(@as(Word, word.False), h(heap_val, c));
    try std.testing.expectEqual(@as(Word, word.True), t(heap_val, c));
    // make builds a cell with an arbitrary tag; setTag (on the singleton) rewrites it.
    const apnode = make(heap_val, .AP, word.I, word.NIL);
    try std.testing.expectEqual(word.NodeTag.AP, getTag(heap_val, apnode));
    heap_val.setTag(apnode, .CONS);
    try std.testing.expectEqual(word.NodeTag.CONS, getTag(heap_val, apnode));
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
        try std.testing.expectEqual(word.NodeTag.CONS, getTag(heap(), w));
        try std.testing.expectEqual(@mod(expected, 100), h(heap(), w));
        w = t(heap(), w);
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
    try std.testing.expectEqual(@as(Word, 1), h(heap(), before));
    try std.testing.expectEqual(@as(Word, 2), t(heap(), before));

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
    hp(heap(), before).* = 99;
    tp(heap(), before).* = 98;
    var i: Word = 0;
    while (i < 50) : (i += 1) {
        _ = heap().cons(0, 0);
    }

    heap().restore(&snap);

    try std.testing.expectEqual(@as(Word, 1), h(heap(), before));
    try std.testing.expectEqual(@as(Word, 2), t(heap(), before));
    try std.testing.expectEqual(top_before, heap().TOP());
    try std.testing.expectEqual(free_head_before, heap().free_head);
    try std.testing.expectEqual(cellcount_before, heap().cellcount);
    try std.testing.expectEqual(claims_before, heap().claims);
}
test "tries: builds a TRIES alternative-chain cell" {
    tu.freshInterp();
    const tr = tries(word.True, word.NIL);
    try std.testing.expectEqual(word.NodeTag.TRIES, getTag(heap(), tr));
    try std.testing.expectEqual(@as(Word, word.True), h(heap(), tr));
    try std.testing.expectEqual(@as(Word, word.NIL), t(heap(), tr));
}
test "stoChar / getChar / isChar: bare Latin-1 and wide UNICODE chars" {
    tu.freshInterp();
    // Latin-1: stored bare as the code point itself.
    try std.testing.expectEqual(@as(Word, 65), stoChar(65));
    try std.testing.expect(isChar(65));
    try std.testing.expectEqual(@as(Word, 65), getChar(65));
    // Wide: boxed in a UNICODE cell, but still a char that decodes back.
    const emoji = stoChar(0x1F600);
    try std.testing.expectEqual(word.NodeTag.UNICODE, getTag(heap(), emoji));
    try std.testing.expect(isChar(emoji));
    try std.testing.expectEqual(@as(Word, 0x1F600), getChar(emoji));
    // A combinator atom is not a char.
    try std.testing.expect(!isChar(word.S));
}
test "stoId/idWho/getId/getHere/getaka: identifier accessors" {
    tu.freshInterp();

    // stoId builds a plain id with no recorded "who" (definition-site/alias)
    // info -- idWho is NIL, so getHere/getaka fall back to the simple case.
    const plain = stoId("zzheap_getaka_plain");
    try std.testing.expectEqualStrings("zzheap_getaka_plain", getId(plain));
    try std.testing.expectEqual(@as(Word, word.NIL), idWho(plain));
    try std.testing.expectEqual(@as(Word, word.NIL), getHere(plain));
    try std.testing.expectEqualStrings("zzheap_getaka_plain", getaka(plain));

    // An id whose "who" field is a CONS (aka-name-holder . location): getHere
    // reads the location, getaka reads the alias name instead of the plain one.
    const aka_container = cons(heap(), strtab.strBits(strtab.table(), @as([*:0]const u8, "zzheap_aka")), word.NIL);
    const who_val = cons(heap(), aka_container, word.True); // word.True stands in for a location marker
    const name_holder = make(heap(), .STRCONS, strtab.strBits(strtab.table(), @as([*:0]const u8, "zzheap_getaka_aliased")), who_val);
    const aliased = make(heap(), .ID, cons(heap(), name_holder, word.undef_t), word.UNDEF);

    try std.testing.expectEqualStrings("zzheap_getaka_aliased", getId(aliased));
    try std.testing.expectEqual(who_val, idWho(aliased));
    try std.testing.expectEqual(@as(Word, word.True), getHere(aliased));
    try std.testing.expectEqualStrings("zzheap_aka", getaka(aliased));
}
test "append1: links y onto the tail of list x" {
    tu.freshInterp();
    // [True] with [False] linked on → True : False : NIL
    const x = cons(heap(), word.True, word.NIL);
    const y = cons(heap(), word.False, word.NIL);
    const r = append1(x, y);
    try std.testing.expectEqual(x, r); // mutates and returns x
    try std.testing.expectEqual(@as(Word, word.True), h(heap(), r));
    try std.testing.expectEqual(@as(Word, word.False), h(heap(), t(heap(), r)));
    try std.testing.expectEqual(@as(Word, word.NIL), t(heap(), t(heap(), r)));
    // appending onto nil just yields y
    try std.testing.expectEqual(y, append1(word.NIL, y));
}
test "hdsort: merge-sorts a list of (id . _) items by id name" {
    tu.freshInterp();
    const id_b = stoId("zzheap_hdsort_bbb");
    const id_a = stoId("zzheap_hdsort_aaa");
    const id_c = stoId("zzheap_hdsort_ccc");
    const item_b = cons(heap(), id_b, 0);
    const item_a = cons(heap(), id_a, 0);
    const item_c = cons(heap(), id_c, 0);
    const list = cons(heap(), item_c, cons(heap(), item_b, cons(heap(), item_a, word.NIL)));

    const sorted = hdsort(list);
    try std.testing.expectEqual(item_a, h(heap(), sorted));
    try std.testing.expectEqual(item_b, h(heap(), t(heap(), sorted)));
    try std.testing.expectEqual(item_c, h(heap(), t(heap(), t(heap(), sorted))));
    try std.testing.expectEqual(@as(Word, word.NIL), t(heap(), t(heap(), t(heap(), sorted))));

    try std.testing.expectEqual(@as(Word, word.NIL), hdsort(word.NIL));
    // A single-element list is returned unchanged.
    const single = cons(heap(), item_a, word.NIL);
    try std.testing.expectEqual(single, hdsort(single));
}
test "stoDbl / getDbl / setdbl: round-trip an f64 in a DOUBLE cell" {
    tu.freshInterp();
    const d = try stoDbl(3.14);
    try std.testing.expectEqual(word.NodeTag.DOUBLE, getTag(heap(), d));
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
test "stosmallint: boxes a signed small int as an INT cell" {
    tu.freshInterp();
    const a = stosmallint(42);
    try std.testing.expectEqual(word.NodeTag.INT, getTag(heap(), a));
    try std.testing.expectEqual(@as(Word, 42), getsmallint(a));
    try std.testing.expectEqual(@as(Word, -5), getsmallint(stosmallint(-5)));
}
test "dlhs / dval: definition-cell head and value accessors" {
    tu.freshInterp();
    // a def cell d = (lhs : (mid : val))
    const d = cons(heap(), word.True, cons(heap(), word.NIL, word.False));
    try std.testing.expectEqual(@as(Word, word.True), dlhs(d));
    try std.testing.expectEqual(@as(Word, word.False), dval(d));
}
test "makeFil/filTime/filShare/filDefs: file-record construction and accessors" {
    tu.freshInterp();
    const defs = cons(heap(), word.True, word.NIL);
    const fil = makeFil("zzheap_fil_test", 12345, 1, defs);
    try std.testing.expectEqual(@as(Word, 12345), filTime(fil));
    try std.testing.expectEqual(@as(Word, 1), filShare(fil));
    try std.testing.expectEqual(defs, filDefs(fil));

    // A null filename stores 0 rather than an interned strBits value.
    const anon = makeFil(null, 0, 0, word.NIL);
    try std.testing.expectEqual(@as(Word, 0), filTime(anon));
    try std.testing.expectEqual(@as(Word, 0), filShare(anon));
}
test "idType/idVal: an id cell's type and value fields" {
    tu.freshInterp();
    // idType(x) = t(h(x)); idVal(x) = t(x) -- an id cell's hd holds a
    // (name . type) pair (matching stoId's own construction), its tl the value.
    const type_holder = cons(heap(), 0, word.type_t);
    const id = cons(heap(), type_holder, word.True);
    try std.testing.expectEqual(@as(Word, word.type_t), idType(id));
    try std.testing.expectEqual(@as(Word, word.True), idVal(id));
}
test "constructor: builds a CONSTRUCTOR cell from Word/i32/C-string fields" {
    tu.freshInterp();

    const from_word = constructor(heap(), word.True, @as(Word, 77));
    try std.testing.expectEqual(word.NodeTag.CONSTRUCTOR, getTag(heap(), from_word));
    try std.testing.expectEqual(@as(Word, word.True), h(heap(), from_word));
    try std.testing.expectEqual(@as(Word, 77), t(heap(), from_word));

    const from_cint = constructor(heap(), word.True, @as(i32, 9));
    try std.testing.expectEqual(@as(Word, 9), t(heap(), from_cint));

    const from_str = constructor(heap(), word.True, @as([*:0]const u8, "zzheap_constructor_test"));
    try std.testing.expectEqualStrings("zzheap_constructor_test", strtab.strOf(strtab.table(), t(heap(), from_str)));
}
test "filInodev/sameFile: dev/ino identity comparison" {
    tu.freshInterp();
    // filInodev(fil) = t(t(h(fil))) -- build the (name . (share . inodev)) shape directly.
    const mk = struct {
        fn fil(dev: Word, ino: Word) Word {
            const inodev = cons(heap(), dev, ino);
            const share_holder = cons(heap(), 0, inodev);
            const name_holder = cons(heap(), 0, share_holder);
            return cons(heap(), name_holder, word.NIL);
        }
    }.fil;

    const a = mk(111, 222);
    const b = mk(111, 222);
    const c = mk(111, 333);
    try std.testing.expect(sameFile(a, b));
    try std.testing.expect(!sameFile(a, c));
}
test "badval: flags values outside the plausible heap range" {
    try std.testing.expect(badval(50)); // below the floor
    try std.testing.expect(badval(60_000_000)); // above the ceiling
    try std.testing.expect(!badval(1000)); // a plausible cell id
}
test "isfreeid/isconstructor/isvariable: identifier-kind predicates" {
    tu.freshInterp();

    // stoId builds a plain, undeclared id -- a %free candidate by construction.
    const free_id = stoId("zzheap_isfreeid_test");
    try std.testing.expect(isfreeid(free_id));

    // Capitalised name: a constructor, not a variable.
    const ctor_id = stoId("Zzheap_Isconstructor_Test");
    try std.testing.expect(isconstructor(heap().*, ctor_id));
    try std.testing.expect(!isvariable(ctor_id));

    // Lowercase name: a variable, not a constructor.
    const var_id = stoId("zzheap_isvariable_test");
    try std.testing.expect(!isconstructor(heap().*, var_id));
    try std.testing.expect(isvariable(var_id));

    // Neither predicate holds for a non-ID cell.
    const not_an_id = cons(heap(), word.True, word.NIL);
    try std.testing.expect(!isconstructor(heap().*, not_an_id));
    try std.testing.expect(!isvariable(not_an_id));
}
test "reverse: reverses a list" {
    tu.freshInterp();
    const l = cons(heap(), word.I, cons(heap(), word.K, cons(heap(), word.S, word.NIL)));
    const r = reverse(l);
    try std.testing.expectEqual(@as(Word, word.S), h(heap(), r));
    try std.testing.expectEqual(@as(Word, word.K), h(heap(), t(heap(), r)));
    try std.testing.expectEqual(@as(Word, word.I), h(heap(), t(heap(), t(heap(), r))));
    try std.testing.expectEqual(@as(Word, word.NIL), t(heap(), t(heap(), t(heap(), r))));
    try std.testing.expectEqual(@as(Word, word.NIL), reverse(word.NIL));
}
test "shunt: reverses x onto the front of y" {
    tu.freshInterp();
    const x = cons(heap(), word.I, cons(heap(), word.K, word.NIL));
    const y = cons(heap(), word.S, word.NIL);
    const r = shunt(x, y); // reverse [I,K] onto [S] → [K,I,S]
    try std.testing.expectEqual(@as(Word, word.K), h(heap(), r));
    try std.testing.expectEqual(@as(Word, word.I), h(heap(), t(heap(), r)));
    try std.testing.expectEqual(@as(Word, word.S), h(heap(), t(heap(), t(heap(), r))));
    try std.testing.expectEqual(@as(Word, word.NIL), t(heap(), t(heap(), t(heap(), r))));
}
test "size: counts the cells of a flat list" {
    tu.freshInterp();
    try std.testing.expectEqual(@as(Word, 0), size(word.NIL));
    const l = cons(heap(), stosmallint(1), cons(heap(), stosmallint(2), cons(heap(), stosmallint(3), word.NIL)));
    try std.testing.expectEqual(@as(Word, 3), size(l));
}
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
