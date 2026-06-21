//! C-coupled lexer bridge: wraps yylex() to produce []Token for the Zig parser.
//!
//! IMPORTANT: Only import this file from C-linked compilation units
//! (mira, steer-tests, lex-tests). Never import from parser-tests,
//! which compiles parser.zig without C linkage.

const std = @import("std");
const word = @import("../runtime/word.zig");
const Allocator = std.mem.Allocator;
const tf = @import("token_filter.zig");
const TokenId = tf.TokenId;
const Token = tf.Token;
const Span = tf.Span;

const abi = @import("../runtime/c_abi.zig");
const lex_state = @import("lex_state.zig");
const ls = &lex_state.ls;

extern fn mira_lex_setup_string(source: [*:0]const u8) void;
extern fn mira_lex_cleanup() void;

// Miranda atom-range constants (from lex.zig — keep in sync with CMBASE = 306).
const CMBASE: abi.word = 306;
const FALSE_ATOM: abi.word = CMBASE + 136; // Miranda boolean False
const TRUE_ATOM: abi.word = CMBASE + 137; // Miranda boolean True
const NIL_ATOM: abi.word = CMBASE + 138;
const NILS_ATOM: abi.word = CMBASE + 139;
const ATOMLIMIT: abi.word = CMBASE + 141;

// Lexer globals exported by lex.zig.
// Heap arrays (data.h: hd and tl are offset so hd(x*2) / tl(x*2) index cell x).


extern fn yylex() c_int;
extern fn is_char(x: abi.word) c_int;
extern fn get_dbl(x: abi.word) f64;
extern fn layout() void;
extern fn setlmargin() void;
extern fn unsetlmargin() void;

// C macro equivalents: hd(x) == hd_array((x)*2), tl(x) == tl_array((x)*2)
const heap = @import("../runtime/heap.zig");

inline fn hd_of(x: abi.word) abi.word {
    return heap.heap.h(x);
}
inline fn tl_of(x: abi.word) abi.word {
    return heap.heap.t(x);
}
inline fn getTag(x: abi.word) u8 {
    return heap.heap.getTag(x);
}

// C macro: get_id(x) == (char*)hd(hd(hd(x)))
fn getIdText(x: abi.word) []const u8 {
    const ptr: usize = @intCast(hd_of(hd_of(hd_of(x))));
    const p: [*:0]const u8 = @ptrFromInt(ptr);
    return std.mem.span(p);
}

/// Traverse a Miranda string CONS chain and produce a UTF-8 owned slice.
/// String literals in Miranda are represented as CONS (tag=11) chains, NOT STRCONS.
/// Each cell hd is either an atom 0-127 (direct ASCII code point) or a UNICODE
/// heap cell (tag=21) whose tl holds the code point.
fn stringFromCons(gpa: Allocator, cell: abi.word) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(gpa);
    var cur = cell;
    while (cur >= ATOMLIMIT and getTag(cur) == word.CONS) {
        const ch_val: abi.word = hd_of(cur);
        cur = tl_of(cur);
        const codepoint: u21 = if (ch_val < ATOMLIMIT)
            @intCast(ch_val) // ASCII/Latin-1 atom: value IS the code point
        else
            @intCast(tl_of(ch_val)); // UNICODE cell: code point is in tl
        var encoded: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(codepoint, &encoded) catch {
            // Replacement character U+FFFD
            try buf.appendSlice(gpa, &.{ 0xEF, 0xBF, 0xBD });
            continue;
        };
        try buf.appendSlice(gpa, encoded[0..n]);
    }
    return buf.toOwnedSlice(gpa);
}

