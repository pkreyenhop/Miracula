//! Phase 10: AST → Miranda heap codegen.
//! Walks ast.Script and produces the same Word heap values as the legacy YACC parser.
//! IMPORTANT: this file calls C runtime functions and must NOT be imported from the
//! pure parser-tests binary (src/parser/parser.zig).  Import it from parser_api.zig or main.zig.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("ast.zig");

const clib = @cImport({
    @cInclude("data.h");
    @cInclude("combs.h");
    @cInclude("big.h");
    @cInclude("parser_bridge.h");
});

const Word = clib.word;

// ---------------------------------------------------------------------------
// Heap cell accessors
// ---------------------------------------------------------------------------

extern var hd: [*]Word;
extern var tl: [*]Word;
extern var tag: [*]u8;

inline fn h(x: Word) Word {
    return hd[@as(usize, @intCast(x)) * 2];
}
inline fn t(x: Word) Word {
    return tl[@as(usize, @intCast(x)) * 2];
}
inline fn tg(x: Word) u8 {
    return tag[@as(usize, @intCast(x))];
}

// ---------------------------------------------------------------------------
// Heap construction helpers (mirrors data.h macros)
// ---------------------------------------------------------------------------

inline fn ap(x: Word, y: Word) Word {
    return clib.make(clib.AP, x, y);
}
inline fn ap2(x: Word, y: Word, z: Word) Word {
    return ap(ap(x, y), z);
}
inline fn ap3(w: Word, x: Word, y: Word, z: Word) Word {
    return ap(ap2(w, x, y), z);
}
inline fn mkcons(x: Word, y: Word) Word {
    return clib.make(clib.CONS, x, y);
}
inline fn mklabel(x: Word, y: Word) Word {
    return clib.make(clib.LABEL, x, y);
}
inline fn mklambda(x: Word, y: Word) Word {
    return clib.make(clib.LAMBDA, x, y);
}
inline fn mkpair(x: Word, y: Word) Word {
    return clib.make(clib.PAIR, x, y);
}
inline fn mktcons(x: Word, y: Word) Word {
    return clib.make(clib.TCONS, x, y);
}

// ---------------------------------------------------------------------------
// C function externs
// ---------------------------------------------------------------------------

extern fn genlhs(x: Word) Word;
extern fn compzf(e: Word, qq: Word, diag: Word) Word;
extern fn block(defs: Word, e: Word, keep: Word) Word;
extern fn declare(x: Word, e: Word) void;
extern fn specify(x: Word, t_word: Word, h_word: Word) void;
extern fn decl_type(tf: Word, type_class: Word, info: Word, here: Word) void;
extern fn declconstr(x: Word, n: Word, t_word: Word) Word;
extern fn redtvars(t_word: Word) Word;
extern fn bigscan(p: [*:0]const u8) Word;
extern fn sto_dbl(R: f64) Word;
extern fn sto_id(p: [*:0]const u8) Word;
extern fn sto_char(ch: c_int) Word;
extern fn head(x: Word) Word;
extern fn isconstrname(s: [*:0]const u8) c_int;

// ---------------------------------------------------------------------------
// Runtime globals
// ---------------------------------------------------------------------------

extern var listdiff_fn: Word;
extern var Void: Word;
extern var big_one: Word;
extern var current_file: Word;

// ---------------------------------------------------------------------------
// Type constants (from data.h — replicated so we don't need the macros)
// ---------------------------------------------------------------------------

const undef_t: Word = 0; // #define undef_t 0
const arrow_t: Word = 6; // #define arrow_t 6
const list_t: Word = 4;  // #define list_t  4
const comma_t: Word = 5; // #define comma_t 5
const void_t: Word = 7;  // #define void_t  7

// ---------------------------------------------------------------------------
// 'here' generation: fileinfo(get_fil(current_file), line_no)
// ---------------------------------------------------------------------------

fn makeHere(line: u32) Word {
    // get_fil(current_file) = (char*)hd(hd(hd(current_file)))
    const fil_name = h(h(h(current_file)));
    return clib.make(clib.FILEINFO, fil_name, @intCast(line));
}

// ---------------------------------------------------------------------------
// Helper: is this ID word a constructor name?
// ---------------------------------------------------------------------------

fn isConstructorWord(x: Word) bool {
    if (tg(x) != clib.ID) return false;
    // get_id(x) = (char*)hd(hd(hd(x)))
    const name_ptr: [*:0]const u8 = @ptrFromInt(@as(usize, @intCast(h(h(h(x))))));
    return isconstrname(name_ptr) != 0;
}

