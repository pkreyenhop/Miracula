/// Miranda interpreter domain errors.
///
/// Used wherever Zig error unions replace C setjmp/longjmp non-local exits.
/// Signal-handler recovery (SIGINT, SIGFPE via siglongjmp on rs.env) is NOT
/// represented here — POSIX signal handlers are asynchronous and cannot
/// propagate Zig errors up the call stack; those paths retain sigjmp_buf.
pub const MiraError = error{
    /// A syntactic error was detected by the parser.
    /// The error message has already been printed; the caller should
    /// clean up state and return to the REPL prompt.
    SyntaxError,

    /// A fatal cycle in type synonym "==" definitions was detected by the
    /// type checker.  main.cs.TYPERRS has been incremented and the error printed
    /// before this error is raised.  The caller should abandon the current
    /// compilation unit.
    TypeCheckAbort,

    /// The heap is exhausted and GC cannot free enough space.
    /// The interpreter prints a diagnostic and exits; this variant is
    /// provided for future structured recovery.
    HeapExhausted,

    /// A source file could not be loaded (not found, or compilation failed).
    LoadError,

    /// Evaluation was interrupted by the user (Ctrl-C) or a recoverable
    /// runtime error (e.g. floating-point overflow).
    /// Recovery is via siglongjmp on rs.env; this variant documents the
    /// intent without replacing the signal mechanism.
    EvaluationInterrupted,
};

const std = @import("std");
const clib = @import("main_clib.zig");
const word = @import("word.zig");

/// Print a diagnostic to stderr and terminate the process with status 1.
///
/// Use for unrecoverable command-line, startup, and source-load errors — the
/// cases that previously open-coded an `fprintf(stderr, …)` immediately
/// followed by `exit(1)`. This centralises the "print then die" idiom so the
/// diagnostic and the exit status can never drift apart.
///
/// Not for the evaluator's heap-exhaustion / impossible-state aborts, which
/// dump interpreter statistics via `outstats()` before exiting — those remain
/// their own category. `fmt`/`args` follow the `word.fprintf` printf-style
/// convention (both `.{a}` and `.{.{a}}` arg tuples are accepted).
pub fn fatal(fmt: [*:0]const u8, args: anytype) noreturn {
    _ = word.fprintf(clib.stderr(), fmt, args);
    clib.exit(1);
}

test "MiraError variants are all distinct" {
    const variants = [_]MiraError{
        error.SyntaxError,
        error.TypeCheckAbort,
        error.HeapExhausted,
        error.LoadError,
        error.EvaluationInterrupted,
    };
    for (variants, 0..) |a, i| {
        for (variants, 0..) |b, j| {
            if (i != j) try std.testing.expect(a != b);
        }
    }
}

test "MiraError is a subset of anyerror" {
    const e: anyerror = error.TypeCheckAbort;
    try std.testing.expectEqual(error.TypeCheckAbort, e);
}
