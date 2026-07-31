//! semantics/lower_prims.zig — trivial cell/type wrapper layer (docs/GoReady.md P4).

const word = @import("../graph/word.zig");
const strtab = @import("../graph/strtab.zig");
const os = @import("../os.zig");
const match = @import("match.zig");
const Word = i64;
const list_t = word.list_t;
const arrow_t = word.arrow_t;
const CMBASE = word.CMBASE;
const PLUS: Word = CMBASE + 54;
const ATOMLIMIT = word.ATOMLIMIT;
const heap_mod = @import("../graph/heap.zig");
const Heap = heap_mod.Heap;
const lex = @import("../parser/lex.zig");
const make = heap_mod.make;
const isconstrname = lex.isconstrname;

/// The standard-output `Stream` handle.
pub fn getStdout() ?*word.Stream {
    return os.stdout();
}

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

/// The head of an application spine (walk `hd` while it is an `AP`).
pub fn appHead(heap: *Heap, input_x: Word) Word {
    var x = input_x;
    while (getTag(heap, x) == .AP) {
        x = h(heap, x);
    }
    return x;
}

/// Allocate a `CONS` cell `(x . y)`.
pub fn cons(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .CONS, x, y);
}

/// Allocate a `PAIR` cell `(x . y)`.
pub fn pair(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .PAIR, x, y);
}

/// Allocate a `DATAPAIR` cell.
pub fn datapair(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .DATAPAIR, x, y);
}

/// Allocate a `CONSTRUCTOR` cell (tag `n`, fields `x`).
pub fn constructor(heap: *Heap, n: Word, x: Word) Word {
    return make(heap, .CONSTRUCTOR, n, x);
}

/// Allocate a `LAMBDA` cell `(x . y)`.
pub fn lambda(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .LAMBDA, x, y);
}

/// Allocate a `SHARE` cell (a shared / lazily-evaluated binding).
pub fn share(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .SHARE, x, y);
}

/// Allocate a `TRIES` cell (a chain of pattern-match alternatives).
pub fn tries(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .TRIES, x, y);
}

/// Allocate a `LET` cell.
pub fn let(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .LET, x, y);
}

/// Allocate a `LETREC` cell.
pub fn letrec(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .LETREC, x, y);
}

/// Allocate an application `(x y)`.
pub fn ap(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .AP, x, y);
}

/// Allocate `((x y) z)`.
pub fn ap2(heap: *Heap, x: Word, y: Word, z: Word) Word {
    return ap(heap, ap(heap, x, y), z);
}

/// Allocate `(((w x) y) z)`.
pub fn ap3(heap: *Heap, w: Word, x: Word, y: Word, z: Word) Word {
    return ap(heap, ap2(heap, w, x, y), z);
}

/// The interned name text of id `x`.
pub fn getId(heap: *Heap, x: Word) [:0]const u8 {
    return strtab.strOf(strtab.table(), h(heap, h(heap, h(heap, x))));
}

/// The definition-site field of id `x`.
pub fn idWho(heap: *Heap, x: Word) Word {
    return t(heap, h(heap, h(heap, x)));
}

/// Set the definition-site field of id `x`.
pub fn setIdWho(heap: *Heap, x: Word, value: Word) void {
    tp(heap, h(heap, h(heap, x))).* = value;
}

/// The type field of id `x`.
pub fn idType(heap: *Heap, x: Word) Word {
    return t(heap, h(heap, x));
}

/// The value field of id `x`.
pub fn idVal(heap: *Heap, x: Word) Word {
    return t(heap, x);
}

/// Set the type field of id `x`.
pub fn setIdType(heap: *Heap, x: Word, value: Word) void {
    tp(heap, h(heap, x)).* = value;
}

/// Set the value field of id `x`.
pub fn setIdVal(heap: *Heap, x: Word, value: Word) void {
    tp(heap, x).* = value;
}

/// Build a type descriptor cell `((arity . showfn) . (class . info))`.
pub fn makeTyp(heap: *Heap, arity: Word, showfn: Word, class: Word, info: Word) Word {
    return cons(heap, cons(heap, arity, showfn), cons(heap, class, info));
}

