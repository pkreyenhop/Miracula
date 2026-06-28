//! Token definitions for the Miranda Zig recursive-descent / Pratt parser.
//!
//! IMPORTANT: The Miranda `:` list-cons operator is represented as `.cons`
//! in `TokenId` — NOT `.colon` — to distinguish it unambiguously from
//! `::` (coloncolon) and `::=` (colon2eq).


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

pub const Span = struct {
    line: u32,
    col: u32,
};

pub const Token = struct {
    id: TokenId,
    span: Span,
    /// Raw text for name / cname / string / integer tokens.
    text: []const u8 = &.{},
    int_val: i64 = 0,
    float_val: f64 = 0.0,
    char_val: u21 = 0,
};
