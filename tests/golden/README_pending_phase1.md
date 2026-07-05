# Pending Phase-1 fixtures: the library mechanism

`directive_include.m`/`.in`, `directive_include_lib.m`, `directive_include_alias.m`/`.in`,
`directive_export_scope.m`/`.in`, and `directive_free.m`/`directive_free_lib.m`/`.in` are
real, manual-derived test cases for `%include`, `%export`, and `%free`
(docs/man/mira.man.ms section 27, "The Miranda Library Mechanism") — but they have
**no `.expected`/`.expected_err`** and are not run by `zig build test-golden`.

They were left unpinned deliberately: running them against the current `mira` binary
shows the library mechanism is not actually wired up end to end, confirmed at two
points —

- `src/parser/codegen.zig:808` — `.include, .export_list, .free_directive => {}`: the
  AST nodes the parser produces for these directives are no-ops in codegen.
- `src/parser/lex_bridge.zig` — the `word.INCLUDE` case drops the pathname payload the
  legacy lexer's `directive()` already parsed (`ls().yylval`), so `parser.zig`'s
  `parseInclude` (which does `expect(.kw_include)` then `expect(.pathname)`) never
  actually receives a `.pathname` token; even a bare `%include "x"` with nothing else
  in the file fails with a syntax error at the following token. This reproduces on the
  shipped `miralib/ex/polish.m` example too, on a clean `main` checkout — it is not
  something this branch's changes caused.

So this isn't a case of "pin today's buggy output" — today's output is just "feature
absent," which isn't worth freezing as a golden case. Per
[docs/ZIG_NATIVE_PLAN.md](../../docs/ZIG_NATIVE_PLAN.md) Phase 1, `semantics/modules.zig`
must *implement* `%include`/`%export`/`%free` (aliasing, free-binding substitution,
cycle detection, dependency ordering) against the new native front end, not merely
preserve existing behavior. Once that lands, run:

```
zig build generate-golden
```

to capture real `.expected`/`.expected_err` output for these five fixtures, review it,
and commit it — turning them into real regression coverage for the library mechanism.

`directive_insert.m`/`.in` (the `%insert` directive) is unaffected by this gap — it is
pinned normally (`directive_insert.expected`) because `%insert` is pure textual
substitution performed entirely inside the legacy lexer, with no AST/codegen node of
its own to wire up.
