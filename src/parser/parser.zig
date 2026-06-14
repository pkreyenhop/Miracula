//! Miranda top-down recursive-descent parser.
//!
//! Handles the statement-level grammar (scripts, definitions, type
//! declarations, type specifications, patterns).  Expression parsing is
//! delegated to the Pratt engine in `pratt.zig`.
//!
//! Operator / token names follow `token_filter.zig`.  In particular the
//! Miranda list-cons operator `:` is `.cons`, NOT `.colon`.

const std = @import("std");
pub const ast = @import("ast.zig");
pub const tf = @import("token_filter.zig");
pub const pratt = @import("pratt.zig");

const Allocator = std.mem.Allocator;
const TokenId = tf.TokenId;
const Token = tf.Token;
const Span = tf.Span;
const TokenStream = pratt.TokenStream;
const ParseError = pratt.ParseError;

// ---------------------------------------------------------------------------
// Parser state
// ---------------------------------------------------------------------------

pub const Parser = struct {
    gpa: Allocator,
    ts: TokenStream,

    pub fn init(gpa: Allocator, tokens: []const Token) Parser {
        return .{
            .gpa = gpa,
            .ts  = TokenStream{ .tokens = tokens },
        };
    }

    fn peek(self: *Parser) Token    { return self.ts.peek(); }
    fn advance(self: *Parser) Token { return self.ts.advance(); }

    fn check(self: *Parser, id: TokenId) bool { return self.ts.check(id); }

    fn eat(self: *Parser, id: TokenId) bool { return self.ts.eat(id); }

    fn expect(self: *Parser, id: TokenId) ParseError!Token {
        return self.ts.expect(id);
    }

    fn span(self: *Parser) Span { return self.peek().span; }
};

// ---------------------------------------------------------------------------
// Type expression parsers
//
// Grammar (from rules.y):
//   type    ::= type1 | type '->' type
//   type1   ::= type2 (INFIXNAME type1)?
//   type2   ::= tap | argtype
//   tap     ::= NAME argtype | tap argtype
//   argtype ::= NAME | typevar | '(' typelist ')' | '[' type ']'
// ---------------------------------------------------------------------------

/// True if `id` can start an argtype (a type atom).
fn isArgtypeStart(id: TokenId) bool {
    return switch (id) {
        .name, .typevar, .star, .lparen, .lbracket => true,
        else => false,
    };
}

/// Parse a full Miranda type expression.
pub fn parseType(p: *Parser) ParseError!ast.TypeExpr {
    const te = try parseType1(p);
    if (p.eat(.arrow)) {
        const from_ptr = try p.gpa.create(ast.TypeExpr);
        from_ptr.* = te;
        const to_te = try parseType(p); // right-recursive for right-assoc
        const to_ptr = try p.gpa.create(ast.TypeExpr);
        to_ptr.* = to_te;
        return ast.TypeExpr{ .arrow = .{ .from = from_ptr, .to = to_ptr } };
    }
    return te;
}

/// Parse type1: a type2 optionally followed by an infix type name.
fn parseType1(p: *Parser) ParseError!ast.TypeExpr {
    // Miranda's INFIXNAME for types is rare; fall through to type2.
    return parseType2(p);
}

/// Parse type2: a type application or a single argtype.
fn parseType2(p: *Parser) ParseError!ast.TypeExpr {
    const tok = p.peek();
    if (tok.id == .name and isArgtypeStart(p.ts.peekAt(1).id)) {
        return parseTap(p);
    }
    return parseArgtype(p);
}

/// Parse a type application: `NAME argtype+`
///
/// Each successive argument is folded in left-to-right.  The `args` field
/// of `TypeExpr.type_app` is a heap-allocated slice; we use `gpa.dupe`
/// rather than a pointer to a stack / comptime array literal — otherwise
/// Zig would give us `*const [1]TypeExpr` where `[]TypeExpr` is required.
fn parseTap(p: *Parser) ParseError!ast.TypeExpr {
    const name_tok = p.advance(); // consume NAME
    const sp = name_tok.span;
    var base = ast.TypeExpr{ .type_name = .{ .name = name_tok.text, .span = sp } };

    while (isArgtypeStart(p.peek().id)) {
        const arg_te = try parseArgtype(p);

        const func_ptr = try p.gpa.create(ast.TypeExpr);
        func_ptr.* = base;

        // Allocate a fresh heap slice for `args`.  A comptime literal like
        // `&.{arg_te}` produces `*const [1]TypeExpr`, which does not coerce
        // to `[]TypeExpr`; `gpa.dupe` produces the correctly-typed `[]TypeExpr`.
        const args = try p.gpa.dupe(ast.TypeExpr, &.{arg_te});

        base = ast.TypeExpr{ .type_app = .{ .func = func_ptr, .args = args } };
    }
    return base;
}

