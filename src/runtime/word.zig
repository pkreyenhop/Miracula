//! word.zig — the leaf vocabulary of the interpreter: the `Word` value model,
//! every numeric constant (cell tags, combinator/token codes, type codes,
//! `XBASE` dump markers), and a self-contained libc-style runtime (C-string
//! helpers, a pooled `FILE` with `printf`/`fopen`/`getc`/… and the ctype
//! predicates). It has no allocator dependency, so everything else can import it
//! freely. String-*handle* accessors live in `strtab.zig`, not here.

const std = @import("std");

/// The interpreter's universal machine word — a tagged graph value: a bare
/// immediate (char/small int), an atom code (token/combinator/named atom), or a
/// heap-cell handle. Native 64-bit (R4.5 retired the old `c_long`).
pub const Word = i64;
/// A Unicode code point, as carried by the char / `UNICODE`-cell paths.
pub const Unicode = c_ulong;

/// Base of the combinator / named-atom code range: combinator code `n` is
/// `CMBASE + n`, and its printed name is `combinator.cmbnms[n]`.
pub const CMBASE: Word = 306;

// Sentinel values and limits
/// The empty list `[]` — also the universal list terminator.
pub const NIL: Word = CMBASE + 138;
/// A distinct nil sentinel used internally alongside [NIL].
pub const NILS: Word = CMBASE + 139;
/// The undefined value: an unbound identifier or unfilled placeholder.
pub const UNDEF: Word = CMBASE + 140;
/// First heap-cell handle. A `Word` `>= ATOMLIMIT` is a cell; below it is an
/// atom (see [isAtom]).
pub const ATOMLIMIT: Word = CMBASE + 141;
/// Layout sentinel: the offside-rule column marker the lexer injects.
pub const OFFSIDE: Word = 270;

/// A heap-graph reference: a `Word` that denotes a node — a named atom
/// (`nil`/`undef`/`nils`) or a heap cell (`_`) — as opposed to an immediate
/// char/int value. Introduced in R4 to make the handle/immediate distinction
/// explicit at boundaries; convert with `.w()` / `Ref.of()`.
pub const Ref = enum(Word) {
    nil = NIL,
    undef = UNDEF,
    nils = NILS,
    _,
    /// The raw `Word` value of this reference (`@intFromEnum`).
    pub inline fn w(self: Ref) Word {
        return @intFromEnum(self);
    }
    /// Wrap a raw `Word` `x` as a `Ref` (`@enumFromInt`).
    pub inline fn of(x: Word) Ref {
        return @enumFromInt(x);
    }
};

test "Ref.w / Ref.of: round-trip a Word through the handle enum" {
    try std.testing.expectEqual(@as(Word, NIL), Ref.nil.w());
    try std.testing.expectEqual(Ref.nil, Ref.of(NIL));
    const r = Ref.of(ATOMLIMIT + 5);
    try std.testing.expectEqual(@as(Word, ATOMLIMIT + 5), r.w());
}

/// True when `x` is an atom (combinator, char, token, or named atom) — i.e. it
/// is below `ATOMLIMIT` and therefore has no hd/tl, rather than being a heap
/// cell. Replaces the bare `x < ATOMLIMIT` magic-threshold checks (R4).
///
/// Tests: isAtom: true below ATOMLIMIT (atoms/chars), false for heap cells
pub inline fn isAtom(x: Word) bool {
    return x < ATOMLIMIT;
}

test "isAtom: true below ATOMLIMIT (atoms/chars), false for heap cells" {
    try std.testing.expect(isAtom(0)); // a bare immediate
    try std.testing.expect(isAtom(S)); // a combinator atom
    try std.testing.expect(isAtom(ATOMLIMIT - 1));
    try std.testing.expect(!isAtom(ATOMLIMIT)); // first heap-cell handle
    try std.testing.expect(!isAtom(ATOMLIMIT + 1000));
}

/// True when `x` is small enough to be stored bare in a single byte rather than
/// boxed in a heap cell — chars below this are bare Latin-1 atoms (else a
/// UNICODE cell), small ints below this are bare (else an INT cell). Replaces
/// the bare `x < 256` magic-threshold checks (R4).
///
/// Tests: fitsInByte: true iff the value is storable bare in [0,256)
pub inline fn fitsInByte(x: Word) bool {
    return x < 256;
}

test "fitsInByte: true iff the value is storable bare in [0,256)" {
    try std.testing.expect(fitsInByte(0));
    try std.testing.expect(fitsInByte(255));
    try std.testing.expect(!fitsInByte(256));
}

/// True when `x` is a valid char value in the bare Latin-1 range [0, 256).
///
/// Tests: isLatin1Char: only the bare Latin-1 range [0,256)
pub inline fn isLatin1Char(x: Word) bool {
    return 0 <= x and x < 256;
}

test "isLatin1Char: only the bare Latin-1 range [0,256)" {
    try std.testing.expect(isLatin1Char(0));
    try std.testing.expect(isLatin1Char(255));
    try std.testing.expect(!isLatin1Char(256));
    try std.testing.expect(!isLatin1Char(-1));
}

/// The role of a `Word`, recovered from its numeric range — the typed value
/// seam for Track B2 (re-scoped: option *a*). This is the explicit replacement
/// for the scattered `isAtom` / `fitsInByte` / `isLatin1Char` range tests:
/// `classify` once and `switch` on the result, instead of chaining threshold
/// comparisons at each read site.
///
/// Note the representation deliberately cannot tell a Latin-1 *char* from a
/// small-int / index immediate — both are bare `0..255` and which one a value
/// is is fixed by Miranda's type system at compile time, not at runtime — so
/// both classify as `.imm`. Numbers proper are boxed (`INT`/`DOUBLE` cells) and
/// therefore appear as `.ref`; inspect the cell tag for the concrete kind.
pub const Value = union(enum) {
    /// A bare immediate in `0..255`: a Latin-1 char or a small-int / index.
    imm: u8,
    /// A combinator / token / named atom (`256 <= x < ATOMLIMIT`).
    atom: Word,
    /// A heap-cell handle (`x >= ATOMLIMIT`); read its tag for the cell kind.
    ref: Ref,
};

