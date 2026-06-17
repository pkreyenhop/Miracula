# No Header Changes

After thorough exploration of the repository and its active migration from C to Zig, it has been verified that all `*.h` header files (`big.h`, `combs.h`, `data.h`, `lex.h`, `platform.h`, `reduce_internal.h`, `runtime.h`, `signals.h`, `utf8.h`, `version.h`, `src/parser/legacy/parser_bridge.h`, and `src/parser/legacy/y.tab.h`) are still strictly required.

The new Zig implementation deeply relies on these legacy C headers through `@cInclude` directives (for constants, macros, and structs) while the legacy C parser (`y.tab.c`, `parser_bridge.c`) also continues to import them. Removing any of these headers would break the build.