/// Parse an argtype atom: a name, type variable, parenthesised type, or list type.
fn parseArgtype(p: *Parser) ParseError!ast.TypeExpr {
    const tok = p.advance();
    return switch (tok.id) {
        .name => ast.TypeExpr{ .type_name = .{ .name = tok.text, .span = tok.span } },

        .typevar => ast.TypeExpr{ .type_var = .{ .name = tok.text, .span = tok.span } },

        // `*` alone is also a type variable in Miranda
        .star => ast.TypeExpr{ .type_var = .{ .name = "*", .span = tok.span } },

        .lparen => paren: {
            if (p.eat(.rparen)) break :paren ast.TypeExpr{ .void_t = {} };

            const first = try parseType(p);
            if (p.eat(.rparen)) break :paren first;

            // Tuple type: `(A, B, …)`
            var elems: std.ArrayList(ast.TypeExpr) = .empty;
            errdefer elems.deinit(p.gpa);
            try elems.append(p.gpa, first);
            while (p.eat(.comma)) {
                try elems.append(p.gpa, try parseType(p));
            }
            _ = try p.expect(.rparen);
            break :paren ast.TypeExpr{ .tuple = try elems.toOwnedSlice(p.gpa) };
        },

        .lbracket => list: {
            const inner = try parseType(p);
            _ = try p.expect(.rbracket);
            const inner_ptr = try p.gpa.create(ast.TypeExpr);
            inner_ptr.* = inner;
            break :list ast.TypeExpr{ .list = inner_ptr };
        },

        else => return error.UnexpectedToken,
    };
}

// ---------------------------------------------------------------------------
// Type specification parser:  `namelist :: type`
// ---------------------------------------------------------------------------

pub fn parseTypeSpec(p: *Parser) ParseError!ast.TopLevel {
    const sp = p.span();
    var names: std.ArrayList([]const u8) = .empty;
    errdefer names.deinit(p.gpa);

    // namelist: NAME (',' NAME)*
    const first_tok = try p.expect(.name);
    try names.append(p.gpa, first_tok.text);
    while (p.eat(.comma)) {
        const n = try p.expect(.name);
        try names.append(p.gpa, n.text);
    }

    _ = try p.expect(.coloncolon);
    const typ = try parseType(p);

    return ast.TopLevel{ .type_spec = ast.TypeSpec{
        .names = try names.toOwnedSlice(p.gpa),
        .typ   = typ,
        .span  = sp,
    } };
}

// ---------------------------------------------------------------------------
// Pattern parsers
//
// Grammar (from rules.y):
//   v   ::= v1 | v1 ':' v
//   v1  ::= '-' CONST | v2 INFIXNAME v1 | v2 INFIXCNAME v1 | v2
//   v2  ::= v3 | v2 v3
//   v3  ::= NAME | CNAME | CONST | '[' ']' | '[' vlist ']'
//         | '(' ')' | '(' v ')' | '(' v ',' vlist ')'
// ---------------------------------------------------------------------------

/// Parse a full pattern (v in the grammar), including cons patterns `head : tail`.
pub fn parsePat(p: *Parser) ParseError!ast.Pat {
    return parsePatV(p);
}

fn parsePatV(p: *Parser) ParseError!ast.Pat {
    var head = try parsePatV1(p);

    // Miranda `:` (cons) in patterns is TokenId.cons — NOT .colon.
    // Check whether the next token is the list-cons separator.
    const next_tok = p.peek();
    if (next_tok.id == .cons) {
        _ = p.advance(); // consume `:`
        const tail = try parsePatV(p); // right-recursive
        const head_ptr = try p.gpa.create(ast.Pat);
        head_ptr.* = head;
        const tail_ptr = try p.gpa.create(ast.Pat);
        tail_ptr.* = tail;
        head = ast.Pat{ .cons_pat = .{ .head = head_ptr, .tail = tail_ptr } };
    }
    return head;
}

