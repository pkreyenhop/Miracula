//! editor.zig (renamed from driver/lineedit.zig, Phase 4 step 1,
//! docs/GoReady.md) — interactive REPL line editing and history
//! (via zigline).
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
const word = @import("../graph/word.zig");
const os = @import("../os.zig");
const lex = @import("../parser/lex.zig");
const heap = @import("../graph/heap.zig");
const Editor = @import("zigline").Editor;
const CompletionSuggestion = Editor.CompletionSuggestion;

/// zigline calls this handler's `tab_complete` on Tab. It must declare *only*
/// the handler methods it implements (setHandler reflects over its decls).
/// `heap` is set once by `init()` (the only place that constructs this
/// handler, already holding the process's one `*Heap`), so `tab_complete`
/// reads it off `self` rather than the ambient singleton.
const CompletionHandler = struct {
    heap: *heap.Heap = undefined,

    /// zigline's reflected Tab handler: returns completions for the word at the cursor.
    pub fn tab_complete(self: *CompletionHandler) ![]const CompletionSuggestion {
        return completeWord(self.heap);
    }
};

/// All line-editor / history / tab-completion state, folded into `Interp`
/// (shared-state plan Phase 6) so it's no longer a standalone module global.
/// Only ever populated when stdin is a TTY (see `active`); a batch/piped run
/// never touches this beyond the `active = false` default.
pub const LineEditState = struct {
    editor: Editor = undefined,
    gpa: std.mem.Allocator = undefined,
    next_prompt: []const u8 = "",
    hist_path_buf: [1024]u8 = undefined,
    hist_path: ?[]const u8 = null,
    /// Whether the line editor is installed (stdin was interactive at startup).
    active: bool = false,
    // Tab-completion scratch. The name pointers are into the permanent
    // dictionary storage, so the suggestion `text` slices stay valid after
    // the handler returns.
    name_storage: [128][*:0]const u8 = undefined,
    sugg_storage: [128]CompletionSuggestion = undefined,
    prefix_buf: [256]u8 = undefined,
    completion_handler: CompletionHandler = .{},
};

/// Pointer to the singleton `LineEditState` inside `current_interp`.
pub inline fn state() *LineEditState {
    return &@import("interp.zig").current_interp.lineedit;
}

/// Whether the line editor is installed (stdin was interactive at startup).
pub inline fn active() bool {
    return state().active;
}

/// Whether code point `c` can appear in a Miranda identifier.
fn isIdentChar(c: u32) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
        (c >= '0' and c <= '9') or c == '_' or c == '\'';
}

/// Complete the identifier ending at the cursor against the in-scope dictionary.
fn completeWord(heap_ptr: *heap.Heap) []const CompletionSuggestion {
    const st = state();
    const buf = st.editor.getBuffer(); // code points
    const cursor = st.editor.cursor;
    var start = cursor;
    while (start > 0 and isIdentChar(buf[start - 1])) start -= 1;
    const prefix_len = cursor - start;
    if (prefix_len == 0 or prefix_len > st.prefix_buf.len) return &.{};
    // The dictionary holds ASCII identifiers; bail on a non-ASCII prefix.
    var i: usize = 0;
    while (i < prefix_len) : (i += 1) {
        if (buf[start + i] > 127) return &.{};
        st.prefix_buf[i] = @intCast(buf[start + i]);
    }
    const count = lex.completeIds(heap_ptr, st.prefix_buf[0..prefix_len], &st.name_storage);
    for (st.name_storage[0..count], 0..) |name, n| {
        // text is the whole identifier; invariant_offset is the already-typed
        // prefix, so zigline inserts only the remaining suffix.
        st.sugg_storage[n] = .{ .text = std.mem.span(name), .invariant_offset = prefix_len };
    }
    return st.sugg_storage[0..count];
}

/// Initialise the editor and install the stdin hook. Call once at REPL startup,
/// only when stdin is a TTY. Loads persistent history from `$HOME/.miranda_history`.
pub fn init(heap_ptr: *heap.Heap, allocator: std.mem.Allocator, io: std.Io) void {
    const st = state();
    if (st.active) return;
    st.gpa = allocator;
    st.editor = Editor.init(allocator, io, .{});
    st.completion_handler.heap = heap_ptr;
    st.editor.setHandler(&st.completion_handler); // Tab → identifier completion
    if (os.getenv("HOME")) |home_ptr| {
        const home = std.mem.span(home_ptr);
        if (std.fmt.bufPrint(&st.hist_path_buf, "{s}/.miranda_history", .{home})) |path| {
            st.hist_path = path;
            st.editor.loadHistory(path) catch {}; // absent on first run — fine
        } else |_| {}
    }
    word.fio().std_in.readInteractiveLine = &fillLine;
    st.active = true;
}

/// Save history and tear down the editor (best effort; call before exit).
pub fn deinit() void {
    const st = state();
    if (!st.active) return;
    if (st.hist_path) |path| st.editor.saveHistory(path) catch {};
    st.editor.deinit();
    word.fio().std_in.readInteractiveLine = null;
    st.active = false;
}

/// Set the prompt shown for the next top-level line. Continuation refills (when
/// the lexer pulls more input mid-expression) carry an empty prompt.
pub fn setPrompt(p: []const u8) void {
    state().next_prompt = p;
}

/// `Stream.readInteractiveLine` hook (installed on `std_in` only): read one
/// edited line and copy it (plus a terminating newline, which the lexer
/// expects) into `dst`. Returns the byte count written, or null at end of
/// input (Ctrl-D / read error).
fn fillLine(dst: []u8) ?usize {
    const st = state();
    const line = st.editor.getLine(st.next_prompt) catch return null; // error.Eof, etc.
    defer st.gpa.free(line);
    st.editor.addToHistory(line) catch {};
    st.next_prompt = "";
    const n = @min(line.len, dst.len - 1); // cap at buffer size (lines rarely overflow)
    @memcpy(dst[0..n], line[0..n]);
    dst[n] = '\n';
    return n + 1;
}
