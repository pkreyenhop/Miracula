//! parser_api.zig — the entry points that drive parsing.
//!
//! `parseCurrent`/`parseString` are the production entry points
//! (`parseCurrent` feeds `module_loader.zig`'s `loadfile` and the REPL loop;
//! file-based parsing goes through `loadfile`'s own open+`parseCurrent`
//! sequence, not a `parseFile` wrapper here — see `compiler/module_loader.zig`).
//! Phase 1 step 8: the native `syntax/` pipeline (`Source` → `lexer` →
//! `applyLayout` → `parser.zig`/`codegen.zig`) is the only front end —
//! the legacy `lex_bridge.zig` (real `yylex()`) path and the
//! `-Dlegacy-lexer` escape hatch were deleted once the native pipeline had
//! been the production default (step 7) for long enough to trust.
//! `parseWithNew` (string input only, used by `parser_tests.zig`) now goes
//! through the same native pipeline as `parseCurrentNative`.

const std = @import("std");
const heap = @import("../runtime/heap.zig");
const options = @import("version_options");

const word = @import("../runtime/word.zig");
const rt = @import("../runtime/runtime_state.zig");
const core = @import("../runtime/core_state.zig");
const compiler_state = @import("../compiler/compiler_state.zig");

const parser_mod = @import("parser.zig");
const codegen = @import("codegen.zig");
const repl = @import("../driver/repl.zig");
const lex_state = @import("lex_state.zig");
// Forks like the original C evaluate(): compiling=0 only in child; parent's heap is safe.
const evaluateRepl = repl.evaluateRepl;

const source_mod = @import("../syntax/source.zig");
const lexer_mod = @import("../syntax/lexer.zig");
const layout_mod = @import("../syntax/layout.zig");
const modules = @import("../semantics/modules.zig");
/// Errors the parse entry points can return.
pub const ParseError = error{
    SyntaxError,
    ParseFailed,
};

/// The outcome of a successful parse.
pub const ParseResult = enum {
    success,
};

/// Parses the currently active stream through the native `syntax/`
/// pipeline (`Source` → `lexer` → `applyLayout` → `parser.zig`/
/// `codegen.zig`) — the only front end since the legacy `lex_bridge.zig`
/// (real `yylex()`) path and its `-Dlegacy-lexer` escape hatch were deleted
/// (Phase 1 step 8), once step 7 had proven the native pipeline out as the
/// production default.
pub fn parseCurrent() ParseError!ParseResult {
    return parseCurrentNative();
}

/// Read from the currently-open stream (`rt.rs().s_in`) into an owned
/// buffer, one byte at a time via `word.getc` — the native pipeline's
/// `Source` needs a whole unit of input up front (it isn't a streaming
/// reader), but this doesn't require changing how/where the stream was
/// opened (`lex.zig`'s `openfile`, driven by callers like
/// `module_loader.zig`'s `loadfile`, is untouched).
///
/// `stop_at_newline`: command-mode (the interactive REPL prompt) reads
/// **one line at a time** from a long-lived `stdin` shared across many
/// `parseCurrent` calls — `driver/repl.zig`'s command loop calls this once
/// per line the user types, and reads the *next* line on its *next* call.
/// Draining the whole stream here (as whole-script compilation correctly
/// does) would silently swallow lines meant for later prompts. Matches
/// `lex.zig`'s own line-oriented reading, driven by `lexs.c` at the
/// caller's level (see `runParsedTokens`'s command-mode success path for
/// why that field still matters even though this pipeline never reads it).
fn slurpCurrentStream(gpa: std.mem.Allocator, stop_at_newline: bool) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    while (true) {
        const c = word.getc(rt.rs().s_in);
        if (c < 0) break;
        try out.append(gpa, @intCast(c));
        if (stop_at_newline and c == '\n') break;
    }
    return out.toOwnedSlice(gpa);
}

