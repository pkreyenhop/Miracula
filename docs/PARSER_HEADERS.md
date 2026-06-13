# Miranda Parser Header Specifications

This document catalogs the header interfaces that form the boundary between the legacy C yacc parser components and the Zig runtime.

## 1. Header Overview

The parser subsystem relies on three main C header files for structure definitions, token definitions, and interface APIs:
- `combs.h`: Contains internal runtime tag values (such as `NIL` and constructor tags).
- `data.h`: Declares external global variable words and core list/heap data layouts.
- `src/parser/legacy/parser_bridge.h`: Formal ABI specification connecting the Zig runtime to the yacc parser execution.

---

## 2. ABI Interface (`parser_bridge.h`)

This header is the only file imported via `@cImport` in the Zig parser wrapper. It encapsulates the core runtime interface:

```c
#ifndef PARSER_BRIDGE_H
#define PARSER_BRIDGE_H

#include "data.h"

/* Execution Control */
int mira_parse_file(const char *filename);
int mira_parse_string(const char *source);
int mira_parse_current(void);
void mira_lex_setup_string(const char *source);
void mira_lex_cleanup(void);

/* Semantic AST Construction Action Shims */
word parse_nil(void);
word parse_cons(word lhs, word rhs);
word parse_cons_pre(word lhs);
word parse_neg(word rhs);
word parse_plus(word lhs, word rhs);
word parse_infix(word op, word lhs, word rhs);
/* ... (additional operator functions) */

/* Garbage Collection Hooks */
void mira_parser_mark_roots(void);

#endif
```

---

## 3. Decoupling Glibc Dependencies

A major portability issue during the C-to-Zig runtime migration was that yacc-generated code (`y.tab.c`) frequently includes standard libc headers (such as `<stdio.h>`), which trigger glibc translation errors during `@cImport` translation on Linux targets.

### The Resolution Strategy
1. **Isolation of `@cImport`**: `@cImport` is **only** called on `parser_bridge.h` in `src/parser/parser_api.zig`. No C headers are imported directly in other parts of the Zig runtime.
2. **Bridge Abstraction**: File and memory buffer management (`fmemopen`) are written entirely in C inside `parser_bridge.c`.
3. **Abstract Data Types**: The Zig runtime communicates using the opaque `word` type, meaning Zig does not need to parse or compile OS-specific `FILE` pointers or standard library struct definitions.
4. **Platform Macros**: Standard POSIX/Darwin macro definitions are passed via `build.zig` to ensure proper linking without header pollution.
