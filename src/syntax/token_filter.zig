//! Token definitions for the Miranda Zig recursive-descent / Pratt parser.
//!
//! IMPORTANT: The Miranda `:` list-cons operator is represented as `.cons`
//! in `TokenId` — NOT `.colon` — to distinguish it unambiguously from
//! `::` (coloncolon) and `::=` (colon2eq).

const std = @import("std");

/// Which stream + wrapper format a lex-level diagnostic prints with —
/// legacy's printing isn't uniform across call sites (`compiler/setup.zig`'s
/// `syntax()` helper: stderr, adds its own "syntax error: " prefix; ad hoc
/// `word.print` call sites like `errclass()`/`directive()`: stdout, exact
/// text).
pub const DiagnosticStream = enum { stdout, stderr };

/// A single parse/lex-level diagnostic: where it happened, what it says,
/// and (since legacy's printing isn't uniform across call sites — see
/// `DiagnosticStream`'s doc comment) how to print it. Shared by
/// `parser/parser.zig`, `syntax/lexer.zig`, and `syntax/directives.zig`
/// (Phase 2 step 2, docs/GO_PORT_PLAN.md — promoted from three
/// independently-defined, near-identical structs to one, living here for
/// the same reason `Span`/`DiagnosticStream` do: `syntax/` already depends
/// on `parser/`, so `parser/ast.zig`/`parser/parser.zig` importing
/// `syntax/lexer.zig` back would cycle, and `token_filter.zig` has no
/// dependencies of its own). `parser.zig`'s own diagnostics never set
/// `stream`/`add_prefix` explicitly — the defaults (`.stderr`/`true`) are
/// inert for its existing reporting path, which doesn't read either field.
pub const Diagnostic = struct {
    span: Span,
    message: []const u8,
    stream: DiagnosticStream = .stderr,
    add_prefix: bool = true,
};

/// The lexical token kinds the Pratt parser consumes: identifiers/literals,
/// keywords, the single- and multi-character operators, the layout tokens the
/// offside filter injects, and the `eof`/`error_tok` specials.
pub const TokenId = enum {
    // --- identifiers and literals ---
    name, // lowercase identifier
    cname, // constructor / uppercase identifier
    typevar, // type variable (*a, *b, …)
    const_int,
    const_float,
    const_str,
    const_char,
    infixname, // `name`
    infixcname, // `Cname`
    dollars, // $$
    pathname,
    /// A whole `%include`/`%export`/`%free`/`%insert`/... directive, scanned
    /// as one atomic unit (`syntax/directives.zig`'s `Scanner`) rather than as
    /// ordinary tokens — its structured payload lives in a side table the
    /// lexer/parser share, indexed by this token's `int_val`. See
    /// `syntax/lexer.zig`'s `lexDirective`.
    directive,

    // --- keywords ---
    kw_where,
    kw_if,
    kw_otherwise,
    kw_abstype,
    kw_with,
    kw_type,
    kw_free,
    kw_include,
    kw_export,
    kw_bnf,
    kw_lex,
    kw_readvals,
    kw_show,
    kw_div,
    kw_mod,

    // --- single-character tokens ---
    plus, // +
    minus, // -
    star, // *
    slash, // /
    caret, // ^
    dot, // .   (function composition)
    bang, // !   (list subscript)
    tilde, // ~   (logical / unary negation)
    hash, // #   (list length)
    eq, // =
    lt, // <
    gt, // >
    amp, // &   (logical and)
    pipe, // |   (list-compr. / constructor alt separator)
    lparen, // (
    rparen, // )
    lbracket, // [
    rbracket, // ]
    lbrace, // {
    rbrace, // }
    comma, // ,
    semicolon, // ;
    question, // ?   (lex optional quantifier)

    /// `:` — Miranda list-cons operator.
    /// Named `cons` (not `colon`) to avoid confusion with `::` and `::=`.
    cons,

    // --- multi-character tokens ---
    arrow, // ->
    plus_plus, // ++
    minus_minus, // --
    dot_dot, // ..
    vel, // \/  (logical disjunction)
    ge, // >=
    ne, // ~=
    le, // <=
    left_arrow, // <-
    coloncolon, // ::
    colon2eq, // ::=
    eq_eq, // ==

    // --- layout tokens injected by the filter pass ---
    offside,
    elseq, // OFFSIDE =

    // --- specials ---
    eof,
    error_tok,
};