/// Classify a clean, non-negative `Word` by its immediate role. Marked spine
/// words and sentinels (negative) are not values — mask them off first.
///
/// Tests: classify maps Words to their value role
pub inline fn classify(x: Word) Value {
    if (x >= ATOMLIMIT) return .{ .ref = Ref.of(x) };
    if (isLatin1Char(x)) return .{ .imm = @intCast(x) };
    return .{ .atom = x };
}

test "classify maps Words to their value role" {
    // Bare immediates (0..255): chars / small-ints / indices.
    try std.testing.expectEqual(Value{ .imm = 0 }, classify(0));
    try std.testing.expectEqual(Value{ .imm = 65 }, classify(65)); // 'A' or int 65
    try std.testing.expectEqual(Value{ .imm = 255 }, classify(255));

    // Atoms: tokens / combinators / named atoms (256 .. ATOMLIMIT).
    try std.testing.expectEqual(Value{ .atom = 256 }, classify(256));
    try std.testing.expectEqual(Value{ .atom = S }, classify(S));
    try std.testing.expectEqual(Value{ .atom = NIL }, classify(NIL));
    try std.testing.expectEqual(Value{ .atom = ATOMLIMIT - 1 }, classify(ATOMLIMIT - 1));

    // Refs: heap-cell handles (>= ATOMLIMIT).
    try std.testing.expectEqual(Value{ .ref = Ref.of(ATOMLIMIT) }, classify(ATOMLIMIT));
    try std.testing.expectEqual(Value{ .ref = Ref.of(ATOMLIMIT + 1000) }, classify(ATOMLIMIT + 1000));
}

// Lexer / parser token codes (Miranda grammar terminals, 257..305). These are
// the values `yylex` returns; the parser dispatches on them.

/// Token: a `$$`-style value / evaluation request.
pub const VALUE: Word = 257;
/// Token: an evaluate-expression request.
pub const EVAL: Word = 258;
/// Token: the `where` keyword.
pub const WHERE: Word = 259;
/// Token: the `if` keyword (guard).
pub const IF: Word = 260;
/// Token: the `..` "to" marker in an arithmetic sequence.
pub const TO: Word = 261;
/// Token: `<-` (generator arrow in a list comprehension).
pub const LEFTARROW: Word = 262;
/// Token: `::` (type-signature separator).
pub const COLONCOLON: Word = 263;
/// Token: `::=` (algebraic type definition).
pub const COLON2EQ: Word = 264;
/// Token: a type variable, e.g. `*a`.
pub const TYPEVAR: Word = 265;
/// Token: a lowercase identifier.
pub const NAME: Word = 266;
/// Token: a constructor / uppercase identifier.
pub const CNAME: Word = 267;
/// Token: a literal constant (number / char / string).
pub const CONST: Word = 268;
/// Token: `$$` (the implicit-argument symbol).
pub const DOLLARS: Word = 269;
/// Token: the offside `=` of an `otherwise`/else guard branch.
pub const ELSEQ: Word = 271;
/// Token: the `abstype` keyword.
pub const ABSTYPE: Word = 272;
/// Token: the `with` keyword (abstype signature block).
pub const WITH: Word = 273;
/// Token: a `%diagnostic` directive.
pub const DIAG: Word = 274;
/// Token: `==` (type-synonym definition).
pub const EQEQ: Word = 275;
/// Token: the `%free` directive.
pub const FREE: Word = 276;
/// Token: the `%include` directive.
pub const INCLUDE: Word = 277;
/// Token: the `%export` directive.
pub const EXPORT: Word = 278;
/// Token: the `type` keyword.
pub const TYPE: Word = 279;
/// Token: the `otherwise` keyword.
pub const OTHERWISE: Word = 280;
/// Token: the `show` directive symbol.
pub const SHOWSYM: Word = 281;
/// Token: a file pathname (after a directive).
pub const PATHNAME: Word = 282;
/// Token: the `%bnf` grammar directive.
pub const BNF: Word = 283;
/// Token: the `%lex` lexer directive.
pub const LEX: Word = 284;
/// Token: end of a directive section.
pub const ENDIR: Word = 285;
/// Token: the BNF `error` symbol.
pub const ERRORSY: Word = 286;
/// Token: the BNF `end` symbol.
pub const ENDSY: Word = 287;
/// Token: the BNF `empty` symbol.
pub const EMPTYSY: Word = 288;
/// Token: the `readvals` symbol.
pub const READVALSY: Word = 289;
/// Token: a lexical (`%lex`) definition.
pub const LEXDEF: Word = 290;
/// Token: a lexer character class `[...]`.
pub const CHARCLASS: Word = 291;
/// Token: a negated lexer character class `[^...]`.
pub const ANTICHARCLASS: Word = 292;
/// Token: the start of a lexer block.
pub const LBEGIN: Word = 293;
/// Token: `->` (function-type arrow).
pub const ARROW: Word = 294;
/// Token: `++` (list append).
pub const PLUSPLUS: Word = 295;
/// Token: `--` (list difference).
pub const MINUSMINUS: Word = 296;
/// Token: `..` (range / arithmetic sequence).
pub const DOTDOT: Word = 297;
/// Token: `\/` (logical or).
pub const VEL: Word = 298;
/// Token: `>=`.
pub const GE: Word = 299;
/// Token: `~=` (not equal).
pub const NE: Word = 300;
/// Token: `<=`.
pub const LE: Word = 301;
/// Token: the `mod` (remainder) keyword.
pub const REM: Word = 302;
/// Token: the `div` (integer division) keyword.
pub const DIV: Word = 303;
/// Token: a back-quoted infix name, `` `f` ``.
pub const INFIXNAME: Word = 304;
/// Token: a back-quoted infix constructor, `` `C` ``.
pub const INFIXCNAME: Word = 305;

