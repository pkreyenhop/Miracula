# Warning Inventory

This inventory records the warning suppressions that keep the current strict
build warning-clean. It is the Phase 1 baseline for warning reduction work.

The default C profile is:

```text
-std=c2y -D_POSIX_C_SOURCE=200809L -Weverything -Werror
```

The compatibility C++ profile is:

```text
-std=c++26 -D_POSIX_C_SOURCE=200809L
```

## Audit Target

Use `make warning-audit` to run the current strict C smoke-test build, then
rebuild `mira` with selected high-value suppressions removed and `-Werror`
disabled.

The first audit removes:

- `-Wno-missing-prototypes`
- `-Wno-missing-variable-declarations`
- `-Wno-unsafe-buffer-usage`
- `-Wno-disabled-macro-expansion`
- `-Wno-shadow`

These categories are broad enough to expose real cleanup work, but narrow
enough that the first audit remains readable.

## High-Value Cleanup Warnings

### `-Wno-unsafe-buffer-usage`

Classification: real code smell and security risk.

Primary patterns:

- manual `strcpy`, `strcat`, and `sprintf` into fixed-size or global buffers;
- path and command string construction in `steer.c`, `lex.c`, `data.c`, and
  `menudriver.c`;
- formatter scratch buffers in `reduce.c`, `big.c`, and `utf8.c`.

Cleanup direction:

- introduce checked copy, concat, and format helpers;
- use explicit destination capacities;
- add long-path and truncation tests before changing behavior.

### `-Wno-missing-prototypes`

Classification: maintainability issue.

Primary patterns:

- file-local helpers that are not marked `static`;
- implementation functions exported accidentally through broad headers;
- parser/generated functions that are not cleanly separated from handwritten
  module APIs.

Cleanup direction:

- mark private helpers `static`;
- split broad headers into smaller public interfaces;
- keep generated-code exceptions isolated from handwritten-code checks.

### `-Wno-missing-variable-declarations`

Classification: maintainability issue.

Primary patterns:

- shared mutable globals exported by convention rather than through explicit
  owning modules;
- compiler, typechecker, reducer, and lexer state living in global namespace;
- implementation-only globals visible across translation units.

Cleanup direction:

- move module-private state to `static`;
- group shared state into documented context structs;
- expose accessors only where cross-module mutation is required.

### `-Wno-disabled-macro-expansion`

Classification: historical design and maintainability issue.

Primary patterns:

- heap access macros such as `hd`, `tl`, and constructor macros;
- parser and reducer macros that depend on lvalue expansion;
- generated parser macros.

Cleanup direction:

- convert low-risk object constructors to `static inline` functions;
- document heap invariants;
- separate generated-code macro suppressions from handwritten-code suppressions.

### `-Wno-shadow`

Classification: readability issue.

Primary patterns:

- short historical local names reused across deeply nested functions;
- generated parser names;
- broad global names that make accidental shadowing easy.

Cleanup direction:

- fix handwritten code module by module;
- leave generated-code shadowing isolated behind generated targets;
- prefer descriptive local names when touching risky functions.

## Mechanical Or Historical-Style Warnings

These suppressions mostly reflect the historical style of the C code. They are
worth reducing, but they are lower priority than unsafe buffers and accidental
global exports.

- `-Wno-declaration-after-statement`
- `-Wno-comma`
- `-Wno-extra-semi-stmt`
- `-Wno-bad-function-cast`
- `-Wno-unreachable-code-return`
- `-Wno-conditional-uninitialized`
- `-Wno-implicit-fallthrough`
- `-Wno-missing-noreturn`

Cleanup direction:

- remove these after module-local refactors;
- avoid mechanical churn in generated files unless generation is updated;
- add comments only where control flow is genuinely non-obvious.

## Conversion And Type-Width Warnings

These suppressions are tied to the historical `word` representation, pointer and
integer conversions, and mixed signed/unsigned length handling.

- `-Wno-sign-conversion`
- `-Wno-conversion`
- `-Wno-shorten-64-to-32`
- `-Wno-implicit-int-float-conversion`
- `-Wno-float-conversion`
- `-Wno-format-signedness`
- `-Wno-cast-align`
- `-Wno-cast-qual`
- `-Wno-cast-function-type-strict`

Cleanup direction:

- define explicit conversion helpers around `word`, heap indexes, byte values,
  and string lengths;
- fix string-length comparisons as buffer APIs are replaced;
- leave representation-sensitive casts alone until heap invariants are tested.

## Generated Or Compatibility Noise

These suppressions are mostly about generated code, C++ compatibility, or
compiler-specific naming rules.

- `-Wno-padded`
- `-Wno-c++98-compat`
- `-Wno-c++-compat`
- `-Wno-c++98-compat-pedantic`
- `-Wno-switch-enum`
- `-Wno-covered-switch-default`
- `-Wno-switch-default`
- `-Wno-reserved-id-macro`
- `-Wno-reserved-identifier`
- `-Wno-documentation-unknown-command`
- `-Wno-undef`
- `-Wno-unused-macros`

Cleanup direction:

- split handwritten and generated warning profiles;
- keep C++ compatibility warnings separate from the normal C build;
- remove suppressions only when generated output or local macros can be changed
  without obscuring behavior.

## C++ Compatibility Suppressions

The C++ compatibility build intentionally compiles C sources as C++26. These
flags keep the compatibility target focused on language and linkage issues.

- `-Wno-deprecated`
- `-Wno-deprecated-register`
- `-Wno-writable-strings`
- `-Wno-c++98-compat`
- `-Wno-c++98-compat-pedantic`

Cleanup direction:

- keep this profile separate from the C profile;
- reduce `-Wno-writable-strings` after string literal APIs become `const` clean;
- do not let C++ compatibility changes make normal C code less idiomatic.

## Zig C Suppressions

`zig cc` uses the same project C profile plus:

- `-Wno-deprecated-octal-literals`

This is scoped to Zig C builds because Zig's system header path currently
expands glibc file-type macros that contain legacy octal literals under C2y.
The Clang C2y project build keeps this warning active, and project-owned octal
integer literals have been converted to hex constants.

## Phase 1 Status

- Current suppressions are inventoried and grouped by cleanup value.
- `make warning-audit` provides a repeatable first-pass audit.
- Generated-code and handwritten-code separation remains future work.
