//! Phase 10: AST → Miranda heap codegen.
//! Walks ast.Script and produces the same Word heap values as the legacy YACC parser.
//! IMPORTANT: this file calls C runtime functions and must NOT be imported from the
//! pure parser-tests binary (src/syntax/parser.zig).  Import it from parser_api.zig or main.zig.

const std = @import("std");
const word = @import("../graph/word.zig");
const strtab = @import("../graph/strtab.zig");
const Allocator = std.mem.Allocator;
const ast = @import("../syntax/ast.zig");

const rt = @import("../runtime/runtime_state.zig");
const script_store = @import("../session/script_store.zig");
const repl_session = @import("../session/repl_session.zig");
const lex_state = @import("lex_state.zig");
const ls = lex_state.ls;
// Cross-module functions via direct @import (R7.3 — eliminate extern-fn linker decls).
const trans = @import("../semantics/lower.zig");
const match = @import("../semantics/match.zig");
const types_mod = @import("../semantics/unify.zig");
const big = @import("../graph/bignum.zig");
const big_fmt = @import("../graph/bignum_fmt.zig");
const lex = @import("lex.zig");
const reduce_mod = @import("../eval/reduce_rt.zig");
const heap = @import("../graph/heap.zig");
const symbols = @import("../semantics/symbols.zig");
const setup = @import("../compiler/setup.zig");
const Value = @import("../graph/value.zig").Value;

const Word = word.Word;

// Miranda predefined atom words (from lex.zig — keep in sync with CMBASE = 306).
const CMBASE = word.CMBASE;
const FALSE_ATOM: Word = CMBASE + 136;
const TRUE_ATOM: Word = CMBASE + 137;

// ---------------------------------------------------------------------------
// Heap cell accessors
// ---------------------------------------------------------------------------

inline fn h(heap_ptr: *heap.Heap, x: Word) Word {
    return heap_ptr.h(x);
}
inline fn t(heap_ptr: *heap.Heap, x: Word) Word {
    return heap_ptr.t(x);
}
inline fn tp(heap_ptr: *heap.Heap, x: Word) *Word {
    return heap_ptr.tp(x);
}
inline fn tg(heap_ptr: *heap.Heap, x: Word) word.NodeTag {
    return heap_ptr.getTag(x);
}

// ---------------------------------------------------------------------------
// Heap construction helpers (mirrors data.h macros)
// ---------------------------------------------------------------------------

inline fn ap(heap_ptr: *heap.Heap, x: Word, y: Word) Word {
    return heap.make(heap_ptr, .AP, x, y);
}
inline fn ap2(heap_ptr: *heap.Heap, x: Word, y: Word, z: Word) Word {
    return ap(heap_ptr, ap(heap_ptr, x, y), z);
}
inline fn ap3(heap_ptr: *heap.Heap, w: Word, x: Word, y: Word, z: Word) Word {
    return ap(heap_ptr, ap2(heap_ptr, w, x, y), z);
}
inline fn mkcons(heap_ptr: *heap.Heap, x: Word, y: Word) Word {
    return heap.make(heap_ptr, .CONS, x, y);
}
inline fn mklabel(heap_ptr: *heap.Heap, x: Word, y: Word) Word {
    return heap.make(heap_ptr, .LABEL, x, y);
}
inline fn mklambda(heap_ptr: *heap.Heap, x: Word, y: Word) Word {
    return heap.make(heap_ptr, .LAMBDA, x, y);
}
inline fn mkpair(heap_ptr: *heap.Heap, x: Word, y: Word) Word {
    return heap.make(heap_ptr, .PAIR, x, y);
}
inline fn mktcons(heap_ptr: *heap.Heap, x: Word, y: Word) Word {
    return heap.make(heap_ptr, .TCONS, x, y);
}

// ---------------------------------------------------------------------------
// C function externs
// ---------------------------------------------------------------------------

const genlhs = match.genlhs;
const irrefutable = trans.irrefutable;
const compzf = trans.compzf;
const block = trans.block;
const declare = trans.declare;
const specify = trans.specify;
const declType = trans.declType;
const declconstr = trans.declconstr;
const redtvars = types_mod.redtvars;
const bigscan = big_fmt.scanDecimal;
const stoDbl = heap.stoDbl;
const stoId = heap.stoId;
const keep = lex.keep;
const stoChar = heap.stoChar;
const head = reduce_mod.head;
const isconstrname = lex.isconstrname;

/// Parse decimal `text` into a bignum (via a temporary NUL-terminated copy).
fn bigscanZ(heap_ptr: *heap.Heap, alloc: Allocator, text: []const u8) Word {
    const z = alloc.dupeSentinel(u8, text, 0) catch return word.NIL;
    if (std.mem.startsWith(u8, z, "0x") or std.mem.startsWith(u8, z, "0X")) {
        return big_fmt.scanHex(heap_ptr, z.ptr + 2, z.ptr + z.len);
    } else if (std.mem.startsWith(u8, z, "0o") or std.mem.startsWith(u8, z, "0O")) {
        return big_fmt.scanOctal(heap_ptr, z.ptr + 2, z.ptr + z.len);
    } else {
        return bigscan(heap_ptr, z.ptr);
    }
}