fn parsePatV1(p: *Parser) ParseError!ast.Pat {
    const tok = p.peek();

    // `-` CONST → negated numeric literal pattern
    if (tok.id == .minus) {
        _ = p.advance();
        const lit_tok = try p.expect(.const_int);
        return ast.Pat{ .literal = .{
            .value = .{ .int = -lit_tok.int_val },
            .span  = tok.span,
        } };
    }

    const lhs = try parsePatV2(p);

    // INFIXNAME / INFIXCNAME infix patterns: `lhs `op` rhs`
    // Desugar as: ((op lhs) rhs)
    if (p.check(.infixname) or p.check(.infixcname)) {
        const op_tok = p.advance();
        const rhs = try parsePatV1(p);

        const op_ptr = try applyPatName(p.gpa, op_tok);
        const lp = try p.gpa.create(ast.Pat);
        lp.* = lhs;
        const inner = try p.gpa.create(ast.Pat);
        inner.* = ast.Pat{ .application = .{ .func = op_ptr, .arg = lp } };
        const rp = try p.gpa.create(ast.Pat);
        rp.* = rhs;
        return ast.Pat{ .application = .{ .func = inner, .arg = rp } };
    }

    return lhs;
}

/// Wrap an operator token in a Pat.name for use as an infix pattern function.
fn applyPatName(gpa: Allocator, tok: Token) Allocator.Error!*ast.Pat {
    const p = try gpa.create(ast.Pat);
    p.* = ast.Pat{ .name = .{ .text = tok.text, .span = tok.span } };
    return p;
}

fn parsePatV2(p: *Parser) ParseError!ast.Pat {
    var pat = try parsePatV3(p);
    // Constructor application: `C arg1 arg2 …`
    while (isPatV3Start(p.peek().id)) {
        const arg = try parsePatV3(p);
        const fp = try p.gpa.create(ast.Pat);
        fp.* = pat;
        const ap = try p.gpa.create(ast.Pat);
        ap.* = arg;
        pat = ast.Pat{ .application = .{ .func = fp, .arg = ap } };
    }
    return pat;
}

fn isPatV3Start(id: TokenId) bool {
    return switch (id) {
        .name, .cname, .const_int, .const_float, .const_str, .const_char,
        .lbracket, .lparen,
        => true,
        else => false,
    };
}

fn parsePatV3(p: *Parser) ParseError!ast.Pat {
    const tok = p.advance();
    return switch (tok.id) {
        .name => ast.Pat{ .name = .{ .text = tok.text, .span = tok.span } },

        .cname => ast.Pat{ .cname = .{ .text = tok.text, .span = tok.span } },

        .const_int => ast.Pat{ .literal = .{
            .value = .{ .int = tok.int_val },
            .span  = tok.span,
        } },
        .const_float => ast.Pat{ .literal = .{
            .value = .{ .float = tok.float_val },
            .span  = tok.span,
        } },
        .const_str => ast.Pat{ .literal = .{
            .value = .{ .string = tok.text },
            .span  = tok.span,
        } },
        .const_char => ast.Pat{ .literal = .{
            .value = .{ .char = tok.char_val },
            .span  = tok.span,
        } },

        .lbracket => list: {
            if (p.eat(.rbracket)) {
                break :list ast.Pat{ .list = try p.gpa.alloc(ast.Pat, 0) };
            }
            var elems: std.ArrayList(ast.Pat) = .empty;
            errdefer elems.deinit(p.gpa);
            try elems.append(p.gpa, try parsePat(p));
            while (p.eat(.comma)) {
                try elems.append(p.gpa, try parsePat(p));
            }
            _ = try p.expect(.rbracket);
            break :list ast.Pat{ .list = try elems.toOwnedSlice(p.gpa) };
        },

        .lparen => paren: {
            if (p.eat(.rparen)) break :paren ast.Pat{ .wildcard = {} };
            const inner = try parsePat(p);
            if (p.eat(.rparen)) break :paren inner;
            var elems: std.ArrayList(ast.Pat) = .empty;
            errdefer elems.deinit(p.gpa);
            try elems.append(p.gpa, inner);
            while (p.eat(.comma)) {
                try elems.append(p.gpa, try parsePat(p));
            }
            _ = try p.expect(.rparen);
            break :paren ast.Pat{ .tuple = try elems.toOwnedSlice(p.gpa) };
        },

        else => return error.UnexpectedToken,
    };
}