/// A source position: 1-based `line` and `col`.
pub const Span = struct {
    line: u32,
    col: u32,
};

/// A lexed token: its `id` (kind), source `span`, and any literal payload. Only
/// the field matching `id` is meaningful — `text` for name/cname/string/integer
/// tokens, `int_val`/`float_val`/`char_val` for the corresponding literals.
pub const Token = struct {
    id: TokenId,
    span: Span,
    /// Raw text for name / cname / string / integer tokens.
    text: []const u8 = &.{},
    int_val: i64 = 0,
    float_val: f64 = 0.0,
    char_val: u21 = 0,
};

/// A `.directive` token's structured payload (`syntax/directives.zig`'s
/// `Scanner` output) — defined here, not in `syntax/directives.zig` or
/// `parser/ast.zig`, so both can use the same type without an import cycle:
/// `syntax/` already imports from `parser/` (e.g. `syntax/layout.zig`
/// imports `parser/parser.zig`), so `parser/ast.zig` importing
/// `syntax/directives.zig` the other way would cycle. `token_filter.zig`
/// has no dependencies of its own, so it's the natural shared home — the
/// same role `Span` already plays.
///
/// One `new/old` rename or `-old` suppression in an `%include`'s alias list
/// (`%include "mike" -g mike_f/f`).
pub const DirectiveAlias = union(enum) {
    rename: struct { new: []const u8, old: []const u8 },
    suppress: []const u8,
};

pub const DirectiveInclude = struct {
    /// The pathname exactly as written (no `.m` extension added, no `~`
    /// expansion, no prefix resolution).
    path: []const u8,
    /// `<...>` (relative to miralib) vs `"..."` (relative to the including
    /// script's own directory, or absolute, or `~`-relative).
    from_miralib: bool,
    /// Raw text of the `{...}` free-binding block, or `&.{}` if absent.
    bindings_text: []const u8,
    /// Alias list following the pathname/bindings, parsed (unlike the
    /// bindings block, since the alias grammar is simple enough to scan
    /// directly: `identifier/identifier` or `-identifier`, whitespace
    /// separated, ending at the line's end).
    aliases: []const DirectiveAlias,
    span: Span,
};

/// A whole `%`-directive, scanned as one atomic unit (its grammar doesn't
/// decompose into ordinary tokens — see `syntax/directives.zig`'s header).
pub const Directive = union(enum) {
    include: DirectiveInclude,
    /// Raw text of the parts list (`identifier`/`Cname`/`"fileid"`/`+`/
    /// `-identifier`, space separated), up to end-of-line.
    export_list: struct { parts_text: []const u8, span: Span },
    /// Raw text of the `{ signature }` block (braces excluded).
    free: struct { spec_text: []const u8, span: Span },
    /// `%insert`/`%list`/`%nolist`/`%bnf`/`%lex`/`%begin` — recognized, not
    /// processed (see `syntax/directives.zig`'s header).
    unsupported: struct { keyword: []const u8, span: Span },
    /// A `%` followed by a name that isn't a known directive keyword
    /// (matches `lex.zig`'s `directive()` "unknown directive" error path).
    unknown: struct { text: []const u8, span: Span },

    /// Frees whatever this directive owns. Every field except `.include`'s
    /// `aliases` (from `syntax/directives.zig`'s `scanAliases`'s
    /// `toOwnedSlice`) is a borrowed slice into the `Source` that produced
    /// it — nothing else to free.
    pub fn deinit(self: Directive, gpa: std.mem.Allocator) void {
        switch (self) {
            .include => |inc| gpa.free(inc.aliases),
            .export_list, .free, .unsupported, .unknown => {},
        }
    }
};
