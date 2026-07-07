//! Miranda AST node types produced by the Zig recursive-descent / Pratt parser.

/// Source position (re-exported from `token_filter`) carried by AST nodes.
pub const Span = @import("token_filter.zig").Span;

// ---------------------------------------------------------------------------
// Type expressions
// ---------------------------------------------------------------------------

/// A type expression — the parsed form of a `::` annotation or the body of a
/// `type`/`abstype` declaration. Compound forms hold `*TypeExpr` children.
pub const TypeExpr = union(enum) {
    /// Type variable, e.g. `*a`
    type_var: struct { name: []const u8, span: Span },
    /// Named type constructor, e.g. `num`, `bool`, `Tree`
    type_name: struct { name: []const u8, span: Span },
    /// Function arrow type: `A -> B`
    arrow: struct { from: *TypeExpr, to: *TypeExpr },
    /// Type-constructor application: `Tree *a` or `Either *a *b`.
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

/// A literal constant. `int` keeps the source digits (the bignum is built later);
/// `float`/`char` are decoded, `string` is the raw text.
pub const Literal = union(enum) {
    int: []const u8,
    float: f64,
    string: []const u8,
    char: u21,
};

// ---------------------------------------------------------------------------
// Expressions
// ---------------------------------------------------------------------------

/// A list-comprehension qualifier: generator (`pat <- src`) or guard (`pred`).
pub const Qualifier = union(enum) {
    generator: struct { pat: Expr, source: *Expr },
    /// Sequence generator: `pat <- src, step ..`  →  ITERATE/ITERATE1 combinator.
    sequence_generator: struct { pat: Expr, source: *Expr, step: *Expr },
    guard: *Expr,
};

/// An expression node. Compound forms hold `*Expr` children; the variants cover
/// application, the infix/prefix operators, list/tuple/range/comprehension
/// syntax, operator sections, type annotations, and `where`.
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
    /// Right operator section: `(op expr)` — e.g. `(+1)` means `\x -> x + 1`
    section_right: struct { op: []const u8, arg: *Expr },
    /// Left operator section: `(expr op)` — e.g. `(1+)` means `\x -> 1 + x`
    section_left: struct { arg: *Expr, op: []const u8 },
    /// Operator-as-function: `(+)`, `(*)`, etc.  Field is the token tag-name.
    op_func: []const u8,
    /// Arithmetic sequence: `[from..]`, `[from..to]`, `[from,step..]`, `[from,step..to]`
    range: struct { from: *Expr, step: ?*Expr, to: ?*Expr },
    /// List comprehension: `[body | q1; q2; …]`
    listcomp: struct { body: *Expr, qualifiers: []Qualifier },
};

// ---------------------------------------------------------------------------
// Patterns
// ---------------------------------------------------------------------------

/// A pattern: the LHS of a definition or a formal argument. Compound forms hold
/// `*Pat` children (cons/application) or slices (list/tuple).
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

/// One guarded alternative of a right-hand side: `body, if cond`. When
/// `is_otherwise` is set the branch is unconditional and `cond` is a placeholder.
pub const Guard = struct {
    cond: Expr,
    body: Expr,
    /// True when the guard is `body, otherwise` (always-true branch).
    /// When true, `cond` is a placeholder and should not be evaluated.
    is_otherwise: bool,
    span: Span,
};

/// The right-hand side of a definition: a single `expr`, or a list of `guarded`
/// alternatives (`= body, if cond`).
pub const Rhs = union(enum) {
    expr: Expr,
    guarded: []Guard,
};

/// A definition `lhs = rhs`, with any local `where_defs`. `lhs` is an `Expr`
/// (a name, or an application encoding a function's formal parameters).
pub const Def = struct {
    lhs: Expr,
    rhs: Rhs,
    where_defs: []Def,
    span: Span,
};

// ---------------------------------------------------------------------------
// Type declarations
// ---------------------------------------------------------------------------

/// A bundled type specification: `names :: type`
pub const TypeSpec = struct {
    names: [][]const u8,
    typ: TypeExpr,
    span: Span,
};

/// One data constructor of an algebraic type: its `name` and `fields` (the
/// argument types).
pub const Constructor = struct {
    name: []const u8,
    fields: []TypeExpr,
    span: Span,
};

/// A type declaration: a `synonym` (`==`), an `algebraic` type (`::=`), or an
/// `abstype` (abstract type with its exported specs).
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
        specs: []TypeSpec,
        span: Span,
    },
};

// ---------------------------------------------------------------------------
// Top-level items and script root
// ---------------------------------------------------------------------------

/// A top-level script item: a definition, a type spec/declaration, an evaluation
/// request, or an `%include`/`%export`/`%free` directive.
pub const TopLevel = union(enum) {
    definition: Def,
    type_spec: TypeSpec,
    type_decl: TypeDecl,
    eval: Expr,
    /// A directive parsed via the *legacy-bridge-fed* token stream
    /// (`kw_include`/`pathname` etc. — see `parser.zig`'s `parseInclude`):
    /// today's live production shape, narrower than what real
    /// `%include`/`%export`/`%free` semantics need (no bindings, no
    /// aliases, no `<...>` miralib-relative form, no `+`/`-exclude`/quoted-
    /// fileid export forms). Left untouched — see `.directive` below.
    include: struct { path: []const u8, span: Span },
    export_list: struct { names: [][]const u8, span: Span },
    free_directive: struct { specs: []TypeSpec, span: Span },
    /// A directive parsed via the *native* pipeline's single atomic
    /// `.directive` token (`syntax/lexer.zig`'s `lexDirective`,
    /// `syntax/directives.zig`'s `Scanner`) — carries the real grammar's
    /// full data (bindings, aliases, `from_miralib`, the full `%export`
    /// parts grammar as raw text). Not yet consumed by `codegen.zig` (a
    /// no-op there, like the three variants above) or bound to real
    /// `%include`/`%export`/`%free` compilation semantics — see
    /// docs/ZIG_NATIVE_PLAN.md's step 5 for what's still needed
    /// (loading/compiling the included file, cycle detection,
    /// free-binding substitution).
    directive: Directive,
};

/// Re-exported from `token_filter.zig`: see its own doc comment on
/// `Directive` for why the type lives there rather than being imported from
/// `syntax/directives.zig` (which produces it) or defined fresh here.
pub const Directive = @import("token_filter.zig").Directive;

/// A parsed script: its sequence of top-level `items`.
pub const Script = struct {
    items: []TopLevel,
};