// ---------------------------------------------------------------------------
// Expression parsing (delegates to Pratt)
// ---------------------------------------------------------------------------

pub fn parseExpr(p: *Parser) ParseError!ast.Expr {
    return pratt.parseExpr(p.gpa, &p.ts, 0);
}

// ---------------------------------------------------------------------------
// Right-hand side and definition parsers
// ---------------------------------------------------------------------------

/// Parse an expression optionally followed by a `where` clause.
pub fn parseRhs(p: *Parser) ParseError!ast.Expr {
    const body = try parseExpr(p);
    if (!p.eat(.kw_where)) return body;

    var defs: std.ArrayList(ast.Def) = .empty;
    errdefer defs.deinit(p.gpa);

    // Consume at least one local definition; skip layout between defs
    try defs.append(p.gpa, try parseDef(p));
    while (true) {
        while (p.eat(.offside) or p.eat(.elseq) or p.eat(.semicolon)) {}
        if (!p.check(.name) and !p.check(.cname)) break;
        try defs.append(p.gpa, try parseDef(p));
    }

    const body_ptr = try p.gpa.create(ast.Expr);
    body_ptr.* = body;
    return ast.Expr{ .where = .{
        .body = body_ptr,
        .defs = try defs.toOwnedSlice(p.gpa),
    } };
}

/// Parse one definition: `lhs_expr = rhs_expr`
pub fn parseDef(p: *Parser) ParseError!ast.Def {
    const sp = p.span();
    // Parse LHS with min_bp > 40 so the definition '=' (bp.left=40) is not
    // consumed as an infix equality operator — it is the definition separator.
    const lhs = try pratt.parseExpr(p.gpa, &p.ts, 41);
    _ = try p.expect(.eq);
    const rhs_expr = try parseRhs(p);
    return ast.Def{
        .lhs        = lhs,
        .rhs        = .{ .expr = rhs_expr },
        .where_defs = &.{},
        .span       = sp,
    };
}

// ---------------------------------------------------------------------------
// Script (top-level item list)
// ---------------------------------------------------------------------------

pub fn parseScript(p: *Parser) ParseError!ast.Script {
    var items: std.ArrayList(ast.TopLevel) = .empty;
    errdefer items.deinit(p.gpa);

    while (!p.check(.eof)) {
        // Skip layout tokens between items
        while (p.eat(.offside) or p.eat(.elseq) or p.eat(.semicolon)) {}
        if (p.check(.eof)) break;

        const item = try parseTopLevel(p);
        try items.append(p.gpa, item);
    }

    return ast.Script{ .items = try items.toOwnedSlice(p.gpa) };
}

fn parseTopLevel(p: *Parser) ParseError!ast.TopLevel {
    const tok = p.peek();

    switch (tok.id) {
        // Type synonym: `type Name params == body`
        .kw_type     => return parseTypeSynonym(p),
        // Abstract type: `abstype name params with specs`
        .kw_abstype  => return parseAbstype(p),
        // Module directives
        .kw_include  => return parseInclude(p),
        .kw_export   => return parseExport(p),
        .kw_free     => return parseFree(p),
        // BNF / LEX sections — parse and discard
        .kw_bnf, .kw_lex => return parseDiscardSection(p),
        else => {},
    }

    // When the item starts with a lowercase name, look ahead to decide between:
    //   type spec:       `Name (, Name)* :: type`
    //   algebraic type:  `name (typevar | *)* ::= constructors`
    //   definition:      everything else
    if (tok.id == .name) {
        // Check for algebraic type declaration: skip type params to find ::=
        var i: usize = 1;
        while (p.ts.peekAt(i).id == .typevar or p.ts.peekAt(i).id == .star) i += 1;
        if (p.ts.peekAt(i).id == .colon2eq) return parseAlgebraicType(p);

        // Check for type specification: NAME (, NAME)* ::
        var j: usize = 1;
        while (p.ts.peekAt(j).id == .comma) {
            j += 1;
            if (p.ts.peekAt(j).id != .name) break;
            j += 1;
        }
        if (p.ts.peekAt(j).id == .coloncolon) return parseTypeSpec(p);
    }

    const def = try parseDef(p);
    return ast.TopLevel{ .definition = def };
}

