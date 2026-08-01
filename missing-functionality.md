# Missing functionality in the Go Miranda implementation

This document audits the complete manual shipped in `lib/miralib/manual`
against the Go implementation as of commit `eb469bc`. It is an implementation
backlog, not a statement that the current parser merely accepts a spelling.
A feature counts as available only when its documented syntax, static
semantics, lazy runtime behavior, diagnostics, and system-interface effects
are present and tested.

## Audit method and coverage

The audit covered manual sections 1 through 34, including every subsection of
13, 27, and 31, plus the lexical grammar in section 26 and the formal grammar
in section 24. Historical, copyright, style, printing, and overview-only
sections (2, 3, 28, 30, 32, 33, 34, 99, and 100) were checked for behavioral
claims but do not themselves define additional language features.

Evidence was taken from the Go lexer/parser, semantic compiler, runtime,
module loader, REPL, command-line option dispatcher, tests, and representative
local executions. In particular, parser-corpus success is not treated as
proof of evaluation or typing support.

The work below should be implemented in dependency order. Each numbered item
is intended to be independently actionable by a coding agent.

## P0: language and runtime foundations

### MISSING-001 — Replace the partial type checker with full Miranda inference ✅

Status: completed. The semantic checker now provides SCC-aware polymorphic
inference, Miranda type parsing/formatting, declared and imported signatures,
synonyms, parameterized algebraic constructors, abstract representation
checking, pattern/guard/comprehension inference, command-expression checking,
and source-ordered recovery of independent type errors. File loading treats
these diagnostics as authoritative and the former save-time `reverse`
heuristic has been removed.

Manual sections: 14, 18–23, 24.

Current difference:

- `internal/semantics/compiler.go` infers only a small expression subset and
  `PrimitiveType` knows essentially `+` only.
- Type signatures are parsed but not enforced.
- Save-time checking in `ValidateCurrentTypes` is a targeted heuristic for
  numeric guards and `reverse`, not a language type checker.
- Type synonyms, algebraic types, abstract types, placeholder types,
  polymorphic type variables, constructor types, and the special typing rules
  for `show` and `readvals` are not implemented.
- Compilation errors are discarded by `LoadProgram`, which installs an empty
  semantic program and continues with the separate AST runtime.

Implementation instructions:

1. Define a single typed core AST used by both files and command expressions.
2. Implement Hindley–Milner inference with generalization at top-level
   bindings, instantiation at uses, occurs checking, mutually recursive binding
   groups, and stable Miranda type-variable printing (`*`, `**`, ...).
3. Populate the initial type environment with every primitive and standard
   environment binding.
4. Parse and enforce `::` declarations, including declarations that restrict
   an inferred polymorphic type and “specified but not defined” identifiers.
5. Implement synonym expansion with recursive-synonym rejection, algebraic
   type constructors, type parameters, placeholder types, and abstract-type
   generativity/signatures.
6. Implement monomorphic-use constraints for `show` and `readvals`, including
   abstract-type `showfoo` integration.
7. Make `LoadProgram` fail with all source-ordered type errors instead of
   swallowing semantic compilation errors. Remove the heuristic validator once
   the real checker supplies equivalent diagnostics.

Acceptance tests:

- Infer the manual examples `id :: *->*`, `map :: (*->**)->[*]->[**]`, and
  `plural :: [char]->[char]`.
- Reject inconsistent signatures and report every independent file error in
  source order.
- Type-check parameterized algebraic and abstract type examples from sections
  20 and 21.
- Preserve the existing `f1 x = reverse x, if x < 1000` diagnostic.

### MISSING-002 — Implement non-strict graph reduction consistently ✅

Status: completed. The production language runtime now uses memoized
call-by-need thunks for user applications, constructor fields, tuples, lists,
and cons cells. It preserves sharing and lazy call environments, detects
cyclic evaluation, retries interrupted thunks, honors strict constructor
fields, and implements irrefutable projection semantics for tuples and
one-constructor product types. Infinite recursive values and unused `undef`
arguments are covered by runtime tests.

