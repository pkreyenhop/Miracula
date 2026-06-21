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
    /// type checker.  TYPERRS has been incremented and the error printed
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