// Raw heap-cell tag values (0..22), derived from the canonical [NodeTag] enum
// below so there is a single source of truth for the numeric codes. The bare
// `Word` form is used only where a raw tag byte is written (e.g. `make(AP, …)`);
// reads `switch` on [getTag], which returns the typed `NodeTag`.

/// Typed view of the heap-cell tag byte (R3.2) — the canonical definition of the
/// tag codes (the raw `ATOM`…`TCONS` `Word` consts above are derived from it).
/// As an `enum(u8)` so reads can `switch` exhaustively. [getTag] returns this.
/// Fully exhaustive (no open `_` catch-all) since B3 (2026-07-01): the old
/// mark-sweep GC stored a cell's "already marked this cycle" state by
/// negating its tag byte's sign bit, so a live cell's stored byte could
/// briefly be any of the 23 values' two's-complement negation -- values with
/// no named member, needing the catch-all. `Heap`'s tracing GC (`live: a
/// `std.DynamicBitSetUnmanaged`) tracks that separately now, so a cell's tag
/// byte is always exactly one of the 23 members below, and Zig can enforce it.
pub const NodeTag = enum(u8) {
    ATOM = 0,
    DOUBLE = 1,
    DATAPAIR = 2,
    FILEINFO = 3,
    TVAR = 4,
    INT = 5,
    CONSTRUCTOR = 6,
    STRCONS = 7,
    ID = 8,
    AP = 9,
    LAMBDA = 10,
    CONS = 11,
    TRIES = 12,
    LABEL = 13,
    SHOW = 14,
    STARTREADVALS = 15,
    LET = 16,
    LETREC = 17,
    SHARE = 18,
    LEXER = 19,
    PAIR = 20,
    UNICODE = 21,
    TCONS = 22,
};

// Tag-pointer bits and misc parser/config constants, relocated from c_abi.zig.

/// Sentinel 0: end-of-list marker in the pattern compiler.
pub const END = 0;
/// List-comprehension qualifier kind: a generator (`pat <- src`).
pub const GENERATOR = 0;
/// List-comprehension qualifier kind: a guard (boolean predicate).
pub const GUARD = 1;
/// Identifier hash-table bucket count.
pub const hashsize = 512;
/// Upper bound on pattern-vector nodes (`pnvec`).
pub const pnlim = 1024;
/// `sysconf` selector `_SC_CLK_TCK` (clock ticks/second) — C-interop constant.
pub const _SC_CLK_TCK = 3;

// Combinator codes (CMBASE + n). These atoms are the reducer's rewrite-rule
// dispatch keys; their printed names are `combinator.cmbnms[n]`.

