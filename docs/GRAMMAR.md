# Miranda Grammar Specification

This document describes the formal syntax of the Miranda programming language as implemented in the handwritten recursive-descent + Pratt parser pipeline in [parser.zig](file:///Users/pkreyenhop/src/experiments/Miracula/src/parser/parser.zig).

## 1. Lexical Conventions

### 1.1. Identifiers
- **Variable Identifiers (`NAME`)**: Start with a lowercase letter, followed by letters, digits, or single quotes. Examples: `x`, `map`, `xs'`.
- **Constructor Identifiers (`CNAME`)**: Start with an uppercase letter, followed by letters, digits, or single quotes. Examples: `True`, `Node`, `Leaf`.
- **Type Variables (`TYPEVAR`)**: Represented by one or more asterisks (`*`, `**`, etc.).
- **User-Defined Operators (`INFIXNAME` / `INFIXCNAME`)**: Any standard identifier enclosed by `$` signs to act as an infix operator. Examples: `$plus$`, `$Union$`.

### 1.2. Offside Rule (Layout-Sensitive Indentation)
Miranda uses indentation levels rather than explicit brackets to delimit block scopes:
- **`LBEGIN`**: Emitted when entering a nested layout scope (e.g., after `where`).
- **`OFFSIDE`**: Emitted when a line's indentation level is less than the current layout margin, signaling block closure.
- **`ELSEQ`**: Emitted when a line is aligned with the parent block margin.

---

## 2. Grammar Rules (BNF)

Below is the simplified Backus-Naur Form (BNF) structure of the grammar rules.

### 2.1. Top-Level Structure
```bnf
script        ::= directive_list defs
directive_list::= directive*
defs          ::= def (';' def)*
```

### 2.2. Definitions
```bnf
def           ::= var_def
                | type_def
                | spec_def
                | abstype_def

var_def       ::= lhs '=' rhs
                | lhs rhs_cases

type_def      ::= CNAME typevar* '::=' constructor_list
                | CNAME typevar* '==' type_expr
```

### 2.3. Right-Hand Side & Guards
```bnf
rhs           ::= exp ('where' ldefs)?
                | rhs_cases ('where' ldefs)?

rhs_cases     ::= '=' exp ',' 'if' cond
                | '=' exp ',' 'otherwise'
                | rhs_cases '=' exp ',' 'if' cond
                | rhs_cases '=' exp ',' 'otherwise'
```

### 2.4. Expressions
```bnf
exp           ::= exp infix_op exp
                | '-' exp
                | '#' exp
                | exp_app
                | list_comprehension
                | list_generator
                | section

exp_app       ::= exp_app? primary_exp

primary_exp   ::= NAME
                | CNAME
                | CONST (literals)
                | '(' exp ')'
                | '[' list_elements ']'
                | '(' exp_list ')' (tuples)
```

### 2.5. Lists and Generators
```bnf
list_elements ::= exp (',' exp)*
list_generator::= '[' exp '..' exp? ']'
list_comprehension ::= '[' exp '|' qualifier_list ']'
qualifier_list::= qualifier (';' qualifier)*
qualifier     ::= exp
                | pattern '<-' exp
```

### 2.6. Operator Sections
Sections are partial applications of binary operators:
- Left section: `(exp +)`
- Right section: `(+ exp)`
```bnf
section       ::= '(' infix_op exp ')'
                | '(' exp infix_op ')'
```