/// Add id `x` to the current file's definition environment.
pub fn addToEnv(heap: *Heap, x: Word) void {
    const current_file_defs = h(heap, heap.files);
    if (current_file_defs >= ATOMLIMIT) {
        tp(heap, current_file_defs).* = cons(heap, x, tp(heap, current_file_defs).*);
    }
}

/// Whether `x` names a data constructor.
pub fn isConstructor(heap: *Heap, x: Word) bool {
    return getTag(heap, x) == .ID and isconstrname(getId(heap, x));
}

/// Whether `x` names an ordinary variable.
pub fn isVariable(heap: *Heap, x: Word) bool {
    return getTag(heap, x) == .ID and !isconstrname(getId(heap, x));
}

/// Whether `x` is an `n+k` pattern.
pub fn isNPlusKPattern(heap: *Heap, x: Word) bool {
    return getTag(heap, x) == .AP and getTag(heap, h(heap, x)) == .AP and h(heap, h(heap, x)) == PLUS;
}

/// Whether a type node is a function (`->`) type.
pub fn isArrowType(heap: *Heap, x: Word) bool {
    return getTag(heap, x) == .AP and getTag(heap, h(heap, x)) == .AP and h(heap, h(heap, x)) == arrow_t;
}

/// Whether a type node is a list type.
pub fn isListType(heap: *Heap, x: Word) bool {
    return getTag(heap, x) == .AP and h(heap, x) == list_t;
}

/// Whether a type node is a type variable.
pub fn isTypeVariable(heap: *Heap, x: Word) bool {
    return getTag(heap, x) == .TVAR;
}

/// Whether a type node is a compound (application) type.
pub fn isCompoundType(heap: *Heap, x: Word) bool {
    return getTag(heap, x) == .AP;
}

/// Whether `x` is a char value.
pub fn isChar(x: Word) bool {
    return 0 <= x and x <= 255;
}

/// The arity recorded in a type descriptor.
pub fn typeArity(heap: *Heap, x: Word) Word {
    return h(heap, h(heap, t(heap, x)));
}

/// The `show` function recorded in a type descriptor.
pub fn typeShowFn(heap: *Heap, x: Word) Word {
    return t(heap, h(heap, t(heap, x)));
}

/// The class (algebraic/synonym/abstract) of a type descriptor.
pub fn typeClass(heap: *Heap, x: Word) Word {
    return h(heap, t(heap, t(heap, x)));
}

/// Set the class field of a type descriptor.
pub fn setTypeClass(heap: *Heap, x: Word, value: Word) void {
    hp(heap, t(heap, t(heap, x))).* = value;
}

/// The info field of a type descriptor.
pub fn typeInfo(heap: *Heap, x: Word) Word {
    return t(heap, t(heap, t(heap, x)));
}

/// Set the info field of a type descriptor.
pub fn setTypeInfo(heap: *Heap, x: Word, value: Word) void {
    tp(heap, t(heap, t(heap, x))).* = value;
}

/// The index of type variable `x`.
pub fn getTypeVariable(heap: *Heap, x: Word) Word {
    return t(heap, x);
}

/// Box index `i` (bare if small, else an `INT` cell).
pub fn mkindex(i: Word) Word {
    return if (word.fitsInByte(i)) i else make(heap_mod.heap(), .INT, i, 0);
}

/// The left-hand side of a definition cell `d`.
pub fn dlhs(heap: *Heap, d: Word) Word {
    return h(heap, d);
}

/// Set the left-hand side of a definition cell `d`.
pub fn setDlhs(heap: *Heap, d: Word, value: Word) void {
    hp(heap, d).* = value;
}

/// The value of a definition cell `d`.
pub fn dval(heap: *Heap, d: Word) Word {
    return t(heap, t(heap, d));
}

/// Set the value of a definition cell `d`.
pub fn setDval(heap: *Heap, d: Word, value: Word) void {
    tp(heap, t(heap, d)).* = value;
}