/// Combinator `S`: `S f g x → f x (g x)`.
pub const S: Word = CMBASE + 0;
/// Combinator `K`: `K x y → x`.
pub const K: Word = CMBASE + 1;
/// Combinator `Y`: the fixpoint combinator (recursion).
pub const Y: Word = CMBASE + 2;
/// Combinator `C`: `C f x y → f y x` (flip).
pub const C: Word = CMBASE + 3;
/// Combinator `B`: `B f g x → f (g x)` (function composition).
pub const B: Word = CMBASE + 4;
/// Combinator `CB`: a Turner bracket-abstraction optimisation combinator.
pub const CB: Word = CMBASE + 5;
/// Combinator `I`: `I x → x` (identity).
pub const I: Word = CMBASE + 6;
/// Combinator `HD`: list head.
pub const HD: Word = CMBASE + 7;
/// Combinator `TL`: list tail.
pub const TL: Word = CMBASE + 8;
/// Combinator `BODY`: the defining body selector (used in `where`/letrec setup).
pub const BODY: Word = CMBASE + 9;
/// Combinator `LAST`: the last-clause selector (paired with `BODY`).
pub const LAST: Word = CMBASE + 10;
/// Combinator `S'`: the optimised `S` (`S' c f g x → c (f x) (g x)`).
pub const S_p: Word = CMBASE + 11;
/// Combinator `U`: uncurry onto a cons — `U f (a:b) → f a b` (pattern matching).
pub const U: Word = CMBASE + 12;
/// Combinator `Uf`: an `U` variant that forces its argument.
pub const Uf: Word = CMBASE + 13;
/// Combinator `U_`: an `U` variant discarding part of the match.
pub const U_: Word = CMBASE + 14;
/// Combinator `Ug`: an `U` variant used by generator desugaring.
pub const Ug: Word = CMBASE + 15;
/// Combinator `COND`: `COND c t e` — the conditional (if/then/else).
pub const COND: Word = CMBASE + 16;
/// Combinator `EQ`: equality test.
pub const EQ: Word = CMBASE + 17;
/// Combinator `NEQ`: inequality test.
pub const NEQ: Word = CMBASE + 18;
/// Combinator `NEG`: arithmetic negation.
pub const NEG: Word = CMBASE + 19;
/// Combinator `AND`: short-circuit logical and.
pub const AND: Word = CMBASE + 20;
/// Combinator `OR`: short-circuit logical or.
pub const OR: Word = CMBASE + 21;
/// Combinator `NOT`: logical negation.
pub const NOT: Word = CMBASE + 22;
/// Combinator `APPEND`: list concatenation (`++`).
pub const APPEND: Word = CMBASE + 23;
/// Combinator `STEP`: the stepped arithmetic sequence `[a, b ..]`.
pub const STEP: Word = CMBASE + 24;
/// Combinator `STEPUNTIL`: the bounded stepped sequence `[a, b .. c]`.
pub const STEPUNTIL: Word = CMBASE + 25;
/// Combinator `GENSEQ`: the arithmetic sequence `[a ..]` / `[a .. b]`.
pub const GENSEQ: Word = CMBASE + 26;
/// Combinator `MAP`: apply a function over a list.
pub const MAP: Word = CMBASE + 27;
/// Combinator `ZIP`: pair up two lists.
pub const ZIP: Word = CMBASE + 28;
/// Combinator `TAKE`: the first `n` elements of a list.
pub const TAKE: Word = CMBASE + 29;
/// Combinator `DROP`: a list without its first `n` elements.
pub const DROP: Word = CMBASE + 30;
/// Combinator `FLATMAP`: concat-map (`//`).
pub const FLATMAP: Word = CMBASE + 31;
/// Combinator `FILTER`: keep the elements satisfying a predicate.
pub const FILTER: Word = CMBASE + 32;
/// Combinator `FOLDL`: left fold with a seed.
pub const FOLDL: Word = CMBASE + 33;
/// Combinator `MERGE`: merge two ascending lists.
pub const MERGE: Word = CMBASE + 34;
/// Combinator `FOLDL1`: left fold seeded by the first element.
pub const FOLDL1: Word = CMBASE + 35;
/// Combinator `LIST_LAST`: the last element of a list.
pub const LIST_LAST: Word = CMBASE + 36;
/// Combinator `FOLDR`: right fold.
pub const FOLDR: Word = CMBASE + 37;
/// Combinator `MATCH`: match a value against a constructor pattern.
pub const MATCH: Word = CMBASE + 38;
/// Combinator `MATCHINT`: match a value against an integer-literal pattern.
pub const MATCHINT: Word = CMBASE + 39;
/// Combinator `TRY`: try the next pattern-match alternative on failure.
pub const TRY: Word = CMBASE + 40;
/// Combinator `SUBSCRIPT`: list indexing (`!`).
pub const SUBSCRIPT: Word = CMBASE + 41;
/// Combinator `ATLEAST`: test that a list has at least `n` elements.
pub const ATLEAST: Word = CMBASE + 42;
/// Combinator `P`: the pairing/tuple constructor.
pub const P: Word = CMBASE + 43;
/// Combinator `B'`: the optimised `B` (`B' c f g x → c f (g x)`).
pub const B_p: Word = CMBASE + 44;
/// Combinator `C'`: the optimised `C` (`C' c f g x → c (f x) g`).
pub const C_p: Word = CMBASE + 45;
/// Combinator `S1`: an indexed `S` variant (Turner optimisation).
pub const S1: Word = CMBASE + 46;
/// Combinator `B1`: an indexed `B` variant (Turner optimisation).
pub const B1: Word = CMBASE + 47;
/// Combinator `C1`: an indexed `C` variant (Turner optimisation).
pub const C1: Word = CMBASE + 48;
/// Combinator `ITERATE`: `iterate f x = [x, f x, f (f x), …]`.
pub const ITERATE: Word = CMBASE + 49;
/// Combinator `ITERATE1`: the strict-step variant of `ITERATE`.
pub const ITERATE1: Word = CMBASE + 50;
/// Combinator `SEQ`: force the first argument, then return the second.
pub const SEQ: Word = CMBASE + 51;
/// Combinator `FORCE`: reduce the argument to weak head normal form.
pub const FORCE: Word = CMBASE + 52;
/// Combinator `MINUS`: integer/float subtraction.
pub const MINUS: Word = CMBASE + 53;
/// Combinator `PLUS`: integer/float addition.
pub const PLUS: Word = CMBASE + 54;
/// Combinator `TIMES`: integer/float multiplication.
pub const TIMES: Word = CMBASE + 55;
/// Combinator `INTDIV`: integer division (`div`).
pub const INTDIV: Word = CMBASE + 56;
/// Combinator `FDIV`: floating-point division (`/`).
pub const FDIV: Word = CMBASE + 57;
/// Combinator `MOD`: integer remainder (`mod`).
pub const MOD: Word = CMBASE + 58;
/// Combinator `GR`: greater-than (`>`).
pub const GR: Word = CMBASE + 59;
/// Combinator `GRE`: greater-than-or-equal (`>=`).
pub const GRE: Word = CMBASE + 60;
/// Combinator `POWER`: exponentiation (`^`).
pub const POWER: Word = CMBASE + 61;
/// Combinator `CODE`: character → code point (`code`).
pub const CODE: Word = CMBASE + 62;
/// Combinator `DECODE`: code point → character (`decode`).
pub const DECODE: Word = CMBASE + 63;
/// Combinator `LENGTH`: list length (`#`).
pub const LENGTH: Word = CMBASE + 64;
/// Combinator `ARCTAN_FN`: the `arctan` builtin.
pub const ARCTAN_FN: Word = CMBASE + 65;
/// Combinator `EXP_FN`: the `exp` builtin.
pub const EXP_FN: Word = CMBASE + 66;
/// Combinator `ENTIER_FN`: the `entier` (floor) builtin.
pub const ENTIER_FN: Word = CMBASE + 67;
/// Combinator `LOG_FN`: the natural-log `log` builtin.
pub const LOG_FN: Word = CMBASE + 68;
/// Combinator `LOG10_FN`: the base-10 `log10` builtin.
pub const LOG10_FN: Word = CMBASE + 69;
/// Combinator `SIN_FN`: the `sin` builtin.
pub const SIN_FN: Word = CMBASE + 70;
/// Combinator `COS_FN`: the `cos` builtin.
pub const COS_FN: Word = CMBASE + 71;
/// Combinator `SQRT_FN`: the `sqrt` builtin.
pub const SQRT_FN: Word = CMBASE + 72;
/// Combinator `FILEMODE`: query a file's mode bits.
pub const FILEMODE: Word = CMBASE + 73;
/// Combinator `FILESTAT`: `stat` a file.
pub const FILESTAT: Word = CMBASE + 74;
/// Combinator `GETENV`: read an environment variable.
pub const GETENV: Word = CMBASE + 75;
/// Combinator `EXEC`: run a subprocess.
pub const EXEC: Word = CMBASE + 76;
/// Combinator `WAIT`: wait for a child process.
pub const WAIT: Word = CMBASE + 77;
/// Combinator `INTEGER`: the integer-valued predicate.
pub const INTEGER: Word = CMBASE + 78;
/// Combinator `SHOWNUM`: format a number as decimal text.
pub const SHOWNUM: Word = CMBASE + 79;
/// Combinator `SHOWHEX`: format an integer as hexadecimal text.
pub const SHOWHEX: Word = CMBASE + 80;
/// Combinator `SHOWOCT`: format an integer as octal text.
pub const SHOWOCT: Word = CMBASE + 81;
/// Combinator `SHOWSCALED`: format a float with a fixed number of decimals.
pub const SHOWSCALED: Word = CMBASE + 82;
/// Combinator `SHOWFLOAT`: format a floating-point number.
pub const SHOWFLOAT: Word = CMBASE + 83;
/// Combinator `NUMVAL`: parse a numeric string to a number.
pub const NUMVAL: Word = CMBASE + 84;
/// Combinator `STARTREAD`: begin reading a file as a lazy char stream.
pub const STARTREAD: Word = CMBASE + 85;
/// Combinator `STARTREADBIN`: begin reading a file as a lazy byte stream.
pub const STARTREADBIN: Word = CMBASE + 86;
/// Combinator `NB_STARTREAD`: non-blocking `STARTREAD`.
pub const NB_STARTREAD: Word = CMBASE + 87;
/// Combinator `READVALS`: read a stream of values from a file.
pub const READVALS: Word = CMBASE + 88;
/// Combinator `NB_READ`: non-blocking read.
pub const NB_READ: Word = CMBASE + 89;
/// Combinator `READ`: read a file's full contents.
pub const READ: Word = CMBASE + 90;
/// Combinator `READBIN`: read a file's full contents as bytes.
pub const READBIN: Word = CMBASE + 91;
/// Combinator `GETARGS`: the program's command-line arguments.
pub const GETARGS: Word = CMBASE + 92;
/// Combinator `Ush`: an uncurry helper used by `show` desugaring.
pub const Ush: Word = CMBASE + 93;
/// Combinator `Ush1`: a variant of `Ush`.
pub const Ush1: Word = CMBASE + 94;
/// Combinator `KI`: `K I` — `KI x y → y` (returns its second argument).
pub const KI: Word = CMBASE + 95;
// Grammar (`%bnf`) combinators — the parser-combinator primitives the BNF
// feature compiles a grammar into.