/// Run the native `syntax/` pipeline (`Source` → `lexer` → `applyLayout` →
/// `parser.zig`/`codegen.zig`) on the currently active Miranda lex stream.
/// The Phase 1 step 7 default.
fn parseCurrentNative() ParseError!ParseResult {
    if (options.is_strict) {
        if (rt.rs().current_script) |script_name| {
            validateUtf8File(script_name) catch |err| {
                core.s().SYNERR = 1;
                return err;
            };
        }
    }
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Command mode (the interactive REPL prompt) reads one line at a time
    // from a long-lived stdin, not a whole standalone file — neither
    // "read until EOF" nor filename-based literate detection apply.
    const command_mode = core.s().commandmode != 0;
    const raw = slurpCurrentStream(alloc, command_mode) catch return ParseError.ParseFailed;

    // legacy's yylex() resets `s_in` to stdin itself, as a side effect of
    // lexEndOfFile() popping the last entry off the file queue while
    // reading character-by-character -- the batch/slurp model above has no
    // equivalent incremental moment, so replicate the same postcondition
    // explicitly: once a whole file (not a REPL line) has been fully read,
    // its stream is spent and must not be read from again. Close it (
    // lexEndOfFile() does too, once per popped queue entry) and point
    // s_in back at stdin, matching getStdin()'s role there. Guarded on
    // "not already stdin" so REPL/string input (s_in already == stdin) is
    // never closed.
    if (!command_mode and rt.rs().s_in != word.stdin()) {
        _ = word.fclose(rt.rs().s_in);
        rt.rs().s_in = word.stdin();
    }

    const name_says_literate = !command_mode and if (rt.rs().current_script) |name|
        source_mod.Source.isLiterateName(std.mem.span(name))
    else
        false;
    // %insert splices another file's bytes in place, textually, before
    // tokenizing at all -- see Source.resolveInserts's doc comment. Resolved
    // relative to the current script's own directory (REPL/string input has
    // no current_script, so nothing to resolve against -- "." is inert
    // there since %insert can't meaningfully appear in a typed expression
    // anyway).
    const base_dir = if (!command_mode and rt.rs().current_script != null)
        std.fs.path.dirname(std.mem.span(rt.rs().current_script.?)) orelse "."
    else
        ".";
    const spliced = source_mod.Source.resolveInserts(alloc, raw, base_dir, std.Options.debug_io, 0) catch return ParseError.ParseFailed;
    var src = source_mod.Source.init(alloc, spliced, name_says_literate) catch return ParseError.ParseFailed;
    const tok_result = lexer_mod.tokenizeWithDirectives(alloc, &src) catch return ParseError.ParseFailed;
    const laid_out = layout_mod.applyLayout(alloc, tok_result.tokens) catch return ParseError.ParseFailed;

    var p = parser_mod.Parser.initWithDirectives(alloc, laid_out, tok_result.directives);
    return runParsedTokens(&p, alloc, tok_result.diagnostics, base_dir);
}

/// Print one lex-level diagnostic exactly as legacy would have, given which
/// stream/wrapper its originating call site used (see `lexer_mod.Diagnostic`'s
/// doc comment).
fn reportLexerDiagnostic(d: lexer_mod.Diagnostic) void {
    switch (d.stream) {
        // Legacy's ad hoc word.print() call sites (errclass(),
        // directive()'s "unknown directive") -- stdout, exact text, no
        // prefix added here (baked into the message already if the call
        // site needs one).
        .stdout => word.print("{s}\n", .{d.message}),
        // Legacy's shared syntax() helper -- stderr, with a "syntax
        // error: " prefix syntax() adds itself.
        .stderr => if (d.add_prefix)
            word.printErr("syntax error: {s}\n", .{d.message})
        else
            word.printErr("{s}\n", .{d.message}),
    }
}

