# Libc Dependency Audit

This document audits the remaining libc dependencies in the Miracula project, specifically focusing on the `runtime`, `compiler`, and `io` subsystems.

## Audit Table

| File | Symbol | Purpose | Replacement Strategy |
| ---- | ------ | ------- | -------------------- |
| `src/io/utf8.zig` | `printf` | Writing formatted UTF-8 data to stdout. | Replace with `std.io.getStdOut().writer()` or pass a writer interface. |
| `src/io/utf8.zig` | `putchar` | Writing single characters to stdout. | Replace with `std.io.getStdOut().writer().writeByte()`. |
| `src/io/signals.zig` | `signal` / `sigaction` | Setting up signal handlers for division-by-zero, interrupt signals, etc. | Port to use `std.posix.sigaction` directly, avoiding `@cImport`. |
| `src/runtime/big.zig` | `errno` | Standard C errno for tracking math errors. | Replace with Zig errors or native Thread Local Storage (TLS) errno from `std.posix`. |
| `src/runtime/big.zig` | `isdigit` / `isspace` | C character classification functions. | Replace with native Zig functions in `std.ascii`. |
| `src/runtime/big.zig` | `log` / `exp` / `sin` / `cos` / `sqrt` / `atan` / `log10` | Floating-point math functions. | Replace with native Zig math functions from `std.math`. |
| `src/runtime/heap.zig` | `fprintf` | Printing error and panic messages to stderr. | Replace with `std.io.getStdErr().writer().print()`. |
| `src/runtime/heap.zig` | `exit` | Terminating process execution on fatal memory panics. | Replace with `std.process.exit()`. |
| `src/runtime/heap.zig` | `longjmp` | Jumping back to typechecker/compiler loop on fatal errors. | Replace with native Zig error return propagation (`!void`) or isolate it. |
| `src/runtime/reduce.zig` | `times` / `clock` | Retrieval of CPU time execution metrics. | Replace with `std.time.nanoTimestamp()` or standard Zig CPU timing facilities. |
| `src/compiler/types.zig` | `printf` / `fprintf` / `putchar` | Writing typechecking output and diagnostics. | Replace with Zig `std.io` writer interfaces. |
| `src/compiler/types.zig` | `setjmp` / `longjmp` | Error recovery flow control to jump back to parsing loop. | Replace with native Zig `try/catch` and error union returns. |
| `src/compiler/trans.zig` | `printf` / `putchar` / `exit` | Printing intermediate representations and exiting on compilation errors. | Replace with `std.io` writers and `std.process.exit()`. |
| `src/main.zig` | `siglongjmp` / `sigsetjmp` | Jumping out of interrupts/signals back to REPL main loop. | Relocate/encapsulate to the main program loop wrapper, keeping runtime files clean. |
| `src/main.zig` | `strcmp` / `strcpy` / `strlen` / `strcat` | String operations for CLI arguments and file paths. | Replace with standard Zig slice comparisons, formatting (`std.fmt.allocPrint`), etc. |
| `src/main.zig` | `isatty` | Checking if stdin/stdout is a terminal. | Replace with `std.posix.isatty` or query file descriptors via `std.posix`. |

