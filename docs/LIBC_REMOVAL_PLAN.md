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

## Sub-phase 6c: Port `FILE*` stdio to `std.io`

**What**: Replace all `FILE*`-based I/O with Zig file handles and writer/reader interfaces. This is the largest refactor.

**Core types to change**:

- `export var s_in: ?*clib.FILE` → `export var s_in: std.fs.File`
- `extern var s_out: ?*clib.FILE` → `export var s_out: std.fs.File`

Both are currently init'd to `stdin`/`stdout`. In Zig: `std.io.getStdIn()` / `std.io.getStdOut()`.

**Function-by-function replacements**:

| Old | New |
|---|---|
| `clib.fopen(path, "r")` | `std.fs.cwd().openFile(path, .{})` |
| `clib.fopen(path, "w")` | `std.fs.cwd().createFile(path, .{})` |
| `clib.fclose(f)` | `f.close()` |
| `clib.fprintf(f, fmt, ...)` | `f.writer().print(fmt, ...)` (Zig fmt syntax) |
| `clib.printf(fmt, ...)` | `std.io.getStdOut().writer().print(fmt, ...)` |
| `clib.fscanf(f, fmt, ...)` | Manual: `f.reader().readUntilDelimiter(...)` + parse |
| `clib.getc(f)` | `f.reader().readByte()` |
| `clib.putc(ch, f)` | `f.writer().writeByte(ch)` |
| `clib.fputc(ch, f)` | `f.writer().writeByte(ch)` |
| `clib.putchar(ch)` | `std.io.getStdOut().writer().writeByte(ch)` |
| `clib.snprintf(&buf, len, fmt, ...)` | `std.fmt.bufPrint(&buf, fmt, ...)` |
| `clib.sprintf(&buf, fmt, ...)` | `std.fmt.bufPrint(&buf, fmt, ...)` |

**Functions that take `FILE*` parameters — port signatures**:

- `getln(in: ?*clib.FILE, n: Word, s_ptr: [*]u8) c_int` (main.zig:715)  
  → `getln(in: std.fs.File, n: Word, s_ptr: [*]u8) c_int`  
  — body: replace `clib.getc(in)` with `in.reader().readByte() catch -1`

- `parseline(t_val: Word, f: std.fs.File, fil: Word) Word` (main.zig:1092)  
  — pass `std.io.getStdIn()` at call sites

- `fromUTF8(f: std.fs.File) Word` (extern fn in reduce.zig:46, impl in utf8.zig)  
  — `utf8.zig`: replace `extern fn getc(FILE)` with `f.reader().readByte()`

- `out(f: std.fs.File, x: Word)` (types.zig:60, trans.zig:155)  
  — propagate `std.fs.File` through the call chain

**`fscanf` in `rc_read()`** (main.zig:823): Replace with buffered line read + manual integer parsing using `std.fmt.parseInt`.

**`getStdin/getStdout/getStderr` helpers** (main.zig:359–398): Delete entirely; use `std.io.getStdIn()` etc. directly.

**Outcome**: All `stdio.h` imports removed. `@cImport` for `stdio.h` and `FILE` types gone from all files.

---

## Sub-phase 6d: Port POSIX process and signal calls to `std.posix`

**What**: Replace raw C POSIX wrappers (`clib.fork`, `clib.wait`, `clib.open`, `clib.close`, `clib.read`, `clib.write`, `clib.ioctl`) with `std.posix.*` equivalents that work without `linkLibC()`.

**Mapping**:

| Old (`@cImport` + clib) | New |
|---|---|
| `clib.fork()` | `std.posix.fork()` |
| `clib.wait(&status)` | `std.posix.wait()` / `std.posix.waitpid(pid, 0)` |
| `clib.open(path, flags)` | `std.posix.open(path, flags, 0)` |
| `clib.close(fd)` | `std.posix.close(fd)` |
| `clib.read(fd, buf, n)` | `std.posix.read(fd, buf)` |
| `clib.write(fd, buf, n)` | `std.posix.write(fd, buf)` |
| `clib.ioctl(fd, TIOCGWINSZ, &win)` | `std.posix.ioctl(fd, std.os.linux.T.IOCGWINSZ, &win)` |
| `clib.unlink(path)` | `std.posix.unlink(path)` |
| `clib.exit(n)` | `std.process.exit(n)` |
| `clib.perror(msg)` | `std.debug.print("{s}: {s}\n", .{msg, @errorName(err)})` |

**Signals** (`src/io/signals.zig`): Replace `extern fn sigaction(...)` (line 9) with `std.posix.sigaction()`. The `SigAction` struct is available as `std.posix.Sigaction`. Signal numbers (`SIGINT`, `SIGBUS`, `SIGSEGV`, `SIGFPE`) are available as `std.posix.SIG.*`.

**`src/io/platform.zig`**: The `stat()`-based file-modification-time query can be replaced with `std.fs.File.stat()` which returns `std.fs.File.Stat` containing `.mtime`. Drop `@cImport` of `sys/stat.h` and `unistd.h`. The Linux-vs-macOS errno pointer hack (`__errno_location` / `__error`) can be replaced by letting `std.posix` calls return Zig errors directly.

**`twidth()` / `TIOCGWINSZ`** (main.zig:595–601): Replace with `std.posix.ioctl` and the `winsize` struct from `std.os.linux` / `std.posix`.

**Outcome**: All `unistd.h`, `fcntl.h`, `sys/wait.h`, `sys/ioctl.h`, `sys/stat.h`, `signal.h` `@cImport`s removed. Only `setjmp.h` remains.

---

## Sub-phase 6e: Replace setjmp/longjmp with structured error recovery

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

---

## Sub-phase 6f: Remove linkLibC() and audit the result

**What**: Remove `linkLibC()` and any remaining `@cImport` from `build.zig`. Verify a clean build and full test pass.

**Steps**:

1. Remove from `build.zig`:
   ```zig
   // mira.linkLibC();               ← delete
   // steer_tests.linkLibC();        ← delete  
   // lex_tests.linkLibC();          ← delete
   // mira.root_module.linkSystemLibrary("m", .{});  ← already gone after 6b
   ```

2. Run `zig build` and fix any unresolved symbols — these point to remaining `@cImport` uses or missed libc calls.

3. Run `zig build test --summary all`. Target: ≥ 60/61 pass (same baseline as today).

4. Cross-compile check:
   ```bash
   zig build -Dtarget=x86_64-linux-musl
   zig build -Dtarget=aarch64-macos
   ```
   A pure-Zig binary targeting `musl` should link statically with no external libc dependency at all. The macOS build will still link `libSystem.dylib` (unavoidable on Darwin) but will not import any stdio or malloc symbols from it.

5. Verify with `otool -L zig-out/bin/mira` (macOS) or `ldd zig-out/bin/mira` (Linux) that `libc.so` / `libstdc++` are not listed.

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