/// `parseCurrentNative`'s tail: command-mode expression evaluation, or
/// full-script parse + codegen + diagnostic reporting. `lexer_diagnostics`
/// are the native pipeline's lex-level diagnostics, collected during
/// tokenization rather than reported immediately (unlike the deleted
/// legacy lexer's `acterror()`/`syntax()` calls, made directly mid-scan).
fn runParsedTokens(p: *parser_mod.Parser, alloc: std.mem.Allocator, lexer_diagnostics: []const lexer_mod.Diagnostic, base_dir: []const u8) ParseError!ParseResult {
    // Command mode: the user typed an expression at the REPL prompt.
    // In the old YACC grammar this was handled by `EVAL exp { evaluate($2); }`.
    // We parse one expression, codegen it, then fork via evaluateRepl().
    if (core.s().commandmode != 0) {
        const expr = parser_mod.parseExpr(p) catch |err| {
            core.s().SYNERR = 1;
            // A lex-level error (e.g. a bad string escape) surfaces here as
            // parseExpr choking on the resulting .error_tok -- report the
            // *specific* lexer diagnostic instead of the generic fallback
            // when one exists, matching legacy (whose lexer prints its own
            // message immediately, before the parser ever sees anything).
            if (lexer_diagnostics.len > 0) {
                reportLexerDiagnostic(lexer_diagnostics[0]);
            } else if (err == error.UnexpectedEof) {
                _ = word.print("syntax error - unexpected newline\n", .{.{}});
            } else {
                _ = word.print("syntax error - unexpected token\n", .{.{}});
            }
            return ParseError.SyntaxError;
        };
        if (options.is_strict or @import("builtin").mode == .Debug) {
            heap.heap().validate();
            p.validate();
            rt.rs().validate();
        }
        if (!p.ts.check(.eof) and !p.ts.check(.offside)) {
            // Trailing tokens after the expression — treat as syntax error.
            core.s().SYNERR = 1;
            _ = word.print("syntax error - unexpected token\n", .{.{}});
            return ParseError.SyntaxError;
        }
        const expr_word = codegen.codegenExpr(alloc, expr);
        if (options.is_strict or @import("builtin").mode == .Debug) {
            heap.heap().validate();
            p.validate();
            rt.rs().validate();
        }
        rt.rs().lastexp = expr_word; // anchor as GC root before typeOf() inside evaluateRepl() can trigger GC
        evaluateRepl(heap.heap(), core.s(), compiler_state.cs(), rt.rs(), expr_word);
        // driver/repl.zig's command loop checks `lexs.c` after this call
        // returns to decide whether the line held trailing garbage (`lexs.c
        // != '\n'` -> "syntax error", matching the legacy lexer's own
        // single-character-lookahead contract). The checks above already
        // confirmed nothing but eof/offside follows the parsed expression,
        // so satisfy that contract explicitly -- this pipeline never
        // touches `lexs.c` otherwise (it's internal to the lex.zig/
        // lex_state.zig machinery this pipeline doesn't use).
        lex_state.ls().c = '\n';
        // Child prints newline before exit(0); parent returns here.
        return .success;
    }

    const script = parser_mod.parseScript(p) catch return ParseError.ParseFailed;
    if (options.is_strict or @import("builtin").mode == .Debug) {
        heap.heap().validate();
        p.validate();
        rt.rs().validate();
    }

    // Lexer diagnostics logically precede parser diagnostics in source order
    // for the common case (a lex error yields an .error_tok the parser then
    // also complains about) -- report them first. Only the *first* lexer
    // diagnostic, matching legacy's `syntax()`/`acterror()`: both guard on
    // `SYNERR != 0` and are no-ops once it's already set, so only the
    // earliest lex-level error ever actually prints.
    if (!@import("builtin").is_test) {
        if (lexer_diagnostics.len > 0) {
            reportLexerDiagnostic(lexer_diagnostics[0]);
        }
        for (p.diagnostics.items) |d| {
            std.debug.print("{d}:{d}: {s}\n", .{ d.span.line, d.span.col, d.message });
        }
    }
    if (lexer_diagnostics.len > 0) {
        core.s().SYNERR = 1;
        core.s().errline = @intCast(lexer_diagnostics[0].span.line);
        core.s().errcol = @intCast(lexer_diagnostics[0].span.col);
        recordDiagnosticMessage(lexer_diagnostics[0].message);
        return ParseError.SyntaxError;
    }
    if (p.diagnostics.items.len > 0) {
        core.s().SYNERR = 1;
        core.s().errline = @intCast(p.diagnostics.items[0].span.line);
        core.s().errcol = @intCast(p.diagnostics.items[0].span.col);
        recordDiagnosticMessage(p.diagnostics.items[0].message);
        return ParseError.SyntaxError;
    }

    var including_stack: modules.IncludingStack = .{};
    defer including_stack.deinit(alloc);
    modules.processIncludes(alloc, script, base_dir, &including_stack) catch |err| {
        reportIncludeError(err);
        return ParseError.ParseFailed;
    };

    codegen.codegenScript(alloc, script);
    if (options.is_strict or @import("builtin").mode == .Debug) {
        heap.heap().validate();
        p.validate();
        rt.rs().validate();
    }
    return .success;
}

/// Persist the first diagnostic's message text into
/// `core.s().last_diagnostic_message` (Phase 2 step 2, additive). `message`
/// is arena-backed (the caller's diagnostics list lives in the same arena
/// `parseCurrentNative`/`parseWithNew` frees on return), so it must be
/// duplicated with a longer-lived allocator to survive past this call —
/// leaked deliberately (like `lex.zig`'s `keep()` permanently retaining
/// dictionary strings), matching this field's "one message per failed
/// compile, for the life of the process" role. First diagnostic wins:
/// callers only reach this once per parse (each call site returns
/// immediately after), same as `errline`/`errcol`/`SYNERR`.
fn recordDiagnosticMessage(message: []const u8) void {
    core.s().last_diagnostic_message = rt.allocator.dupe(u8, message) catch return;
}

/// Report a `modules.processIncludes` failure and set `SYNERR` — shared by
/// `runParsedTokens` and `parseWithNew`, both of which process `%include`s
/// before their own `codegenScript` call.
fn reportIncludeError(err: anyerror) void {
    core.s().SYNERR = 1;
    switch (err) {
        modules.ModuleError.IncludeCycle => word.printErr("syntax error: circular %include\n", .{}),
        else => word.printErr("syntax error: %include failed ({s})\n", .{@errorName(err)}),
    }
}