// ---------------------------------------------------------------------------
// Type declaration parsers (algebraic, synonym, abstype)
// ---------------------------------------------------------------------------

/// Parse a constructor: `CNAME argtype*`
fn parseConstructor(p: *Parser) ParseError!ast.Constructor {
    const sp = p.span();
    const name_tok = try p.expect(.cname);
    var fields: std.ArrayList(ast.TypeExpr) = .empty;
    errdefer fields.deinit(p.gpa);
    while (isArgtypeStart(p.peek().id)) {
        try fields.append(p.gpa, try parseArgtype(p));
    }
    return ast.Constructor{
        .name   = name_tok.text,
        .fields = try fields.toOwnedSlice(p.gpa),
        .span   = sp,
    };
}

/// Parse `name (typevar | *)* ::= Constructor1 type* | Constructor2 type* | …`
fn parseAlgebraicType(p: *Parser) ParseError!ast.TopLevel {
    const sp = p.span();
    const name_tok = try p.expect(.name);

    var params: std.ArrayList([]const u8) = .empty;
    errdefer params.deinit(p.gpa);
    while (p.check(.typevar) or p.check(.star)) {
        const pv = p.advance();
        try params.append(p.gpa, pv.text);
    }

    _ = try p.expect(.colon2eq);

    var ctors: std.ArrayList(ast.Constructor) = .empty;
    errdefer ctors.deinit(p.gpa);
    try ctors.append(p.gpa, try parseConstructor(p));
    while (p.eat(.pipe)) {
        try ctors.append(p.gpa, try parseConstructor(p));
    }

    return ast.TopLevel{ .type_decl = .{ .algebraic = .{
        .name         = name_tok.text,
        .params       = try params.toOwnedSlice(p.gpa),
        .constructors = try ctors.toOwnedSlice(p.gpa),
        .span         = sp,
    } } };
}

/// Parse `type Name params == body`
fn parseTypeSynonym(p: *Parser) ParseError!ast.TopLevel {
    const sp = p.span();
    _ = try p.expect(.kw_type);
    const name_tok = try p.expect(.name);

    var params: std.ArrayList([]const u8) = .empty;
    errdefer params.deinit(p.gpa);
    while (p.check(.typevar) or p.check(.star)) {
        const pv = p.advance();
        try params.append(p.gpa, pv.text);
    }

    _ = try p.expect(.eq_eq);
    const body = try parseType(p);

    return ast.TopLevel{ .type_decl = .{ .synonym = .{
        .name   = name_tok.text,
        .params = try params.toOwnedSlice(p.gpa),
        .body   = body,
        .span   = sp,
    } } };
}

/// Parse a single type-spec inside an abstype/free block: `name (, name)* :: type`
fn parseOneTypeSpec(p: *Parser) ParseError!ast.TypeSpec {
    const sp = p.span();
    var names: std.ArrayList([]const u8) = .empty;
    errdefer names.deinit(p.gpa);
    const first = try p.expect(.name);
    try names.append(p.gpa, first.text);
    while (p.eat(.comma)) {
        const n = try p.expect(.name);
        try names.append(p.gpa, n.text);
    }
    _ = try p.expect(.coloncolon);
    const typ = try parseType(p);
    return ast.TypeSpec{
        .names = try names.toOwnedSlice(p.gpa),
        .typ   = typ,
        .span  = sp,
    };
}

