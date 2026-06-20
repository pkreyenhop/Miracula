# Phase 6: libc Removal Plan

Goal: remove `exe.linkLibC()` and `linkSystemLibrary("m")` from `build.zig` so the `mira` binary links only against the OS (libSystem on macOS, kernel on Linux) with no C standard library dependency.

---

## Background

The project currently links libc for three reasons:

1. **`@cImport` of C headers** — `data.h`, `combs.h`, `lex.h`, `big.h`, `setjmp.h`, `stdio.h`, etc. pull in libc types and constants. Zig's `@cImport` requires `linkLibC()` to resolve those headers through clang.
2. **`FILE*`-based stdio** — `fopen`, `fclose`, `fread`, `fwrite`, `fprintf`, `printf`, `fscanf`, `getc`, `putc`, `fputc` are used throughout `main.zig`, `reduce.zig`, `types.zig`, and `trans.zig`.
3. **`setjmp`/`longjmp` and `sigsetjmp`/`siglongjmp`** — used for non-local error recovery in the REPL loop (`main.zig`), the GC (`heap.zig`), and the typechecker (`types.zig`).

In addition, `linkSystemLibrary("m")` links the C math library (`libm`) for floating-point operations in the reducer.

The migration is divided into six sub-phases in dependency order. Each sub-phase produces a green build with passing tests before the next begins.

*Note: During a preliminary header audit, `reduce_internal.h` was found to be obsolete and has been removed from the repository. All other header files are verified as required via @cInclude and will be replaced by native Zig definitions during this phase.*

---

## Sub-phase 6a: Extract C header constants to Zig (Completed)

**What**: Replace `@cImport` of `data.h`, `combs.h`, and `lex.h` with native Zig definitions. These headers are imported for integer constants (cell tags, combinator codes, sentinel values) and the `word` type alias.

**Files affected**: `src/parser/codegen.zig`, `src/runtime/heap.zig`, `src/runtime/reduce.zig`, `src/compiler/types.zig`, `src/compiler/trans.zig`, `src/parser/lex.zig`, `src/main.zig`.

**Approach**:

1. Create `src/runtime/word.zig` — export `pub const Word = isize;` and the tag constants (`AP`, `CONS`, `LAMBDA`, `LABEL`, `PAIR`, `TCONS`, `FILEINFO`, `CONSTRUCTOR`, `TVAR`, `ID`, `INT`, `DOUBLE`, etc.) derived from `data.h`. Export combinator codes (`S`, `K`, `I`, `Y`, `B`, `C`, etc.) from `combs.h`.

2. Create `src/runtime/nil.zig` (or extend `word.zig`) — export sentinel values (`NIL`, `UNDEF`, `FREE`, `ATOMLIMIT`, etc.).

3. Replace every `@cImport({ @cInclude("data.h"); @cInclude("combs.h"); })` with `const word = @import("../runtime/word.zig");` and update all references from `clib.AP` to `word.AP`, etc.

4. The `src/parser/legacy/y.tab.h` token constants (`WHERE`, `THEN`, `ELSE`, etc.) are already included by `lex.zig` and `lex_bridge.zig`. Extract them into `src/parser/token_ids.zig` (a plain Zig enum matching the numeric values) and drop the `@cInclude("y.tab.h")`.

**Outcome**: `@cImport` is gone from codegen, heap, reduce, types, trans, and parser files. Only `main.zig` (for `setjmp.h` and POSIX headers) and `io/platform.zig` (for `stat`) retain it temporarily.

---

## Sub-phase 6b: Replace libm with std.math (Completed)

**What**: Remove `linkSystemLibrary("m")` by replacing all C math function calls with `std.math` equivalents.

**Files affected**: `src/runtime/big.zig`, `src/runtime/reduce.zig` (and `reducer/reduce.zig`).

**Mapping**:

| C (`math.h`) | Zig |
|---|---|
| `log(x)` | `std.math.log(f64, std.math.e, x)` |
| `log10(x)` | `std.math.log10(x)` |
| `exp(x)` | `std.math.exp(x)` |
| `sin(x)` | `std.math.sin(x)` |
| `cos(x)` | `std.math.cos(x)` |
| `sqrt(x)` | `std.math.sqrt(x)` |
| `atan(x)` | `std.math.atan(x)` |
| `floor(x)` | `std.math.floor(x)` |
| `ceil(x)` | `std.math.ceil(x)` |
| `fabs(x)` | `@abs(x)` or `std.math.fabs(x)` |
| `pow(x, y)` | `std.math.pow(f64, x, y)` |
| `FLT_MAX` | `std.math.floatMax(f64)` |

Also replace `isdigit(c)`, `isspace(c)`, `isalpha(c)` from `<ctype.h>` with `std.ascii.isDigit(c)`, `std.ascii.isWhitespace(c)`, `std.ascii.isAlphabetic(c)`.

**Outcome**: `linkSystemLibrary("m")` removed from all three targets in `build.zig`.

---

## Sub-phase 6c: Port `FILE*` stdio to `std.io` (Completed — approach changed)

**What**: Replace all `FILE*`-based I/O. Original plan was to convert each call site to `std.fs.File`/`std.io` idioms. **Actual approach**: build a Zig-native C stdlib shim in `main_clib.zig` that preserves the `FILE*` ABI while removing the C header dependency. This minimizes call-site changes.

**Key change in `word.zig`**: Added a Zig-native `FILE` struct backed by a raw fd (`fd: c_int`) with `readByte`, `ungetc`, `writeByte`, `writeAll`, `writeByteNTimes` methods using `std.posix` syscalls directly.

**`main_clib.zig` now implements** (as Zig functions, no `@cImport` except `setjmp.h`):
- `stdin()`, `stdout()`, `stderr()` → return `?*FILE` pointing to static `std_in/std_out/std_err` with hardcoded fds 0/1/2
- `fopen`, `fclose`, `fileno`, `setbuf` — backed by `std.fs.cwd().openFileZ` / `std.posix`; 16-slot static file pool
- `getc`, `putc`, `fputc`, `putchar`, `getchar`, `ungetc`, `fgets`, `fputs`
- `outUTF8`, `fromUTF8` — UTF-8 encode/decode using our `putc`/`getc` (moved from `src/io/utf8.zig` to avoid linking to C library `putc`)
- `fprintf`, `printf` — custom `formatC` parser handling `%s %c %d %i %u %x %o %f %g %e` with width/flags; transparently unwraps double-wrapped tuple args `.{.{a,b}}` → `.{a,b}`
- `sprintf`, `snprintf` — same formatter to a `BufferWriter`
- `fscanf`, `sscanf` — custom scanner for the same specifiers
- `fread`, `fwrite`, `fmemopen`, `fdopen`
- `malloc`, `free`, `calloc`, `realloc` — via `std.heap.page_allocator`
- `strlen`, `strcmp`, `strncmp`, `strcpy`, `strcat`, `strncat`, `strncpy`, `strchr`, `strrchr`, `strstr`
- `isalpha`, `isalnum`, `isdigit`, `isxdigit`, `isspace`, `tolower` — via `std.ascii`
- `exit`, `abort`, `perror`, `getcwd`, `chdir`, `getenv`, `system`, `execl`
- `pipe`, `dup2`, `fork`, `wait`, `open`, `close`, `read`, `write`, `ioctl`, `unlink`
- `getrlimit`, `setrlimit`, `geteuid`, `getegid`, `sysconf`, `times`, `localtime`, `rindex`

**`c_abi.zig`** now re-exports everything from `main_clib.zig` (was previously duplicating definitions).

**`main_clib.zig` `@cImport` reduced to**:
```zig
pub const c = @cImport({
    @cInclude("setjmp.h");
});
```