Manual sections: 3, 16, 20, 21, 23.

Current difference:

- `languageRuntime.eval` evaluates a function argument before application, so
  ordinary function calls are eager. Constructor arguments and tuple/list
  members are also commonly evaluated eagerly.
- This violates Miranda’s non-strict semantics, sharing requirements, infinite
  data support, and irrefutable product-pattern behavior.
- The repository contains a graph evaluator, but the primary REPL path uses a
  separate partial AST interpreter.

Implementation instructions:

1. Select one production evaluator. Prefer lowering the fully typed core AST
   to the existing graph reducer; remove or confine the AST interpreter to
   tests/bootstrap code.
2. Pass arguments as updateable thunks and force only at primitive strictness
   points or refutable pattern matches.
3. Preserve sharing (call-by-need), black-hole detection, interruption, and GC
   root safety.
4. Make constructors non-strict by default and honor `!` strict-field
   annotations.
5. Implement direct-product/irrefutable pattern semantics so examples such as
   a tuple projection over `undef` produce the documented result.

Acceptance tests:

- A constant function applied to `undef` terminates without forcing it.
- Infinite lists and recursive algebraic values can be consumed finitely.
- Strict constructor fields force errors while unannotated fields remain lazy.
- Repeated use of an expensive argument is evaluated once.

### MISSING-003 — Complete expression operators and their semantics

Manual sections: 7–9, 24, 26.

Current difference:

- Working coverage includes basic arithmetic, numeric comparisons, `:`, `++`,
  numeric ranges, and common operator sections.
- Missing or incomplete: list subtraction `--`, boolean `\/`, `&`, and prefix
  `~`; function composition `.`; list subscript `!`; `$identifier` and
  `$IDENTIFIER` custom infix; structural equality/ordering; function-comparison
  errors; and several operator-as-value cases.
- `^` is not the documented numeric power operation for all numeric inputs.
- `/` works, but `div`/`mod` need the documented laws for negative operands
  verified explicitly.

Implementation instructions:

1. Lower every operator in section 8 through the typed primitive environment,
   retaining the documented associativity and precedence.
2. Implement short-circuit lazy boolean operators.
3. Implement structural comparison for every non-function type and reject
   functions anywhere inside compared structures.
4. Implement `--` as first-occurrence multiset subtraction, `!` with bounds
   diagnostics, composition, and custom infix application.
5. Support presections, postsections, and parenthesized operators uniformly;
   retain the documented prohibition on a bare prefix-minus section.

Acceptance tests: execute every example in manual sections 8 and 9, including
negative `div`/`mod`, continued relations, structured equality, and sections.

### MISSING-004 — Complete literals and character semantics

Manual sections: 10–12, 26, 32.

Current difference:

- The runtime evaluator has no `char` expression case even though syntax and
  parts of semantic inference recognize characters.
- Go `strconv.Unquote` does not exactly implement Miranda decimal, `\x`/`\X`,
  escaped-newline, and diagnostic rules.
- Hexadecimal floating-point syntax and all documented tokenization edge cases
  are not demonstrated end to end.
- Identifier apostrophes/digits, Unicode character values, and `code`/`decode`
  require full runtime tests.

Implementation instructions:

1. Implement Miranda-specific character/string decoding rather than relying
   on Go literal rules.
2. Add character runtime values, comparison, showing, `code`, and `decode`.
3. Support decimal, hexadecimal, and uppercase-hex Unicode escapes with the
   documented maximum lengths and precise malformed-escape diagnostics.
4. Support hexadecimal floating literals and escaped physical newlines.
5. Add lexer conformance tests generated from section 26’s grammar.

### MISSING-005 — Complete ranges and list comprehensions lazily

Manual sections: 13/1–13/3.

Current difference:

- Numeric ranges accept integers only; the manual permits fractional ranges.
- Ordinary comprehensions materialize each generator with a hard limit of one
  million elements, so infinite generators do not work as documented.
- Recurrence generators (`x <- a, f x ..`) are not implemented.
- Multi-variable generator shorthand and full pattern generators are partial.
- Diagonal comprehensions (`//`) and fair Cantorian enumeration are absent.

Implementation instructions:

1. Represent range and comprehension results as lazy streams with no arbitrary
   semantic materialization limit.
2. Implement integer and floating arithmetic progressions, including ascending
   and descending finite ranges and infinite ranges.
3. Implement left-to-right qualifier scope, filters, pattern-failure skipping,
   multi-variable shorthand, and recurrence generators.
4. Add a distinct diagonal-comprehension core node and fair enumeration for
   any generator count.

Acceptance tests: run every example in sections 13/1–13/3, including finite
prefixes of multiple infinite diagonal generators.

### MISSING-006 — Complete definitions, guards, local scope, and patterns

Manual sections: 12, 14–16, 24–25.

Current difference:

- Runtime source installation is line-oriented and does not implement the
  formal offside grammar.
- `where` blocks and nested local definitions are not evaluated with their
  documented recursive scope over all guarded alternatives.
- Top-level conformal definitions are not supported.
- Repeated variables in patterns are rebound rather than equality-checked.
- Natural-number `p+k`, negative literal, float rejection, constructor infix,
  parenthesized function forms, and all irrefutable-pattern rules are missing
  or partial.
- Guard checking is partial; `otherwise` works only as line-selection fallback
  and the static bool requirement is not generally enforced.
- Duplicate top-level bindings, equation contiguity/arity, undefined names,
  and declaration-order independence are not comprehensively validated.

Implementation instructions:

1. Replace line splitting with a layout-aware declaration parser producing
   complete equation groups, guarded alternatives, and nested `where` groups.
2. Build dependency SCCs for top-level and local recursive groups.
3. Implement every pattern form in section 16, repeated-name equality, and
   first-match source ordering without premature forcing.
4. Implement conformal bindings atomically: all bound names become undefined
   when the match fails.
5. Enforce guard type `bool`, `otherwise` placement, function arity consistency,
   and top-level uniqueness.

## P0: standard environment and effects

### MISSING-007 — Actually load and expose the complete standard environment

Manual sections: 4, 7–9, 11, 13, 16, 18, 23, 28, 31.

Current difference:

- Startup stores `prelude` and `stdenv.m` source for queries but does not
  compile/install their definitions into the runtime environment.
- A small hand-written builtin set masks this for functions such as `sum`,
  `reverse`, `take`, `map`, `foldl`, and `foldr`; many documented standard
  names are undefined (a local probe found `fst` undefined).
- `?` and completion do not enumerate the complete in-scope standard
  environment, although `?name` now has a source lookup fallback.

Implementation instructions:

1. Compile `prelude` and `stdenv.m` through the same production compiler as
   user scripts at boot, in dependency order.
2. Remove duplicate hand-written implementations unless they are explicitly
   typed primitives beneath the source definitions.
3. Validate the complete exported name/type profile against `stdenv.m`.
4. Feed the unified scope index to evaluation, `?`, `?name`, `??name`, `/find`,
   completion, and undefined-name checking.

Acceptance tests: every exported standard-environment name resolves, has the
declared type, and its documented examples execute.

### MISSING-008 — Implement the complete system-message I/O model

Manual sections: 31/1–31/3 and 31/9.

Current difference:

- Only a subset of `system`, `readvals`, `Appendfile`, and `Tofile` behavior is
  represented by builtins, and constructor/message execution is incomplete.
- Missing/incomplete input functions include `read`, `readb`, `filemode`, and
  `getenv`, with their documented error behavior.
