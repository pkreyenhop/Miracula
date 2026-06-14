# Miranda Parser Replacement Plan (Phase 5)

This document provides a comprehensive, implementation-ready design specification for replacing the legacy yacc/bison parser (`y.tab.c`) with a modern, native Zig parser.

## 1. Architectural Strategy

The proposed parser replacement avoids parser generators, state tables, and generated code. Instead, it utilizes a clean, hand-written combination of **Recursive Descent** and a **Pratt Operator Precedence Parser**.

```text
Source Code
    ↓
Lexer (src/parser/lex.zig)
    ↓
Token Stream Filter (Layout Indentation Handler)
    ↓
Recursive Descent Parser (For Declarations, Types, Where clauses)
    ↓
Pratt Expression Engine (For expressions, operators, sections)
    ↓
AST Builder (parse_actions.zig)
```

---

## 2. Token Stream Filter (Layout Engine)

To parse Miranda's offside rule without complex feedback loops in the lexer:
1. The lexer will output raw indentation columns and newlines.
2. A **Token Stream Filter** wrapper will intercept these tokens and maintain a margin stack.
3. The filter will inject synthetic block-delimiters (`LBEGIN`, `OFFSIDE`, `ELSEQ`, and `SEMICOLON`) into the parser's view.
4. This keeps the core parser code clean and layout-agnostic.

---

## 3. Parser Design

### 3.1. Recursive Descent (Top-level and Declarations)
A standard recursive descent parser is highly suited for parsing structure and declarations:
- Top-level scripts (`parseScript`)
- Directives (`parseDirective` for `%export`, `%insert`, `%list`)
- Type definitions (`parseTypeDefinition` for `::=` and `==`)
- Pattern structures (tuple, list, and constructor patterns)
- Where-clause scoping blocks

### 3.2. Pratt Parser (Expressions)
Miranda supports infix operator applications, prefix operators, user-defined operators (`$op$`), and operator sections (e.g. `(+1)`, `(1+)`). A Pratt parser handles this cleanly using binding powers:
```zig
pub const BindingPower = enum(u8) {
    none = 0,
    lowest = 1,
    logical_or = 2,
    logical_and = 3,
    comparison = 4,
    cons_list = 5,
    addition = 6,
    multiplication = 7,
    exponentiation = 8,
    application = 9,
    highest = 10,
};

pub fn parseExpression(parser: *Parser, min_bp: BindingPower) ParseError!Word {
    var token = parser.next();
    var lhs = try parser.prefixRules(token);
    
    while (true) {
        const op = parser.peek();
        const op_bp = parser.infixBindingPower(op);
        if (op_bp.left < @intFromEnum(min_bp)) break;
        
        _ = parser.next(); // consume op
        lhs = try parser.infixRules(op, lhs, op_bp.right);
    }
    return lhs;
}
```

---

## 4. Replacement Action Plan

1. **Pratt Expression Engine**: Implement the core expression parsing logic with fixed and user-defined precedence rules.
2. **Indentation Layout Filter**: Port layout margin logic from `lex.zig` into a clean token stream filter struct.
3. **Recursive Descent Structure**: Implement top-level scripts, data types, patterns, and where-clauses.
4. **Integration**: Swap out `y.tab.c` and `parser_bridge.c` from `build.zig`. Wire the new parser into `parser_api.zig`.
5. **Validation**: Execute the snapshot test suite (`zig build test`) to ensure output AST matches the golden snapshots.
