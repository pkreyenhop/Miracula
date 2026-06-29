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

/// True for the six Miranda relational operators.
fn isRelopId(id: TokenId) bool {
    return switch (id) {
        .eq, .ne, .lt, .gt, .le, .ge => true,
        else => false,
    };
}

/// Whether operator `op` is a relational operator (for chained-comparison parsing).
fn isRelopName(op: []const u8) bool {
    const relops = [_][]const u8{ "eq", "ne", "lt", "gt", "le", "ge" };
    for (relops) |r| if (std.mem.eql(u8, op, r)) return true;
    return false;
}

/// For a chained comparison `lhs relop rhs`, extract the subject (the
/// right operand of the previous comparison) so we can build
///   AND(lhs, subject relop2 next)
/// Returns null if `e` is not a comparison or AND-chain of comparisons.
fn chainSubject(e: *const Expr) ?*const Expr {
    switch (e.*) {
        .infix => |*inf| {
            if (isRelopName(inf.op)) return inf.rhs;
            if (std.mem.eql(u8, inf.op, "amp")) {
                // AND(A, B): subject is rhs of B (the rightmost comparison)
                if (std.meta.activeTag(inf.rhs.*) == .infix and
                    isRelopName(inf.rhs.*.infix.op))
                {
                    return inf.rhs.*.infix.rhs;
                }
            }
            return null;
        },
        else => return null,
    }
}

/// Infix operator binding-power entry.
const InfixBp = struct { id: TokenId, left: u8, right: u8 };

/// Infix binding-power table for Miranda operators.
/// `left` > `right` → right-associative; `left` < `right` → left-associative;
/// `left` == `right` would be non-associative (not used here; we let the
/// grammar reject chaining via type checking instead).
const infix_bp = [_]InfixBp{
    .{ .id = .vel, .left = 20, .right = 19 }, // \/ right-assoc
    .{ .id = .amp, .left = 30, .right = 29 }, // &  right-assoc
    .{ .id = .eq, .left = 40, .right = 41 }, // =  left (non-assoc enforced later)
    .{ .id = .ne, .left = 40, .right = 41 }, // ~=
    .{ .id = .lt, .left = 40, .right = 41 }, // <
    .{ .id = .gt, .left = 40, .right = 41 }, // >
    .{ .id = .le, .left = 40, .right = 41 }, // <=
    .{ .id = .ge, .left = 40, .right = 41 }, // >=
    .{ .id = .cons, .left = 50, .right = 49 }, // :  right-assoc (list cons)
    .{ .id = .plus_plus, .left = 50, .right = 49 }, // ++ right-assoc
    .{ .id = .minus_minus, .left = 50, .right = 49 }, // -- right-assoc
    .{ .id = .plus, .left = 60, .right = 61 }, // +  left-assoc
    .{ .id = .minus, .left = 60, .right = 61 }, // -  left-assoc
    .{ .id = .star, .left = 70, .right = 71 }, // *  left-assoc
    .{ .id = .slash, .left = 70, .right = 71 }, // /  left-assoc
    .{ .id = .kw_div, .left = 70, .right = 71 }, // div left-assoc
    .{ .id = .kw_mod, .left = 70, .right = 71 }, // mod left-assoc
    .{ .id = .caret, .left = 79, .right = 78 }, // ^  right-assoc
    .{ .id = .dot, .left = 80, .right = 81 }, // .  left-assoc (compose)
    .{ .id = .bang, .left = 90, .right = 91 }, // !  left-assoc (subscript)
};

/// Returns the infix binding powers for `id`, or `null` if it is not infix.
///
/// Tests: infixBp: cons is right-associative, infixBp: plus is left-associative,
/// infixBp: unknown token returns null
pub fn infixBp(id: TokenId) ?struct { left: u8, right: u8 } {
    for (infix_bp) |entry| {
        if (entry.id == id) return .{ .left = entry.left, .right = entry.right };
    }
    return null;
}

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

/// Prefix binding power for unary prefix operators.
///
/// Tests: prefixBp: tilde/hash/minus bind, others don't
pub fn prefixBp(id: TokenId) ?u8 {
    return switch (id) {
        .tilde => 35, // ~expr  logical negation
        .hash => 85, // #expr  list length
        .minus => 65, // -expr  arithmetic negation (above + but below *)
        else => null,
    };
}