- Missing/incomplete output messages include `Stdout`, `Stderr`, `Tofile`,
  `Closefile`, `Appendfile`, `System`, `Exit`, and binary variants, including
  ordered stream lifetime semantics.
- `$-`, `$:-`, and `$+` are not implemented as typed input values.
- `readvals` does not provide full typed, lazy, one-expression-per-line parsing
  with terminal retry behavior.

Implementation instructions:

1. Model `sys_message` as a real algebraic type and interpret a lazy message
   list sequentially only at the output boundary.
2. Add an evaluation-scoped world/I/O context for standard input, arguments,
   output streams, exit status, UTF-8/text conversion, and binary mode.
3. Implement all functions and constructors from sections 31/1, 31/2, and
   31/9, closing streams deterministically on completion/error/interruption.
4. Implement typed `readvals` and `$+`; prohibit simultaneous `$-`/`$:-` use.
5. Test UTF-8, non-Latin-1 errors where applicable, arbitrary binary bytes,
   stream append/replace behavior, and `Exit` short-circuiting.

## P1: modules, compilation, and command-line modes

### MISSING-009 — Finish `%include`, `%export`, aliases, and scope rules

Manual sections: 17 and 27/1–27/3.

Current difference:

- Relative quoted includes are recursively source-installed, but
  miralib-relative `<path>` includes are explicitly rejected.
- Export processing is simplistic; `+`, file re-exports, `-identifier`, type
  exports, constructor export coupling, and the default export profile are not
  faithfully implemented.
- Alias name-clash detection, original-name tracking, type/constructor alias
  rules, and `/find` semantics are absent or partial.
- Closed-script validation, include-cycle diagnostics, dependency scope, and
  source-location ownership are incomplete.

Implementation instructions:

1. Build a module graph before installation, resolving quoted paths relative
   to the containing source and angle paths relative to `LibraryPath`, adding
   `.m` where documented.
2. Compile each module in its own scope and compute an explicit export profile.
3. Apply aliases/suppression at the import boundary with clash checks and
   provenance retained for `?`, `??`, and `/find`.
4. Detect cycles and reject incorrect/open includees at the include site.
5. Make dependency metadata drive reload and object-cache invalidation.

### MISSING-010 — Implement `%free` parameterized scripts

Manual section: 27/4.

Current difference: syntax is recognized superficially, and include binding
text is partially scanned, but free signatures, value/type binding, type
checking, generative types, repeated instantiation, and exports are not
implemented.

Implementation instructions: represent module parameters in the typed module
IR; validate complete explicit bindings; substitute type and value parameters
without scope capture; generate fresh nominal identities per instantiation;
then apply exports and aliases. Use both numeric and boolean matrix examples
from section 27/4 as end-to-end tests.

### MISSING-011 — Make `.x` files real validated compiled artifacts

Manual section: 27/5.

Current difference: dumps are written/read for migration compatibility, but
normal loading recompiles source and does not use a dependency-aware compiled
program as described. Error/undefined-name state, export profiles, dependency
timestamps/hashes, and module code are not authoritative in `.x` files.

Implementation instructions:

1. Define a versioned artifact containing typed core/code, exports, source and
   dependency identities, diagnostics, and target/runtime compatibility data.
2. Load it when valid; rebuild only stale nodes in dependency order; write
   atomically; reject corrupt/incompatible artifacts safely.
3. Implement the documented behavior for missing source, moved files where
   feasible, and cleanup of orphan `.x` files.
4. Test cold build, warm no-recompile load, transitive invalidation, corruption,
   and source deletion.

### MISSING-012 — Implement special command-line modes instead of REPL fallback

Manual sections: 27/5, 31/4, and 31/7.

Current difference:

- Option parsing recognizes `-make`, `-exports`, `-sources`, `-exec`, and
  `-exec2`, but command dispatch sends all except a minimal `-make` validation
  path into the ordinary REPL.
- `-make` does not build all named roots/dependencies or guarantee the
  documented exit status.