/// Grammar combinator `G_ERROR`: an error production.
pub const G_ERROR: Word = CMBASE + 96;
/// Grammar combinator `G_ALT`: alternation (`a | b`).
pub const G_ALT: Word = CMBASE + 97;
/// Grammar combinator `G_OPT`: an optional production (`a?`).
pub const G_OPT: Word = CMBASE + 98;
/// Grammar combinator `G_STAR`: zero-or-more repetition (`a*`).
pub const G_STAR: Word = CMBASE + 99;
/// Grammar combinator `G_FBSTAR`: a full-backtracking `*`.
pub const G_FBSTAR: Word = CMBASE + 100;
/// Grammar combinator `G_SYMB`: match a terminal symbol.
pub const G_SYMB: Word = CMBASE + 101;
/// Grammar combinator `G_ANY`: match any symbol.
pub const G_ANY: Word = CMBASE + 102;
/// Grammar combinator `G_SUCHTHAT`: a semantic-predicate guard.
pub const G_SUCHTHAT: Word = CMBASE + 103;
/// Grammar combinator `G_END`: match end of input.
pub const G_END: Word = CMBASE + 104;
/// Grammar combinator `G_STATE`: thread the parser state.
pub const G_STATE: Word = CMBASE + 105;
/// Grammar combinator `G_SEQ`: sequence two productions.
pub const G_SEQ: Word = CMBASE + 106;
/// Grammar combinator `G_RULE`: a named rule / production.
pub const G_RULE: Word = CMBASE + 107;
/// Grammar combinator `G_UNIT`: the empty (unit) production.
pub const G_UNIT: Word = CMBASE + 108;
/// Grammar combinator `G_ZERO`: the always-failing production.
pub const G_ZERO: Word = CMBASE + 109;
/// Grammar combinator `G_CLOSE`: close a production group.
pub const G_CLOSE: Word = CMBASE + 110;
/// Grammar combinator `G_COUNT`: a counted repetition.
pub const G_COUNT: Word = CMBASE + 111;
// Lexer (`%lex`) combinators — the primitives a `%lex` specification compiles
// into for scanning input.

/// Lexer combinator `LEX_RPT`: zero-or-more repetition of a matcher.
pub const LEX_RPT: Word = CMBASE + 112;
/// Lexer combinator `LEX_RPT1`: one-or-more repetition.
pub const LEX_RPT1: Word = CMBASE + 113;
/// Lexer combinator `LEX_TRY`: try a matcher with backtracking.
pub const LEX_TRY: Word = CMBASE + 114;
/// Lexer combinator `LEX_TRY_`: a `LEX_TRY` variant discarding its result.
pub const LEX_TRY_: Word = CMBASE + 115;
/// Lexer combinator `LEX_TRY1`: try one alternative.
pub const LEX_TRY1: Word = CMBASE + 116;
/// Lexer combinator `LEX_TRY1_`: a `LEX_TRY1` variant discarding its result.
pub const LEX_TRY1_: Word = CMBASE + 117;
/// Combinator `DESTREV`: destructive in-place list reverse (lexer scratch).
pub const DESTREV: Word = CMBASE + 118;
/// Lexer combinator `LEX_COUNT`: a counted repetition.
pub const LEX_COUNT: Word = CMBASE + 119;
/// Lexer combinator `LEX_COUNT0`: a counted repetition allowing zero.
pub const LEX_COUNT0: Word = CMBASE + 120;
/// Lexer combinator `LEX_FAIL`: the always-failing matcher.
pub const LEX_FAIL: Word = CMBASE + 121;
/// Lexer combinator `LEX_STRING`: match a literal string.
pub const LEX_STRING: Word = CMBASE + 122;
/// Lexer combinator `LEX_CLASS`: match a character class `[...]`.
pub const LEX_CLASS: Word = CMBASE + 123;
/// Lexer combinator `LEX_CHAR`: match a single character.
pub const LEX_CHAR: Word = CMBASE + 124;
/// Lexer combinator `LEX_DOT`: match any character (`.`).
pub const LEX_DOT: Word = CMBASE + 125;
/// Lexer combinator `LEX_SEQ`: sequence two matchers.
pub const LEX_SEQ: Word = CMBASE + 126;
/// Lexer combinator `LEX_OR`: alternation between matchers.
pub const LEX_OR: Word = CMBASE + 127;
/// Lexer combinator `LEX_RCONTEXT`: right-context (trailing-context) lookahead.
pub const LEX_RCONTEXT: Word = CMBASE + 128;
/// Lexer combinator `LEX_STAR`: zero-or-more (greedy `*`).
pub const LEX_STAR: Word = CMBASE + 129;
/// Lexer combinator `LEX_OPT`: an optional matcher (`?`).
pub const LEX_OPT: Word = CMBASE + 130;
/// Combinator `MKSTRICT`: force a strict-annotated argument.
pub const MKSTRICT: Word = CMBASE + 131;
/// Combinator `BADCASE`: the "no matching case alternative" runtime error.
pub const BADCASE: Word = CMBASE + 132;
/// Combinator `CONFERROR`: a configuration / well-formedness error.
pub const CONFERROR: Word = CMBASE + 133;
/// Combinator `ERROR`: the `error` builtin (abort with a message).
pub const ERROR: Word = CMBASE + 134;
/// Combinator `FAIL`: pattern-match failure (triggers the next `TRY`).
pub const FAIL: Word = CMBASE + 135;
/// Named atom `False`: the boolean false.
pub const False: Word = CMBASE + 136;
/// Named atom `True`: the boolean true.
pub const True: Word = CMBASE + 137;

