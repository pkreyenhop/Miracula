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
const cs = compiler_state.cs;
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)

const heap_cells = @import("heap_cells.zig");
pub const Heap = heap_cells.Heap;
pub const Cell = heap_cells.Cell;
pub const heap = heap_cells.heap;
pub const bind = heap_cells.bind;
pub const mallocPanic = heap_cells.mallocPanic;
pub const mallocfail = heap_cells.mallocfail;

const Word = i64;

/// The value field of a type/definition cell.
pub inline fn theVal(x: Word) Word {
    return t(heap(), x);
}

/// The arity recorded in a type node.
pub inline fn tArity(x: Word) Word {
    return h(heap(), h(heap(), t(heap(), x)));
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

/// Head (`hd`) of cell `x`.
///
/// Tests: heap accessors: cons/make build cells that h/t/getTag read back
pub fn h(heap_ptr: *Heap, x: Word) Word {
    return heap_ptr.h(x);
}

/// Pointer to the head field of cell `x` (for in-place mutation).
pub fn hp(heap_ptr: *Heap, x: Word) *Word {
    return heap_ptr.hp(x);
}

/// Tail (`tl`) of cell `x`.
pub fn t(heap_ptr: *Heap, x: Word) Word {
    return heap_ptr.t(x);
}

/// Pointer to the tail field of cell `x` (for in-place mutation).
pub fn tp(heap_ptr: *Heap, x: Word) *Word {
    return heap_ptr.tp(x);
}

/// The node tag of cell `x`.
pub fn getTag(heap_ptr: *Heap, x: Word) word.NodeTag {
    return heap_ptr.getTag(x);
}

/// Allocate a `CONS` cell `(x . y)`.
///
/// Tests: heap accessors: cons/make build cells that h/t/getTag read back
pub fn cons(heap_ptr: *Heap, x: Word, y: Word) Word {
    return heap_ptr.cons(x, y);
}

/// Allocate a `TRIES` cell `(x . y)` (a pattern-match alternative chain).
///
/// Tests: tries: builds a TRIES alternative-chain cell
///
/// Tests: tries: builds a TRIES alternative-chain cell
pub fn tries(x: Word, y: Word) Word {
    return make(heap(), .TRIES, x, y);
}

/// The 'who' (definition-site) field of id `x`.
pub fn idWho(x: Word) Word {
    return t(heap(), h(heap(), h(heap(), x)));
}

/// The interned name text of id `x`.
pub fn getId(x: Word) [:0]const u8 {
    return strtab.strOf(strtab.table(), h(heap(), h(heap(), h(heap(), x))));
}

/// The filename of file-record `fil`, or null when absent.
///
/// The single file-name accessor: callers that want the empty string for an absent
/// name use `getFil(fil) orelse ""` (matches `strtab.strOf(strtab.table(), 0)`).
pub fn getFil(fil: Word) ?[:0]const u8 {
    const val = h(heap(), h(heap(), h(heap(), fil)));
    if (val == 0) return null;
    return strtab.strOf(strtab.table(), val);
}

/// Box char `ch`: bare Latin-1, or a `UNICODE` cell for wider code points.
///
/// Tests: stoChar / getChar / isChar: bare Latin-1 and wide UNICODE chars
pub fn stoChar(ch: Word) Word {
    return if (word.fitsInByte(ch)) ch else make(heap(), .UNICODE, ch, 0);
}

/// The code point of char value `x`.
///
/// Tests: stoChar / getChar / isChar: bare Latin-1 and wide UNICODE chars
pub fn getChar(x: Word) Word {
    switch (word.classify(x)) {
        .imm => |c| return c, // bare Latin-1 code point
        .ref => if (getTag(heap(), x) == .UNICODE) return h(heap(), x), // UNICODE cell: code point in hd
        .atom => {},
    }
    std.debug.print("impossible event in getChar(x), tag[x]=={d}\n", .{heap().getTag(x)});
    std.process.exit(1);
}

/// Whether `x` is a char value (1/0).
///
/// Tests: stoChar / getChar / isChar: bare Latin-1 and wide UNICODE chars
pub fn isChar(x: Word) bool {
    return switch (word.classify(x)) {
        .imm => true, // bare Latin-1 char
        .ref => getTag(heap(), x) == .UNICODE, // wide char cell
        .atom => false, // a combinator/named atom is not a char
    };
}

/// The source location (`HERE`) recorded for id `x`.
pub fn getHere(x: Word) Word {
    const y = idWho(x);
    return if (getTag(heap(), y) == .CONS) t(heap(), y) else y;
}

/// The original ('also known as') name of id `x` (before any alias).
pub fn getaka(x: Word) [:0]const u8 {
    const y = idWho(x);
    return if (getTag(heap(), y) != .CONS) getId(x) else strtab.strOf(strtab.table(), h(heap(), h(heap(), y)));
}

// Tests: stoId/idWho/getId/getHere/getaka: identifier construction and
// name/location/alias accessors

/// Append a single element to the end of list `x`.
///
/// Tests: append1: links y onto the tail of list x
pub fn append1(x: Word, y: Word) Word {
    var x1 = x;
    if (x1 == nil()) return y;
    while (t(heap(), x1) != nil()) x1 = t(heap(), x1);
    tp(heap(), x1).* = y;
    return x;
}

/// Sort list `input` by cell head (merge sort).
pub fn hdsort(input: Word) Word {
    var x = input;
    var a: Word = nil();
    var b: Word = nil();
    if (x == nil()) return nil();
    if (t(heap(), x) == nil()) return x;
    while (x != nil()) {
        const hold = a;
        a = cons(heap(), h(heap(), x), b);
        b = hold;
        x = t(heap(), x);
    }
    a = hdsort(a);
    b = hdsort(b);
    while (a != nil() and b != nil()) {
        if (std.mem.order(u8, getId(h(heap(), h(heap(), a))), getId(h(heap(), h(heap(), b)))) == .lt) {
            x = cons(heap(), h(heap(), a), x);
            a = t(heap(), a);
        } else {
            x = cons(heap(), h(heap(), b), x);
            b = t(heap(), b);
        }
    }
    if (a == nil()) a = b;
    while (a != nil()) {
        x = cons(heap(), h(heap(), a), x);
        a = t(heap(), a);
    }
    return reverse(x);
}

// Tests: hdsort: merge sort by cell head

/// The `f64` stored in `DOUBLE` cell `x`.
///
/// Tests: stoDbl / getDbl / setdbl: round-trip an f64 in a DOUBLE cell
pub fn getDbl(x: Word) f64 {
    var r: fpdatum = undefined;
    if (comptime @sizeOf(Word) == 4) {
        r.bits.left = h(heap(), x);
        r.bits.right = t(heap(), x);
    } else {
        r.bits = h(heap(), x);
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
        return make(heap(), .DOUBLE, r.bits.left, r.bits.right);
    } else {
        return make(heap(), .DOUBLE, r.bits, 0);
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
        hp(heap(), x).* = r.bits.left;
        tp(heap(), x).* = r.bits.right;
    } else {
        hp(heap(), x).* = r.bits;
        tp(heap(), x).* = 0;
    }
}

/// The `NIL` sentinel.
pub fn nil() Word {
    return 306 + 138;
}

// (Dead module duplicates of `Heap.SPACE`/`Heap.listp` removed — the live
// copies are the struct fields, accessed via `self.SPACE`/`self.listp`.)

var init_clock: *const fn () void = struct {
    fn noop() void {}
}.noop;

pub fn bindInitClock(callback: *const fn () void) void {
    init_clock = callback;
}
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

/// Reset the per-evaluation GC counters.
pub fn resetgcstats() void {
    heap().cellcount = -heap().claims;
    heap().nogcs = 0;
    heap().hnogcs = 0;
    init_clock();
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
pub inline fn make(heap_ptr: *Heap, t_val: word.NodeTag, x: Word, y: Word) Word {
    return heap_ptr.make(t_val, x, y);
}

/// Run a mark-sweep garbage collection.
pub fn gc() void {
    heap().gc();
}

/// Intern name `p1`, returning its dictionary `ID` node (inserting if new).
pub fn stoId(p1: [*:0]const u8) Word {
    return make(heap(), .ID, cons(heap(), make(heap(), .STRCONS, strtab.strBitsZ(strtab.table(), p1), word.NIL), word.undef_t), word.UNDEF);
}

const SIGNBIT = 0x10000000;
const MAXDIGIT = 0x7fff;

/// The next digit cell of a bignum chain.
pub fn rest(x: Word) Word {
    return t(heap(), x);
}

/// The raw head digit of a bignum cell.
fn digit(x: Word) Word {
    return h(heap(), x);
}

/// The head digit of a bignum cell with the sign bit masked off.
fn digit0(x: Word) Word {
    return h(heap(), x) & MAXDIGIT;
}

/// Decode a single-cell bignum to a signed `Word`.
pub fn getsmallint(x: Word) Word {
    return if ((h(heap(), x) & SIGNBIT) != 0) -digit0(x) else digit(x);
}

/// Box small int `x`: bare, or as an `INT` cell if it doesn't fit.
///
/// Tests: stosmallint: boxes a signed small int as an INT cell
pub fn stosmallint(x: Word) Word {
    const val = if (x < 0) SIGNBIT | @as(Word, @intCast(-x)) else x;
    return make(heap(), .INT, val, 0);
}

/// The left-hand side (head) of a definition cell `d`.
///
/// Tests: dlhs / dval: definition-cell head and value accessors
pub inline fn dlhs(d: Word) Word {
    return h(heap(), d);
}

/// The value of a definition cell `d` (`t(t(d))`).
///
/// Tests: dlhs / dval: definition-cell head and value accessors
pub inline fn dval(d: Word) Word {
    return t(heap(), t(heap(), d));
}

/// The mtime stored in file record `fil`.
pub fn filTime(fil: Word) Word {
    return t(heap(), h(heap(), h(heap(), fil)));
}

/// The share/include flag of file record `fil`.
pub fn filShare(fil: Word) Word {
    return h(heap(), t(heap(), h(heap(), fil)));
}

/// The definitions list of file record `fil`.
pub fn filDefs(fil: Word) Word {
    return t(heap(), fil);
}

/// Build a file record `(name, mtime, share, defs)`.
pub fn makeFil(fil_name: ?[*:0]const u8, time_val: Word, share: Word, defs: Word) Word {
    const name_word = if (fil_name) |n| @as(Word, strtab.strBitsZ(strtab.table(), n)) else 0;
    return cons(heap(), cons(heap(), make(heap(), .FILEINFO, name_word, time_val), cons(heap(), share, word.NIL)), defs);
}

// Tests: makeFil/filTime/filShare/filDefs: file-record construction and accessors

/// The type field of id `x`.
pub fn idType(x: Word) Word {
    return t(heap(), h(heap(), x));
}

/// The value field of id `x`.
pub fn idVal(x: Word) Word {
    return t(heap(), x);
}

// Tests: idType/idVal: an id cell's type and value fields

/// The type class (algebraic/synonym/abstract/…) of type node `x`.
pub fn tClass(x: Word) Word {
    return h(heap(), t(heap(), theVal(x)));
}

/// The info field of type node `x`.
pub fn tInfo(x: Word) Word {
    return t(heap(), t(heap(), x));
}

/// Allocate a `CONSTRUCTOR` cell (tag `n`, fields `x`).
pub fn constructor(self: *Heap, n: Word, x: Word) Word {
    return self.make(.CONSTRUCTOR, n, x);
}

pub fn constructorInt(self: *Heap, n: Word, x: i32) Word {
    return constructor(self, n, @intCast(x));
}

pub fn constructorName(self: *Heap, n: Word, x: [*:0]const u8) Word {
    return constructor(self, n, strtab.strBitsZ(strtab.table(), x));
}

// Tests: constructor: builds a CONSTRUCTOR cell from a Word, C-int, or C string

// Relocated heap/node domain metadata accessors and lifecycle utilities
/// The `(dev . ino)` filesystem identity of file record `fil`.
pub fn filInodev(fil: Word) Word {
    return t(heap(), t(heap(), h(heap(), fil)));
}

/// Whether two file records name the same inode.
pub fn sameFile(x: Word, y: Word) bool {
    const ix = filInodev(x);
    const iy = filInodev(y);
    return h(heap(), ix) == h(heap(), iy) and t(heap(), ix) == t(heap(), iy);
}

// Tests: filInodev/sameFile: filesystem-identity comparison of file records

/// Whether `x` is a bad/error sentinel value.
///
/// Tests: badval: flags values outside the plausible heap range
pub fn badval(x: Word) bool {
    return x < 100 or x > 50000000;
}

/// Whether id `x` is a `%free` identifier.
pub fn isfreeid(x: Word) bool {
    return idType(x) == word.undef_t and idVal(x) == word.UNDEF;
}

fn isconstrname(input: [*:0]const u8) bool {
    var name = input;
    if (name[0] == '$') name += 1;
    return std.ascii.isUpper(name[0]);
}
/// Whether `x` names a data constructor.
pub fn isconstructor(self: Heap, x: Word) bool {
    return self.getTag(x) == .ID and isconstrname(getId(x));
}

/// Whether `x` names an ordinary variable.
pub fn isvariable(x: Word) bool {
    return getTag(heap(), x) == .ID and !isconstrname(getId(x));
}

// Tests: isfreeid/isconstructor/isvariable: identifier-kind predicates

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
    var x_root = heap().roots.root(rt.allocator, &x);
    defer x_root.deinit();
    var y_root = heap().roots.root(rt.allocator, &y);
    defer y_root.deinit();
    while (x != NIL) {
        y = cons(heap(), h(heap(), x), y);
        x = t(heap(), x);
    }
    return y;
}

/// Reverse `x` onto the front of `y` (shunt / reverse-append).
///
/// Tests: shunt: reverses x onto the front of y
pub fn shunt(input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    var x_root = heap().roots.root(rt.allocator, &x);
    defer x_root.deinit();
    var y_root = heap().roots.root(rt.allocator, &y);
    defer y_root.deinit();
    while (x != NIL) {
        y = cons(heap(), h(heap(), x), y);
        x = t(heap(), x);
    }
    return y;
}

/// The length of list `input`.
///
/// Tests: size: counts the cells of a flat list
pub fn size(input: Word) Word {
    var x = input;
    var s: Word = 0;
    while (getTag(heap(), x) == .CONS or getTag(heap(), x) == .AP) {
        s += 1 + size(h(heap(), x));
        x = t(heap(), x);
    }
    return s;
}

/// Detect whether the current locale is UTF-8 (1/0).
pub fn utf8test() bool {
    const lang = std.process.Environ.getPosix(rt.environ, "LC_CTYPE") orelse
        std.process.Environ.getPosix(rt.environ, "LANG") orelse return false;
    return std.mem.indexOf(u8, lang, "UTF-8") != null or
        std.mem.indexOf(u8, lang, "UTF8") != null or
        std.mem.indexOf(u8, lang, "utf-8") != null or
        std.mem.indexOf(u8, lang, "utf8") != null;
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
