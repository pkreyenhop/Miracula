# New Parser Foundation Progress Report (Phase 5)

This document reviews the architectural proof-of-concept and initial parser implementation constructed during Phase 5 of the Miranda Zig Migration. The primary goal of this phase was to build a clean, native Zig parser foundation alongside the legacy parser, and successfully parse simple definitions using a hybrid of Recursive Descent and Pratt Parsing.

## Implemented

We have successfully implemented and verified the core components of the new parser architecture:

1. **AST Specifications ([ast.zig](file:///Users/pkreyenhop/src/Miracula/src/parser/ast.zig))**:
   - Implemented standard tagged union definitions for AST representation of modules, definitions, types, patterns, and expressions.
   - Core structures: [Module](file:///Users/pkreyenhop/src/Miracula/src/parser/ast.zig#L8-L10), [Definition](file:///Users/pkreyenhop/src/Miracula/src/parser/ast.zig#L12-L18), [Expression](file:///Users/pkreyenhop/src/Miracula/src/parser/ast.zig#L62-L136), [Pattern](file:///Users/pkreyenhop/src/Miracula/src/parser/ast.zig#L20-L30), [TypeDefinition](file:///Users/pkreyenhop/src/Miracula/src/parser/ast.zig#L36-L46), and [WhereClause](file:///Users/pkreyenhop/src/Miracula/src/parser/ast.zig#L32-L34).
   - Formatter support for printing nodes in standardized syntax/lisp format for snapshots (e.g. `formatDefinition`, `formatPattern`).

2. **Diagnostics Accumulator ([diagnostics.zig](file:///Users/pkreyenhop/src/Miracula/src/parser/diagnostics.zig))**:
   - Implemented a thread-safe / clean diagnostics logging system that aggregates parser errors, warnings, and notes, rather than aborting compilation immediately.
   - Built helper functions like `addError`, `addWarning`, and `addNote` to record exact location-based line and column information.

3. **Token Filter Stream ([token_filter.zig](file:///Users/pkreyenhop/src/Miracula/src/parser/token_filter.zig))**:
   - Designed a token adapter interface bridging raw C-lexer tokens (`yylex`) to clean Zig types.
   - Supports lookahead operations via `peek()` and standard token iteration via `next()`.
   - Setup initial structure to support virtual tokens, offside/indentation markers, and future macro expansions.

4. **Pratt Operator Precedence Parser ([pratt.zig](file:///Users/pkreyenhop/src/Miracula/src/parser/pratt.zig))**:
   - Implemented `parseExpression` supporting operator precedence lookup.
   - Supported basic operators: `+`, `-`, `*`, `/` using binding powers read directly from operator info structures.
   - Handled unary prefix negation, parenthesis formatting, function applications (left-associative, highest binding power), and right-operator sections (e.g., `(+1)`).

5. **Recursive Descent Framework ([parser.zig](file:///Users/pkreyenhop/src/Miracula/src/parser/parser.zig))**:
   - Constructed the main [Parser](file:///Users/pkreyenhop/src/Miracula/src/parser/parser.zig#L12) structure managing standard arena allocations.
   - Implemented top-level recursive parsing paths: `parseModule()`, `parseDefinition()`, `parsePattern()`, and `parseExpression()`.

6. **Dual Parser Integration ([parser_api.zig](file:///Users/pkreyenhop/src/Miracula/src/parser/parser_api.zig) & [main.zig](file:///Users/pkreyenhop/src/Miracula/src/main.zig))**:
   - Configured `parser_mode` global setting to select between `.legacy` and `.new` modes.
   - Enabled invocation of the new parser via `--parser=new` CLI option.
   - Built dedicated entry points: `parseWithLegacy()` and `parseWithNew()` to facilitate parallel testing.

7. **Snapshot & Integration Testing ([parser_tests.zig](file:///Users/pkreyenhop/src/Miracula/src/parser/parser_tests.zig))**:
   - Implemented AST snapshot serialization to `tests/parser/new_parser/` for architectural verification.
   - Verified that simple definitions like `square x = x * x`, `id x = x`, `double x = x + x`, `inc = (+1)`, and `main = square 5` parse correctly and match their expected AST snapshots.
   - Added validation under the main `zig build test` pipeline, fully integrating it into the verification gate.

---

## Missing

The current framework acts as a structural foundation. The following language features are not yet implemented in the native parser:

- **Full Miranda Syntax**:
  - Complex pattern matching structures (e.g. lists, tuples, constructor-based destructuring).
  - List comprehensions, list generator ranges, guards/alternatives, and type declarations (e.g., standard `::` signatures).
  - Advanced structures like ZF expressions (list comprehensions) and type synonyms (`==`).
- **Complete Layout Engine**:
  - The token filter interface currently bridges raw lexer tokens. The full virtual layout engine that handles offside rule column indentation stacking and block generation is not yet implemented. It currently relies on explicit delimiters.
- **Type Checking Actions**:
  - Hand-off actions between AST compilation and type-checking / AST lowering to reduce graph cells.

---

## Risks

1. **Offside Rule Alignment**:
   - Integrating Miranda's complex layout engine (offside rules) with the recursive descent parser presents a coordination challenge. Subtle differences in how the legacy filter calculates column margins (e.g., RHS margin offset rules) compared to the new filter must be thoroughly audited.
2. **Lexer Mutual State**:
   - The C lexer maintains global states (`yylval`, `dicp`, `col`, `line_no`). Care must be taken when switching between the legacy parser and the new parser during dual-mode CLI runs, to ensure states are fully reset/isolated.
3. **Precedence Consistency**:
   - Ensuring custom user-defined operators (`$op$`) properly update binding powers at parse-time.

---

## Next Milestone

The next milestone is **Phase 6: Full Parser Substitution**.
Key steps:
1. **Extend the Layout Engine**: Fully implement the offside rule margin stack in `token_filter.zig` to automate the generation of block constructs.
2. **Expand Parser Coverage**: Add support for types, patterns, complex guard conditions, lists, and list comprehensions.
3. **Low Level Lowering**: Map the AST nodes (`ast.Definition` / `ast.Expression`) into C-level `Word` nodes to bridge into the existing graph reducer engine, replacing the legacy Bison semantic actions.
4. **Deprecate Legacy Parser**: Remove `rules.y`, `y.tab.c`, and `y.tab.h` once parity is proven.