/// Map one yylex() return value to a Token.
/// Returns null for internal tokens that the Zig parser should skip.
fn mapToken(gpa: Allocator, raw: c_int, span: Span) !?Token {
    const w: abi.word = ls.yylval;

    return switch (raw) {
        // EOF / END (both == 0 from data.h)
        0 => Token{ .id = .eof, .span = span },

        // --- single-character tokens (returned as ASCII value) ---
        '+' => Token{ .id = .plus, .span = span },
        '-' => Token{ .id = .minus, .span = span },
        '*' => Token{ .id = .star, .span = span },
        '/' => Token{ .id = .slash, .span = span },
        '^' => Token{ .id = .caret, .span = span },
        '.' => Token{ .id = .dot, .span = span },
        '!' => Token{ .id = .bang, .span = span },
        '~' => Token{ .id = .tilde, .span = span },
        '#' => Token{ .id = .hash, .span = span },
        '=' => Token{ .id = .eq, .span = span },
        '<' => Token{ .id = .lt, .span = span },
        '>' => Token{ .id = .gt, .span = span },
        '&' => Token{ .id = .amp, .span = span },
        '|' => Token{ .id = .pipe, .span = span },
        '(' => Token{ .id = .lparen, .span = span },
        ')' => Token{ .id = .rparen, .span = span },
        '[' => Token{ .id = .lbracket, .span = span },
        ']' => Token{ .id = .rbracket, .span = span },
        '{' => Token{ .id = .lbrace, .span = span },
        '}' => Token{ .id = .rbrace, .span = span },
        ',' => Token{ .id = .comma, .span = span },
        ';' => Token{ .id = .semicolon, .span = span },
        '?' => Token{ .id = .question, .span = span },
        ':' => Token{ .id = .cons, .span = span },

        // --- multi-character and keyword tokens ---
        word.WHERE => Token{ .id = .kw_where, .span = span },
        word.IF => Token{ .id = .kw_if, .span = span },
        word.LEFTARROW => Token{ .id = .left_arrow, .span = span },
        word.COLONCOLON => Token{ .id = .coloncolon, .span = span },
        word.COLON2EQ => Token{ .id = .colon2eq, .span = span },
        word.TYPEVAR => Token{
            .id = .typevar,
            .span = span,
            .int_val = @intCast(tl_of(w)), // number of stars stored in tl
        },
        word.NAME => Token{
            .id = .name,
            .span = span,
            .text = try gpa.dupe(u8, getIdText(w)),
        },
        word.CNAME => Token{
            .id = .cname,
            .span = span,
            .text = try gpa.dupe(u8, getIdText(w)),
        },
        word.CONST => blk: {
            // 0. Miranda boolean atoms: True and False are returned by the lexer
            //    as CONST with predefined atom values, not as CNAME. Map them to
            //    CNAME so the parser handles them as constructor patterns/exprs.
            //    The codegen emits the atom word directly for "True"/"False".
            if (w == TRUE_ATOM) break :blk Token{ .id = .cname, .span = span, .text = try gpa.dupe(u8, "True") };
            if (w == FALSE_ATOM) break :blk Token{ .id = .cname, .span = span, .text = try gpa.dupe(u8, "False") };
            // 1. Char literal: is_char() handles atoms 0-255 and UNICODE heap cells.
            if (is_char(w) != 0) {
                const cp: u21 = if (w < ATOMLIMIT)
                    @intCast(w) // Latin-1 atom: value is the code point
                else
                    @intCast(tl_of(w)); // UNICODE cell: code point in tl
                break :blk Token{ .id = .const_char, .span = span, .char_val = cp };
            }
            // 2. Empty string (yylval == NIL or NILS after string())
            if (w == NIL_ATOM or w == NILS_ATOM) {
                break :blk Token{ .id = .const_str, .span = span, .text = try gpa.dupe(u8, "") };
            }
            if (w >= ATOMLIMIT) {
                const t_tag = getTag(w);
                // 3. Non-empty string literal: CONS chain of char values
                if (t_tag == word.CONS) {
                    break :blk Token{
                        .id = .const_str,
                        .span = span,
                        .text = try stringFromCons(gpa, w),
                    };
                }
                // 4. Float literal: DOUBLE-tagged heap cell; text in dicp
                if (t_tag == word.DOUBLE) {
                    break :blk Token{
                        .id = .const_float,
                        .span = span,
                        .float_val = get_dbl(w),
                    };
                }
                // 5. Integer literal: INT-tagged heap cell; decimal text in dicp.
                // Keep the original text so arbitrary precision values are not
                // truncated to a machine integer before codegen calls bigscan().
                if (t_tag == word.INT) {
                    const text_slice = std.mem.span(@as([*:0]u8, @ptrCast(ls.dicp)));
                    break :blk Token{ .id = .const_int, .span = span, .text = try gpa.dupe(u8, text_slice) };
                }
            }
            // Unknown CONST form (e.g. $* internal syntax)
            break :blk Token{ .id = .error_tok, .span = span };
        },
        word.DOLLARS => Token{ .id = .dollars, .span = span },
        word.OFFSIDE => Token{ .id = .offside, .span = span },
        word.ELSEQ => Token{ .id = .elseq, .span = span },
        word.ABSTYPE => Token{ .id = .kw_abstype, .span = span },
        word.WITH => Token{ .id = .kw_with, .span = span },
        word.EQEQ => Token{ .id = .eq_eq, .span = span },
        word.FREE => Token{ .id = .kw_free, .span = span },
        word.INCLUDE => Token{ .id = .kw_include, .span = span },
        word.EXPORT => Token{ .id = .kw_export, .span = span },
        word.TYPE => Token{ .id = .kw_type, .span = span },
        word.OTHERWISE => Token{ .id = .kw_otherwise, .span = span },
        word.SHOWSYM => Token{ .id = .kw_show, .span = span },
        word.PATHNAME => Token{
            .id = .pathname,
            .span = span,
            .text = try gpa.dupe(u8, std.mem.span(@as([*:0]u8, @ptrCast(ls.dicp)))),
        },
        word.BNF => Token{ .id = .kw_bnf, .span = span },
        word.LEX => Token{ .id = .kw_lex, .span = span },
        word.READVALSY => Token{ .id = .kw_readvals, .span = span },
        word.ARROW => Token{ .id = .arrow, .span = span },
        word.PLUSPLUS => Token{ .id = .plus_plus, .span = span },
        word.MINUSMINUS => Token{ .id = .minus_minus, .span = span },
        word.DOTDOT => Token{ .id = .dot_dot, .span = span },
        word.VEL => Token{ .id = .vel, .span = span },
        word.GE => Token{ .id = .ge, .span = span },
        word.NE => Token{ .id = .ne, .span = span },
        word.LE => Token{ .id = .le, .span = span },
        word.REM => Token{ .id = .kw_mod, .span = span },
        word.DIV => Token{ .id = .kw_div, .span = span },
        word.INFIXNAME => Token{
            .id = .infixname,
            .span = span,
            .text = try gpa.dupe(u8, getIdText(w)),
        },
        word.INFIXCNAME => Token{
            .id = .infixcname,
            .span = span,
            .text = try gpa.dupe(u8, getIdText(w)),
        },

        // Internal / BNF / LEX tokens not in the Zig parser vocabulary — skip.
        else => null,
    };
}

