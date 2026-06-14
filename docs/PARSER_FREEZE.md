# Miranda Parser Freeze and Isolation Spec

This document details the freeze policy and isolation boundary established for the legacy yacc/bison parser in the Miranda runtime migration.

## 1. Freeze Policy

The legacy parser files are considered **functionally frozen**:
- `src/parser/legacy/rules.y`
- `src/parser/legacy/y.tab.c`
- `src/parser/legacy/y.tab.h`

### Guidelines
1. **No Regeneration**: The Bison source `rules.y` must **never** be compiled or regenerated into `y.tab.c` during build.
2. **Direct Compilation**: The checked-in C source files (`y.tab.c` and `parser_bridge.c`) are compiled directly by `build.zig`.
3. **No Legacy Alterations**: No modification to `y.tab.c` or `rules.y` is permitted, except for necessary external declarations required for garbage collection or compilation warnings.

---

## 2. Isolation API

The legacy parser is isolated behind a narrow Zig interface in `src/parser/parser_api.zig`. All interactions with the parser from the rest of the codebase must go through this API.

### Public Interface
```zig
pub const ParseError = error{
    SyntaxError,
    ParseFailed,
};

pub const ParseResult = enum {
    success,
};

/// Parses the currently active stream.
pub fn parseCurrent() ParseError!ParseResult;

/// Parses a script file by filename.
pub fn parseFile(filename: [*:0]const u8) ParseError!ParseResult;

/// Parses a script string.
pub fn parseString(source: [*:0]const u8) ParseError!ParseResult;
```

---

## 3. Boundary Restrictions

Parser internals must never leak outside of the `src/parser/` directory.

### Forbidden References
The following symbols are internal to the legacy parser and must **never** be imported or referenced by modules outside of the parser package:
- `yyparse`
- `yylex`
- `yychar`
- `yylval`
- `yyval`
- `yydebug`
- `yyerror`

---

## 4. Garbage Collector Roots Integration

Because the legacy parser utilizes global state variables for AST construction and lookahead, the garbage collector must mark these variables to prevent premature reclamation of heap cells.

### C/Zig Bridge Roots
The bridge function `mira_parser_mark_roots()` is defined in `parser_bridge.c` and called by the garbage collector in `src/runtime/heap.zig`. It registers the following variables as GC roots:

| Root Variable | Type | Description |
|---|---|---|
| `yyval` | `word` | Current parser semantic value |
| `yylval` | `word` | Lexer semantic value / token payload |
| `fileq` | `word` | Stack of active input files (`s_in`) |
| `idsused` | `word` | Track identifiers defined in the current scope |
| `gvars` | `word` | Global variable lists |
| `lexvar` | `word` | Lexer variables |
| `margstack` | `word` | Margin indentation stack |
| `vergstack` | `word` | Indentation margin verge stack |
| `litstack` | `word` | Literate script state stack |
| `linostack` | `word` | Line number tracking stack |
| `prefixstack`| `word` | Active file prefix path stack |
| `echostack` | `word` | Print/echo output state stack |
| `files` | `word` | Input scripts tracked for compilation |
| `exportfiles`| `word` | List of files marked for export |