/// Parse `abstype name params with name :: type …`
fn parseAbstype(p: *Parser) ParseError!ast.TopLevel {
    const sp = p.span();
    _ = try p.expect(.kw_abstype);
    const name_tok = try p.expect(.name);

    var params: std.ArrayList([]const u8) = .empty;
    errdefer params.deinit(p.gpa);
    while (p.check(.typevar) or p.check(.star)) {
        const pv = p.advance();
        try params.append(p.gpa, pv.text);
    }

    // Skip layout / additional typeforms until `with`
    while (!p.check(.kw_with) and !p.check(.eof)) _ = p.advance();
    _ = try p.expect(.kw_with);

    // Parse indented type specs
    while (p.eat(.offside) or p.eat(.elseq) or p.eat(.semicolon)) {}
    var specs: std.ArrayList(ast.TypeSpec) = .empty;
    errdefer specs.deinit(p.gpa);
    while (p.check(.name)) {
        try specs.append(p.gpa, try parseOneTypeSpec(p));
        while (p.eat(.offside) or p.eat(.elseq) or p.eat(.semicolon)) {}
    }

    return ast.TopLevel{ .type_decl = .{ .abstype = .{
        .name   = name_tok.text,
        .params = try params.toOwnedSlice(p.gpa),
        .specs  = try specs.toOwnedSlice(p.gpa),
        .span   = sp,
    } } };
}

// ---------------------------------------------------------------------------
// Module directive parsers
// ---------------------------------------------------------------------------

/// Parse `%include <pathname>`
fn parseInclude(p: *Parser) ParseError!ast.TopLevel {
    const sp = p.span();
    _ = try p.expect(.kw_include);
    const path_tok = try p.expect(.pathname);
    return ast.TopLevel{ .include = .{ .path = path_tok.text, .span = sp } };
}

/// Parse `%export name …`
fn parseExport(p: *Parser) ParseError!ast.TopLevel {
    const sp = p.span();
    _ = try p.expect(.kw_export);
    var names: std.ArrayList([]const u8) = .empty;
    errdefer names.deinit(p.gpa);
    while (p.check(.name) or p.check(.cname)) {
        try names.append(p.gpa, p.advance().text);
    }
    return ast.TopLevel{ .export_list = .{
        .names = try names.toOwnedSlice(p.gpa),
        .span  = sp,
    } };
}

/// Parse `%free name :: type …`  (opaque type with external implementations)
fn parseFree(p: *Parser) ParseError!ast.TopLevel {
    const sp = p.span();
    _ = try p.expect(.kw_free);
    while (p.eat(.offside) or p.eat(.elseq) or p.eat(.semicolon)) {}
    var specs: std.ArrayList(ast.TypeSpec) = .empty;
    errdefer specs.deinit(p.gpa);
    while (p.check(.name)) {
        try specs.append(p.gpa, try parseOneTypeSpec(p));
        while (p.eat(.offside) or p.eat(.elseq) or p.eat(.semicolon)) {}
    }
    return ast.TopLevel{ .free_directive = .{
        .specs = try specs.toOwnedSlice(p.gpa),
        .span  = sp,
    } };
}

