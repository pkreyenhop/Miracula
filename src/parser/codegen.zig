//! Phase 10: AST → Miranda heap codegen.
//! Walks ast.Script and produces the same Word heap values as the legacy YACC parser.
//! IMPORTANT: this file calls C runtime functions and must NOT be imported from the
//! pure parser-tests binary (src/parser/parser.zig).  Import it from parser_api.zig or main.zig.

const std = @import("std");
const word = @import("../runtime/word.zig");
const strtab = @import("../runtime/strtab.zig");
const Allocator = std.mem.Allocator;
const ast = @import("ast.zig");

const main = @import("../main.zig");
const lex_state = @import("lex_state.zig");
const ls = lex_state.ls;
// Cross-module functions via direct @import (R7.3 — eliminate extern-fn linker decls).
const trans = @import("../compiler/trans.zig");
const types_mod = @import("../compiler/types.zig");
const big = @import("../runtime/big.zig");
const lex = @import("lex.zig");
const reduce_mod = @import("../runtime/reduce.zig");
const heap = @import("../runtime/heap.zig");
const core_state = @import("../runtime/core_state.zig");

const Word = word.Word;

// Miranda predefined atom words (from lex.zig — keep in sync with CMBASE = 306).
const CMBASE: Word = 306;
const FALSE_ATOM: Word = CMBASE + 136;
const TRUE_ATOM: Word = CMBASE + 137;

// ---------------------------------------------------------------------------
// Heap cell accessors
// ---------------------------------------------------------------------------

inline fn h(x: Word) Word {
    return heap.heap.h(x);
}
inline fn t(x: Word) Word {
    return heap.heap.t(x);
}
inline fn tp(x: Word) *Word {
    return heap.heap.tp(x);
}
inline fn tg(x: Word) u8 {
    return heap.heap.getTag(x);
}

// ---------------------------------------------------------------------------
// Heap construction helpers (mirrors data.h macros)
// ---------------------------------------------------------------------------

inline fn ap(x: Word, y: Word) Word {
    return heap.make(word.AP, x, y);
}
inline fn ap2(x: Word, y: Word, z: Word) Word {
    return ap(ap(x, y), z);
}
inline fn ap3(w: Word, x: Word, y: Word, z: Word) Word {
    return ap(ap2(w, x, y), z);
}
inline fn mkcons(x: Word, y: Word) Word {
    return heap.make(word.CONS, x, y);
}
inline fn mklabel(x: Word, y: Word) Word {
    return heap.make(word.LABEL, x, y);
}
inline fn mklambda(x: Word, y: Word) Word {
    return heap.make(word.LAMBDA, x, y);
}
inline fn mkpair(x: Word, y: Word) Word {
    return heap.make(word.PAIR, x, y);
}
inline fn mktcons(x: Word, y: Word) Word {
    return heap.make(word.TCONS, x, y);
}

// ---------------------------------------------------------------------------
// C function externs
// ---------------------------------------------------------------------------

const genlhs = trans.genlhs;
const irrefutable = trans.irrefutable;
const compzf = trans.compzf;
const block = trans.block;
const declare = trans.declare;
const specify = trans.specify;
const declType = trans.declType;
const declconstr = trans.declconstr;
const redtvars = types_mod.redtvars;
const bigscan = big.scanDecimal;
const stoDbl = heap.stoDbl;
const stoId = heap.stoId;
const keep = lex.keep;
const findid = lex.findid;
const makeId = lex.makeId;
const stoChar = heap.stoChar;
const head = reduce_mod.head;
const isconstrname = lex.isconstrname;

/// Parse decimal `text` into a bignum (via a temporary NUL-terminated copy).
fn bigscanZ(alloc: Allocator, text: []const u8) Word {
    const z = alloc.dupeSentinel(u8, text, 0) catch return word.NIL;
    return bigscan(z.ptr);
}

