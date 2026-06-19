# Header Verification

After thorough exploration of the repository and its active migration from C to Zig, it has been verified that all `*.h` header files except `reduce_internal.h` are still required.

`reduce_internal.h` was found to be completely unused by both the C and Zig source code and has been removed. All other headers (`big.h`, `combs.h`, `data.h`, `lex.h`, `platform.h`, `runtime.h`, `signals.h`, `utf8.h`, and `version.h`) are still strictly required as they are imported by Zig files via `@cInclude` directives for constants, macros, and structures.
