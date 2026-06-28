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
const Editor = @import("zigline").Editor;

var editor: Editor = undefined;
var gpa: std.mem.Allocator = undefined;
var next_prompt: []const u8 = "";
var hist_path_buf: [1024]u8 = undefined;
var hist_path: ?[]const u8 = null;

/// Whether the line editor is installed (stdin was interactive at startup).
pub var active: bool = false;

/// Initialise the editor and install the stdin hook. Call once at REPL startup,
/// only when stdin is a TTY. Loads persistent history from `$HOME/.miranda_history`.
pub fn init(allocator: std.mem.Allocator, io: std.Io) void {
    if (active) return;
    gpa = allocator;
    editor = Editor.init(allocator, io, .{});
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
