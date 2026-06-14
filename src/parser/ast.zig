//! Miranda AST node types produced by the Zig recursive-descent / Pratt parser.

const std = @import("std");
pub const Span = @import("token_filter.zig").Span;

// ---------------------------------------------------------------------------
// Type expressions
// ---------------------------------------------------------------------------

pub const TypeExpr = union(enum) {
    /// Type variable, e.g. `*a`
    type_var: struct { name: []const u8, span: Span },
    /// Named type constructor, e.g. `num`, `bool`, `Tree`
    type_name: struct { name: []const u8, span: Span },
    /// Function arrow type: `A -> B`
    arrow: struct { from: *TypeExpr, to: *TypeExpr },
    /// Type-constructor application: `Tree *a` or `Either *a *b`.
    /// `args` is a non-empty heap-allocated slice — never a pointer to a
    /// stack / comptime array literal.
    type_app: struct { func: *TypeExpr, args: []TypeExpr },
    /// Tuple type: `(A, B)`, `(A, B, C)`, …
    tuple: []TypeExpr,
    /// List type: `[A]`
    list: *TypeExpr,
    /// Void / unit type `()`
    void_t,
};

// ---------------------------------------------------------------------------
// Literals
// ---------------------------------------------------------------------------

pub const Literal = union(enum) {
    int: i64,
    float: f64,
    string: []const u8,
    char: u21,
};

// ---------------------------------------------------------------------------
// Expressions
// ---------------------------------------------------------------------------

pub const Expr = union(enum) {
    name: struct { text: []const u8, span: Span },
    cname: struct { text: []const u8, span: Span },
    literal: struct { value: Literal, span: Span },
    /// Function application (juxtaposition): `f x`
    application: struct { func: *Expr, arg: *Expr },
    /// Infix operation: `x + y`, `x : y`, …  `op` is the token tag-name.
    infix: struct { op: []const u8, lhs: *Expr, rhs: *Expr },
    /// Unary negation: `~x`
    neg: *Expr,
    /// List-length prefix: `#x`
    length: *Expr,
    /// Empty list `[]`
    list_nil,
    /// Non-empty list literal: `[a, b, c]`
    list: []Expr,
    /// Tuple literal: `(a, b)`, `(a, b, c)`, …
    tuple: []Expr,
    /// Type annotation: `expr :: type`
    typed: struct { expr: *Expr, typ: *TypeExpr },
    /// Where clause: `body where { defs }`
    where: struct { body: *Expr, defs: []Def },
    /// Conditional guard (internal): `expr, if cond`
    cond: struct { guard: *Expr, then_expr: *Expr },
};

// ---------------------------------------------------------------------------
// Patterns
// ---------------------------------------------------------------------------

pub const Pat = union(enum) {
    wildcard,
    name: struct { text: []const u8, span: Span },
    cname: struct { text: []const u8, span: Span },
    literal: struct { value: Literal, span: Span },
    /// List cons pattern: `head : tail`
    cons_pat: struct { head: *Pat, tail: *Pat },
    list: []Pat,
    tuple: []Pat,
    application: struct { func: *Pat, arg: *Pat },
};

// ---------------------------------------------------------------------------
// Definitions and right-hand sides
// ---------------------------------------------------------------------------

pub const Guard = struct {
    cond: Expr,
    body: Expr,
    span: Span,
};

pub const Rhs = union(enum) {
    expr: Expr,
    guarded: []Guard,
};

pub const Def = struct {
    lhs: Expr,
    rhs: Rhs,
    where_defs: []Def,
    span: Span,
};

// ---------------------------------------------------------------------------
// Type declarations
// ---------------------------------------------------------------------------

pub const Constructor = struct {
    name: []const u8,
    fields: []TypeExpr,
    span: Span,
};

pub const TypeDecl = union(enum) {
    synonym: struct {
        name: []const u8,
        params: [][]const u8,
        body: TypeExpr,
        span: Span,
    },
    algebraic: struct {
        name: []const u8,
        params: [][]const u8,
        constructors: []Constructor,
        span: Span,
    },
    abstype: struct {
        name: []const u8,
        params: [][]const u8,
        span: Span,
    },
};

// ---------------------------------------------------------------------------
// Top-level items and script root
// ---------------------------------------------------------------------------

pub const TopLevel = union(enum) {
    definition: Def,
    type_spec: struct { names: [][]const u8, typ: TypeExpr, span: Span },
    type_decl: TypeDecl,
    eval: Expr,
    include: struct { path: []const u8, span: Span },
    export_list: struct { names: [][]const u8, span: Span },
};

pub const Script = struct {
    items: []TopLevel,
};