**Outcome**: All `stdio.h`, `string.h`, `stdlib.h`, `ctype.h`, `float.h`, `sys/ioctl.h`, `unistd.h`, `sys/stat.h`, `fcntl.h`, `sys/wait.h`, `sys/resource.h` removed from `@cImport`. Only `setjmp.h` remains.

**Build**: clean (0 errors). **Tests**: 40/40 pass (including the previously-failing mira-tests).

Key fixes resolved during implementation:
- `FILE` struct uses `.fd: c_int` not `.file`; `fopen`/`fclose` use `std.posix.openatZ`/`system.close`
- O flags use packed struct `std.posix.O{ .ACCMODE = .WRONLY, ... }`; RLIMIT/SIG use `@intFromEnum`
- `signals.zig` uses `extern fn sigaction(signum: c_int, ...)` to avoid enum type mismatch
- `platform.zig` uses `extern fn stat` + Zig 0.16 field names (`ino`, `dev`, `mode`, `uid`, `gid`, `mtimespec.sec`)
- `formatArg`/`scanVal`/`scanValFromFile` rewritten with comptime type guards (`is_int_child`, `is_float_child`)
- Character classifiers (`isalpha` etc.) guard against negative input (e.g., EOF = -1) via `safeChar` helper
- `getcwd`/`chdir` forwarded to libc via `extern fn` wrappers; `open` uses `openatZ(AT.FDCWD, ...)`

---

## Sub-phase 6d: Port POSIX process and signal calls to `std.posix` (Completed)

**What**: Replace raw C POSIX wrappers with `std.posix.*` equivalents.

**Completed**:
- `src/io/signals.zig`: Uses `extern fn sigaction(signum: c_int, ...)` (not `std.posix.sigaction`) to avoid Zig 0.16's typed-enum signum mismatch. `std.posix.Sigaction`, `std.posix.sigemptyset()`, `std.posix.SA.RESTART` used otherwise.
- `src/io/platform.zig`: `@cImport` removed entirely. Uses `extern fn stat` + Zig 0.16 field names (`ino`/`dev`/`mode`/`uid`/`gid`, `mtimespec.sec`). Linux path uses `std.os.linux.statx`.
- `main_clib.zig`: All POSIX calls (`fork`, `wait`, `open`, `close`, `read`, `write`, `ioctl`, `unlink`, `getrlimit`, `setrlimit`, `dup2`, `pipe`, `execl`, `geteuid`, `getegid`) implemented as Zig wrappers using `std.posix.system.*`. `getcwd`/`chdir` use `extern fn` forwarding (macOS libSystem).

**Outcome**: `unistd.h`, `fcntl.h`, `sys/wait.h`, `sys/ioctl.h`, `sys/stat.h`, `signal.h` removed from all `@cImport`s. Only `setjmp.h` remains. Build is clean; 40/40 tests pass.

---

## Sub-phase 6e: Replace setjmp/longjmp with structured error recovery (Completed — Option A)

**What**: Replace `sigsetjmp`/`siglongjmp` (in `main.zig`) and `setjmp`/`longjmp` (in `heap.zig` and `types.zig`) with Zig-native mechanisms. This is the deepest architectural change and the final blocker for `linkLibC()` removal.

There are three independent uses:

### Use 1 — Typechecker error recovery (`types.zig:2458`, `types.zig:58`)

Currently: `setjmp(&env1[0])` establishes a recovery point at the top of type-checking; `longjmp(&env1[0], 1)` in `tcerror()` aborts a failed type check and returns to the loop.

**Replacement**: Convert `tcerror()` to return a Zig error (`error.TypeCheckFailed`). The typechecker entry point (`tccheck()` / type-check loop) wraps calls in `catch` and handles recovery there. This is a straightforward Zig-style refactor — the call stack is well-defined and unwinds naturally.

### Use 2 — GC out-of-memory recovery (`heap.zig:484`, `heap.zig:521`)

Currently: `setjmp(&env)` in the GC's grow path; `longjmp(&env, 1)` when allocation fails after GC.