/// Tokenize a Miranda source string using yylex(). Sets up the lex stream,
/// drives it to EOF, and maps each C token to our TokenId vocabulary.
/// Caller owns the result; call deinit() to free.
pub fn tokenize(gpa: Allocator, source: [:0]const u8) ![]Token {
    mira_lex_setup_string(source.ptr);
    defer mira_lex_cleanup();
    return try tokenizeLoop(gpa);
}

/// Tokenize the currently active Miranda lex stream (s_in already opened).
/// Does NOT call mira_lex_setup_string or mira_lex_cleanup; the caller is
/// responsible for the stream lifetime.  Used in Phase 13 to drive yylex()
/// from whatever file openfile() opened.
pub fn tokenizeCurrent(gpa: Allocator) ![]Token {
    return try tokenizeLoop(gpa);
}

/// Inner tokenize loop shared by tokenize() and tokenizeCurrent().
fn tokenizeLoop(gpa: Allocator) ![]Token {
    var toks: std.ArrayList(Token) = .empty;
    errdefer {
        for (toks.items) |tok| {
            if (tok.text.len > 0) gpa.free(tok.text);
        }
        toks.deinit(gpa);
    }

    // Layout state mirrors the YACC grammar actions:
    //
    //   indent  (before definition '='): layout(); setlmargin()
    //   outdent (after OFFSIDE):         unsetlmargin()
    //   reindent (before ELSEQ alt):     unsetlmargin(); layout(); setlmargin()
    //
    // CRITICAL: only the DEFINITION '=' triggers setlmargin(), NOT comparison
    // '=' inside expressions (e.g. `if a=b`).  We distinguish them by tracking
    // whether we have already seen the definition '=' for the current item.
    //
    //   seen_def_eq – true once setlmargin() has been called for the current
    //                 definition; prevents inner '=' from re-calling it.
    //   paren_depth – definition '=' never appears inside () or []; any '='
    //                 inside brackets is definitely a comparison.
    var seen_def_eq: bool = false;
    var paren_depth: i32 = 0;

    while (true) {
        const raw = yylex();
        // Capture span AFTER yylex so that line_no reflects the line that was
        // just processed. Use tok_start_col (set by yylex right after layout())
        // for the column — this is the column at the START of the token, before
        // any characters are read. Using col (post-read) would give different
        // columns for same-indented identifiers of different lengths.
        const span = Span{
            .line = @intCast(ls.line_no),
            .col = @intCast(ls.tok_start_col),
        };
        if (try mapToken(gpa, raw, span)) |tok| {
            try toks.append(gpa, tok);
            if (tok.id == .eof or tok.id == .error_tok) break;

            switch (tok.id) {
                // Track bracket nesting: '=' inside brackets is always a comparison.
                .lparen, .lbracket, .lbrace => paren_depth += 1,
                .rparen, .rbracket, .rbrace => paren_depth -= 1,

                // Definition '=': call layout()+setlmargin() exactly once per
                // definition.  Subsequent '=' (comparisons) are skipped.
                .eq => {
                    if (paren_depth == 0 and !seen_def_eq) {
                        layout();
                        setlmargin();
                        seen_def_eq = true;
                    }
                },

                // OFFSIDE ends the current definition; restore outer lmargin and
                // reset seen_def_eq so the next definition '=' triggers setlmargin.
                .offside => {
                    unsetlmargin();
                    seen_def_eq = false;
                    paren_depth = 0;
                },

                // ELSEQ is the layout-generated '=' that starts an alternative
                // guard case.  Mirror YACC's `reindent` production:
                //   unsetlmargin(); layout(); setlmargin()
                // Then mark seen_def_eq=true because the ELSEQ itself consumed
                // the '=' — the next RHS body should not trigger setlmargin again.
                .elseq => {
                    unsetlmargin();
                    layout();
                    setlmargin();
                    seen_def_eq = true;
                },

                // WHERE begins local definitions; reset seen_def_eq so each local
                // definition '=' correctly triggers setlmargin.
                .kw_where => {
                    seen_def_eq = false;
                },

                // COLON2EQ (::=) opens an algebraic type body.
                // Mirror YACC's `typeform indent act1 here COLON2EQ` where the
                // `indent` mid-rule action fires (with ::= as lookahead) and calls
                // layout()+setlmargin(), setting lmargin to the column of the first
                // constructor.  This prevents tokens on a new line at col < lmargin
                // from being consumed as constructor field types.
                .colon2eq => {
                    layout();
                    setlmargin();
                },

                // EQEQ (==) opens a type synonym body (only at top-level).
                // Same treatment as COLON2EQ.  Guard on !seen_def_eq so that ==
                // used as an equality comparison inside a function body is skipped.
                .eq_eq => {
                    if (!seen_def_eq) {
                        layout();
                        setlmargin();
                    }
                },

                // COLONCOLON (::) introduces a type signature body.
                // Mirror YACC's `namelist indent here COLONCOLON type outdent` where
                // the `indent` mid-rule fires before COLONCOLON: layout()+setlmargin()
                // sets lmargin to the column of the type body.  The matching OFFSIDE
                // (generated at the start of the next top-level definition) will call
                // unsetlmargin() to restore the outer margin.
                // Guard on paren_depth==0 so that `expr :: type` casts inside
                // expressions do not affect lmargin.
                .coloncolon => {
                    if (paren_depth == 0) {
                        layout();
                        setlmargin();
                    }
                },

                else => {},
            }
        }
        if (raw == 0) break; // END/EOF without a mapped token (shouldn't happen)
    }

    return toks.toOwnedSlice(gpa);
}

/// Free all memory associated with a tokenize() result.
pub fn deinit(gpa: Allocator, tokens: []Token) void {
    for (tokens) |tok| {
        if (tok.text.len > 0) gpa.free(tok.text);
    }
    gpa.free(tokens);
}