- `-exec` does not evaluate `main`; `$*` is absent; `-exec2` logging is absent.

Implementation instructions:

1. Give each mode a separate command path with no REPL startup.
2. `-make`: accept all roots, normalize `.m`/`.x`, update the dependency DAG,
   report bad roots, and return 0/1 as documented.
3. `-exports`: build as needed and emit exact exported names and types.
4. `-sources`: emit the transitive `%include`/`%insert` source set, excluding
   implicit `stdenv`.
5. `-exec`: evaluate typed `main` with `$*` containing command plus arguments.
6. `-exec2`: additionally redirect runtime failures to `miralog/<program>`
   when that writable directory exists.
7. Add shebang integration tests and retain `-exp`/`-log` obsolete diagnostics.

### MISSING-013 — Complete `%insert`, listing directives, and literate syntax

Manual sections: 17 and 29.

Current difference:

- `%insert` recursively expands relative files, but indentation propagation,
  exact source locations, and dependency metadata require completion.
- `%list`/`%nolist` are parsed but do not control source echo during compilation.
- Literate source blanking exists, but the required blank-line separation rule,
  underlined nroff tokens, and underlined comparison-symbol compatibility are
  not enforced/recognized.

Implementation instructions: preserve a source map through recursive inserts;
apply insertion indentation before layout; implement listing state per source;
validate literate narrative/formal boundaries; normalize documented nroff
underlining before lexing; and test `.lit.m` plus first-character `>` detection.

## P1: REPL and manual interface

### MISSING-014 — Complete command-level expression facilities

Manual section: 4.

Current difference:

- `$$` (last expression) is absent.
- `exp ::` type queries are not parsed as documented.
- `exp &>` and `exp &>>`, including one/two output paths, background execution,
  append mode, error routing, and closed stdin, are absent.
- `%` current-script substitution is not applied consistently to session and
  shell commands; escaped literal `%` is absent.
- `!!` shell-command repetition is absent.

Implementation instructions: add a command-line lexer before expression
parsing; retain the previous typed expression as a shared thunk for `$$`;
route `::` through inference without evaluation; implement cancellable child
evaluation contexts for redirection/background execution; centralize `%`
substitution and shell history. Add interactive integration tests.

### MISSING-015 — Bring identifier discovery and completion to full scope parity

Manual sections: 4 and 27/3.

Current difference:

- `?name`/`??name` can now fall back to definitions in stored library source,
  but `?` and tab completion enumerate only the current compiled program.
- Included-module provenance and alias/original-name reporting are incomplete.
- `/find` is currently equivalent to a local type/name lookup rather than the
  documented original-alias lookup.

Implementation instructions: create one scope/provenance index from the module
graph and use it for all name-list, query, edit, completion, undefined-name,
and `/find` operations. Test standard, included, aliased, suppressed, local,
and shadowing cases.

### MISSING-016 — Complete pathname and reload behavior

Manual sections: 4, 14, 27/5, and 31/5.

Current difference:

- `~` and `~user` expansion is not centralized for script commands.
- `<miralib-relative>` path syntax is not accepted by `/cd` and related
  commands.
- `/f %` recompilation and `%` substitution are incomplete.
- Recheck watches only the current script metadata, not every transitive
  included/inserted source; automatic reload after shell/editor actions is
  therefore incomplete.

Implementation instructions: add a session pathname resolver for `%`, `~`,
`~user`, quoted paths, and `<...>`; track metadata for the full dependency DAG;
reload affected nodes in order while preserving source-ordered diagnostics.

### MISSING-017 — Finish the recursive manual menu protocol

Manual section: 1.

Current difference:

- Paging, forward search, menu-wide `/text` search, Space, Enter, `b`, `q`, and
  Escape are available.
- Numbered submenu directories such as `13`, `27`, and `31` are treated as
  files, so recursive contents menus do not work.
