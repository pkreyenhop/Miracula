//! errors.zig — the interpreter's domain-error set (`MiraError`, the Zig
//! error-union replacement for the C `setjmp`/`longjmp` exits) and `fatal()`,
//! the print-then-exit helper for unrecoverable command-line/startup/load errors.

const std = @import("std");
const abi = @import("../os.zig");
const word = @import("../graph/word.zig");

/// Miranda interpreter domain errors.
///
/// Used wherever Zig error unions replace C setjmp/longjmp non-local exits.
/// SIGINT and float-overflow recovery (docs/ZIG_NATIVE_PLAN.md Phase 3) no
/// longer uses signal-context `siglongjmp`/`sigjmp_buf` at all: the SIGINT
/// handler only sets a polled atomic flag (`runtime_state.zig`'s
/// `interrupt_flag`), and float overflow is an explicit finite-check, not a
/// real signal — both unwind via `word.ReduceError` (`Interrupted`/
/// `FloatOverflow`), the reduction engine's own narrow error set, rather
/// than through this broader `MiraError`. `EvaluationInterrupted` below
/// remains an unused placeholder for the compiler's own error-union work
/// (Phase 3 step 5, not yet done).
///
/// Tests: MiraError variants are all distinct, MiraError is a subset of anyerror
pub const MiraError = error{
    /// A syntactic error was detected by the parser.
    /// The error message has already been printed; the caller should
    /// clean up state and return to the REPL prompt.
    SyntaxError,

    /// A fatal cycle in type synonym "==" definitions was detected by the
    /// type checker.  `cs.TYPERRS` has been incremented and the error printed
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
    /// runtime error (e.g. floating-point overflow). Unused placeholder:
    /// the reduction engine actually signals these via `word.ReduceError`
    /// (`Interrupted`/`FloatOverflow`), not this broader `MiraError` set —
    /// reserved for the compiler's own error-union work (Phase 3 step 5).
    EvaluationInterrupted,
};

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

/// Print a diagnostic to stderr and terminate the process with status 1.
///
/// Use for unrecoverable command-line, startup, and source-load errors — the
/// cases that previously open-coded an `fprintf(stderr, …)` immediately
/// followed by `exit(1)`. This centralises the "print then die" idiom so the
/// diagnostic and the exit status can never drift apart.
///
/// Not for the evaluator's heap-exhaustion / impossible-state aborts, which
/// dump interpreter statistics via `outstats()` before exiting — those remain
/// their own category. `fmt`/`args` are Zig format strings (Phase 2 step 3,
/// docs/ZIG_NATIVE_PLAN.md — converted from the old C-format/`word.fprintf`
/// convention along with all 16 call sites; `fmt` is now `comptime`, matching
/// `word.print`/`word.printErr`).
///
/// Not unit-tested: it is `noreturn` (calls `exit(1)`), so exercising it would
/// terminate the test runner; covered by the integration suite's error paths.
pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    word.printErr(fmt, args);
    const options = @import("version_options");
    if (options.is_strict) {
        std.debug.panic("fatal error in strict mode", .{});
    } else {
        abi.exit(1);
    }
}