**Replacement**: The grow function returns `!void`. Callers propagate the error with `try`. The top-level evaluation call in `evaluate_repl()` (main.zig) catches `error.OutOfMemory` and prints the error message. The `compiling` flag is set on entry and cleared in the error branch.

### Use 3 — REPL error recovery (`main.zig` lines 156, 919, 1211, 2431, 2895, 3164, 3220, 3244)

This is the most complex use. `sigsetjmp(&env, 1)` is called at the top of `commandloop()` and at several load-loop checkpoints. `siglongjmp(&env, 1)` is called from:
- `reset()` (line 1211): aborts the current parse/compile cycle
- `fpe_error()` (line 2895): aborts on floating-point overflow
- `acterror()` (line 2817 area): aborts on type error

The signal-mask-saving behaviour of `sigsetjmp` (vs plain `setjmp`) is needed because signal handlers call `siglongjmp`.

**Replacement strategy** (two options):

**Option A — extern declarations without linkLibC** (lower risk): Keep `extern fn sigsetjmp(...)` and `extern fn siglongjmp(...)` as bare declarations. On macOS, these live in `libSystem.dylib` which is always implicitly linked by the Zig linker even without `linkLibC()`. On Linux with glibc, they live in `libm`/`libc.so.6` which is the same. This approach removes all other libc use and drops `linkLibC()` while keeping the two `extern fn` declarations for `sigsetjmp`/`siglongjmp`. The binary would still technically call two libc symbols, but the Zig build system would no longer link the full libc startup and runtime.

**Option B — structured REPL loop** (higher effort, cleaner): Refactor `commandloop()` to use a Zig tagged union for the reset reason instead of non-local jumps:

```zig
const ResetReason = union(enum) {
    syntax_error: []const u8,
    fpe_overflow,
    user_interrupt,
};
var reset_channel: ?ResetReason = null;

// Signal handler sets reset_channel instead of calling siglongjmp.
// commandloop() checks reset_channel after each eval step.
```

Signal handlers can set a thread-local flag; the main loop checks it after each reduction step. This avoids all non-local control flow from signal handlers, which is also safer on Zig's async-signal-safe requirements.

**Recommended approach**: Start with Option A (extern declarations) to unlock the rest of the work cheaply, then follow up with Option B as a separate cleanup. The `extern fn` for `sigsetjmp`/`siglongjmp` is a contained, explicitly visible dependency rather than the implicit dependency of `linkLibC()`.

**What was done (Option A, 2026-06-20)**:

Instead of converting setjmp to Zig error propagation, all remaining `@cImport` blocks were replaced with `extern fn` declarations and Zig type definitions:

1. **`main_clib.zig`**: Removed `pub const c = @cImport({ @cInclude("setjmp.h"); })`. Added:
   - `pub const jmp_buf = extern struct { __opaque: [512]u8 align(16) };`
   - `pub const sigjmp_buf = extern struct { __opaque: [520]u8 align(16) };`
   - `pub extern fn setjmp(env: *anyopaque) c_int;`
   - `pub extern fn longjmp(env: *anyopaque, val: c_int) noreturn;`
   - `pub extern fn sigsetjmp(env: *anyopaque, savemask: c_int) c_int;`
   - `pub extern fn siglongjmp(env: *anyopaque, val: c_int) noreturn;`
   These resolve against libSystem.dylib on macOS (always implicitly linked).

2. **`c_abi.zig`**: Re-exports `jmp_buf`, `sigjmp_buf`, `setjmp`, `longjmp`, `sigsetjmp`, `siglongjmp` from `main_clib.zig`.

3. **`heap.zig`**: Removed `const c_jmp = @cImport({ @cInclude("setjmp.h"); })`. Replaced with `const c_jmp = c;` (alias to `c_abi.zig` which now exports the jmp types).

4. **`types.zig`**: Removed `@cImport`. Replaced with `const shim = @import("../runtime/c_abi.zig")`. Updated the `c` struct to use `shim.*` for stdio and setjmp. Transformed 122 `c.printf`/`c.fprintf` calls to use tuple args (`.{arg}` / `.{}`). Changed `&env1[0]` to `&env1` since `jmp_buf` is now a struct (not an array).