// Type-representation codes used by the type checker (the "what kind of type"
// tags for inferred/declared types).

/// Type code: an undefined / not-yet-known type.
pub const undef_t: Word = 0;
/// Type code: `bool`.
pub const bool_t: Word = 1;
/// Type code: `num`.
pub const num_t: Word = 2;
/// Type code: `char`.
pub const char_t: Word = 3;
/// Type code: the list type constructor `[*]`.
pub const list_t: Word = 4;
/// Type code: the tuple (comma) type constructor.
pub const comma_t: Word = 5;
/// Type code: the function-arrow type constructor `->`.
pub const arrow_t: Word = 6;
/// Type code: the void / unit type `()`.
pub const void_t: Word = 7;
/// Type code: the "ill-typed" marker produced on a type error.
pub const wrong_t: Word = 8;
/// Type code: a type binding (variable ↦ type).
pub const bind_t: Word = 9;
/// Type code: the type-of-a-type (a kind).
pub const type_t: Word = 10;
/// Type code: a strictness annotation on a type.
pub const strict_t: Word = 11;
/// Type code: a type synonym / alias.
pub const alias_t: Word = 12;
/// Type code: a freshly introduced type.
pub const new_t: Word = 13;

// NB: these kind codes MUST match the values the type-checker switches on in
// `compiler/trans.zig` and `compiler/types.zig` (the C-ported core): a type node's
// class field is written here (via `codegen`→`declType`) and read there. They were
// previously mis-numbered (algebraic=2 / abstract=3 / placeholder=5), which collided
// `algebraic_t` with the checker's local `abstract_t=2` and made every user `::=`
// type be processed as an `abstype`. See the regression goldens `algebraic_*`.
/// Type-declaration kind: a `::=` algebraic type.
pub const algebraic_t: Word = 0;
/// Type-declaration kind: a `==` synonym.
pub const synonym_t: Word = 1;
/// Type-declaration kind: an `abstype`.
pub const abstract_t: Word = 2;
/// Type-declaration kind: a forward-reference placeholder.
pub const placeholder_t: Word = 3;
/// Type-declaration kind: a `%free` parameter.
pub const free_t: Word = 4;

// Compiler and reducer action constants — the reducer's step status.

/// Reducer action: no pending work.
pub const ACT_NONE: Word = 0;
/// Reducer action: advance to the next redex.
pub const ACT_NEXTREDEX: Word = 1;
/// Reducer action: reduction of the current redex is complete.
pub const ACT_DONE: Word = 2;

/// Sign bit set on a bignum's head digit to mark it negative (see `big.zig`).
pub const SIGNBIT: Word = 0x10000000;
/// Mask selecting a bignum digit's 15 value bits (`IBASE - 1`).
pub const MAXDIGIT: Word = 0x7fff;
/// Largest Unicode code point (`U+10FFFF`).
pub const UMAX: Word = 0x10ffff;
/// Dump-file format version written/expected by the `.x` serialiser.
pub const XVERSION: Word = 83;

// Dump-file (`.x`) serialiser marker codes (`XBASE + n`): the tag bytes the
// dump/undump round-trip writes ahead of each serialised node.

/// Base of the dump-marker range.
pub const XBASE: Word = ATOMLIMIT - 256;
/// Dump marker: a character value.
pub const CHAR_X: Word = XBASE;
/// Dump marker: a short integer.
pub const SHORT_X: Word = XBASE + 1;
/// Dump marker: a (big) integer.
pub const INT_X: Word = XBASE + 2;
/// Dump marker: a double-precision float.
pub const DBL_X: Word = XBASE + 3;
/// Dump marker: an identifier.
pub const ID_X: Word = XBASE + 4;
/// Dump marker: an alias (`a.k.a.`) reference to an already-dumped node.
pub const AKA_X: Word = XBASE + 5;
/// Dump marker: a source-position (`here`) annotation.
pub const HERE_X: Word = XBASE + 6;
/// Dump marker: a constructor node.
pub const CONSTRUCT_X: Word = XBASE + 7;
/// Dump marker: a `readvals` node.
pub const RV_X: Word = XBASE + 8;
/// Dump marker: a pattern node.
pub const PN_X: Word = XBASE + 9;
/// Dump marker: a one-argument pattern node.
pub const PN1_X: Word = XBASE + 10;
/// Dump marker: a definition.
pub const DEF_X: Word = XBASE + 11;
/// Dump marker: a function application.
pub const AP_X: Word = XBASE + 12;
/// Dump marker: a cons cell.
pub const CONS_X: Word = XBASE + 13;
/// Dump marker: a type variable.
pub const TVAR_X: Word = XBASE + 14;
/// Dump marker: a Unicode character.
pub const UNICODE_X: Word = XBASE + 15;

