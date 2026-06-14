//! Pratt (top-down operator-precedence) expression parser for Miranda.
//!
//! Operator precedence mirrors the %left / %right / %nonassoc declarations
//! in src/parser/legacy/rules.y.  Higher binding-power values bind tighter.
//!
//! Function application (juxtaposition) is the tightest infix operator
//! (bp = 100) and is left-associative.

const std = @import("std");
const ast = @import("ast.zig");
const tf = @import("token_filter.zig");

const Allocator = std.mem.Allocator;
const TokenId = tf.TokenId;
const Token = tf.Token;
const Expr = ast.Expr;
const Span = ast.Span;

pub const ParseError = error{ UnexpectedToken, UnexpectedEof, OutOfMemory };

/// Infix operator binding-power entry.
const InfixBp = struct { id: TokenId, left: u8, right: u8 };

/// Infix binding-power table for Miranda operators.
/// `left` > `right` → right-associative; `left` < `right` → left-associative;
/// `left` == `right` would be non-associative (not used here; we let the
/// grammar reject chaining via type checking instead).
const infix_bp = [_]InfixBp{
    .{ .id = .vel,         .left = 20, .right = 19 }, // \/ right-assoc
    .{ .id = .amp,         .left = 30, .right = 29 }, // &  right-assoc
    .{ .id = .eq,          .left = 40, .right = 41 }, // =  left (non-assoc enforced later)
    .{ .id = .ne,          .left = 40, .right = 41 }, // ~=
    .{ .id = .lt,          .left = 40, .right = 41 }, // <
    .{ .id = .gt,          .left = 40, .right = 41 }, // >
    .{ .id = .le,          .left = 40, .right = 41 }, // <=
    .{ .id = .ge,          .left = 40, .right = 41 }, // >=
    .{ .id = .cons,        .left = 50, .right = 49 }, // :  right-assoc (list cons)
    .{ .id = .plus_plus,   .left = 50, .right = 49 }, // ++ right-assoc
    .{ .id = .minus_minus, .left = 50, .right = 49 }, // -- right-assoc
    .{ .id = .plus,        .left = 60, .right = 61 }, // +  left-assoc
    .{ .id = .minus,       .left = 60, .right = 61 }, // -  left-assoc
    .{ .id = .star,        .left = 70, .right = 71 }, // *  left-assoc
    .{ .id = .slash,       .left = 70, .right = 71 }, // /  left-assoc
    .{ .id = .kw_div,      .left = 70, .right = 71 }, // div left-assoc
    .{ .id = .kw_mod,      .left = 70, .right = 71 }, // mod left-assoc
    .{ .id = .caret,       .left = 79, .right = 78 }, // ^  right-assoc
    .{ .id = .dot,         .left = 80, .right = 81 }, // .  left-assoc (compose)
    .{ .id = .bang,        .left = 90, .right = 91 }, // !  left-assoc (subscript)
};

/// Returns the infix binding powers for `id`, or `null` if it is not infix.
pub fn infixBp(id: TokenId) ?struct { left: u8, right: u8 } {
    for (infix_bp) |entry| {
        if (entry.id == id) return .{ .left = entry.left, .right = entry.right };
    }
    return null;
}

/// Prefix binding power for unary prefix operators.
pub fn prefixBp(id: TokenId) ?u8 {
    return switch (id) {
        .tilde => 35, // ~expr  logical negation
        .hash  => 85, // #expr  list length
        .minus => 65, // -expr  arithmetic negation (above + but below *)
        else   => null,
    };
}

// ---------------------------------------------------------------------------
// Token stream
// ---------------------------------------------------------------------------

/// Thin read cursor over a pre-tokenised slice.
pub const TokenStream = struct {
    tokens: []const Token,
    pos: usize = 0,

    pub fn peek(self: *const TokenStream) Token {
        if (self.pos >= self.tokens.len)
            return .{ .id = .eof, .span = .{ .line = 0, .col = 0 } };
        return self.tokens[self.pos];
    }

    pub fn advance(self: *TokenStream) Token {
        const tok = self.peek();
        if (self.pos < self.tokens.len) self.pos += 1;
        return tok;
    }

    pub fn expect(self: *TokenStream, id: TokenId) ParseError!Token {
        const tok = self.peek();
        if (tok.id != id) return error.UnexpectedToken;
        return self.advance();
    }

    pub fn check(self: *const TokenStream, id: TokenId) bool {
        return self.peek().id == id;
    }

    pub fn eat(self: *TokenStream, id: TokenId) bool {
        if (self.check(id)) {
            _ = self.advance();
            return true;
        }
        return false;
    }

    /// Peek N tokens ahead (0 = current).  Returns eof past the end.
    pub fn peekAt(self: *const TokenStream, n: usize) Token {
        const idx = self.pos + n;
        if (idx >= self.tokens.len)
            return .{ .id = .eof, .span = .{ .line = 0, .col = 0 } };
        return self.tokens[idx];
    }
};

