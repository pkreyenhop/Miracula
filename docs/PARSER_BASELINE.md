# Miranda Parser Test Baseline

This document specifies the testing and validation baseline captured to ensure that future parser replacements introduce no regressions in syntax handling.

## 1. Snapshot Testing Strategy

To capture the parser's exact behaviour, a snapshot-testing runner is implemented in `src/parser/parser_tests.zig`. It processes test cases and records both the parsed **token stream** and the **parse outcome** into snapshot files.

### Snapshot Directory
Snapshot files are saved under:
- `tests/parser/snapshots/*.snapshot`

### Snapshot Format
Each snapshot contains a header indicating whether parsing succeeded or failed, followed by the exact sequence of tokens emitted by the lexer:
```text
PARSE_RESULT: SUCCESS

TOKENS:
NAME("square")
NAME("x")
EQUALS
NAME("x")
TIMES
NAME("x")
```

---

## 2. Test Cases and Coverage

The test suite covers both valid syntax structures (golden baseline) and syntax errors.

### 2.1. Golden Test Cases
1. **`simple_def`**: Basic variable definition and arithmetic expressions (`square x = x * x`).
2. **`recursion`**: Pattern matching with numerical constants (`fact 0 = 1`).
3. **`lists`**: List literal construction (`[1, 2, 3]`).
4. **`list_comprehensions`**: List generators and qualifiers (`[x*x | x <- [1..10]]`).
5. **`pattern_matching`**: List patterns (`sum (x:xs) = x + sum xs`).
6. **`type_definitions`**: Algebraic data types (`tree ::= Leaf num | Node tree tree`).
7. **`where_clauses`**: Nested block indentation and local scopes.
8. **`operator_sections`**: Right and left operator sections (`(+1)` and `(1+)`).
9. **`layout`**: Indentation checks for multiple aligned definitions.

### 2.2. Error Test Cases
1. **`unexpected_token`**: Structural errors in syntax (`x = + * 2`).
2. **`unterminated_string`**: Lexical string termination errors (`x = "hello`).
3. **`invalid_operator`**: Unsupported operators (`x = 1 @ 2`).
4. **`bad_indentation`**: Indentation alignment violation under layout rules.
5. **`unexpected_eof`**: Truncated input files (`x = `).
6. **`malformed_type`**: Truncated or syntax-violating algebraic type signatures.

---

## 3. Standard Library Integration Test

To guarantee parser completeness, a full integration test executes against the entire standard prelude library of Miranda:
- **Test Target**: `test "prelude parsing test"` in `src/parser/parser_tests.zig`.
- **Target File**: `miralib/prelude`.
- **Verification**: Parses the entire standard library file without emitting syntax errors.

---

## 4. Run and Update Commands

### Run Verification Gate
To run all tests and verify against the snapshot baseline:
```bash
zig build test
```

### Update Snapshots
If syntax features are intentionally updated, snapshots can be updated automatically:
```bash
UPDATE_SNAPSHOTS=1 zig build test
```