/// Tests: castToCStr: yields null for null, unwraps optionals
pub fn castToCStr(val: anytype) ?[*:0]const u8 {
    const T = @TypeOf(val);
    if (T == @TypeOf(null)) return null;
    if (@typeInfo(T) == .optional) {
        if (val) |v| {
            return @ptrCast(v);
        } else {
            return null;
        }
    }
    return @ptrCast(val);
}

test "castToCStr: yields null for null, unwraps optionals" {
    try std.testing.expect(castToCStr(null) == null);
    const some: ?[*:0]const u8 = "hi";
    try std.testing.expectEqualStrings("hi", std.mem.span(castToCStr(some).?));
    const none: ?[*:0]const u8 = null;
    try std.testing.expect(castToCStr(none) == null);
}

/// Coerce any pointer/optional/null to an optional mutable C-string.
pub fn castToCStrMut(val: anytype) ?[*:0]u8 {
    const T = @TypeOf(val);
    if (T == @TypeOf(null)) return null;
    if (@typeInfo(T) == .optional) {
        if (val) |v| {
            return @ptrCast(v);
        } else {
            return null;
        }
    }
    return @ptrCast(val);
}

/// libc `strcpy` over the polymorphic C-string casts.
///
/// Tests: string helpers strcpy and strcat
pub fn strcpy(dst_any: anytype, src_any: anytype) ?[*:0]u8 {
    const dst = castToCStrMut(dst_any);
    const src = castToCStr(src_any);
    if (dst == null or src == null) return dst;
    const d = dst.?;
    const s = src.?;
    const src_len = std.mem.span(s).len;
    @memcpy(d[0..src_len], s[0..src_len]);
    d[src_len] = 0;
    return dst;
}

/// libc `strcat`.
///
/// Tests: string helpers strcpy and strcat
pub fn strcat(dst_any: anytype, src_any: anytype) ?[*:0]u8 {
    const dst = castToCStrMut(dst_any);
    const src = castToCStr(src_any);
    if (dst == null or src == null) return dst;
    const d = dst.?;
    const s = src.?;
    const dst_len = std.mem.span(d).len;
    const src_len = std.mem.span(s).len;
    @memcpy(d[dst_len .. dst_len + src_len], s[0..src_len]);
    d[dst_len + src_len] = 0;
    return dst;
}

test "string helpers strcpy and strcat" {
    var buf1: [32:0]u8 = undefined;
    _ = strcpy(&buf1, "hello");
    try std.testing.expectEqualSlices(u8, "hello", std.mem.span(@as([*:0]u8, &buf1)));

    _ = strcat(&buf1, " world");
    try std.testing.expectEqualSlices(u8, "hello world", std.mem.span(@as([*:0]u8, &buf1)));
}

// String-handle accessors moved to `strtab.zig` (B1 / R6, step 2): node-stored
// identifier/pathname strings are now interned `StrId`s, not pointers, so the
// accessors need the string table's allocator and live in that owner module.
// Call sites use `strtab.strOf` (read) and `strtab.strBits` (intern + store).
// `word.zig` stays a pure leaf with no allocator dependency.

/// libc `strlen` (0 for null).
///
/// Tests: strlen: counts bytes up to NUL, 0 for null
pub fn strlen(s_any: anytype) usize {
    const s = castToCStr(s_any);
    if (s == null) return 0;
    return std.mem.span(s.?).len;
}

test "strlen: counts bytes up to NUL, 0 for null" {
    try std.testing.expectEqual(@as(usize, 5), strlen("hello"));
    try std.testing.expectEqual(@as(usize, 0), strlen(""));
    try std.testing.expectEqual(@as(usize, 0), strlen(null));
}

/// libc `strcmp` (-1 / 0 / 1).
///
/// Tests: strcmp: lexicographic ordering as -1 / 0 / 1
pub fn strcmp(s1_any: anytype, s2_any: anytype) c_int {
    const s1 = castToCStr(s1_any);
    const s2 = castToCStr(s2_any);
    if (s1 == null or s2 == null) return 0;
    const span1 = std.mem.span(s1.?);
    const span2 = std.mem.span(s2.?);
    const order = std.mem.order(u8, span1, span2);
    return switch (order) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

test "strcmp: lexicographic ordering as -1 / 0 / 1" {
    try std.testing.expectEqual(@as(c_int, 0), strcmp("abc", "abc"));
    try std.testing.expectEqual(@as(c_int, -1), strcmp("abc", "abd"));
    try std.testing.expectEqual(@as(c_int, 1), strcmp("abd", "abc"));
}

/// libc `strncmp` over the first `n` bytes.
///
/// Tests: strncmp: compares only the first n bytes
pub fn strncmp(s1_any: anytype, s2_any: anytype, n: usize) c_int {
    const s1 = castToCStr(s1_any);
    const s2 = castToCStr(s2_any);
    if (s1 == null or s2 == null) return 0;
    const span1 = std.mem.span(s1.?);
    const span2 = std.mem.span(s2.?);
    const sa = span1[0..@min(span1.len, n)];
    const sb = span2[0..@min(span2.len, n)];
    const order = std.mem.order(u8, sa, sb);
    return switch (order) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

test "strncmp: compares only the first n bytes" {
    try std.testing.expectEqual(@as(c_int, 0), strncmp("abXX", "abYY", 2));
    try std.testing.expectEqual(@as(c_int, -1), strncmp("abX", "abY", 3));
}

/// libc `strncpy` (NUL-pads out to `n`).
///
/// Tests: strncpy: copies up to n bytes and NUL-pads the rest
pub fn strncpy(dst_any: anytype, src_any: anytype, n: usize) ?[*:0]u8 {
    const dst = castToCStrMut(dst_any);
    const src = castToCStr(src_any);
    if (dst == null or src == null) return dst;
    const d = dst.?;
    const s = src.?;
    const src_span = std.mem.span(s);
    const limit = @min(src_span.len, n);
    @memcpy(d[0..limit], src_span[0..limit]);
    if (limit < n) {
        @memset(d[limit..n], 0);
    }
    return dst;
}

test "strncpy: copies up to n bytes and NUL-pads the rest" {
    var buf: [8:0]u8 = undefined;
    @memset(buf[0..], 'Z');
    _ = strncpy(&buf, "ab", 5);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 'a', 'b', 0, 0, 0 }, buf[0..5]);
}