- Menu commands `.`, `+`, `-`, and `!command` are absent.
- Pager backward search `?context` and help `h` are absent; terminal height is
  fixed at 23 lines rather than detected.
- `VIEWER`, `MENUVIEWER`, and `RETURNTOMENU` compatibility is absent (the Go
  pager may intentionally replace external viewers, but the documented
  difference must be resolved or the manual updated).

Implementation instructions:

1. Maintain a stack of menu directories and load each directory’s `contents`.
2. Blank selection returns one level; blank at root exits. Chapter completion
   returns to its owning menu.
3. Track last/current numeric selection for `.`, `+`, and `-`; implement guarded
   shell escape `!command` with terminal suspension.
4. Add backward/repeated search and a pager help screen; obtain terminal rows
   dynamically with a testable fallback.
5. Add a pseudo-terminal integration test traversing `13 -> 2 -> parent -> root`.

## P2: diagnostics, configuration, and compatibility

### MISSING-018 — Make diagnostics compiler-wide and source accurate

Manual sections: 4, 14–18, 27, and 31/5.

Current difference: undefined-name collection and one guarded type mismatch are
reported well after edit, but syntax/type/module errors are not uniformly
aggregated; insert/include source maps, definition context, columns, cascades,
and editor navigation across files are incomplete.

Implementation instructions: introduce a structured diagnostic type with
severity, phase, file, span, definition, notes, and stable ordering; allow
parser/type/module phases to recover and collect independent errors; render
legacy-compatible text at the UI boundary; navigate to the first diagnostic.

### MISSING-019 — Complete settings, flags, and environment behavior

Manual sections: 6 and 31/5–31/8.

Current difference:

- Many commands/flags exist, but dictionary size is informational only and the
  configured heap size is not clearly the live evaluator allocation after a
  change.
- `/list` source echo, `-object` query output, automatic recheck when an editor
  template contains `&`, and full sticky-setting semantics are incomplete.
- `MIRALIB`, `EDITOR`, `RECHECKMIRA`, `SHELL`, `MIRAPROMPT`, `NOSTRICTIF`,
  locale detection, and global/user `.mirarc` precedence need complete
  conformance tests; viewer variables are not honored.
- Linux is intentionally unsupported by this Go cutover, unlike the historical
  platform claims in manual sections 3/32. The manual must explicitly describe
  the Go target policy rather than imply those targets are supported.

Implementation instructions: define a documented config precedence table
(defaults, global rc, environment, user rc, CLI), make every advertised switch
effective, persist only sticky settings, and add table-driven startup tests.
Update historical/current support wording without altering historical facts.

### MISSING-020 — Remove arbitrary semantic list limits while retaining safe output

Manual sections: 3, 4, 13, 18, and 20.

Current difference: `finiteList` imposes a one-million-element limit in
operations such as length, pattern matching, and comprehensions. This changes
language semantics. Streamed REPL output correctly permits Ctrl-C, but semantic
operations still materialize lists unnecessarily.

Implementation instructions: replace materializing algorithms with streaming
folds or graph primitives; allow genuinely infinite computations where Miranda
does; keep resource protection as cancellable UI/output policy rather than a
language result. Add large finite and infinite-prefix regression tests.

## Completion gate

The audit is complete only when all items above are implemented and the
following automated gate exists:

1. Extract executable examples from every normative manual section into a
   versioned conformance corpus.
2. For each example, assert parse result, inferred type or expected diagnostic,
   evaluation/output, laziness/termination where relevant, and source location.
3. Add pseudo-terminal tests for every REPL/manual interaction and filesystem
   fixtures for modules, object files, editor reload, and system-message I/O.
4. Run the corpus against the production `build/mira`, not package-private
   helper paths.
5. Maintain a machine-readable section-to-test manifest so every manual section
   is either covered or explicitly marked non-normative.

Until that gate passes, the shipped manual describes substantially more than
the Go implementation provides and should not be presented as fully conformant.