// ---------------------------------------------------------------------------
// Pratt expression parser
// ---------------------------------------------------------------------------

/// True if `id` is an infix operator that cannot begin a prefix expression,
/// which makes it a legal right-section operator after `(`.
/// Excluded: `-` and `~` (prefix negation), `#` (prefix length).
fn isRightSectionOp(id: TokenId) bool {
    return switch (id) {
        .plus, .star, .slash, .caret, .dot, .bang,
        .amp, .vel, .cons,
        .plus_plus, .minus_minus,
        .eq, .ne, .lt, .gt, .le, .ge, .eq_eq,
        .kw_div, .kw_mod,
        .infixname, .infixcname,
        => true,
        else => false,
    };
}

/// True if `id` can start an argument in function-application position.
fn isArgStart(id: TokenId) bool {
    return switch (id) {
        .name, .cname, .const_int, .const_float,
        .const_str, .const_char, .lparen, .lbracket,
        .dollars, .kw_readvals, .kw_show,
        => true,
        else => false,
    };
}

/// Parse a Miranda expression with minimum binding power `min_bp`.
///
/// Implements the standard Pratt loop:
///   1. Parse a prefix atom (name, literal, prefix op, parenthesised expr, …).
///   2. Repeatedly fold infix / postfix / application operators whose left
///      binding power exceeds `min_bp`.
pub fn parseExpr(
    gpa: Allocator,
    ts: *TokenStream,
    min_bp: u8,
) ParseError!Expr {
    // ── prefix / atom phase ────────────────────────────────────────────────
    var lhs: Expr = blk: {
        const tok = ts.advance();
        break :blk switch (tok.id) {
            .name  => Expr{ .name  = .{ .text = tok.text, .span = tok.span } },
            .cname => Expr{ .cname = .{ .text = tok.text, .span = tok.span } },

            .const_int => Expr{ .literal = .{
                .value = .{ .int = tok.int_val },
                .span  = tok.span,
            } },
            .const_float => Expr{ .literal = .{
                .value = .{ .float = tok.float_val },
                .span  = tok.span,
            } },
            .const_str => Expr{ .literal = .{
                .value = .{ .string = tok.text },
                .span  = tok.span,
            } },
            .const_char => Expr{ .literal = .{
                .value = .{ .char = tok.char_val },
                .span  = tok.span,
            } },

            .tilde => inner: {
                const rhs = try parseExpr(gpa, ts, prefixBp(.tilde).?);
                const p = try gpa.create(Expr);
                p.* = rhs;
                break :inner Expr{ .neg = p };
            },
            .hash => inner: {
                const rhs = try parseExpr(gpa, ts, prefixBp(.hash).?);
                const p = try gpa.create(Expr);
                p.* = rhs;
                break :inner Expr{ .length = p };
            },
            .minus => inner: {
                const rhs = try parseExpr(gpa, ts, prefixBp(.minus).?);
                const p = try gpa.create(Expr);
                p.* = rhs;
                break :inner Expr{ .neg = p };
            },

            .lbracket => inner: {
                if (ts.eat(.rbracket)) break :inner Expr{ .list_nil = {} };
                const first = try parseExpr(gpa, ts, 0);

                // [from..] or [from..to]
                if (ts.eat(.dot_dot)) {
                    const fp = try gpa.create(Expr); fp.* = first;
                    if (ts.eat(.rbracket))
                        break :inner Expr{ .range = .{ .from = fp, .step = null, .to = null } };
                    const to = try parseExpr(gpa, ts, 0);
                    _ = try ts.expect(.rbracket);
                    const tp = try gpa.create(Expr); tp.* = to;
                    break :inner Expr{ .range = .{ .from = fp, .step = null, .to = tp } };
                }

                // [body | quals]
                if (ts.eat(.pipe)) {
                    const bp = try gpa.create(Expr); bp.* = first;
                    var qs: std.ArrayList(ast.Qualifier) = .empty;
                    errdefer qs.deinit(gpa);
                    try qs.append(gpa, try parseQualifier(gpa, ts));
                    while (ts.check(.semicolon) or ts.check(.comma)) {
                        _ = ts.advance();
                        if (ts.check(.rbracket)) break;
                        try qs.append(gpa, try parseQualifier(gpa, ts));
                    }
                    _ = try ts.expect(.rbracket);
                    break :inner Expr{ .listcomp = .{
                        .body = bp,
                        .qualifiers = try qs.toOwnedSlice(gpa),
                    } };
                }

                // [first] or [first, ...] or [first, step..to?]
                var elems: std.ArrayList(Expr) = .empty;
                try elems.append(gpa, first);

                while (ts.eat(.comma)) {
                    const elem = try parseExpr(gpa, ts, 0);
                    // [first, elem..to?] → arithmetic sequence with step
                    if (ts.eat(.dot_dot)) {
                        const fp = try gpa.create(Expr); fp.* = elems.items[0];
                        const sp2 = try gpa.create(Expr); sp2.* = elem;
                        elems.deinit(gpa);
                        if (ts.eat(.rbracket))
                            break :inner Expr{ .range = .{ .from = fp, .step = sp2, .to = null } };
                        const to = try parseExpr(gpa, ts, 0);
                        _ = try ts.expect(.rbracket);
                        const tp = try gpa.create(Expr); tp.* = to;
                        break :inner Expr{ .range = .{ .from = fp, .step = sp2, .to = tp } };
                    }
                    try elems.append(gpa, elem);
                }

                _ = try ts.expect(.rbracket);
                break :inner Expr{ .list = try elems.toOwnedSlice(gpa) };
            },

            .lparen => inner: {
                if (ts.eat(.rparen)) {
                    // Empty tuple / void: ()
                    const items = try gpa.alloc(Expr, 0);
                    break :inner Expr{ .tuple = items };
                }
                // (op) → operator as function;  (op expr) → right section.
                // An infix-only operator here cannot start a normal prefix expression.
                if (isRightSectionOp(ts.peek().id)) {
                    const op_tok = ts.advance();
                    // (op) — operator lifted to a function value, e.g. (+)
                    if (ts.eat(.rparen)) break :inner Expr{ .op_func = @tagName(op_tok.id) };
                    // (op expr) — right section, e.g. (+1)
                    const arg = try parseExpr(gpa, ts, 0);
                    _ = try ts.expect(.rparen);
                    const argp = try gpa.create(Expr);
                    argp.* = arg;
                    break :inner Expr{ .section_right = .{ .op = @tagName(op_tok.id), .arg = argp } };
                }
                const first = try parseExpr(gpa, ts, 0);
                if (ts.eat(.rparen)) break :inner first;
                // Left operator section: (expr op) — e.g. (1+), (10*)
                if (isRightSectionOp(ts.peek().id)) {
                    const op_tok = ts.advance();
                    _ = try ts.expect(.rparen);
                    const firstp = try gpa.create(Expr);
                    firstp.* = first;
                    break :inner Expr{ .section_left = .{ .arg = firstp, .op = @tagName(op_tok.id) } };
                }
                var elems: std.ArrayList(Expr) = .empty;
                errdefer elems.deinit(gpa);
                try elems.append(gpa, first);
                while (ts.eat(.comma)) {
                    try elems.append(gpa, try parseExpr(gpa, ts, 0));
                }
                _ = try ts.expect(.rparen);
                break :inner Expr{ .tuple = try elems.toOwnedSlice(gpa) };
            },

            .eof  => return error.UnexpectedEof,
            else  => return error.UnexpectedToken,
        };
    };

    // ── infix / application phase ──────────────────────────────────────────
    while (true) {
        const tok = ts.peek();

        // Tokens that terminate an expression at this level
        switch (tok.id) {
            .eof, .rparen, .rbracket, .rbrace,
            .comma, .semicolon, .offside, .elseq,
            .kw_where, .kw_if, .kw_otherwise,
            .coloncolon, .arrow, .dot_dot,
            .pipe, .left_arrow,
            => break,
            else => {},
        }

        // Function application (juxtaposition) — bp 100, left-associative
        if (isArgStart(tok.id)) {
            if (100 <= min_bp) break;
            const arg = try parseExpr(gpa, ts, 101);
            const fp = try gpa.create(Expr);
            fp.* = lhs;
            const ap = try gpa.create(Expr);
            ap.* = arg;
            lhs = Expr{ .application = .{ .func = fp, .arg = ap } };
            continue;
        }

        // Named infix operator
        if (infixBp(tok.id)) |bp| {
            if (bp.left <= min_bp) break;
            _ = ts.advance();
            const rhs = try parseExpr(gpa, ts, bp.right);
            const lp = try gpa.create(Expr);
            lp.* = lhs;
            const rp = try gpa.create(Expr);
            rp.* = rhs;
            lhs = Expr{ .infix = .{
                .op  = @tagName(tok.id),
                .lhs = lp,
                .rhs = rp,
            } };
            continue;
        }

        break;
    }

    return lhs;
}