test "prefixBp: tilde/hash/minus bind, others don't" {
    try std.testing.expectEqual(@as(?u8, 35), prefixBp(.tilde));
    try std.testing.expectEqual(@as(?u8, 85), prefixBp(.hash));
    try std.testing.expectEqual(@as(?u8, 65), prefixBp(.minus));
    try std.testing.expect(prefixBp(.plus) == null);
}

// ---------------------------------------------------------------------------
// Token stream
// ---------------------------------------------------------------------------

/// Thin read cursor over a pre-tokenised slice.
///
/// Tests: TokenStream: peek/advance/check/eat/expect/peekAt cursor behaviour
pub const TokenStream = struct {
    tokens: []const Token,
    pos: usize = 0,

    /// The current token, without consuming it.
    pub fn peek(self: *const TokenStream) Token {
        if (self.pos >= self.tokens.len)
            return .{ .id = .eof, .span = .{ .line = 0, .col = 0 } };
        return self.tokens[self.pos];
    }

    /// Consume and return the current token.
    pub fn advance(self: *TokenStream) Token {
        const tok = self.peek();
        if (self.pos < self.tokens.len) self.pos += 1;
        return tok;
    }

    /// Consume a token of id `id`, or return a parse error.
    pub fn expect(self: *TokenStream, id: TokenId) ParseError!Token {
        const tok = self.peek();
        if (tok.id != id) return error.UnexpectedToken;
        return self.advance();
    }

    /// Whether the current token has id `id`.
    pub fn check(self: *const TokenStream, id: TokenId) bool {
        return self.peek().id == id;
    }

    /// Consume the current token if it has id `id`; returns whether it did.
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

test "TokenStream: peek/advance/check/eat/expect/peekAt cursor behaviour" {
    const toks = [_]Token{
        .{ .id = .name, .span = .{ .line = 1, .col = 1 }, .text = "a" },
        .{ .id = .plus, .span = .{ .line = 1, .col = 2 } },
        .{ .id = .eof, .span = .{ .line = 1, .col = 3 } },
    };
    var ts = TokenStream{ .tokens = &toks };
    try std.testing.expect(ts.check(.name));
    try std.testing.expectEqual(@as(TokenId, .plus), ts.peekAt(1).id);
    try std.testing.expectEqual(@as(TokenId, .name), ts.advance().id);
    try std.testing.expect(!ts.eat(.name)); // current is plus, not name
    try std.testing.expect(ts.eat(.plus));
    _ = try ts.expect(.eof);
    try std.testing.expectEqual(@as(TokenId, .eof), ts.peek().id); // past end → eof
    try std.testing.expectError(error.UnexpectedToken, ts.expect(.name));
}

// ---------------------------------------------------------------------------
// Pratt expression parser
// ---------------------------------------------------------------------------

/// True if `id` is an infix operator that cannot begin a prefix expression,
/// which makes it a legal right-section operator after `(`.
/// Excluded: `-` and `~` (prefix negation), `#` (prefix length).
fn isRightSectionOp(id: TokenId) bool {
    return switch (id) {
        .plus,
        .star,
        .slash,
        .caret,
        .dot,
        .bang,
        .amp,
        .vel,
        .cons,
        .plus_plus,
        .minus_minus,
        .eq,
        .ne,
        .lt,
        .gt,
        .le,
        .ge,
        .eq_eq,
        .kw_div,
        .kw_mod,
        .infixname,
        .infixcname,
        => true,
        else => false,
    };
}

/// True if `id` can start an argument in function-application position.
fn isArgStart(id: TokenId) bool {
    return switch (id) {
        .name,
        .cname,
        .const_int,
        .const_float,
        .const_str,
        .const_char,
        .lparen,
        .lbracket,
        .dollars,
        .kw_readvals,
        .kw_show,
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
///
/// Tests: parseExpr: name atom, parseExpr: integer literal, parseExpr: empty
/// list, parseExpr: cons infix
pub fn parseExpr(
    gpa: Allocator,
    ts: *TokenStream,
    min_bp: u8,
) ParseError!Expr {
    // ── prefix / atom phase ────────────────────────────────────────────────
    var lhs: Expr = blk: {
        const tok = ts.advance();
        break :blk switch (tok.id) {
            .name => Expr{ .name = .{ .text = tok.text, .span = tok.span } },
            .cname => Expr{ .cname = .{ .text = tok.text, .span = tok.span } },

            // Miranda built-in primitives emitted as keyword tokens by the C lexer.
            // `show` → make(SHOW, 0, 0); `readvals` → make(STARTREADVALS, 0, 0);
            // `$$`   → lastexp (REPL only; codegen handles it).
            // We encode them as op_func nodes so opWord() in codegen can map them.
            .kw_show => Expr{ .op_func = "kw_show" },
            .kw_readvals => Expr{ .op_func = "kw_readvals" },
            .dollars => Expr{ .op_func = "dollars" },

            .const_int => Expr{ .literal = .{
                .value = .{ .int = tok.text },
                .span = tok.span,
            } },
            .const_float => Expr{ .literal = .{
                .value = .{ .float = tok.float_val },
                .span = tok.span,
            } },
            .const_str => Expr{ .literal = .{
                .value = .{ .string = tok.text },
                .span = tok.span,
            } },
            .const_char => Expr{ .literal = .{
                .value = .{ .char = tok.char_val },
                .span = tok.span,
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
                    const fp = try gpa.create(Expr);
                    fp.* = first;
                    if (ts.eat(.rbracket))
                        break :inner Expr{ .range = .{ .from = fp, .step = null, .to = null } };
                    const to = try parseExpr(gpa, ts, 0);
                    _ = try ts.expect(.rbracket);
                    const tp = try gpa.create(Expr);
                    tp.* = to;
                    break :inner Expr{ .range = .{ .from = fp, .step = null, .to = tp } };
                }

                // [body | quals]
                if (ts.eat(.pipe)) {
                    const bp = try gpa.create(Expr);
                    bp.* = first;
                    var qs: std.ArrayList(ast.Qualifier) = .empty;
                    errdefer qs.deinit(gpa);
                    try parseQualifier(gpa, ts, &qs);
                    while (ts.check(.semicolon)) {
                        _ = ts.advance();
                        if (ts.check(.rbracket)) break;
                        try parseQualifier(gpa, ts, &qs);
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
                        const fp = try gpa.create(Expr);
                        fp.* = elems.items[0];
                        const sp2 = try gpa.create(Expr);
                        sp2.* = elem;
                        elems.deinit(gpa);
                        if (ts.eat(.rbracket))
                            break :inner Expr{ .range = .{ .from = fp, .step = sp2, .to = null } };
                        const to = try parseExpr(gpa, ts, 0);
                        _ = try ts.expect(.rbracket);
                        const tp = try gpa.create(Expr);
                        tp.* = to;
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

            .eof => return error.UnexpectedEof,
            else => return error.UnexpectedToken,
        };
    };

    // ── infix / application phase ──────────────────────────────────────────
    while (true) {
        const tok = ts.peek();

        // Tokens that terminate an expression at this level
        switch (tok.id) {
            .eof,
            .rparen,
            .rbracket,
            .rbrace,
            .comma,
            .semicolon,
            .offside,
            .elseq,
            .kw_where,
            .kw_if,
            .kw_otherwise,
            .coloncolon,
            .arrow,
            .dot_dot,
            .pipe,
            .left_arrow,
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
            // `(expr op)` left-section: the operator is immediately followed by `)`.
            // Stop here so the enclosing paren handler can recognise the section.
            if (isRightSectionOp(tok.id) and ts.peekAt(1).id == .rparen) break;
            const op_id = tok.id;
            _ = ts.advance();
            const rhs = try parseExpr(gpa, ts, bp.right);
            const lp = try gpa.create(Expr);
            lp.* = lhs;
            const rp = try gpa.create(Expr);
            rp.* = rhs;

            // Chained comparison: `a < b < c` → `(a < b) && (b < c)`
            // Mirrors the YACC `reln relop e2` rule in rules.y.
            if (isRelopId(op_id)) {
                if (chainSubject(&lhs)) |subj| {
                    const sp = try gpa.create(Expr);
                    sp.* = try cloneExpr(gpa, subj);
                    const inner = try gpa.create(Expr);
                    inner.* = Expr{ .infix = .{ .op = @tagName(op_id), .lhs = sp, .rhs = rp } };
                    lhs = Expr{ .infix = .{ .op = "amp", .lhs = lp, .rhs = inner } };
                    continue;
                }
            }

            lhs = Expr{ .infix = .{
                .op = @tagName(op_id),
                .lhs = lp,
                .rhs = rp,
            } };
            continue;
        }

        break;
    }

    return lhs;
}

test "parseExpr: name atom" {
    const gpa = std.testing.allocator;
    const tokens = [_]Token{
        .{ .id = .name, .span = .{ .line = 1, .col = 1 }, .text = "foo" },
        .{ .id = .eof, .span = .{ .line = 1, .col = 4 } },
    };
    var ts = TokenStream{ .tokens = &tokens };
    const expr = try parseExpr(gpa, &ts, 0);
    try std.testing.expectEqual(std.meta.Tag(Expr).name, std.meta.activeTag(expr));
    try std.testing.expectEqualStrings("foo", expr.name.text);
}

test "parseExpr: integer literal" {
    const gpa = std.testing.allocator;
    const tokens = [_]Token{
        .{ .id = .const_int, .span = .{ .line = 1, .col = 1 }, .text = "42", .int_val = 42 },
        .{ .id = .eof, .span = .{ .line = 1, .col = 3 } },
    };
    var ts = TokenStream{ .tokens = &tokens };
    const expr = try parseExpr(gpa, &ts, 0);
    try std.testing.expectEqual(std.meta.Tag(Expr).literal, std.meta.activeTag(expr));
    try std.testing.expectEqualStrings("42", expr.literal.value.int);
}

test "parseExpr: empty list" {
    const gpa = std.testing.allocator;
    const tokens = [_]Token{
        .{ .id = .lbracket, .span = .{ .line = 1, .col = 1 } },
        .{ .id = .rbracket, .span = .{ .line = 1, .col = 2 } },
        .{ .id = .eof, .span = .{ .line = 1, .col = 3 } },
    };
    var ts = TokenStream{ .tokens = &tokens };
    const expr = try parseExpr(gpa, &ts, 0);
    try std.testing.expectEqual(std.meta.Tag(Expr).list_nil, std.meta.activeTag(expr));
}

test "parseExpr: cons infix" {
    // 1 : []
    const gpa = std.testing.allocator;
    const tokens = [_]Token{
        .{ .id = .const_int, .span = .{ .line = 1, .col = 1 }, .text = "1", .int_val = 1 },
        .{ .id = .cons, .span = .{ .line = 1, .col = 3 } },
        .{ .id = .lbracket, .span = .{ .line = 1, .col = 5 } },
        .{ .id = .rbracket, .span = .{ .line = 1, .col = 6 } },
        .{ .id = .eof, .span = .{ .line = 1, .col = 7 } },
    };
    var ts = TokenStream{ .tokens = &tokens };
    const expr = try parseExpr(gpa, &ts, 0);
    try std.testing.expectEqual(std.meta.Tag(Expr).infix, std.meta.activeTag(expr));
    try std.testing.expectEqualStrings("cons", expr.infix.op);
    gpa.destroy(expr.infix.lhs);
    gpa.destroy(expr.infix.rhs);
}

/// Parse one list-comprehension qualifier and append it to `qs`.
///
/// Handles three forms:
///   pat <- source          → single generator
///   pat1, pat2 <- source   → two generators (cartesian-product, mirroring the
///                            YACC `e1 ',' generator` / REPEAT rule in rules.y)
///   expr                   → guard predicate
///
/// NOTE: inside `[body | quals]`, Miranda uses `;` (not `,`) as the
/// qualifier separator.  A `,` here is always part of a multi-var generator.
fn parseQualifier(
    gpa: Allocator,
    ts: *TokenStream,
    qs: *std.ArrayList(ast.Qualifier),
) ParseError!void {
    const e = try parseExpr(gpa, ts, 0);
    if (ts.eat(.left_arrow)) {
        const src = try parseExpr(gpa, ts, 0);
        // Sequence generator: `pat <- src, step ..`  →  ITERATE/ITERATE1 combinator.
        // The `,` here is INSIDE the generator rule, not a qualifier separator.
        if (ts.eat(.comma)) {
            const step = try parseExpr(gpa, ts, 0);
            _ = try ts.expect(.dot_dot);
            const srcp = try gpa.create(Expr);
            srcp.* = src;
            const stepp = try gpa.create(Expr);
            stepp.* = step;
            try qs.append(gpa, ast.Qualifier{ .sequence_generator = .{
                .pat = e,
                .source = srcp,
                .step = stepp,
            } });
            return;
        }
        const srcp = try gpa.create(Expr);
        srcp.* = src;
        try qs.append(gpa, ast.Qualifier{ .generator = .{ .pat = e, .source = srcp } });
        return;
    }
    // Multi-var generator: `a, b, … <- source`
    // Collect all LHS patterns, then consume `<-` and the source.
    // Desugar to one generator per variable so that the code generator sees
    // independent generators producing the Cartesian product (matching legacy
    // behaviour: `a,b <- xs` ≡ `a <- xs ; b <- xs`).
    if (ts.check(.comma)) {
        var vars: std.ArrayList(Expr) = .empty;
        defer vars.deinit(gpa);
        try vars.append(gpa, e);
        while (ts.eat(.comma)) {
            try vars.append(gpa, try parseExpr(gpa, ts, 0));
        }
        _ = try ts.expect(.left_arrow);
        const src = try parseExpr(gpa, ts, 0);
        for (vars.items, 0..) |v, i| {
            const sp = try gpa.create(Expr);
            if (i + 1 < vars.items.len) {
                sp.* = try cloneExpr(gpa, &src);
            } else {
                sp.* = src;
            }
            try qs.append(gpa, ast.Qualifier{ .generator = .{ .pat = v, .source = sp } });
        }
        return;
    }
    // Guard expression
    const ep = try gpa.create(Expr);
    ep.* = e;
    try qs.append(gpa, ast.Qualifier{ .guard = ep });
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

/// Allocate an Expr node on the heap.
///
/// Tests: boxExpr: heap-allocates a copy of the expr
pub fn boxExpr(gpa: Allocator, e: Expr) Allocator.Error!*Expr {
    const p = try gpa.create(Expr);
    p.* = e;
    return p;
}

test "boxExpr: heap-allocates a copy of the expr" {
    const gpa = std.testing.allocator;
    const p = try boxExpr(gpa, Expr{ .list_nil = {} });
    defer gpa.destroy(p);
    try std.testing.expectEqual(std.meta.Tag(Expr).list_nil, std.meta.activeTag(p.*));
}

/// Deep-clone an expression tree into fresh heap allocations.
///
/// Useful when the same sub-expression is referenced from two AST positions
/// (e.g. when desugaring `f x y` into nested applications).
///
/// Tests: cloneExpr: deep-copies a nested expression
pub fn cloneExpr(gpa: Allocator, src: *const Expr) ParseError!Expr {
    return switch (src.*) {
        .name => |n| Expr{ .name = n },
        .cname => |cn| Expr{ .cname = cn },
        .literal => |lit| Expr{ .literal = lit },
        .list_nil => Expr{ .list_nil = {} },

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

test "cloneExpr: deep-copies a nested expression" {
    const gpa = std.testing.allocator;
    const inner = try boxExpr(gpa, Expr{ .name = .{ .text = "x", .span = .{ .line = 1, .col = 1 } } });
    defer gpa.destroy(inner);
    const src = Expr{ .neg = inner };
    const dst = try cloneExpr(gpa, &src);
    defer gpa.destroy(dst.neg);
    try std.testing.expectEqual(std.meta.Tag(Expr).neg, std.meta.activeTag(dst));
    try std.testing.expect(dst.neg != inner); // a fresh allocation, not the original
    try std.testing.expectEqualStrings("x", dst.neg.name.text);
}