// ---------------------------------------------------------------------------
// nameWord: convert a []const u8 to a Miranda ID Word via sto_id
// ---------------------------------------------------------------------------

fn nameWord(name: []const u8) Word {
    var buf: [512:0]u8 = undefined;
    const n = @min(name.len, buf.len - 1);
    @memcpy(buf[0..n], name[0..n]);
    buf[n] = 0;
    return sto_id(buf[0..n :0]);
}

// ---------------------------------------------------------------------------
// Type variable: convert name string to TVAR cell
//   "*"   → make(TVAR, 0, 1)
//   "**"  → make(TVAR, 0, 2)
//   "***" → make(TVAR, 0, 3)
//   "*a"  → sto_id("*a")  (named typevar — fall back to ident)
// ---------------------------------------------------------------------------

fn codegenTypeVar(name: []const u8) Word {
    var star_count: Word = 0;
    for (name) |c| {
        if (c == '*') star_count += 1 else break;
    }
    if (star_count == @as(Word, @intCast(name.len))) {
        // Pure-star type variable: *, **, ***, …
        return clib.make(clib.TVAR, 0, star_count);
    }
    // Named type variable like *a, *b — treat as identifier for now
    return nameWord(name);
}

// ---------------------------------------------------------------------------
// Type expression codegen
// ---------------------------------------------------------------------------

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

fn opWord(op: []const u8) Word {
    if (std.mem.eql(u8, op, "vel"))       return clib.OR;
    if (std.mem.eql(u8, op, "amp"))       return clib.AND;
    if (std.mem.eql(u8, op, "eq"))        return clib.EQ;
    if (std.mem.eql(u8, op, "eqeq"))      return clib.EQ;
    if (std.mem.eql(u8, op, "ne"))        return clib.NEQ;
    if (std.mem.eql(u8, op, "gt"))        return clib.GR;
    if (std.mem.eql(u8, op, "lt"))        return ap(clib.C, clib.GR);  // relop '<'
    if (std.mem.eql(u8, op, "ge"))        return clib.GRE;
    if (std.mem.eql(u8, op, "le"))        return ap(clib.C, clib.GRE); // relop LE
    if (std.mem.eql(u8, op, "cons"))      return clib.P;               // ':' as section
    if (std.mem.eql(u8, op, "plus_plus")) return clib.APPEND;
    if (std.mem.eql(u8, op, "minus_minus")) return listdiff_fn;
    if (std.mem.eql(u8, op, "plus"))      return clib.PLUS;
    if (std.mem.eql(u8, op, "minus"))     return clib.MINUS;
    if (std.mem.eql(u8, op, "star"))      return clib.TIMES;
    if (std.mem.eql(u8, op, "slash"))     return clib.FDIV;
    if (std.mem.eql(u8, op, "kw_div"))    return clib.INTDIV;
    if (std.mem.eql(u8, op, "kw_mod"))    return clib.MOD;
    if (std.mem.eql(u8, op, "caret"))     return clib.POWER;
    if (std.mem.eql(u8, op, "dot"))       return clib.B;              // function composition
    if (std.mem.eql(u8, op, "bang"))      return ap(clib.C, clib.SUBSCRIPT); // '!'
    if (std.mem.eql(u8, op, "tilde"))     return clib.NOT;
    if (std.mem.eql(u8, op, "hash"))      return clib.LENGTH;
    // Fall back: user-defined infix operator stored as an identifier
    return nameWord(op);
}

// ---------------------------------------------------------------------------
// Guarded alternatives: build COND chain (mirrors parse_compose logic)
// ---------------------------------------------------------------------------

fn codegenGuarded(alloc: Allocator, guards: []const ast.Guard) Word {
    if (guards.len == 0) return clib.FAIL;

    // Build from last guard backwards.  Result shape matches parse_compose output:
    //   COND p0 b0 (label_h1 (COND p1 b1) (label_h2 ... FAIL))
    var i: usize = guards.len;
    var result: Word = clib.FAIL;
    while (i > 0) {
        i -= 1;
        const g = guards[i];
        const cond_w = codegenExpr(alloc, g.cond);
        const body_w = codegenExpr(alloc, g.body);
        result = ap(ap2(clib.COND, cond_w, body_w), result);
        if (i > 0) {
            const ghere = makeHere(@intCast(g.span.line));
            result = mklabel(ghere, result);
        }
    }
    return result;
}

// ---------------------------------------------------------------------------
// String literal → CONS chain of character words
// ---------------------------------------------------------------------------