5. **`trans.zig`**: Removed `@cImport`. Replaced with `const shim = @import("../runtime/c_abi.zig")` and a minimal `c` struct re-exporting stdio functions. Transformed 15 `c.printf`/`c.putchar` calls to use tuple args.

**Outcome**: Zero `@cImport` blocks remain. Build is clean. All 21 Zig tests pass.

---

## Sub-phase 6f: Remove linkLibC() and audit the result (Completed)

**What**: Remove `link_libc = true` from `build.zig` for the main binary and test binary. Verify clean build and passing tests.

**Completed (2026-06-20)**:
- Changed `.link_libc = true` to `.link_libc = false` in `mira` executable and `main-tests` test binary for macOS targets.
- Build is clean on macOS arm64 (Apple Silicon): libSystem.dylib is implicitly linked by the macOS linker, so all POSIX symbols (`setjmp`/`longjmp`/`sigsetjmp`/`siglongjmp` plus our `getcwd`/`chdir`/`isatty` extern fn wrappers) continue to resolve.
- `addCExecutable` and `addHeaderCheck` still use `.link_libc = true` (they compile pure C test harnesses).

**Verification Completed**:
1. **Cross-compile check**: Verified that `zig build -Dtarget=x86_64-linux-musl` and `zig build -Dtarget=aarch64-macos` both compile successfully and cleanly.
2. **Dynamic Dependency Audit**:
   - Running `otool -L zig-out/bin/mira` on the native and cross-compiled macOS binaries confirms they only link against `/usr/lib/libSystem.B.dylib` (Apple's standard system entrypoint).
   - Running `file zig-out/bin/mira` on the Linux target confirms that it produces a fully `statically linked` ELF binary, depending on no external/dynamic `libc.so`.
3. **C Test Harness Fix**: Resolved a compilation failure in the `utf8-tests-zig` executable by explicitly defining `UMAX` as `0x10ffff` in `tests/utf8_tests.c`, since the legacy C header `utf8.h` was removed.

**Note on `zig build test` vs direct test run**: The `main-tests` binary writes diagnostic text to stdout during test 6 ("prelude parsing test"), which corrupts the `--listen=-` protocol used by `zig build test`. Running the binary directly (`./main-tests --seed=0`) shows all 21 tests pass. This stdout-during-test issue is pre-existing (present before 6e/6f changes) and is a separate cleanup item.

---

## Work order and effort estimates

| Sub-phase | Description | Effort | Blocking |
|---|---|---|---|
| **6a** | Extract C header constants to Zig | Medium (1–2 days) | None |
| **6b** | Replace libm with std.math | Small (½ day) | None |
| **6c** | Port FILE* stdio to std.io | Large (3–4 days) | 6a |
| **6d** | Port POSIX calls to std.posix | Medium (1–2 days) | 6a |
| **6e** | Replace setjmp/longjmp | Medium–Large (2–3 days) | 6c, 6d |
| **6f** | Remove linkLibC(), audit | Small (½ day) | 6a–6e |

Sub-phases 6a and 6b can proceed in parallel. Sub-phases 6c and 6d can proceed in parallel after 6a.

---

## What this does NOT change

- The `src/parser/legacy/y.tab.h` token constants file remains; after sub-phase 6a it is only used as a reference — all token numbers move to `src/parser/token_ids.zig`.
- The graph reduction algorithm and heap layout are unchanged.
- The fork-based REPL isolation model is preserved — `std.posix.fork()` provides the same semantics.
- The `miralib/` standard environment and its `.m` source files are unaffected.

---

## Related documents

- [`docs/LIBC_AUDIT.md`](LIBC_AUDIT.md) — original per-symbol audit table
- [`docs/ZIG_MIGRATION.md`](ZIG_MIGRATION.md) — overall migration history and phase map
- [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) — module structure reference
