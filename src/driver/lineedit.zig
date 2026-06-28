//! lineedit.zig — interactive REPL line editing and history (via zigline).
//!
//! Installs `word.readInteractiveLine` so the stdin read path yields fully edited
//! lines — arrow-key history, cursor movement, the usual emacs-style editing —
//! instead of raw bytes. Every downstream reader (the command-loop dispatch and
//! the lexer, which both pull characters from stdin) gets editing + history for
//! free through that one seam.
//!
//! Only wired up when stdin is a TTY (see `startup.mainEntry`); piped or file
//! input leaves the hook null and keeps the plain `read` path, so non-interactive
//! runs (the golden corpus, the integration suite) are completely unaffected.

const std = @import("std");
const word = @import("../runtime/word.zig");
const main_clib = @import("../runtime/main_clib.zig");
const lex = @import("../parser/lex.zig");
const Editor = @import("zigline").Editor;
const CompletionSuggestion = Editor.CompletionSuggestion;

var editor: Editor = undefined;
var gpa: std.mem.Allocator = undefined;
var next_prompt: []const u8 = "";
var hist_path_buf: [1024]u8 = undefined;
var hist_path: ?[]const u8 = null;

/// Whether the line editor is installed (stdin was interactive at startup).
pub var active: bool = false;

// Tab-completion scratch. The name pointers are into the permanent dictionary
// storage, so the suggestion `text` slices stay valid after the handler returns.
var name_storage: [128][*:0]const u8 = undefined;
var sugg_storage: [128]CompletionSuggestion = undefined;
var prefix_buf: [256]u8 = undefined;

/// zigline calls this handler's `tab_complete` on Tab. It must declare *only*
/// the handler methods it implements (setHandler reflects over its decls).
const CompletionHandler = struct {
    pub fn tab_complete(_: *CompletionHandler) ![]const CompletionSuggestion {
        return completeWord();
    }
};
var completion_handler: CompletionHandler = .{};

/// Whether code point `c` can appear in a Miranda identifier.
fn isIdentChar(c: u32) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
        (c >= '0' and c <= '9') or c == '_' or c == '\'';
}

/// Complete the identifier ending at the cursor against the in-scope dictionary.
fn completeWord() []const CompletionSuggestion {
    const buf = editor.getBuffer(); // code points
    const cursor = editor.cursor;
    var start = cursor;
    while (start > 0 and isIdentChar(buf[start - 1])) start -= 1;
    const prefix_len = cursor - start;
    if (prefix_len == 0 or prefix_len > prefix_buf.len) return &.{};
    // The dictionary holds ASCII identifiers; bail on a non-ASCII prefix.
    var i: usize = 0;
    while (i < prefix_len) : (i += 1) {
        if (buf[start + i] > 127) return &.{};
        prefix_buf[i] = @intCast(buf[start + i]);
    }
    const count = lex.completeIds(prefix_buf[0..prefix_len], &name_storage);
    for (name_storage[0..count], 0..) |name, n| {
        // text is the whole identifier; invariant_offset is the already-typed
        // prefix, so zigline inserts only the remaining suffix.
        sugg_storage[n] = .{ .text = std.mem.span(name), .invariant_offset = prefix_len };
    }
    return sugg_storage[0..count];
}

/// Initialise the editor and install the stdin hook. Call once at REPL startup,
/// only when stdin is a TTY. Loads persistent history from `$HOME/.miranda_history`.
pub fn init(allocator: std.mem.Allocator, io: std.Io) void {
    if (active) return;
    gpa = allocator;
    editor = Editor.init(allocator, io, .{});
    editor.setHandler(&completion_handler); // Tab → identifier completion
    if (main_clib.getenv("HOME")) |home_ptr| {
        const home = std.mem.span(home_ptr);
        if (std.fmt.bufPrint(&hist_path_buf, "{s}/.miranda_history", .{home})) |path| {
            hist_path = path;
            editor.loadHistory(path) catch {}; // absent on first run — fine
        } else |_| {}
    }
    word.readInteractiveLine = &fillLine;
    active = true;
}

/// Save history and tear down the editor (best effort; call before exit).
pub fn deinit() void {
    if (!active) return;
    if (hist_path) |path| editor.saveHistory(path) catch {};
    editor.deinit();
    word.readInteractiveLine = null;
    active = false;
}

/// Set the prompt shown for the next top-level line. Continuation refills (when
/// the lexer pulls more input mid-expression) carry an empty prompt.
pub fn setPrompt(p: []const u8) void {
    next_prompt = p;
}

/// `word.readInteractiveLine` hook: read one edited line and copy it (plus a
/// terminating newline, which the lexer expects) into `dst`. Returns the byte
/// count written, or null at end of input (Ctrl-D / read error).
fn fillLine(dst: []u8) ?usize {
    const line = editor.getLine(next_prompt) catch return null; // error.Eof, etc.
    defer gpa.free(line);
    editor.addToHistory(line) catch {};
    next_prompt = "";
    const n = @min(line.len, dst.len - 1); // cap at buffer size (lines rarely overflow)
    @memcpy(dst[0..n], line[0..n]);
    dst[n] = '\n';
    return n + 1;
}