/// Parse one list-comprehension qualifier: `pat <- source` or `guard`.
///
/// The pattern position is parsed as an expression first; if `<-` follows it
/// is treated as a generator, otherwise as a guard predicate.
fn parseQualifier(gpa: Allocator, ts: *TokenStream) ParseError!ast.Qualifier {
    const e = try parseExpr(gpa, ts, 0);
    if (ts.eat(.left_arrow)) {
        const src = try parseExpr(gpa, ts, 0);
        const srcp = try gpa.create(Expr);
        srcp.* = src;
        return ast.Qualifier{ .generator = .{ .pat = e, .source = srcp } };
    }
    const ep = try gpa.create(Expr);
    ep.* = e;
    return ast.Qualifier{ .guard = ep };
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

/// Allocate an Expr node on the heap.
pub fn boxExpr(gpa: Allocator, e: Expr) Allocator.Error!*Expr {
    const p = try gpa.create(Expr);
    p.* = e;
    return p;
}

/// Deep-clone an expression tree into fresh heap allocations.
///
/// Useful when the same sub-expression is referenced from two AST positions
/// (e.g. when desugaring `f x y` into nested applications).
pub fn cloneExpr(gpa: Allocator, src: *const Expr) ParseError!Expr {
    return switch (src.*) {
        .name     => |n|   Expr{ .name    = n },
        .cname    => |cn|  Expr{ .cname   = cn },
        .literal  => |lit| Expr{ .literal = lit },
        .list_nil          => Expr{ .list_nil = {} },

        .neg => |p| ret: {
            const q = try gpa.create(Expr);
            q.* = try cloneExpr(gpa, p);
            break :ret Expr{ .neg = q };
        },
        .length => |p| ret: {
            const q = try gpa.create(Expr);
            q.* = try cloneExpr(gpa, p);
            break :ret Expr{ .length = q };
        },

        // Application: access fields through the original pointer rather than
        // capturing the struct payload — avoids an unnecessary copy and keeps
        // the Zig 0.16 "omit unused captures" rule satisfied.
        .application => ret: {
            const fp = try gpa.create(Expr);
            fp.* = try cloneExpr(gpa, src.application.func);
            const ap = try gpa.create(Expr);
            ap.* = try cloneExpr(gpa, src.application.arg);
            break :ret Expr{ .application = .{ .func = fp, .arg = ap } };
        },

        .infix => ret: {
            const lp = try gpa.create(Expr);
            lp.* = try cloneExpr(gpa, src.infix.lhs);
            const rp = try gpa.create(Expr);
            rp.* = try cloneExpr(gpa, src.infix.rhs);
            break :ret Expr{ .infix = .{ .op = src.infix.op, .lhs = lp, .rhs = rp } };
        },

        .list => |items| ret: {
            const copy = try gpa.alloc(Expr, items.len);
            for (items, 0..) |*item, i| copy[i] = try cloneExpr(gpa, item);
            break :ret Expr{ .list = copy };
        },
        .tuple => |items| ret: {
            const copy = try gpa.alloc(Expr, items.len);
            for (items, 0..) |*item, i| copy[i] = try cloneExpr(gpa, item);
            break :ret Expr{ .tuple = copy };
        },

        .typed => ret: {
            const ep = try gpa.create(Expr);
            ep.* = try cloneExpr(gpa, src.typed.expr);
            const tp = try gpa.create(ast.TypeExpr);
            tp.* = src.typed.typ.*;
            break :ret Expr{ .typed = .{ .expr = ep, .typ = tp } };
        },
        .where => ret: {
            const bp = try gpa.create(Expr);
            bp.* = try cloneExpr(gpa, src.where.body);
            break :ret Expr{ .where = .{ .body = bp, .defs = src.where.defs } };
        },
        .cond => ret: {
            const gp = try gpa.create(Expr);
            gp.* = try cloneExpr(gpa, src.cond.guard);
            const tp = try gpa.create(Expr);
            tp.* = try cloneExpr(gpa, src.cond.then_expr);
            break :ret Expr{ .cond = .{ .guard = gp, .then_expr = tp } };
        },

        .section_right => ret: {
            const ap = try gpa.create(Expr);
            ap.* = try cloneExpr(gpa, src.section_right.arg);
            break :ret Expr{ .section_right = .{ .op = src.section_right.op, .arg = ap } };
        },
        .section_left => ret: {
            const ap = try gpa.create(Expr);
            ap.* = try cloneExpr(gpa, src.section_left.arg);
            break :ret Expr{ .section_left = .{ .arg = ap, .op = src.section_left.op } };
        },

        .op_func => |op| Expr{ .op_func = op },

        .range => ret: {
            const fp = try gpa.create(Expr);
            fp.* = try cloneExpr(gpa, src.range.from);
            const sp2: ?*Expr = if (src.range.step) |s| blk: {
                const p = try gpa.create(Expr);
                p.* = try cloneExpr(gpa, s);
                break :blk p;
            } else null;
            const tp: ?*Expr = if (src.range.to) |t| blk: {
                const p = try gpa.create(Expr);
                p.* = try cloneExpr(gpa, t);
                break :blk p;
            } else null;
            break :ret Expr{ .range = .{ .from = fp, .step = sp2, .to = tp } };
        },

        // List comprehension: shallow clone of qualifiers (arena-backed usage).
        .listcomp => ret: {
            const bp = try gpa.create(Expr);
            bp.* = try cloneExpr(gpa, src.listcomp.body);
            break :ret Expr{ .listcomp = .{ .body = bp, .qualifiers = src.listcomp.qualifiers } };
        },
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "infixBp: cons is right-associative" {
    const bp = infixBp(.cons).?;
    try std.testing.expect(bp.left > bp.right); // right-assoc: left > right
}

test "infixBp: plus is left-associative" {
    const bp = infixBp(.plus).?;
    try std.testing.expect(bp.right > bp.left); // left-assoc: right > left
}

test "infixBp: unknown token returns null" {
    try std.testing.expect(infixBp(.name) == null);
    try std.testing.expect(infixBp(.lparen) == null);
}

test "parse name atom" {
    const gpa = std.testing.allocator;
    const tokens = [_]Token{
        .{ .id = .name, .span = .{ .line = 1, .col = 1 }, .text = "foo" },
        .{ .id = .eof,  .span = .{ .line = 1, .col = 4 } },
    };
    var ts = TokenStream{ .tokens = &tokens };
    const expr = try parseExpr(gpa, &ts, 0);
    try std.testing.expectEqual(std.meta.Tag(Expr).name, std.meta.activeTag(expr));
    try std.testing.expectEqualStrings("foo", expr.name.text);
}

test "parse integer literal" {
    const gpa = std.testing.allocator;
    const tokens = [_]Token{
        .{ .id = .const_int, .span = .{ .line = 1, .col = 1 }, .int_val = 42 },
        .{ .id = .eof,       .span = .{ .line = 1, .col = 3 } },
    };
    var ts = TokenStream{ .tokens = &tokens };
    const expr = try parseExpr(gpa, &ts, 0);
    try std.testing.expectEqual(std.meta.Tag(Expr).literal, std.meta.activeTag(expr));
    try std.testing.expectEqual(@as(i64, 42), expr.literal.value.int);
}

test "parse empty list" {
    const gpa = std.testing.allocator;
    const tokens = [_]Token{
        .{ .id = .lbracket, .span = .{ .line = 1, .col = 1 } },
        .{ .id = .rbracket, .span = .{ .line = 1, .col = 2 } },
        .{ .id = .eof,      .span = .{ .line = 1, .col = 3 } },
    };
    var ts = TokenStream{ .tokens = &tokens };
    const expr = try parseExpr(gpa, &ts, 0);
    try std.testing.expectEqual(std.meta.Tag(Expr).list_nil, std.meta.activeTag(expr));

}

test "parse cons infix" {
    // 1 : []
    const gpa = std.testing.allocator;
    const tokens = [_]Token{
        .{ .id = .const_int, .span = .{ .line = 1, .col = 1 }, .int_val = 1 },
        .{ .id = .cons,      .span = .{ .line = 1, .col = 3 } },
        .{ .id = .lbracket,  .span = .{ .line = 1, .col = 5 } },
        .{ .id = .rbracket,  .span = .{ .line = 1, .col = 6 } },
        .{ .id = .eof,       .span = .{ .line = 1, .col = 7 } },
    };
    var ts = TokenStream{ .tokens = &tokens };
    const expr = try parseExpr(gpa, &ts, 0);
    try std.testing.expectEqual(std.meta.Tag(Expr).infix, std.meta.activeTag(expr));
    try std.testing.expectEqualStrings("cons", expr.infix.op);
    gpa.destroy(expr.infix.lhs);
    gpa.destroy(expr.infix.rhs);
}