// ---------------------------------------------------------------------------
// Runtime globals
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Type constants (from data.h — replicated so we don't need the macros)
// ---------------------------------------------------------------------------

const undef_t = word.undef_t;
const arrow_t = word.arrow_t;
const list_t = word.list_t;
const comma_t = word.comma_t;
const void_t = word.void_t;

// ---------------------------------------------------------------------------
// 'here' generation: fileinfo(getFil(current_file), line_no)
// ---------------------------------------------------------------------------

/// Build a source-location (`HERE`) marker node for `line`.
fn makeHere(heap_ptr: *heap.Heap, line: u32) Word {
    // getFil(current_file) = (char*)hd(hd(hd(current_file)))
    const fil_name = h(heap_ptr, h(heap_ptr, h(heap_ptr, heap_ptr.current_file)));
    return heap.make(heap_ptr, .FILEINFO, fil_name, @intCast(line));
}

// ---------------------------------------------------------------------------
// Helper: is this ID word a constructor name?
// ---------------------------------------------------------------------------

/// Whether heap word `x` is a constructor identifier.
fn isConstructorWord(heap_ptr: *heap.Heap, x: Word) bool {
    if (tg(heap_ptr, x) != .ID) return false;
    // getId(x) = (char*)hd(hd(hd(x)))
    const name_ptr: [*:0]const u8 = strtab.strOf(strtab.table(), h(heap_ptr, h(heap_ptr, h(heap_ptr, x))));
    return isconstrname(name_ptr);
}

// ---------------------------------------------------------------------------
// nameWord: convert a []const u8 to a Miranda ID Word via stoId
// ---------------------------------------------------------------------------

/// Resolve identifier `name` to its dictionary `ID` node.
fn nameWord(name: []const u8) Word {
    var buf: [512:0]u8 = undefined;
    const n = @min(name.len, buf.len - 1);
    @memcpy(buf[0..n], name[0..n]);
    buf[n] = 0;
    // Look up the interned atom from the name table (populated by yylex's
    // name() calls during tokenization). This ensures the same source name
    // always maps to the same heap atom, which is required for multi-equation
    // definitions: decl1() checks `script_store.store().lastname == x` using pointer equality.
    if (symbols.syms().find(buf[0..n])) |existing| return existing.toRaw();
    // Not yet in the name table (e.g., synthesised names). Intern it now.
    const perm = keep(@as([*:0]u8, @ptrCast(&buf)));
    return (symbols.syms().createFresh(rt.allocator, std.mem.span(perm)) catch heap.mallocPanic("symbols dictionary")).toRaw();
}

// ---------------------------------------------------------------------------
// Type variable: convert name string to TVAR cell
//   "*"   → make(TVAR, 0, 1)
//   "**"  → make(TVAR, 0, 2)
//   "***" → make(TVAR, 0, 3)
//   "*a"  → stoId("*a")  (named typevar — fall back to ident)
// ---------------------------------------------------------------------------

/// Code a type variable named `name`.
fn codegenTypeVar(heap_ptr: *heap.Heap, name: []const u8) Word {
    var star_count: Word = 0;
    for (name) |c| {
        if (c == '*') star_count += 1 else break;
    }
    if (star_count == @as(Word, @intCast(name.len))) {
        // Pure-star type variable: *, **, ***, …
        return heap.make(heap_ptr, .TVAR, 0, star_count);
    }
    // Named type variable like *a, *b — treat as identifier for now
    return nameWord(name);
}

// ---------------------------------------------------------------------------
// Type expression codegen
// ---------------------------------------------------------------------------

/// Code a type expression `te` into its runtime type node.
fn codegenType(heap_ptr: *heap.Heap, te: ast.TypeExpr) Word {
    return switch (te) {
        .type_var => |v| codegenTypeVar(heap_ptr, v.name),
        .type_name => |n| nameWord(n.name),
        .arrow => |a| ap2(heap_ptr, arrow_t, codegenType(heap_ptr, a.from.*), codegenType(heap_ptr, a.to.*)),
        .type_app => |ta| blk: {
            var result = codegenType(heap_ptr, ta.func.*);
            for (ta.args) |arg| result = ap(heap_ptr, result, codegenType(heap_ptr, arg));
            break :blk result;
        },
        .tuple => |types| blk: {
            if (types.len == 0) break :blk void_t;
            // (T1, T2, ..., Tn) = ap2(heap_ptr, comma_t, T1, ap2(heap_ptr, comma_t, T2, ... void_t...))
            var result: Word = void_t;
            var i: usize = types.len;
            while (i > 0) {
                i -= 1;
                result = ap2(heap_ptr, comma_t, codegenType(heap_ptr, types[i]), result);
            }
            break :blk result;
        },
        .list => |inner| ap(heap_ptr, list_t, codegenType(heap_ptr, inner.*)),
        .void_t => void_t,
    };
}

// ---------------------------------------------------------------------------
// Operator → Word mapping (diop/relop table from rules.y)
// ---------------------------------------------------------------------------

/// Map an operator symbol `op` to its combinator/atom word.
fn opWord(heap_ptr: *heap.Heap, op: []const u8) Word {
    if (std.mem.eql(u8, op, "vel")) return word.OR;
    if (std.mem.eql(u8, op, "amp")) return word.AND;
    if (std.mem.eql(u8, op, "eq")) return word.EQ;
    if (std.mem.eql(u8, op, "eqeq")) return word.EQ;
    if (std.mem.eql(u8, op, "ne")) return word.NEQ;
    if (std.mem.eql(u8, op, "gt")) return word.GR;
    if (std.mem.eql(u8, op, "lt")) return ap(heap_ptr, word.C, word.GR); // relop '<'
    if (std.mem.eql(u8, op, "ge")) return word.GRE;
    if (std.mem.eql(u8, op, "le")) return ap(heap_ptr, word.C, word.GRE); // relop LE
    if (std.mem.eql(u8, op, "cons")) return word.P; // ':' as section
    if (std.mem.eql(u8, op, "plus_plus")) return word.APPEND;
    if (std.mem.eql(u8, op, "minus_minus")) return rt.rs().listdiff_fn;
    if (std.mem.eql(u8, op, "plus")) return word.PLUS;
    if (std.mem.eql(u8, op, "minus")) return word.MINUS;
    if (std.mem.eql(u8, op, "star")) return word.TIMES;
    if (std.mem.eql(u8, op, "slash")) return word.FDIV;
    if (std.mem.eql(u8, op, "kw_div")) return word.INTDIV;
    if (std.mem.eql(u8, op, "kw_mod")) return word.MOD;
    if (std.mem.eql(u8, op, "caret")) return word.POWER;
    if (std.mem.eql(u8, op, "dot")) return word.B; // function composition
    if (std.mem.eql(u8, op, "bang")) return ap(heap_ptr, word.C, word.SUBSCRIPT); // '!'
    if (std.mem.eql(u8, op, "tilde")) return word.NOT;
    if (std.mem.eql(u8, op, "hash")) return word.LENGTH;
    // Miranda keyword built-ins emitted as keyword tokens by the C lexer.
    // SHOWSYM → make(SHOW, 0, 0); READVALSY → make(STARTREADVALS, 0, 0).
    if (std.mem.eql(u8, op, "kw_show")) return heap.make(heap_ptr, .SHOW, 0, 0);
    if (std.mem.eql(u8, op, "kw_readvals")) return heap.make(heap_ptr, .STARTREADVALS, 0, 0);
    if (std.mem.eql(u8, op, "dollars")) return repl_session.session().lastexp;
    // Fall back: user-defined infix operator stored as an identifier
    return nameWord(op);
}

// ---------------------------------------------------------------------------
// Guarded alternatives: build COND chain (mirrors parse_compose logic)
//
// Legacy representation built by YACC (cases list, newest-first):
//   [otherwise_alt, ..., middle_alts, first_alt]
// parse_compose walks it:
//   1. y = last (at h of list); if OTHERWISE, strip marker: y = t(heap_ptr, y)
//      else: if tg(heap_ptr, y)==LABEL, y = label(h(heap_ptr, y), ap(heap_ptr, t(heap_ptr, y),FAIL)); else y = ap(heap_ptr, y,FAIL)
//   2. fold remaining alts (middle, then first): y = label(h, ap(heap_ptr, body, y)); y = ap(heap_ptr, first, y)
//
// We replicate the output directly from our ordered guards list:
//   guards[0]     = first  (no LABEL wrapper in output)
//   guards[1..N-2] = middle (each wrapped in LABEL)
//   guards[N-1]   = last   (otherwise → bare body; conditional → LABEL(COND x y FAIL))
// ---------------------------------------------------------------------------

/// Code a guarded right-hand side (`= e, if g`) into a conditional chain.
fn codegenGuarded(heap_ptr: *heap.Heap, alloc: Allocator, guards: []const ast.Guard) Word {
    const N = guards.len;
    if (N == 0) return word.FAIL;

    const last = guards[N - 1];

    // ── Build starting from the LAST guard ─────────────────────────────────
    var y: Word = undefined;
    if (last.cond == null) {
        if (N == 1) {
            // Single `body, otherwise` → just body (parse_compose strips OTHERWISE)
            return codegenExprRaw(heap_ptr, alloc, last.body);
        }
        // Multi-case last otherwise: LABEL here body
        y = mklabel(heap_ptr, makeHere(heap_ptr, @intCast(last.span.line)), codegenExprRaw(heap_ptr, alloc, last.body));
    } else {
        // Last case is a conditional: LABEL here (COND cond body FAIL) [if N>1]
        //                          or just COND cond body FAIL           [if N==1]
        const cond_w = codegenExprRaw(heap_ptr, alloc, last.cond.?);
        const body_w = codegenExprRaw(heap_ptr, alloc, last.body);
        y = ap(heap_ptr, ap2(heap_ptr, word.COND, cond_w, body_w), word.FAIL);
        if (N > 1) {
            y = mklabel(heap_ptr, makeHere(heap_ptr, @intCast(last.span.line)), y);
        }
    }

    // ── Fold middle guards (indices N-2 down to 1) ─────────────────────────
    if (N > 2) {
        var j: usize = N - 2;
        while (j > 0) : (j -= 1) {
            const g = guards[j];
            const body_w = codegenExprRaw(heap_ptr, alloc, g.body);
            const cond_w = codegenExprRaw(heap_ptr, alloc, g.cond.?);
            y = mklabel(heap_ptr, makeHere(heap_ptr, @intCast(g.span.line)), ap(heap_ptr, ap2(heap_ptr, word.COND, cond_w, body_w), y));
        }
    }

    // ── Apply the FIRST guard (index 0) without a LABEL wrapper ────────────
    if (N > 1) {
        const first = guards[0];
        const cond_w = codegenExprRaw(heap_ptr, alloc, first.cond.?);
        const body_w = codegenExprRaw(heap_ptr, alloc, first.body);
        y = ap(heap_ptr, ap2(heap_ptr, word.COND, cond_w, body_w), y);
    }

    return y;
}

/// A source float literal (e.g. `1e400`) overflowed `f64` during codegen.
/// Reported the same way other codegen-time syntax errors are (`setup.syntax`
/// sets `SYNERR` and resets the lexer; the caller checks `SYNERR` after
/// codegen and discards the result) rather than `fpeError`'s old
/// `siglongjmp` (Phase 3 step 2, docs/GoReady.md).
fn floatLiteralOverflow(heap_ptr: *heap.Heap) Word {
    setup.syntax(heap_ptr, "floating point number out of range\n") catch {};
    return word.NIL;
}

// ---------------------------------------------------------------------------
// String literal → CONS chain of character words
// ---------------------------------------------------------------------------

/// Code a string literal into a cons-list of characters.
fn codegenString(heap_ptr: *heap.Heap, s: []const u8) Word {
    // Walk the UTF-8 string right-to-left; decode codepoints for stoChar.
    var result: Word = word.NIL;
    var i: usize = s.len;
    while (i > 0) {
        // Simple byte-by-byte (ASCII) walk.  For multi-byte UTF-8 we'd need
        // to decode fully, but Miranda source is usually Latin-1 / ASCII.
        i -= 1;
        result = mkcons(heap_ptr, stoChar(@intCast(s[i])), result);
    }
    return result;
}

// ---------------------------------------------------------------------------
// Pattern codegen: like codegenExpr but for LHS pattern positions.
//
// In Miranda, the LHS of a function definition uses `nill` (not NIL) for
// the empty list pattern `[]`.  The YACC grammar v3 production returns
// `nill` directly; we must replicate that here.
// ---------------------------------------------------------------------------

/// Code pattern expression `e` into match-combinator form.
fn codegenPattern(heap_ptr: *heap.Heap, alloc: Allocator, e: ast.Expr) Word {
    return switch (e) {
        // `[]` in a pattern → nill (the empty list pattern atom).
        .list_nil => heap_ptr.nill,

        // Literal constants in patterns must be tagged with `cons(CONST, value)`
        // so the Miranda runtime distinguishes them from binding positions.
        // YACC grammar: `v3: CONST = { $$ = cons(CONST, $1); }`
        // Float literals are invalid in patterns and are rejected here by
        // falling through to codegenExpr (which will produce a heap constant
        // — the type checker will emit the real error).
        .literal => |lit| blk: {
            const val: Word = switch (lit.value) {
                .int => |v| bigscanZ(heap_ptr, alloc, v),
                .char => |c| stoChar(@intCast(c)),
                .string => |s| codegenString(heap_ptr, s),
                .float => |v| stoDbl(v) catch floatLiteralOverflow(heap_ptr), // type checker will reject this later
            };
            break :blk mkcons(heap_ptr, word.CONST, val);
        },

        // Non-empty list literal patterns: cons-chain terminated with nill.
        .list => |items| blk: {
            var result: Word = heap_ptr.nill;
            var i: usize = items.len;
            while (i > 0) {
                i -= 1;
                result = mkcons(heap_ptr, codegenPattern(heap_ptr, alloc, items[i]), result);
            }
            break :blk result;
        },

        // Infix patterns: `:` is list cons; others fall through to expr.
        .infix => |inf| blk: {
            if (std.mem.eql(u8, inf.op, "cons"))
                break :blk mkcons(heap_ptr, codegenPattern(heap_ptr, alloc, inf.lhs.*), codegenPattern(heap_ptr, alloc, inf.rhs.*));
            break :blk codegenExprRaw(heap_ptr, alloc, e);
        },

        // Constructor application in patterns (e.g. `Node l r`).
        .application => |app| ap(heap_ptr, codegenPattern(heap_ptr, alloc, app.func.*), codegenPattern(heap_ptr, alloc, app.arg.*)),

        // Tuple patterns: pair / tcons chain.
        .tuple => |items| blk: {
            if (items.len == 0) break :blk rt.rs().Void;
            if (items.len == 1) break :blk codegenPattern(heap_ptr, alloc, items[0]);
            var result = mkpair(
                heap_ptr,
                codegenPattern(heap_ptr, alloc, items[items.len - 2]),
                codegenPattern(heap_ptr, alloc, items[items.len - 1]),
            );
            var i: usize = items.len - 2;
            while (i > 0) {
                i -= 1;
                result = mktcons(heap_ptr, codegenPattern(heap_ptr, alloc, items[i]), result);
            }
            break :blk result;
        },

        // True/False are CONST tokens in YACC (not CNAME), so patterns using
        // them are wrapped: cons(CONST, atom). Mirror that here.
        .cname => |n| blk: {
            if (std.mem.eql(u8, n.text, "True")) break :blk mkcons(heap_ptr, word.CONST, TRUE_ATOM);
            if (std.mem.eql(u8, n.text, "False")) break :blk mkcons(heap_ptr, word.CONST, FALSE_ATOM);
            break :blk codegenExprRaw(heap_ptr, alloc, e); // regular constructor: used as-is
        },

        // Names and other cases used as-is.
        else => codegenExprRaw(heap_ptr, alloc, e),
    };
}

// ---------------------------------------------------------------------------
// Expression codegen (the heart of Phase 10)
// ---------------------------------------------------------------------------

/// Code an expression AST node `e` into a combinator graph.
fn codegenExprRaw(heap_ptr: *heap.Heap, alloc: Allocator, e: ast.Expr) Word {
    return switch (e) {
        // --- Identifiers ---
        .name => |n| nameWord(n.text),
        // True/False are Miranda predefined atoms, not regular dictionary entries.
        .cname => |n| if (std.mem.eql(u8, n.text, "True")) TRUE_ATOM else if (std.mem.eql(u8, n.text, "False")) FALSE_ATOM else nameWord(n.text),

        // --- Literals ---
        .literal => |lit| switch (lit.value) {
            .int => |v| bigscanZ(heap_ptr, alloc, v),
            .float => |v| stoDbl(v) catch floatLiteralOverflow(heap_ptr),
            .char => |c| stoChar(@intCast(c)),
            .string => |s| codegenString(heap_ptr, s),
        },

        // --- Function application ---
        .application => |app| ap(heap_ptr, codegenExprRaw(heap_ptr, alloc, app.func.*), codegenExprRaw(heap_ptr, alloc, app.arg.*)),

        // --- Infix operators ---
        .infix => |inf| blk: {
            const op = inf.op;
            const lhs = codegenExprRaw(heap_ptr, alloc, inf.lhs.*);
            const rhs_w = codegenExprRaw(heap_ptr, alloc, inf.rhs.*);
            // '!' subscript: args are REVERSED — ap2(heap_ptr, SUBSCRIPT, rhs, lhs)
            if (std.mem.eql(u8, op, "bang")) break :blk ap2(heap_ptr, word.SUBSCRIPT, rhs_w, lhs);
            // ':' list cons: make(CONS, lhs, rhs)
            if (std.mem.eql(u8, op, "cons")) break :blk mkcons(heap_ptr, lhs, rhs_w);
            // All other operators: ap2(heap_ptr, opWord, lhs, rhs)
            break :blk ap2(heap_ptr, opWord(heap_ptr, op), lhs, rhs_w);
        },

        // --- Unary operators ---
        .neg => |ep| ap(heap_ptr, word.NEG, codegenExprRaw(heap_ptr, alloc, ep.*)),
        .length => |ep| ap(heap_ptr, word.LENGTH, codegenExprRaw(heap_ptr, alloc, ep.*)),

        // --- List literals ---
        .list_nil => word.NIL,
        .list => |items| blk: {
            var result: Word = word.NIL;
            var i: usize = items.len;
            while (i > 0) {
                i -= 1;
                result = mkcons(heap_ptr, codegenExprRaw(heap_ptr, alloc, items[i]), result);
            }
            break :blk result;
        },

        // --- Tuple literals ---
        // (a, b)       → pair(a, b)
        // (a, b, c)    → tcons(a, pair(b, c))
        // (a, b, c, d) → tcons(a, tcons(b, pair(c, d)))
        // ()           → rt.rs().Void
        .tuple => |items| blk: {
            if (items.len == 0) break :blk rt.rs().Void;
            if (items.len == 1) break :blk codegenExprRaw(heap_ptr, alloc, items[0]); // degenerate
            var result = mkpair(
                heap_ptr,
                codegenExprRaw(heap_ptr, alloc, items[items.len - 2]),
                codegenExprRaw(heap_ptr, alloc, items[items.len - 1]),
            );
            var i: usize = items.len - 2;
            while (i > 0) {
                i -= 1;
                result = mktcons(heap_ptr, codegenExprRaw(heap_ptr, alloc, items[i]), result);
            }
            break :blk result;
        },

        // --- Type annotation: discard type, keep expression ---
        .typed => |typed| codegenExprRaw(heap_ptr, alloc, typed.expr.*),

        // --- Where clause: block(ldefs, body, 0) ---
        .where => |w| applyWhereDefs(heap_ptr, alloc, codegenExprRaw(heap_ptr, alloc, w.body.*), w.defs),

        // --- Conditional guard (internal) ---
        .cond => |cond| ap2(heap_ptr, word.COND, codegenExprRaw(heap_ptr, alloc, cond.guard.*), codegenExprRaw(heap_ptr, alloc, cond.then_expr.*)),

        // --- Left section (e op) → ap(heap_ptr, opWord, e) ---
        .section_left => |s| ap(heap_ptr, opWord(heap_ptr, s.op), codegenExprRaw(heap_ptr, alloc, s.arg.*)),

        // --- Right/post section (op e) ---
        // Mirrors rules.y: '(' diop1 e1 ')' → if op_word = ap(heap_ptr, C,x) then ap(heap_ptr, x,e) else ap2(heap_ptr, C,op,e)
        .section_right => |s| blk: {
            const arg_w = codegenExprRaw(heap_ptr, alloc, s.arg.*);
            // Special-case operators whose opWord is already ap(heap_ptr, C,x):
            if (std.mem.eql(u8, s.op, "lt")) break :blk ap(heap_ptr, word.GR, arg_w);
            if (std.mem.eql(u8, s.op, "le")) break :blk ap(heap_ptr, word.GRE, arg_w);
            if (std.mem.eql(u8, s.op, "bang")) break :blk ap(heap_ptr, word.SUBSCRIPT, arg_w);
            break :blk ap2(heap_ptr, word.C, opWord(heap_ptr, s.op), arg_w);
        },

        // --- Operator-as-function: (+), (*), … ---
        .op_func => |op| opWord(heap_ptr, op),

        // --- Arithmetic sequences ---
        // [from..]         → ap2(heap_ptr, STEP, big_one, from)
        // [from..to]       → ap3(heap_ptr, STEPUNTIL, big_one, to, from)
        // [from,step..]    → ap2(heap_ptr, STEP, step-from, from)
        // [from,step..to]  → ap3(heap_ptr, STEPUNTIL, step-from, to, from)
        .range => |r| blk: {
            const from_w = codegenExprRaw(heap_ptr, alloc, r.from.*);
            if (r.step) |step_ptr| {
                const step_w = codegenExprRaw(heap_ptr, alloc, step_ptr.*);
                const delta = ap2(heap_ptr, word.MINUS, step_w, from_w);
                if (r.to) |to_ptr| {
                    break :blk ap3(heap_ptr, word.STEPUNTIL, delta, codegenExprRaw(heap_ptr, alloc, to_ptr.*), from_w);
                } else {
                    break :blk ap2(heap_ptr, word.STEP, delta, from_w);
                }
            } else {
                if (r.to) |to_ptr| {
                    break :blk ap3(heap_ptr, word.STEPUNTIL, big.bn().big_one, codegenExprRaw(heap_ptr, alloc, to_ptr.*), from_w);
                } else {
                    break :blk ap2(heap_ptr, word.STEP, big.bn().big_one, from_w);
                }
            }
        },

        // --- List comprehension: compzf(body, qualifiers, 0) ---
        // Qualifiers must be passed in REVERSED order (newest first).
        .listcomp => |lc| blk: {
            var qq: Word = word.NIL;
            for (lc.qualifiers) |q| {
                const qw: Word = switch (q) {
                    .generator => |g| gen: {
                        // The YACC grammar resets `idsused=NIL` after each
                        // generator's genlhs() call (rules.y:927,932,934).
                        // Mirror that here so each generator's LHS variables
                        // are treated as fresh bindings, not references.
                        ls().idsused = word.NIL;
                        const lhs_w = genlhs(heap_ptr, Value.fromRaw(codegenExprRaw(heap_ptr, alloc, g.pat))).toRaw();
                        ls().idsused = word.NIL;
                        break :gen mkcons(
                            heap_ptr,
                            word.GENERATOR,
                            mkcons(heap_ptr, lhs_w, codegenExprRaw(heap_ptr, alloc, g.source.*)),
                        );
                    },
                    // Sequence generator: `pat <- src, step ..`
                    // Mirrors rules.y: cons(GENERATOR, cons(p, ap2(heap_ptr, ITERATE/ITERATE1, lambda(p,step), src)))
                    .sequence_generator => |sg| sgen: {
                        ls().idsused = word.NIL;
                        const lhs_w = genlhs(heap_ptr, Value.fromRaw(codegenExprRaw(heap_ptr, alloc, sg.pat))).toRaw();
                        ls().idsused = word.NIL;
                        const src_w = codegenExprRaw(heap_ptr, alloc, sg.source.*);
                        const step_w = codegenExprRaw(heap_ptr, alloc, sg.step.*);
                        const comb: Word = if (irrefutable(heap_ptr, lhs_w) != 0) word.ITERATE else word.ITERATE1;
                        break :sgen mkcons(
                            heap_ptr,
                            word.GENERATOR,
                            mkcons(heap_ptr, lhs_w, ap2(heap_ptr, comb, mklambda(heap_ptr, lhs_w, step_w), src_w)),
                        );
                    },
                    .guard => |gp| mkcons(heap_ptr, word.GUARD, codegenExprRaw(heap_ptr, alloc, gp.*)),
                };
                qq = mkcons(heap_ptr, qw, qq); // prepend → reverses order
            }
            break :blk compzf(heap_ptr, codegenExprRaw(heap_ptr, alloc, lc.body.*), qq, 0);
        },
    };
}

/// `Value`-typed wrapper for `codegenExprRaw` (§ GoReady Phase 5 step 4).
pub fn codegenExpr(heap_ptr: *heap.Heap, alloc: Allocator, e: ast.Expr) Value {
    return Value.fromRaw(codegenExprRaw(heap_ptr, alloc, e));
}

// ---------------------------------------------------------------------------
// LHS expression codegen: function application arguments use codegenPattern.
//
// The LHS of a definition is structured as ap(heap_ptr, ap(heap_ptr, f, arg1), arg2) etc.
// Each arg is a PATTERN, so use codegenPattern instead of codegenExpr.
// ---------------------------------------------------------------------------

/// Code the left-hand side of a definition (the name/pattern being defined).
fn codegenLhsExpr(heap_ptr: *heap.Heap, alloc: Allocator, e: ast.Expr) Word {
    return switch (e) {
        .application => |app| ap(heap_ptr, codegenLhsExpr(heap_ptr, alloc, app.func.*), codegenPattern(heap_ptr, alloc, app.arg.*)),
        else => codegenExprRaw(heap_ptr, alloc, e),
    };
}

// ---------------------------------------------------------------------------
// RHS codegen
// ---------------------------------------------------------------------------

/// Code a right-hand side, guarded or plain, including any `where`.
fn codegenRhs(heap_ptr: *heap.Heap, alloc: Allocator, rhs: ast.Rhs) Word {
    return switch (rhs) {
        .expr => |e| codegenExprRaw(heap_ptr, alloc, e),
        .guarded => |guards| codegenGuarded(heap_ptr, alloc, guards),
    };
}

// ---------------------------------------------------------------------------
// Where-clause codegen helpers
// ---------------------------------------------------------------------------

// Mirrors the YACC `ldef` production: returns defn(lhs, undef_t, label(here, rhs)).
// The tries() wrapping is NOT done here — buildLdefs handles it so consecutive
// equations for the same function can be merged into a single TRIES list.
/// Code a single local (`where`) definition.
fn codegenLocalDef(heap_ptr: *heap.Heap, alloc: Allocator, def: ast.Def) Word {
    const here = makeHere(heap_ptr, @intCast(def.span.line));
    var lhs = codegenLhsExpr(heap_ptr, alloc, def.lhs);
    var rhs = codegenRhs(heap_ptr, alloc, def.rhs);

    // Apply nested where clause before lambda-desugaring.
    rhs = applyWhereDefs(heap_ptr, alloc, rhs, def.where_defs);

    // Lambda-desugar: f x y = body → lhs becomes f, rhs gets lambda wrappers
    const f = head(heap_ptr, Value.fromRaw(lhs)).toRaw();
    if (tg(heap_ptr, f) == .ID and !isConstructorWord(heap_ptr, f)) {
        while (tg(heap_ptr, lhs) == .AP) {
            rhs = mklambda(heap_ptr, t(heap_ptr, lhs), rhs);
            lhs = h(heap_ptr, lhs);
        }
    }
    const labeled = mklabel(heap_ptr, here, rhs);
    return mkcons(heap_ptr, lhs, mkcons(heap_ptr, undef_t, labeled));
}

// Mirrors the YACC `ldefs` production: builds the defn list and merges
// consecutive equations for the same function into one defn with a shared
// TRIES list. Without merging, block() sees two separate defns for `f` and
// marks the second as unused via invgetrel().
//
// YACC rule (rules.y:1199):
//   if(dlhs($2)==dlhs(hd($1)))
//     tl(dval(hd($1)))=cons(dval($2),tl(dval(hd($1))));   // merge
//   else { $$=cons($2,$1); dval($2)=tries(...); }          // new entry
/// Build the binding list for a `letrec` of local definitions.
fn buildLdefs(heap_ptr: *heap.Heap, alloc: Allocator, where_defs: []const ast.Def) Word {
    var ldefs: Word = word.NIL;
    for (where_defs) |wd| {
        const cell = codegenLocalDef(heap_ptr, alloc, wd); // defn(lhs, undef_t, labeled)
        const lhs_word = h(heap_ptr, cell);
        const labeled = t(heap_ptr, t(heap_ptr, cell)); // dval(cell) = the labeled rhs
        if (ldefs != word.NIL and h(heap_ptr, h(heap_ptr, ldefs)) == lhs_word) {
            // Same function as head of ldefs: prepend labeled to its tries list.
            // tries_cell = dval(hd(ldefs)) = tl(tl(hd(ldefs)))
            const tries_cell = t(heap_ptr, t(heap_ptr, h(heap_ptr, ldefs)));
            tp(heap_ptr, tries_cell).* = mkcons(heap_ptr, labeled, t(heap_ptr, tries_cell));
        } else {
            // New function: wrap dval in tries(lhs, [labeled]) and prepend to ldefs.
            const new_tries = heap.tries(lhs_word, mkcons(heap_ptr, labeled, word.NIL));
            tp(heap_ptr, t(heap_ptr, cell)).* = new_tries;
            ldefs = mkcons(heap_ptr, cell, ldefs);
        }
    }
    return ldefs;
}

/// Wrap expression `e` in its `where` definitions (as a `letrec`).
fn applyWhereDefs(heap_ptr: *heap.Heap, alloc: Allocator, e: Word, where_defs: []const ast.Def) Word {
    if (where_defs.len == 0) return e;
    return block(heap_ptr, buildLdefs(heap_ptr, alloc, where_defs), e, 0);
}

// ---------------------------------------------------------------------------
// Top-level definition codegen: declares lhs in the environment
// ---------------------------------------------------------------------------

/// Code a top-level definition and install it in the environment.
fn codegenDef(heap_ptr: *heap.Heap, alloc: Allocator, def: ast.Def) void {
    const here = makeHere(heap_ptr, @intCast(def.span.line));
    var lhs = codegenLhsExpr(heap_ptr, alloc, def.lhs);
    var rhs = codegenRhs(heap_ptr, alloc, def.rhs);

    // Apply where clause (block wraps the rhs before lambda-desugaring).
    rhs = applyWhereDefs(heap_ptr, alloc, rhs, def.where_defs);

    // Lambda-desugar
    const f = head(heap_ptr, Value.fromRaw(lhs)).toRaw();
    if (tg(heap_ptr, f) == .ID and !isConstructorWord(heap_ptr, f)) {
        while (tg(heap_ptr, lhs) == .AP) {
            rhs = mklambda(heap_ptr, t(heap_ptr, lhs), rhs);
            lhs = h(heap_ptr, lhs);
        }
    }
    rhs = mklabel(heap_ptr, here, rhs);
    declare(heap_ptr, lhs, rhs);
    // Mirror the YACC grammar: `declare(l,r), script_store.store().lastname=l` — allows
    // consecutive equations for the same function to be accumulated
    // by decl1 rather than triggering a nameclash error.
    script_store.store().lastname = lhs;
}

// ---------------------------------------------------------------------------
// Type specification codegen
// ---------------------------------------------------------------------------

/// Code a type signature (`::`) declaration.
fn codegenTypeSpec(heap_ptr: *heap.Heap, ts: ast.TypeSpec) void {
    const here = makeHere(heap_ptr, @intCast(ts.span.line));
    const type_w = codegenType(heap_ptr, ts.typ);
    for (ts.names) |name| {
        specify(heap_ptr, nameWord(name), type_w, here);
    }
}

// ---------------------------------------------------------------------------
// Type declaration codegen
// ---------------------------------------------------------------------------

/// Code a type/data declaration (`==` / `::=`).
fn codegenTypeDecl(heap_ptr: *heap.Heap, td: ast.TypeDecl) void {
    switch (td) {
        // --- type synonym: type name params == body ---
        .synonym => |s| {
            const here = makeHere(heap_ptr, @intCast(s.span.line));
            // Build typeform: ap(heap_ptr, ap(heap_ptr, name_id, tvar1), tvar2, …)
            var tf = nameWord(s.name);
            for (s.params) |p| tf = ap(heap_ptr, tf, codegenTypeVar(heap_ptr, p));
            // redtvars(ap(heap_ptr, typeform, body)) normalises type vars
            const body_w = codegenType(heap_ptr, s.body);
            const x = redtvars(heap_ptr, ap(heap_ptr, tf, body_w));
            declType(heap_ptr, h(heap_ptr, x), word.synonym_t, t(heap_ptr, x), here);
        },

        // --- algebraic type: name params ::= C1 fields | C2 fields | … ---
        .algebraic => |a| {
            const here = makeHere(heap_ptr, @intCast(a.span.line));
            var tf = nameWord(a.name);
            for (a.params) |p| tf = ap(heap_ptr, tf, codegenTypeVar(heap_ptr, p));

            // Build construction list in REVERSED order (mirrors rules.y `constructs`)
            var construction: Word = word.NIL;
            for (a.constructors) |ctor| {
                var cw = nameWord(ctor.name);
                for (ctor.fields) |field| cw = ap(heap_ptr, cw, codegenType(heap_ptr, field));
                construction = mkcons(heap_ptr, cw, construction);
            }

            // Iterate through reversed construction; peel AP fields to build ctor type
            var n: Word = @intCast(a.constructors.len);
            var r_ids: Word = word.NIL;
            var rhs = construction;
            while (rhs != word.NIL) {
                var hv = h(heap_ptr, rhs);
                var ct = tf;
                while (tg(heap_ptr, hv) == .AP) {
                    ct = ap2(heap_ptr, arrow_t, t(heap_ptr, hv), ct);
                    hv = h(heap_ptr, hv);
                }
                n -= 1;
                _ = declconstr(heap_ptr, hv, n, ct);
                r_ids = mkcons(heap_ptr, hv, r_ids);
                rhs = t(heap_ptr, rhs);
            }
            declType(heap_ptr, tf, word.algebraic_t, r_ids, here);
        },

        // --- abstype: abstype name params with specs ---
        .abstype => |a| {
            const here = makeHere(heap_ptr, @intCast(a.span.line));
            // Specify each operation in the abstract type
            for (a.specs) |spec| {
                const spec_here = makeHere(heap_ptr, @intCast(spec.span.line));
                const type_w = codegenType(heap_ptr, spec.typ);
                for (spec.names) |name| {
                    specify(heap_ptr, nameWord(name), type_w, spec_here);
                }
            }
            // Declare the abstract type itself
            var tf = nameWord(a.name);
            for (a.params) |p| tf = ap(heap_ptr, tf, codegenTypeVar(heap_ptr, p));
            declType(heap_ptr, tf, word.abstract_t, word.undef_t, here);
        },
    }
}

// ---------------------------------------------------------------------------
// Script entry point
// ---------------------------------------------------------------------------

/// Code an entire parsed `script` — the codegen entry point.
pub fn codegenScript(heap_ptr: *heap.Heap, alloc: Allocator, script: ast.Script) void {
    for (script.items) |item| {
        switch (item) {
            .definition => |def| codegenDef(heap_ptr, alloc, def),
            .type_spec => |ts| codegenTypeSpec(heap_ptr, ts),
            .type_decl => |td| codegenTypeDecl(heap_ptr, td),
            .eval => |e| {
                _ = codegenExprRaw(heap_ptr, alloc, e);
            },
            // Directives are handled at a higher level (file inclusion etc.)
            // -- .directive is the native-pipeline counterpart of the three
            // above (see ast.zig's TopLevel doc comment); same no-op today.
            .include, .export_list, .free_directive, .directive => {},
        }
    }
}