fn validateUtf8File(filename: [*:0]const u8) ParseError!void {
    const io = std.Options.debug_io;
    const dir = std.Io.Dir.cwd();
    const file = dir.openFile(io, std.mem.span(filename), .{}) catch return ParseError.ParseFailed;
    defer file.close(io);

    const file_len = file.length(io) catch return ParseError.ParseFailed;
    if (file_len > 10 * 1024 * 1024) return ParseError.ParseFailed;

    const alloc = std.heap.page_allocator;
    const file_bytes = alloc.alloc(u8, @intCast(file_len)) catch return ParseError.ParseFailed;
    defer alloc.free(file_bytes);

    _ = file.readPositionalAll(io, file_bytes, 0) catch return ParseError.ParseFailed;

    if (!std.unicode.utf8ValidateSlice(file_bytes)) {
        std.debug.print("UTF-8 validation failed for file: {s}\n", .{filename});
        return ParseError.ParseFailed;
    }
}

/// Parses a source string.
pub fn parseString(source: [*:0]const u8) ParseError!ParseResult {
    if (options.is_strict) {
        const source_slice = std.mem.span(source);
        if (!std.unicode.utf8ValidateSlice(source_slice)) {
            std.debug.print("UTF-8 validation failed for source string\n", .{});
            core.s().SYNERR = 1;
            return ParseError.ParseFailed;
        }
    }
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    _ = try parseWithNew(arena.allocator(), source);
    return .success;
}

/// Result of parsing with the new Zig pipeline.
pub const NewParseResult = struct {
    /// No-op cleanup — the result owns no heap memory of its own.
    pub fn deinit(_: *NewParseResult) void {}
};

/// Parse a Miranda source string through the native `syntax/` pipeline
/// (`Source` → `lexer` → `applyLayout` → `parser.zig`/`codegen.zig`) — the
/// same front end `parseCurrentNative` uses for file/REPL input, just fed a
/// string directly instead of a stream. Uses an arena so all intermediate
/// allocations are freed on return. On parse errors, diagnostics are
/// printed to stderr and SYNERR is set.
pub fn parseWithNew(gpa: std.mem.Allocator, source: [*:0]const u8) ParseError!NewParseResult {
    const source_slice = std.mem.span(source);
    if (options.is_strict) {
        if (!std.unicode.utf8ValidateSlice(source_slice)) {
            std.debug.print("UTF-8 validation failed for source string\n", .{});
            core.s().SYNERR = 1;
            return ParseError.ParseFailed;
        }
    }
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    var src = source_mod.Source.fromBytes(alloc, source_slice) catch return ParseError.ParseFailed;
    const tok_result = lexer_mod.tokenizeWithDirectives(alloc, &src) catch return ParseError.ParseFailed;
    const laid_out = layout_mod.applyLayout(alloc, tok_result.tokens) catch return ParseError.ParseFailed;

    var p = parser_mod.Parser.initWithDirectives(alloc, laid_out, tok_result.directives);
    const script = parser_mod.parseScript(&p) catch return ParseError.ParseFailed;
    if (options.is_strict or @import("builtin").mode == .Debug) {
        heap.heap().validate();
        p.validate();
        rt.rs().validate();
    }

    // Report accumulated diagnostics before the arena is freed.
    if (!@import("builtin").is_test) {
        if (tok_result.diagnostics.len > 0) {
            reportLexerDiagnostic(tok_result.diagnostics[0]);
        }
        for (p.diagnostics.items) |d| {
            std.debug.print("{d}:{d}: {s}\n", .{ d.span.line, d.span.col, d.message });
        }
    }
    if (tok_result.diagnostics.len > 0) {
        core.s().SYNERR = 1;
        core.s().errline = @intCast(tok_result.diagnostics[0].span.line);
        core.s().errcol = @intCast(tok_result.diagnostics[0].span.col);
        recordDiagnosticMessage(tok_result.diagnostics[0].message);
        return ParseError.ParseFailed;
    }
    if (p.diagnostics.items.len > 0) {
        core.s().SYNERR = 1;
        core.s().errline = @intCast(p.diagnostics.items[0].span.line);
        core.s().errcol = @intCast(p.diagnostics.items[0].span.col);
        recordDiagnosticMessage(p.diagnostics.items[0].message);
        return ParseError.ParseFailed;
    }

    var including_stack: modules.IncludingStack = .{};
    defer including_stack.deinit(alloc);
    modules.processIncludes(alloc, script, ".", &including_stack) catch |err| {
        reportIncludeError(err);
        return ParseError.ParseFailed;
    };

    codegen.codegenScript(alloc, script);
    if (options.is_strict or @import("builtin").mode == .Debug) {
        heap.heap().validate();
        p.validate();
        rt.rs().validate();
    }

    return NewParseResult{};
}