/// libc `strncat` (append up to `n` bytes).
///
/// Tests: strncat: appends at most n bytes, then a NUL
pub fn strncat(dst_any: anytype, src_any: anytype, n: usize) ?[*:0]u8 {
    const dst = castToCStrMut(dst_any);
    const src = castToCStr(src_any);
    if (dst == null or src == null) return dst;
    const d = dst.?;
    const s = src.?;
    const dst_len = std.mem.span(d).len;
    const src_span = std.mem.span(s);
    const limit = @min(src_span.len, n);
    @memcpy(d[dst_len .. dst_len + limit], src_span[0..limit]);
    d[dst_len + limit] = 0;
    return dst;
}

test "strncat: appends at most n bytes, then a NUL" {
    var buf: [16:0]u8 = undefined;
    _ = strcpy(&buf, "foo");
    _ = strncat(&buf, "barbaz", 3);
    try std.testing.expectEqualStrings("foobar", std.mem.span(@as([*:0]u8, &buf)));
}

/// libc `strchr`: first occurrence of `char`, or null.
///
/// Tests: strchr: first occurrence (or null)
pub fn strchr(s_any: anytype, char: c_int) ?[*:0]const u8 {
    const s = castToCStr(s_any);
    if (s == null) return null;
    const ptr = s.?;
    const span = std.mem.span(ptr);
    const ch: u8 = @intCast(char);
    for (span, 0..) |item, i| {
        if (item == ch) {
            return ptr + i;
        }
    }
    return null;
}

test "strchr: first occurrence (or null)" {
    try std.testing.expectEqualStrings(".b.c", std.mem.span(strchr("a.b.c", '.').?));
    try std.testing.expect(strchr("a.b.c", 'z') == null);
}

/// libc `strrchr`: last occurrence of `char`, or null.
///
/// Tests: strrchr: last occurrence (or null)
pub fn strrchr(s_any: anytype, char: c_int) ?[*:0]u8 {
    const s = castToCStr(s_any);
    if (s == null) return null;
    const ptr = @constCast(s.?);
    const span = std.mem.span(ptr);
    const ch: u8 = @intCast(char);
    var i = span.len;
    while (i > 0) {
        i -= 1;
        if (span[i] == ch) {
            return ptr + i;
        }
    }
    return null;
}

test "strrchr: last occurrence (or null)" {
    try std.testing.expectEqualStrings(".c", std.mem.span(@as([*:0]const u8, strrchr("a.b.c", '.').?)));
    try std.testing.expect(strrchr("abc", 'z') == null);
}

/// libc `strstr`: first occurrence of the `needle` substring.
///
/// Tests: strstr: substring search; empty needle matches at the start
pub fn strstr(haystack_any: anytype, needle_any: anytype) ?[*:0]const u8 {
    const haystack = castToCStr(haystack_any);
    const needle = castToCStr(needle_any);
    if (haystack == null or needle == null) return null;
    const h_ptr = haystack.?;
    const n_ptr = needle.?;
    const h_span = std.mem.span(h_ptr);
    const n_span = std.mem.span(n_ptr);
    if (n_span.len == 0) return h_ptr;
    if (h_span.len < n_span.len) return null;
    const limit = h_span.len - n_span.len + 1;
    var i: usize = 0;
    while (i < limit) : (i += 1) {
        if (std.mem.eql(u8, h_span[i .. i + n_span.len], n_span)) {
            return h_ptr + i;
        }
    }
    return null;
}

test "strstr: substring search; empty needle matches at the start" {
    try std.testing.expectEqualStrings("world", std.mem.span(strstr("hello world", "wor").?));
    try std.testing.expect(strstr("abc", "xyz") == null);
    try std.testing.expectEqualStrings("abc", std.mem.span(strstr("abc", "").?));
}

/// BSD `rindex` — an alias for `strrchr`.
///
/// Tests: rindex: last occurrence of a char (libc strrchr alias)
pub fn rindex(s_any: anytype, char: c_int) ?[*:0]u8 {
    return strrchr(s_any, char);
}

test "rindex: last occurrence of a char (libc strrchr alias)" {
    try std.testing.expectEqualStrings("/c", std.mem.span(@as([*:0]const u8, rindex("/a/b/c", '/').?)));
    try std.testing.expect(rindex("abc", '/') == null);
}

// stdio / file-handle machinery (Phase 2 step 4, docs/ZIG_NATIVE_PLAN.md) —
// moved to stream.zig; re-exported here unchanged so every existing
// `word.FILE`/`word.fopen`/etc. call site keeps compiling as-is.
const stream = @import("stream.zig");
pub const FILE = stream.FILE;
pub const IoState = stream.IoState;
pub const fio = stream.fio;
pub const initWriters = stream.initWriters;
pub const print = stream.print;
pub const printErr = stream.printErr;
pub const fprint = stream.fprint;
pub const stdin = stream.stdin;
pub const stdout = stream.stdout;
pub const stderr = stream.stderr;
pub const fopen = stream.fopen;
pub const fclose = stream.fclose;
pub const fileno = stream.fileno;
pub const setbuf = stream.setbuf;
pub const getc = stream.getc;
pub const getchar = stream.getchar;
pub const ungetc = stream.ungetc;
pub const fgets = stream.fgets;
pub const fread = stream.fread;
pub const fwrite = stream.fwrite;
pub const fdopen = stream.fdopen;
pub const putc = stream.putc;
pub const putchar = stream.putchar;