// ---------------------------------------------------------------------------
// Runtime globals
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Type constants (from data.h — replicated so we don't need the macros)
// ---------------------------------------------------------------------------

const undef_t: Word = 0; // #define undef_t 0
const arrow_t: Word = 6; // #define arrow_t 6
const list_t: Word = 4; // #define list_t  4
const comma_t: Word = 5; // #define comma_t 5
const void_t: Word = 7; // #define void_t  7

// ---------------------------------------------------------------------------
// 'here' generation: fileinfo(get_fil(current_file), line_no)
// ---------------------------------------------------------------------------

/// Build a source-location (`HERE`) marker node for `line`.
fn makeHere(line: u32) Word {
    // get_fil(current_file) = (char*)hd(hd(hd(current_file)))
    const fil_name = h(h(h(heap.heap.current_file)));
    return heap.make(word.FILEINFO, fil_name, @intCast(line));
}

// ---------------------------------------------------------------------------
// Helper: is this ID word a constructor name?
// ---------------------------------------------------------------------------

/// Whether heap word `x` is a constructor identifier.
fn isConstructorWord(x: Word) bool {
    if (tg(x) != word.ID) return false;
    // get_id(x) = (char*)hd(hd(hd(x)))
    const name_ptr: [*:0]const u8 = strtab.strOf(h(h(h(x))));
    return isconstrname(name_ptr) != 0;
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
    // definitions: decl1() checks `main.rs.lastname == x` using pointer equality.
    const existing = findid(&buf);
    if (existing != word.NIL) return existing;
    // Not yet in the name table (e.g., synthesised names). Intern it now.
    const perm = keep(@as([*:0]u8, @ptrCast(&buf)));
    return makeId(perm);
}

// ---------------------------------------------------------------------------
// Type variable: convert name string to TVAR cell
//   "*"   → make(TVAR, 0, 1)
//   "**"  → make(TVAR, 0, 2)
//   "***" → make(TVAR, 0, 3)
//   "*a"  → stoId("*a")  (named typevar — fall back to ident)
// ---------------------------------------------------------------------------

/// Code a type variable named `name`.
fn codegenTypeVar(name: []const u8) Word {
    var star_count: Word = 0;
    for (name) |c| {
        if (c == '*') star_count += 1 else break;
    }
    if (star_count == @as(Word, @intCast(name.len))) {
        // Pure-star type variable: *, **, ***, …
        return heap.make(word.TVAR, 0, star_count);
    }
    // Named type variable like *a, *b — treat as identifier for now
    return nameWord(name);
}

// ---------------------------------------------------------------------------
// Type expression codegen
// ---------------------------------------------------------------------------

/// Code a type expression `te` into its runtime type node.
fn codegenType(te: ast.TypeExpr) Word {
    return switch (te) {
        .type_var => |v| codegenTypeVar(v.name),
        .type_name => |n| nameWord(n.name),
        .arrow => |a| ap2(arrow_t, codegenType(a.from.*), codegenType(a.to.*)),
        .type_app => |ta| blk: {
            var result = codegenType(ta.func.*);
            for (ta.args) |arg| result = ap(result, codegenType(arg));
            break :blk result;
        },
        .tuple => |types| blk: {
            if (types.len == 0) break :blk void_t;
            // (T1, T2, ..., Tn) = ap2(comma_t, T1, ap2(comma_t, T2, ... void_t...))
            var result: Word = void_t;
            var i: usize = types.len;
            while (i > 0) {
                i -= 1;
                result = ap2(comma_t, codegenType(types[i]), result);
            }
            break :blk result;
        },
        .list => |inner| ap(list_t, codegenType(inner.*)),
        .void_t => void_t,
    };
}

// ---------------------------------------------------------------------------
// Operator → Word mapping (diop/relop table from rules.y)
// ---------------------------------------------------------------------------

/// Map an operator symbol `op` to its combinator/atom word.
fn opWord(op: []const u8) Word {
    if (std.mem.eql(u8, op, "vel")) return word.OR;
    if (std.mem.eql(u8, op, "amp")) return word.AND;
    if (std.mem.eql(u8, op, "eq")) return word.EQ;
    if (std.mem.eql(u8, op, "eqeq")) return word.EQ;
    if (std.mem.eql(u8, op, "ne")) return word.NEQ;
    if (std.mem.eql(u8, op, "gt")) return word.GR;
    if (std.mem.eql(u8, op, "lt")) return ap(word.C, word.GR); // relop '<'
    if (std.mem.eql(u8, op, "ge")) return word.GRE;
    if (std.mem.eql(u8, op, "le")) return ap(word.C, word.GRE); // relop LE
    if (std.mem.eql(u8, op, "cons")) return word.P; // ':' as section
    if (std.mem.eql(u8, op, "plus_plus")) return word.APPEND;
    if (std.mem.eql(u8, op, "minus_minus")) return main.rs.listdiff_fn;
    if (std.mem.eql(u8, op, "plus")) return word.PLUS;
    if (std.mem.eql(u8, op, "minus")) return word.MINUS;
    if (std.mem.eql(u8, op, "star")) return word.TIMES;
    if (std.mem.eql(u8, op, "slash")) return word.FDIV;
    if (std.mem.eql(u8, op, "kw_div")) return word.INTDIV;
    if (std.mem.eql(u8, op, "kw_mod")) return word.MOD;
    if (std.mem.eql(u8, op, "caret")) return word.POWER;
    if (std.mem.eql(u8, op, "dot")) return word.B; // function composition
    if (std.mem.eql(u8, op, "bang")) return ap(word.C, word.SUBSCRIPT); // '!'
    if (std.mem.eql(u8, op, "tilde")) return word.NOT;
    if (std.mem.eql(u8, op, "hash")) return word.LENGTH;
    // Miranda keyword built-ins emitted as keyword tokens by the C lexer.
    // SHOWSYM → make(SHOW, 0, 0); READVALSY → make(STARTREADVALS, 0, 0).
    if (std.mem.eql(u8, op, "kw_show")) return heap.make(word.SHOW, 0, 0);
    if (std.mem.eql(u8, op, "kw_readvals")) return heap.make(word.STARTREADVALS, 0, 0);
    if (std.mem.eql(u8, op, "dollars")) return main.rs.lastexp;
    // Fall back: user-defined infix operator stored as an identifier
    return nameWord(op);
}

// ---------------------------------------------------------------------------
// Guarded alternatives: build COND chain (mirrors parse_compose logic)
//
// Legacy representation built by YACC (cases list, newest-first):
//   [otherwise_alt, ..., middle_alts, first_alt]
// parse_compose walks it:
//   1. y = last (at h of list); if OTHERWISE, strip marker: y = t(y)
//      else: if tg(y)==LABEL, y = label(h(y), ap(t(y),FAIL)); else y = ap(y,FAIL)
//   2. fold remaining alts (middle, then first): y = label(h, ap(body, y)); y = ap(first, y)
//
// We replicate the output directly from our ordered guards list:
//   guards[0]     = first  (no LABEL wrapper in output)
//   guards[1..N-2] = middle (each wrapped in LABEL)
//   guards[N-1]   = last   (otherwise → bare body; conditional → LABEL(COND x y FAIL))
// ---------------------------------------------------------------------------

/// Code a guarded right-hand side (`= e, if g`) into a conditional chain.
fn codegenGuarded(alloc: Allocator, guards: []const ast.Guard) Word {
    const N = guards.len;
    if (N == 0) return word.FAIL;

    const last = guards[N - 1];

    // ── Build starting from the LAST guard ─────────────────────────────────
    var y: Word = undefined;
    if (last.is_otherwise) {
        if (N == 1) {
            // Single `body, otherwise` → just body (parse_compose strips OTHERWISE)
            return codegenExpr(alloc, last.body);
        }
        // Multi-case last otherwise: LABEL here body
        y = mklabel(makeHere(@intCast(last.span.line)), codegenExpr(alloc, last.body));
    } else {
        // Last case is a conditional: LABEL here (COND cond body FAIL) [if N>1]
        //                          or just COND cond body FAIL           [if N==1]
        const cond_w = codegenExpr(alloc, last.cond);
        const body_w = codegenExpr(alloc, last.body);
        y = ap(ap2(word.COND, cond_w, body_w), word.FAIL);
        if (N > 1) {
            y = mklabel(makeHere(@intCast(last.span.line)), y);
        }
    }

    // ── Fold middle guards (indices N-2 down to 1) ─────────────────────────
    if (N > 2) {
        var j: usize = N - 2;
        while (j > 0) : (j -= 1) {
            const g = guards[j];
            const body_w = codegenExpr(alloc, g.body);
            const cond_w = codegenExpr(alloc, g.cond);
            y = mklabel(makeHere(@intCast(g.span.line)), ap(ap2(word.COND, cond_w, body_w), y));
        }
    }

    // ── Apply the FIRST guard (index 0) without a LABEL wrapper ────────────
    if (N > 1) {
        const first = guards[0];
        const cond_w = codegenExpr(alloc, first.cond);
        const body_w = codegenExpr(alloc, first.body);
        y = ap(ap2(word.COND, cond_w, body_w), y);
    }

    return y;
}

// ---------------------------------------------------------------------------
// String literal → CONS chain of character words
// ---------------------------------------------------------------------------

/// Code a string literal into a cons-list of characters.
fn codegenString(s: []const u8) Word {
    // Walk the UTF-8 string right-to-left; decode codepoints for stoChar.
    var result: Word = word.NIL;
    var i: usize = s.len;
    while (i > 0) {
        // Simple byte-by-byte (ASCII) walk.  For multi-byte UTF-8 we'd need
        // to decode fully, but Miranda source is usually Latin-1 / ASCII.
        i -= 1;
        result = mkcons(stoChar(@intCast(s[i])), result);
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
fn codegenPattern(alloc: Allocator, e: ast.Expr) Word {
    return switch (e) {
        // `[]` in a pattern → nill (the empty list pattern atom).
        .list_nil => core_state.s.nill,

        // Literal constants in patterns must be tagged with `cons(CONST, value)`
        // so the Miranda runtime distinguishes them from binding positions.
        // YACC grammar: `v3: CONST = { $$ = cons(CONST, $1); }`
        // Float literals are invalid in patterns and are rejected here by
        // falling through to codegenExpr (which will produce a heap constant
        // — the type checker will emit the real error).
        .literal => |lit| blk: {
            const val: Word = switch (lit.value) {
                .int => |v| bigscanZ(alloc, v),
                .char => |c| stoChar(@intCast(c)),
                .string => |s| codegenString(s),
                .float => |v| stoDbl(v), // type checker will reject this later
            };
            break :blk mkcons(word.CONST, val);
        },

        // Non-empty list literal patterns: cons-chain terminated with nill.
        .list => |items| blk: {
            var result: Word = core_state.s.nill;
            var i: usize = items.len;
            while (i > 0) {
                i -= 1;
                result = mkcons(codegenPattern(alloc, items[i]), result);
            }
            break :blk result;
        },

        // Infix patterns: `:` is list cons; others fall through to expr.
        .infix => |inf| blk: {
            if (std.mem.eql(u8, inf.op, "cons"))
                break :blk mkcons(codegenPattern(alloc, inf.lhs.*), codegenPattern(alloc, inf.rhs.*));
            break :blk codegenExpr(alloc, e);
        },

        // Constructor application in patterns (e.g. `Node l r`).
        .application => |app| ap(codegenPattern(alloc, app.func.*), codegenPattern(alloc, app.arg.*)),

        // Tuple patterns: pair / tcons chain.
        .tuple => |items| blk: {
            if (items.len == 0) break :blk main.rs.Void;
            if (items.len == 1) break :blk codegenPattern(alloc, items[0]);
            var result = mkpair(
                codegenPattern(alloc, items[items.len - 2]),
                codegenPattern(alloc, items[items.len - 1]),
            );
            var i: usize = items.len - 2;
            while (i > 0) {
                i -= 1;
                result = mktcons(codegenPattern(alloc, items[i]), result);
            }
            break :blk result;
        },

        // True/False are CONST tokens in YACC (not CNAME), so patterns using
        // them are wrapped: cons(CONST, atom). Mirror that here.
        .cname => |n| blk: {
            if (std.mem.eql(u8, n.text, "True")) break :blk mkcons(word.CONST, TRUE_ATOM);
            if (std.mem.eql(u8, n.text, "False")) break :blk mkcons(word.CONST, FALSE_ATOM);
            break :blk codegenExpr(alloc, e); // regular constructor: used as-is
        },

        // Names and other cases used as-is.
        else => codegenExpr(alloc, e),
    };
}

// ---------------------------------------------------------------------------
// Expression codegen (the heart of Phase 10)
// ---------------------------------------------------------------------------

/// Code an expression AST node `e` into a combinator graph.
pub fn codegenExpr(alloc: Allocator, e: ast.Expr) Word {
    return switch (e) {
        // --- Identifiers ---
        .name => |n| nameWord(n.text),
        // True/False are Miranda predefined atoms, not regular dictionary entries.
        .cname => |n| if (std.mem.eql(u8, n.text, "True")) TRUE_ATOM else if (std.mem.eql(u8, n.text, "False")) FALSE_ATOM else nameWord(n.text),

        // --- Literals ---
        .literal => |lit| switch (lit.value) {
            .int => |v| bigscanZ(alloc, v),
            .float => |v| stoDbl(v),
            .char => |c| stoChar(@intCast(c)),
            .string => |s| codegenString(s),
        },

        // --- Function application ---
        .application => |app| ap(codegenExpr(alloc, app.func.*), codegenExpr(alloc, app.arg.*)),

        // --- Infix operators ---
        .infix => |inf| blk: {
            const op = inf.op;
            const lhs = codegenExpr(alloc, inf.lhs.*);
            const rhs_w = codegenExpr(alloc, inf.rhs.*);
            // '!' subscript: args are REVERSED — ap2(SUBSCRIPT, rhs, lhs)
            if (std.mem.eql(u8, op, "bang")) break :blk ap2(word.SUBSCRIPT, rhs_w, lhs);
            // ':' list cons: make(CONS, lhs, rhs)
            if (std.mem.eql(u8, op, "cons")) break :blk mkcons(lhs, rhs_w);
            // All other operators: ap2(opWord, lhs, rhs)
            break :blk ap2(opWord(op), lhs, rhs_w);
        },

        // --- Unary operators ---
        .neg => |ep| ap(word.NEG, codegenExpr(alloc, ep.*)),
        .length => |ep| ap(word.LENGTH, codegenExpr(alloc, ep.*)),

        // --- List literals ---
        .list_nil => word.NIL,
        .list => |items| blk: {
            var result: Word = word.NIL;
            var i: usize = items.len;
            while (i > 0) {
                i -= 1;
                result = mkcons(codegenExpr(alloc, items[i]), result);
            }
            break :blk result;
        },

        // --- Tuple literals ---
        // (a, b)       → pair(a, b)
        // (a, b, c)    → tcons(a, pair(b, c))
        // (a, b, c, d) → tcons(a, tcons(b, pair(c, d)))
        // ()           → main.rs.Void
        .tuple => |items| blk: {
            if (items.len == 0) break :blk main.rs.Void;
            if (items.len == 1) break :blk codegenExpr(alloc, items[0]); // degenerate
            var result = mkpair(
                codegenExpr(alloc, items[items.len - 2]),
                codegenExpr(alloc, items[items.len - 1]),
            );
            var i: usize = items.len - 2;
            while (i > 0) {
                i -= 1;
                result = mktcons(codegenExpr(alloc, items[i]), result);
            }
            break :blk result;
        },

        // --- Type annotation: discard type, keep expression ---
        .typed => |typed| codegenExpr(alloc, typed.expr.*),

        // --- Where clause: block(ldefs, body, 0) ---
        .where => |w| applyWhereDefs(alloc, codegenExpr(alloc, w.body.*), w.defs),

        // --- Conditional guard (internal) ---
        .cond => |cond| ap2(word.COND, codegenExpr(alloc, cond.guard.*), codegenExpr(alloc, cond.then_expr.*)),

        // --- Left section (e op) → ap(opWord, e) ---
        .section_left => |s| ap(opWord(s.op), codegenExpr(alloc, s.arg.*)),

        // --- Right/post section (op e) ---
        // Mirrors rules.y: '(' diop1 e1 ')' → if op_word = ap(C,x) then ap(x,e) else ap2(C,op,e)
        .section_right => |s| blk: {
            const arg_w = codegenExpr(alloc, s.arg.*);
            // Special-case operators whose opWord is already ap(C,x):
            if (std.mem.eql(u8, s.op, "lt")) break :blk ap(word.GR, arg_w);
            if (std.mem.eql(u8, s.op, "le")) break :blk ap(word.GRE, arg_w);
            if (std.mem.eql(u8, s.op, "bang")) break :blk ap(word.SUBSCRIPT, arg_w);
            break :blk ap2(word.C, opWord(s.op), arg_w);
        },

        // --- Operator-as-function: (+), (*), … ---
        .op_func => |op| opWord(op),

        // --- Arithmetic sequences ---
        // [from..]         → ap2(STEP, big_one, from)
        // [from..to]       → ap3(STEPUNTIL, big_one, to, from)
        // [from,step..]    → ap2(STEP, step-from, from)
        // [from,step..to]  → ap3(STEPUNTIL, step-from, to, from)
        .range => |r| blk: {
            const from_w = codegenExpr(alloc, r.from.*);
            if (r.step) |step_ptr| {
                const step_w = codegenExpr(alloc, step_ptr.*);
                const delta = ap2(word.MINUS, step_w, from_w);
                if (r.to) |to_ptr| {
                    break :blk ap3(word.STEPUNTIL, delta, codegenExpr(alloc, to_ptr.*), from_w);
                } else {
                    break :blk ap2(word.STEP, delta, from_w);
                }
            } else {
                if (r.to) |to_ptr| {
                    break :blk ap3(word.STEPUNTIL, big.bn.big_one, codegenExpr(alloc, to_ptr.*), from_w);
                } else {
                    break :blk ap2(word.STEP, big.bn.big_one, from_w);
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
                        ls.idsused = word.NIL;
                        const lhs_w = genlhs(codegenExpr(alloc, g.pat));
                        ls.idsused = word.NIL;
                        break :gen mkcons(
                            word.GENERATOR,
                            mkcons(lhs_w, codegenExpr(alloc, g.source.*)),
                        );
                    },
                    // Sequence generator: `pat <- src, step ..`
                    // Mirrors rules.y: cons(GENERATOR, cons(p, ap2(ITERATE/ITERATE1, lambda(p,step), src)))
                    .sequence_generator => |sg| sgen: {
                        ls.idsused = word.NIL;
                        const lhs_w = genlhs(codegenExpr(alloc, sg.pat));
                        ls.idsused = word.NIL;
                        const src_w = codegenExpr(alloc, sg.source.*);
                        const step_w = codegenExpr(alloc, sg.step.*);
                        const comb: Word = if (irrefutable(lhs_w) != 0) word.ITERATE else word.ITERATE1;
                        break :sgen mkcons(
                            word.GENERATOR,
                            mkcons(lhs_w, ap2(comb, mklambda(lhs_w, step_w), src_w)),
                        );
                    },
                    .guard => |gp| mkcons(word.GUARD, codegenExpr(alloc, gp.*)),
                };
                qq = mkcons(qw, qq); // prepend → reverses order
            }
            break :blk compzf(codegenExpr(alloc, lc.body.*), qq, 0);
        },
    };
}

// ---------------------------------------------------------------------------
// LHS expression codegen: function application arguments use codegenPattern.
//
// The LHS of a definition is structured as ap(ap(f, arg1), arg2) etc.
// Each arg is a PATTERN, so use codegenPattern instead of codegenExpr.
// ---------------------------------------------------------------------------

/// Code the left-hand side of a definition (the name/pattern being defined).
fn codegenLhsExpr(alloc: Allocator, e: ast.Expr) Word {
    return switch (e) {
        .application => |app| ap(codegenLhsExpr(alloc, app.func.*), codegenPattern(alloc, app.arg.*)),
        else => codegenExpr(alloc, e),
    };
}

// ---------------------------------------------------------------------------
// RHS codegen
// ---------------------------------------------------------------------------

/// Code a right-hand side, guarded or plain, including any `where`.
fn codegenRhs(alloc: Allocator, rhs: ast.Rhs) Word {
    return switch (rhs) {
        .expr => |e| codegenExpr(alloc, e),
        .guarded => |guards| codegenGuarded(alloc, guards),
    };
}

// ---------------------------------------------------------------------------
// Where-clause codegen helpers
// ---------------------------------------------------------------------------

// Mirrors the YACC `ldef` production: returns defn(lhs, undef_t, label(here, rhs)).
// The tries() wrapping is NOT done here — buildLdefs handles it so consecutive
// equations for the same function can be merged into a single TRIES list.
/// Code a single local (`where`) definition.
fn codegenLocalDef(alloc: Allocator, def: ast.Def) Word {
    const here = makeHere(@intCast(def.span.line));
    var lhs = codegenLhsExpr(alloc, def.lhs);
    var rhs = codegenRhs(alloc, def.rhs);

    // Apply nested where clause before lambda-desugaring.
    rhs = applyWhereDefs(alloc, rhs, def.where_defs);

    // Lambda-desugar: f x y = body → lhs becomes f, rhs gets lambda wrappers
    const f = head(lhs);
    if (tg(f) == word.ID and !isConstructorWord(f)) {
        while (tg(lhs) == word.AP) {
            rhs = mklambda(t(lhs), rhs);
            lhs = h(lhs);
        }
    }
    const labeled = mklabel(here, rhs);
    return mkcons(lhs, mkcons(undef_t, labeled));
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
fn buildLdefs(alloc: Allocator, where_defs: []const ast.Def) Word {
    var ldefs: Word = word.NIL;
    for (where_defs) |wd| {
        const cell = codegenLocalDef(alloc, wd); // defn(lhs, undef_t, labeled)
        const lhs_word = h(cell);
        const labeled = t(t(cell)); // dval(cell) = the labeled rhs
        if (ldefs != word.NIL and h(h(ldefs)) == lhs_word) {
            // Same function as head of ldefs: prepend labeled to its tries list.
            // tries_cell = dval(hd(ldefs)) = tl(tl(hd(ldefs)))
            const tries_cell = t(t(h(ldefs)));
            tp(tries_cell).* = mkcons(labeled, t(tries_cell));
        } else {
            // New function: wrap dval in tries(lhs, [labeled]) and prepend to ldefs.
            const new_tries = heap.tries(lhs_word, mkcons(labeled, word.NIL));
            tp(t(cell)).* = new_tries;
            ldefs = mkcons(cell, ldefs);
        }
    }
    return ldefs;
}

/// Wrap expression `e` in its `where` definitions (as a `letrec`).
fn applyWhereDefs(alloc: Allocator, e: Word, where_defs: []const ast.Def) Word {
    if (where_defs.len == 0) return e;
    return block(buildLdefs(alloc, where_defs), e, 0);
}

// ---------------------------------------------------------------------------
// Top-level definition codegen: declares lhs in the environment
// ---------------------------------------------------------------------------

/// Code a top-level definition and install it in the environment.
fn codegenDef(alloc: Allocator, def: ast.Def) void {
    const here = makeHere(@intCast(def.span.line));
    var lhs = codegenLhsExpr(alloc, def.lhs);
    var rhs = codegenRhs(alloc, def.rhs);

    // Apply where clause (block wraps the rhs before lambda-desugaring).
    rhs = applyWhereDefs(alloc, rhs, def.where_defs);

    // Lambda-desugar
    const f = head(lhs);
    if (tg(f) == word.ID and !isConstructorWord(f)) {
        while (tg(lhs) == word.AP) {
            rhs = mklambda(t(lhs), rhs);
            lhs = h(lhs);
        }
    }
    rhs = mklabel(here, rhs);
    declare(lhs, rhs);
    // Mirror the YACC grammar: `declare(l,r), main.rs.lastname=l` — allows
    // consecutive equations for the same function to be accumulated
    // by decl1 rather than triggering a nameclash error.
    main.rs.lastname = lhs;
}

// ---------------------------------------------------------------------------
// Type specification codegen
// ---------------------------------------------------------------------------

/// Code a type signature (`::`) declaration.
fn codegenTypeSpec(ts: ast.TypeSpec) void {
    const here = makeHere(@intCast(ts.span.line));
    const type_w = codegenType(ts.typ);
    for (ts.names) |name| {
        specify(nameWord(name), type_w, here);
    }
}

// ---------------------------------------------------------------------------
// Type declaration codegen
// ---------------------------------------------------------------------------

/// Code a type/data declaration (`==` / `::=`).
fn codegenTypeDecl(td: ast.TypeDecl) void {
    switch (td) {
        // --- type synonym: type name params == body ---
        .synonym => |s| {
            const here = makeHere(@intCast(s.span.line));
            // Build typeform: ap(ap(name_id, tvar1), tvar2, …)
            var tf = nameWord(s.name);
            for (s.params) |p| tf = ap(tf, codegenTypeVar(p));
            // redtvars(ap(typeform, body)) normalises type vars
            const body_w = codegenType(s.body);
            const x = redtvars(ap(tf, body_w));
            declType(h(x), word.synonym_t, t(x), here);
        },

        // --- algebraic type: name params ::= C1 fields | C2 fields | … ---
        .algebraic => |a| {
            const here = makeHere(@intCast(a.span.line));
            var tf = nameWord(a.name);
            for (a.params) |p| tf = ap(tf, codegenTypeVar(p));

            // Build construction list in REVERSED order (mirrors rules.y `constructs`)
            var construction: Word = word.NIL;
            for (a.constructors) |ctor| {
                var cw = nameWord(ctor.name);
                for (ctor.fields) |field| cw = ap(cw, codegenType(field));
                construction = mkcons(cw, construction);
            }

            // Iterate through reversed construction; peel AP fields to build ctor type
            var n: Word = @intCast(a.constructors.len);
            var r_ids: Word = word.NIL;
            var rhs = construction;
            while (rhs != word.NIL) {
                var hv = h(rhs);
                var ct = tf;
                while (tg(hv) == word.AP) {
                    ct = ap2(arrow_t, t(hv), ct);
                    hv = h(hv);
                }
                n -= 1;
                _ = declconstr(hv, n, ct);
                r_ids = mkcons(hv, r_ids);
                rhs = t(rhs);
            }
            declType(tf, word.algebraic_t, r_ids, here);
        },

        // --- abstype: abstype name params with specs ---
        .abstype => |a| {
            const here = makeHere(@intCast(a.span.line));
            // Specify each operation in the abstract type
            for (a.specs) |spec| {
                const spec_here = makeHere(@intCast(spec.span.line));
                const type_w = codegenType(spec.typ);
                for (spec.names) |name| {
                    specify(nameWord(name), type_w, spec_here);
                }
            }
            // Declare the abstract type itself
            var tf = nameWord(a.name);
            for (a.params) |p| tf = ap(tf, codegenTypeVar(p));
            declType(tf, word.abstract_t, word.undef_t, here);
        },
    }
}

// ---------------------------------------------------------------------------
// Script entry point
// ---------------------------------------------------------------------------

/// Code an entire parsed `script` — the codegen entry point.
pub fn codegenScript(alloc: Allocator, script: ast.Script) void {
    for (script.items) |item| {
        switch (item) {
            .definition => |def| codegenDef(alloc, def),
            .type_spec => |ts| codegenTypeSpec(ts),
            .type_decl => |td| codegenTypeDecl(td),
            .eval => |e| {
                _ = codegenExpr(alloc, e);
            },
            // Directives are handled at a higher level (file inclusion etc.)
            .include, .export_list, .free_directive => {},
        }
    }
}