fn codegenString(s: []const u8) Word {
    // Walk the UTF-8 string right-to-left; decode codepoints for sto_char.
    var result: Word = clib.NIL;
    var i: usize = s.len;
    while (i > 0) {
        // Simple byte-by-byte (ASCII) walk.  For multi-byte UTF-8 we'd need
        // to decode fully, but Miranda source is usually Latin-1 / ASCII.
        i -= 1;
        result = mkcons(sto_char(@intCast(s[i])), result);
    }
    return result;
}

// ---------------------------------------------------------------------------
// Expression codegen (the heart of Phase 10)
// ---------------------------------------------------------------------------

pub fn codegenExpr(alloc: Allocator, e: ast.Expr) Word {
    return switch (e) {
        // --- Identifiers ---
        .name  => |n| nameWord(n.text),
        .cname => |n| nameWord(n.text),

        // --- Literals ---
        .literal => |lit| switch (lit.value) {
            .int => |v| blk: {
                var buf: [64:0]u8 = undefined;
                const s = std.fmt.bufPrintZ(&buf, "{}", .{v}) catch break :blk clib.NIL;
                _ = s;
                break :blk bigscan(buf[0.. :0]);
            },
            .float  => |v| sto_dbl(v),
            .char   => |c| sto_char(@intCast(c)),
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
            if (std.mem.eql(u8, op, "bang"))  break :blk ap2(clib.SUBSCRIPT, rhs_w, lhs);
            // ':' list cons: make(CONS, lhs, rhs)
            if (std.mem.eql(u8, op, "cons"))  break :blk mkcons(lhs, rhs_w);
            // All other operators: ap2(opWord, lhs, rhs)
            break :blk ap2(opWord(op), lhs, rhs_w);
        },

        // --- Unary operators ---
        .neg    => |ep| ap(clib.NEG,    codegenExpr(alloc, ep.*)),
        .length => |ep| ap(clib.LENGTH, codegenExpr(alloc, ep.*)),

        // --- List literals ---
        .list_nil => clib.NIL,
        .list     => |items| blk: {
            var result: Word = clib.NIL;
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
        // ()           → Void
        .tuple => |items| blk: {
            if (items.len == 0) break :blk Void;
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
        .where => |w| blk: {
            var ldefs: Word = clib.NIL;
            for (w.defs) |def| {
                ldefs = mkcons(codegenLocalDef(alloc, def), ldefs);
            }
            break :blk block(ldefs, codegenExpr(alloc, w.body.*), 0);
        },

        // --- Conditional guard (internal) ---
        .cond => |c| ap2(clib.COND, codegenExpr(alloc, c.guard.*), codegenExpr(alloc, c.then_expr.*)),

        // --- Left section (e op) → ap(opWord, e) ---
        .section_left => |s| ap(opWord(s.op), codegenExpr(alloc, s.arg.*)),

        // --- Right/post section (op e) ---
        // Mirrors rules.y: '(' diop1 e1 ')' → if op_word = ap(C,x) then ap(x,e) else ap2(C,op,e)
        .section_right => |s| blk: {
            const arg_w = codegenExpr(alloc, s.arg.*);
            // Special-case operators whose opWord is already ap(C,x):
            if (std.mem.eql(u8, s.op, "lt"))   break :blk ap(clib.GR,         arg_w);
            if (std.mem.eql(u8, s.op, "le"))   break :blk ap(clib.GRE,        arg_w);
            if (std.mem.eql(u8, s.op, "bang")) break :blk ap(clib.SUBSCRIPT,  arg_w);
            break :blk ap2(clib.C, opWord(s.op), arg_w);
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
                const delta = ap2(clib.MINUS, step_w, from_w);
                if (r.to) |to_ptr| {
                    break :blk ap3(clib.STEPUNTIL, delta, codegenExpr(alloc, to_ptr.*), from_w);
                } else {
                    break :blk ap2(clib.STEP, delta, from_w);
                }
            } else {
                if (r.to) |to_ptr| {
                    break :blk ap3(clib.STEPUNTIL, big_one, codegenExpr(alloc, to_ptr.*), from_w);
                } else {
                    break :blk ap2(clib.STEP, big_one, from_w);
                }
            }
        },

        // --- List comprehension: compzf(body, qualifiers, 0) ---
        // Qualifiers must be passed in REVERSED order (newest first).
        .listcomp => |lc| blk: {
            var qq: Word = clib.NIL;
            for (lc.qualifiers) |q| {
                const qw: Word = switch (q) {
                    .generator => |g| mkcons(
                        clib.GENERATOR,
                        mkcons(genlhs(codegenExpr(alloc, g.pat)), codegenExpr(alloc, g.source.*)),
                    ),
                    .guard => |gp| mkcons(clib.GUARD, codegenExpr(alloc, gp.*)),
                };
                qq = mkcons(qw, qq); // prepend → reverses order
            }
            break :blk compzf(codegenExpr(alloc, lc.body.*), qq, 0);
        },
    };
}

// ---------------------------------------------------------------------------
// RHS codegen
// ---------------------------------------------------------------------------

fn codegenRhs(alloc: Allocator, rhs: ast.Rhs) Word {
    return switch (rhs) {
        .expr    => |e|      codegenExpr(alloc, e),
        .guarded => |guards| codegenGuarded(alloc, guards),
    };
}

// ---------------------------------------------------------------------------
// Local definition codegen (for where clauses)
// Returns a defn(lhs, undef_t, label(here, rhs)) cell.
// ---------------------------------------------------------------------------

fn codegenLocalDef(alloc: Allocator, def: ast.Def) Word {
    const here = makeHere(@intCast(def.span.line));
    var lhs = codegenExpr(alloc, def.lhs);
    var rhs = codegenRhs(alloc, def.rhs);

    // Lambda-desugar: f x y = body → lhs becomes f, rhs gets lambda wrappers
    const f = head(lhs);
    if (tg(f) == clib.ID and !isConstructorWord(f)) {
        while (tg(lhs) == clib.AP) {
            rhs = mklambda(t(lhs), rhs);
            lhs = h(lhs);
        }
    }
    // defn(lhs, undef_t, label(here, rhs)) = cons(lhs, cons(undef_t, label(here, rhs)))
    return mkcons(lhs, mkcons(undef_t, mklabel(here, rhs)));
}

// ---------------------------------------------------------------------------
// Top-level definition codegen: declares lhs in the environment
// ---------------------------------------------------------------------------

fn codegenDef(alloc: Allocator, def: ast.Def) void {
    const here = makeHere(@intCast(def.span.line));
    var lhs = codegenExpr(alloc, def.lhs);
    var rhs = codegenRhs(alloc, def.rhs);

    // Lambda-desugar
    const f = head(lhs);
    if (tg(f) == clib.ID and !isConstructorWord(f)) {
        while (tg(lhs) == clib.AP) {
            rhs = mklambda(t(lhs), rhs);
            lhs = h(lhs);
        }
    }
    rhs = mklabel(here, rhs);
    declare(lhs, rhs);
}

// ---------------------------------------------------------------------------
// Type specification codegen
// ---------------------------------------------------------------------------

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
            decl_type(h(x), clib.synonym_t, t(x), here);
        },

        // --- algebraic type: name params ::= C1 fields | C2 fields | … ---
        .algebraic => |a| {
            const here = makeHere(@intCast(a.span.line));
            var tf = nameWord(a.name);
            for (a.params) |p| tf = ap(tf, codegenTypeVar(p));

            // Build construction list in REVERSED order (mirrors rules.y `constructs`)
            var construction: Word = clib.NIL;
            for (a.constructors) |ctor| {
                var cw = nameWord(ctor.name);
                for (ctor.fields) |field| cw = ap(cw, codegenType(field));
                construction = mkcons(cw, construction);
            }

            // Iterate through reversed construction; peel AP fields to build ctor type
            var n: Word = @intCast(a.constructors.len);
            var r_ids: Word = clib.NIL;
            var rhs = construction;
            while (rhs != clib.NIL) {
                var hv = h(rhs);
                var ct = tf;
                while (tg(hv) == clib.AP) {
                    ct = ap2(arrow_t, t(hv), ct);
                    hv = h(hv);
                }
                n -= 1;
                _ = declconstr(hv, n, ct);
                r_ids = mkcons(hv, r_ids);
                rhs = t(rhs);
            }
            decl_type(tf, clib.algebraic_t, r_ids, here);
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
            decl_type(tf, clib.abstract_t, clib.undef_t, here);
        },
    }
}

// ---------------------------------------------------------------------------
// Script entry point
// ---------------------------------------------------------------------------

pub fn codegenScript(alloc: Allocator, script: ast.Script) void {
    for (script.items) |item| {
        switch (item) {
            .definition  => |def| codegenDef(alloc, def),
            .type_spec   => |ts|  codegenTypeSpec(ts),
            .type_decl   => |td|  codegenTypeDecl(td),
            .eval        => |e|   { _ = codegenExpr(alloc, e); },
            // Directives are handled at a higher level (file inclusion etc.)
            .include, .export_list, .free_directive => {},
        }
    }
}