/// Consume a `%bnf` or `%lex` section and discard its content.
///
/// BNF/LEX sections end when the layout mechanism returns to the enclosing
/// indentation level (OFFSIDE after the section body).  We consume tokens
/// until we see either EOF or an OFFSIDE that brings us back to depth 0.
fn parseDiscardSection(p: *Parser) ParseError!ast.TopLevel {
    _ = p.advance(); // consume kw_bnf or kw_lex
    var depth: i32 = 0;
    while (!p.check(.eof)) {
        const t = p.peek();
        if (t.id == .offside) {
            if (depth <= 0) break;
            depth -= 1;
        } else if (t.id == .elseq) {
            depth += 1;
        }
        _ = p.advance();
    }
    // Return an empty tuple as a placeholder eval expression
    const unit = try p.gpa.alloc(ast.Expr, 0);
    return ast.TopLevel{ .eval = ast.Expr{ .tuple = unit } };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "parseType: simple name" {
    const gpa = std.testing.allocator;
    const tokens = [_]Token{
        .{ .id = .name, .span = .{ .line = 1, .col = 1 }, .text = "num" },
        .{ .id = .eof,  .span = .{ .line = 1, .col = 4 } },
    };
    var p = Parser.init(gpa, &tokens);
    const te = try parseType(&p);
    try std.testing.expectEqual(std.meta.Tag(ast.TypeExpr).type_name, std.meta.activeTag(te));
    try std.testing.expectEqualStrings("num", te.type_name.name);
}

test "parseType: list type [num]" {
    const gpa = std.testing.allocator;
    const tokens = [_]Token{
        .{ .id = .lbracket, .span = .{ .line = 1, .col = 1 } },
        .{ .id = .name,     .span = .{ .line = 1, .col = 2 }, .text = "num" },
        .{ .id = .rbracket, .span = .{ .line = 1, .col = 5 } },
        .{ .id = .eof,      .span = .{ .line = 1, .col = 6 } },
    };
    var p = Parser.init(gpa, &tokens);
    const te = try parseType(&p);
    defer gpa.destroy(te.list);
    try std.testing.expectEqual(std.meta.Tag(ast.TypeExpr).list, std.meta.activeTag(te));
    try std.testing.expectEqualStrings("num", te.list.type_name.name);
}

test "parseType: arrow type num -> bool" {
    const gpa = std.testing.allocator;
    const tokens = [_]Token{
        .{ .id = .name,  .span = .{ .line = 1, .col = 1 }, .text = "num" },
        .{ .id = .arrow, .span = .{ .line = 1, .col = 5 } },
        .{ .id = .name,  .span = .{ .line = 1, .col = 8 }, .text = "bool" },
        .{ .id = .eof,   .span = .{ .line = 1, .col = 12 } },
    };
    var p = Parser.init(gpa, &tokens);
    const te = try parseType(&p);
    defer {
        gpa.destroy(te.arrow.from);
        gpa.destroy(te.arrow.to);
    }
    try std.testing.expectEqual(std.meta.Tag(ast.TypeExpr).arrow, std.meta.activeTag(te));
    try std.testing.expectEqualStrings("num", te.arrow.from.type_name.name);
    try std.testing.expectEqualStrings("bool", te.arrow.to.type_name.name);
}

test "parseTap: type application Tree *a" {
    const gpa = std.testing.allocator;
    const tokens = [_]Token{
        .{ .id = .name,    .span = .{ .line = 1, .col = 1 }, .text = "Tree" },
        .{ .id = .typevar, .span = .{ .line = 1, .col = 6 }, .text = "*a" },
        .{ .id = .eof,     .span = .{ .line = 1, .col = 9 } },
    };
    var p = Parser.init(gpa, &tokens);
    const te = try parseType(&p);
    defer {
        gpa.destroy(te.type_app.func);
        gpa.free(te.type_app.args);
    }
    try std.testing.expectEqual(std.meta.Tag(ast.TypeExpr).type_app, std.meta.activeTag(te));
    try std.testing.expectEqualStrings("Tree", te.type_app.func.type_name.name);
    try std.testing.expectEqual(@as(usize, 1), te.type_app.args.len);
    try std.testing.expectEqualStrings("*a", te.type_app.args[0].type_var.name);
}

test "parsePat: cons pattern x : xs" {
    const gpa = std.testing.allocator;
    const tokens = [_]Token{
        .{ .id = .name, .span = .{ .line = 1, .col = 1 }, .text = "x" },
        .{ .id = .cons, .span = .{ .line = 1, .col = 3 } }, // `:` is .cons, not .colon
        .{ .id = .name, .span = .{ .line = 1, .col = 5 }, .text = "xs" },
        .{ .id = .eof,  .span = .{ .line = 1, .col = 7 } },
    };
    var p = Parser.init(gpa, &tokens);
    const pat = try parsePat(&p);
    defer {
        gpa.destroy(pat.cons_pat.head);
        gpa.destroy(pat.cons_pat.tail);
    }
    try std.testing.expectEqual(std.meta.Tag(ast.Pat).cons_pat, std.meta.activeTag(pat));
    try std.testing.expectEqualStrings("x", pat.cons_pat.head.name.text);
    try std.testing.expectEqualStrings("xs", pat.cons_pat.tail.name.text);
}

test "parsePat: empty list pattern" {
    const gpa = std.testing.allocator;
    const tokens = [_]Token{
        .{ .id = .lbracket, .span = .{ .line = 1, .col = 1 } },
        .{ .id = .rbracket, .span = .{ .line = 1, .col = 2 } },
        .{ .id = .eof,      .span = .{ .line = 1, .col = 3 } },
    };
    var p = Parser.init(gpa, &tokens);
    const pat = try parsePat(&p);
    defer gpa.free(pat.list);
    try std.testing.expectEqual(std.meta.Tag(ast.Pat).list, std.meta.activeTag(pat));
    try std.testing.expectEqual(@as(usize, 0), pat.list.len);
}
