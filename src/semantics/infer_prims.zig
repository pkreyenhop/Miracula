//! semantics/infer_prims.zig — trivial cell/type wrappers (docs/GO_PORT_PLAN.md P4).

const word = @import("../graph/word.zig");
const strtab = @import("../graph/strtab.zig");
const os = @import("../os.zig");
const heap_mod = @import("../graph/heap.zig");
const Heap = heap_mod.Heap;
const Word = word.Word;
const make = heap_mod.make;
const lex_mod = @import("../parser/lex.zig");
const isconstrname = lex_mod.isconstrname;
const list_t: Word = 4;
const comma_t: Word = 5;
const arrow_t: Word = 6;
const void_t: Word = 7;

/// The node tag of cell `x`.
pub inline fn getTag(heap: *Heap, x: Word) word.NodeTag {
    return heap.getTag(x);
}

/// Head (`hd`) of cell `x`.
pub fn h(heap: *Heap, x: Word) Word {
    return heap.h(x);
}

/// Pointer to the head field of cell `x`.
pub fn hp(heap: *Heap, x: Word) *Word {
    return heap.hp(x);
}

/// Tail (`tl`) of cell `x`.
pub fn t(heap: *Heap, x: Word) Word {
    return heap.t(x);
}

/// Pointer to the tail field of cell `x`.
pub fn tp(heap: *Heap, x: Word) *Word {
    return heap.tp(x);
}

/// Allocate a `CONS` cell `(x . y)`.
pub fn cons(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .CONS, x, y);
}

/// The type field of id `x`.
pub fn idType(heap: *Heap, x: Word) Word {
    return t(heap, h(heap, x));
}

/// Whether a type node is a compound (application) type.
pub fn isCompoundType(heap: *Heap, type_node: Word) bool {
    return getTag(heap, type_node) == .AP;
}

/// Whether a type node is a type variable.
pub fn isVarType(heap: *Heap, type_node: Word) bool {
    return getTag(heap, type_node) == .TVAR;
}

/// The arity stored in a type node.
pub fn tArity(heap: *Heap, x: Word) Word {
    return h(heap, h(heap, t(heap, x)));
}

/// The type class of a type node.
pub fn tClass(heap: *Heap, x: Word) Word {
    return h(heap, t(heap, t(heap, x)));
}

/// The info field of a type node.
pub fn tInfo(heap: *Heap, x: Word) Word {
    return t(heap, t(heap, t(heap, x)));
}

/// The `show` function recorded for a type node.
/// The value field of id `x`.
pub fn idVal(heap: *Heap, x: Word) Word {
    return t(heap, x);
}

/// The definition-site field of id `x`.
pub fn idWho(heap: *Heap, x: Word) Word {
    return t(heap, h(heap, h(heap, x)));
}

/// The interned name text of id `x`.
pub fn getId(heap: *Heap, x: Word) [*:0]const u8 {
    return strtab.strOf(strtab.table(), h(heap, h(heap, h(heap, x))));
}

/// Allocate an application cell `(x y)`.
pub fn ap(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .AP, x, y);
}

/// The value (tail) of a private-name node.
pub fn pnVal(heap: *Heap, x: Word) Word {
    return t(heap, x);
}

/// The standard-output `Stream` handle.
pub fn getStdout() ?*word.Stream {
    const T = @TypeOf(os.stdout);
    if (comptime @typeInfo(T) == .@"fn") {
        return os.stdout();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return os.stdout();
    } else {
        return os.stdout;
    }
}

/// Whether `x` names a data constructor.
pub fn isConstructor(heap: *Heap, x: Word) bool {
    return getTag(heap, x) == .ID and isconstrname(getId(heap, x));
}

/// The value field of a type/definition cell.
pub fn theVal(heap: *Heap, x: Word) Word {
    return t(heap, x);
}

/// Allocate `((x y) z)`.
pub fn ap2(heap: *Heap, x: Word, y: Word, z: Word) Word {
    return ap(heap, ap(heap, x, y), z);
}

/// Build a function type `a -> b`.
pub fn tf(heap: *Heap, a: Word, b: Word) Word {
    return ap2(heap, arrow_t, a, b);
}

/// Build the function type `a -> b -> c`.
pub fn tf2(heap: *Heap, a: Word, b: Word, c_param: Word) Word {
    return tf(heap, a, tf(heap, b, c_param));
}

/// Build the function type `a -> b -> c -> d`.
pub fn tf3(heap: *Heap, a: Word, b: Word, c_param: Word, d: Word) Word {
    return tf(heap, a, tf2(heap, b, c_param, d));
}

/// Build the function type `a -> b -> c -> d -> e`.
pub fn tf4(heap: *Heap, a: Word, b: Word, c_param: Word, d: Word, e: Word) Word {
    return tf(heap, a, tf3(heap, b, c_param, d, e));
}

/// Build the list type `[a]`.
pub fn lt(heap: *Heap, a: Word) Word {
    return ap(heap, list_t, a);
}

/// Build a pair (tuple) type `(x, y)`.
pub fn pairType(heap: *Heap, x: Word, y: Word) Word {
    return ap2(heap, comma_t, x, ap2(heap, comma_t, y, void_t));
}

/// The left-hand side (head) of a definition cell `d`.
pub fn dlhs(heap: *Heap, d: Word) Word {
    return h(heap, d);
}

/// The type field of a definition cell `d`.
pub fn dtyp(heap: *Heap, d: Word) Word {
    return h(heap, t(heap, d));
}

/// The value field of a definition cell `d`.
pub fn dval(heap: *Heap, d: Word) Word {
    return t(heap, t(heap, d));
}
