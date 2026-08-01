# Go REPL feature-parity implementation record

## Completion status

Completed on 2026-08-01. All fourteen feature units and the cross-cutting
pseudo-terminal transcript gate are implemented, locally verified, committed,
and pushed to `main`.

| Unit | Production commit |
|---|---|
| F1 — line editor | `a5af758`, completed by `c1dfa6b` |
| F2 — persistent history | `a9f80fd` |
| F3 — identifier completion | `4bde9ec` |
| F4 — timing/GC prompt | `a3be67a` |
| F5 — editor invocation | `b87306d` |
| F6 — go to error | `362d070` |
| F7 — identifier queries | `e804c45` |
| F8 — manual browser | `7cee89a` |
| F9 — command-set parity | `c41e320` |
| F10 — shell escape | `a217039` |
| F11 — comment lines | `c602fc5` |
| F12 — persistent settings | `8eaacb4` |
| F13 — source auto-recheck | `cd51745` |
| F14 — editor-validity warning | `b5e548e` |
| Interactive transcript gate | `b91ac7f` |

The authoritative local acceptance command is `make verify`. It covers unit
tests, race tests, package-DAG enforcement, non-interactive integration tests,
the interactive pseudo-terminal transcript, installation checks, and a
source-only standard-library startup.

## Purpose

The Go `mira` binary (`cmd/mira`, driven by `internal/commandapp` →
`internal/application`) is the production interpreter and has complete language
runtime, compiler, and interactive REPL functionality. This document retains
the behavioral contracts used to implement that REPL.

The feature sections below are retained as acceptance specifications and as a
maintenance guide for future changes.

The removed Zig implementation was the historical behavioral oracle during the
port. Its sources remain available in Git history at the pre-removal parent of
`5ad09a1`. The production Go behavior and tests are now authoritative. Historical
source locations cited below refer to that revision:

| Concern | Zig source |
|---|---|
| REPL loop, prompt, `?`/`??`/`!`/`\|\|` dispatch, timing | `src/session/repl.zig` |
| Line editing / history / completion (zigline seam) | `src/session/editor.zig` |
| `/` command set, editor invocation, go-to-error | `src/session/commands.zig` |
| `.mirarc` persistence, flag parsing, editor validity | `src/session/config.zig` |
| Identifier completion source | `src/parser/lex.zig` (`completeIds`, line 539) |

Current Go REPL: `internal/application/repl.go`
(`REPL`, `runCommand`, `setOption`). Config: `internal/application/config.go`,
`internal/commandapp/config.go`. Session state:
`internal/application/repl_session.go` (`ReplSession`).

## Scope

- **In scope:** interactive comfort — line editing, history, completion,
  editor integration, the full `/` command set, `?`/`??` queries, the manual,
  timing/GC prompts, persistent settings, source auto-recheck.
- **Out of scope:** changing evaluation, typing, or `.x` semantics. This is
  strictly the REPL surface. Do not alter non-interactive (piped/`-exec`)
  behavior — the golden corpus and integration suite run non-interactively and
  must stay byte-identical.

## Guardrails

1. **Interactive only.** Every feature here activates only when stdin is a TTY
   (`i.Services.Terminal(0).Interactive`). Piped/file input must keep the
   current plain `bufio.Scanner`-equivalent path unchanged. The Zig editor is
   installed only for a TTY (`editor.zig` doc comment); mirror that gate.
2. **Package DAG.** Respect the target DAG (`tests/phase6_package_map.json`,
   enforced by `scripts/phase6_architecture.py`). Terminal raw-mode and any
   OS-facing primitive belong in `platformsvc` (leaf); the REPL orchestration
   and line-editor policy live in `application`. Do not make `platformsvc`
   import interpreter packages.
3. **Preserve output.** User-visible whitespace, `\x07` (BEL) bytes, and exact
   wording in the Zig messages are part of the contract. Copy strings verbatim.
4. **Each feature is a unit.** Land features independently, each with tests.
   Order below is the recommended implementation order (later features depend on
   earlier foundations).

---

## F1 — Interactive line-editor foundation

**Why first:** history, navigation, and completion all sit on top of one
line-reading seam. In Zig this is the `readInteractiveLine` hook installed on
stdin (`editor.zig:121`), so *every* downstream reader (command loop + lexer)
gets editing for free. Go needs the equivalent single seam.

**Behavior (from `editor.zig`):**
- Emacs-style editing: cursor left/right, word-left/right, home/end, delete,
  backspace, kill-to-end, transpose — the standard readline set.
- Up/Down arrow walks history (F2).
- Tab triggers completion (F3).
- Ctrl-D on an empty line signals EOF (returns null → REPL prints
  `miranda logout` when verbose and exits 0; see `repl.zig:250`).
- The prompt string is supplied per-line by the caller (F4 controls its text).

**Go target:**
- Add a `LineEditor` abstraction consumed by `application`. Two acceptable
  implementations; pick one and record the choice:
  - **(Recommended)** a small in-tree editor in `application` that puts the
    terminal in raw mode via a new `platformsvc` terminal service
    (`MakeRaw`/`Restore`, read runes, query width) and implements the key
    bindings itself. This keeps dependencies vendored and the DAG clean, and
    matches the "behavior, not a copied library" migration philosophy.
  - a vetted third-party readline (e.g. `peterh/liner` or `chzyer/readline`)
    wrapped behind the same interface, if adding a dependency is acceptable.
- Wire it as the line source for interactive REPL input, replacing
  `bufio.NewScanner(in)` in `REPL` **only when interactive**. Non-interactive
  stays on the scanner.
- Continuation reads (multi-line expressions) reuse the same editor with an
  empty prompt, mirroring `editor.zig:137` (`setPrompt` reset to `""`).

**Acceptance:**
- Interactive session: Left/Right/Home/End/Ctrl-A/Ctrl-E/Ctrl-K/backspace edit
  the current line before Enter submits it.
- Piped input (`echo "1+1" | mira`) produces byte-identical output to today.
- Ctrl-D on empty line exits with `miranda logout\n` (verbose) and status 0.
- Terminal is restored to cooked mode on every exit path, including panic and
  SIGINT.

**Notes:** raw-mode setup/teardown must be robust to interrupts; restore on
`defer` and on signal. Do not leak raw mode into `!shell` child processes (F10)
or the editor subprocess (F5).

---

## F2 — Persistent command history

**Behavior (from `editor.zig`):**
- History file is `$HOME/.miranda_history` (`editor.zig:116`).
- Loaded at REPL start (`loadHistory`, absent-on-first-run is fine —
  `editor.zig:118`).
- Every submitted line is appended to the in-memory history
  (`addToHistory`, `editor.zig:149`).
- Saved on clean teardown (`saveHistory` in `deinit`, `editor.zig:129`), which
  is called on EOF exit (`repl.zig:254`) and should be called on `/q` exit too.

**Go target:**
- Load `$HOME/.miranda_history` into the F1 editor at interactive startup;
  tolerate a missing file.
- Append each non-empty submitted line (commands included, matching Zig, which
  adds every edited line).
- Persist history on every exit path (EOF, `/q`, `/quit`). Add a `deinit`-style
  hook the REPL always runs.

**Acceptance:**
- Start interactive `mira`, submit `1+1`, exit with `/q`; restart; Up-arrow
  recalls `1+1`.
- No history file present at first run does not error.
- Piped runs never read or write the history file.

---

## F3 — Tab completion of identifiers

**Behavior (from `editor.zig:82` `completeWord` + `lex.zig:539` `completeIds`):**
- On Tab, find the identifier ending at the cursor: walk left over identifier
  chars (`[A-Za-z0-9_']`, `editor.zig:76`).
- Empty prefix or non-ASCII prefix → no completions.
- Otherwise ask the dictionary for all in-scope identifiers with that prefix
  (`completeIds`) and offer them; zigline inserts only the un-typed suffix
  (`invariant_offset = prefix_len`, `editor.zig:100`).
- Bounded to 128 suggestions (`name_storage[128]`).

**Go target:**
- Implement a completion callback in the F1 editor.
- Source candidates from the loaded program's symbol table
  (`i.Programs[...]`/`i.Compiler` scope — same set `/n` (F9 names) prints).
  Provide an `application` method `completeIdentifier(prefix string) []string`
  that the editor calls; keep the editor package unaware of interpreter types.
- Match Miranda identifier chars exactly, including the prime `'`.
- Suffix-only insertion; if exactly one match, complete it; if several, list
  them (readline-conventional) without discarding the typed prefix.

**Acceptance:**
- With the standard prelude loaded, typing `fold`⇥ offers `foldr`, `foldl`,
  `foldr1`, … (whatever is in scope).
- `'` is treated as part of the identifier (e.g. `foldl'` completes).
- Non-ASCII or empty prefix yields no completion and does not corrupt the line.

---

## F4 — Timing and GC annotations in the prompt

**Behavior (from `repl.zig:118-141`, `formatExecutionTime` line 68):**
- After evaluating an expression, the *next* prompt is prefixed with the
  elapsed wall time, and the GC count if > 0. Formats:
  - `[<time>] <promptstr>` normally.
  - `[<time>, <n> GC] <promptstr>` / `[<time>, <n> GCs] <promptstr>` when
    `last_gc_count > 0` (singular “GC” for 1).
- `formatExecutionTime`: `< 1ms` → `"{d:.3}ms"`; `< 1000ms` → `"{d:.2}ms"`;
  else → `"{d:.3}s"` (value in seconds).
- Timing is measured with a monotonic clock around the whole
  parse+eval step (`repl.zig:258` start, `:278` end).
- Only shown when verbose (`verbosity != 0`); on a non-verbose interactive
  session the prompt is empty (`repl.zig:137`). Commands (`/…`), comments, and
  blank lines do **not** set a timing (they clear `last_elapsed_ns`).
- `promptstr` default is `Miranda ` (Go `Config.Prompt`, already `"Miranda "`).

**Go target:**
- Time each expression evaluation with `platformsvc` monotonic clock (add a
  `MonotonicNanos()` service if absent — keep it in `platformsvc`).
- Track a per-session `lastElapsed *time.Duration` and `lastGC *int` on
  `ReplSession`; set them after expression evaluation, clear them for
  commands/blank/comment lines.
- Build the prompt exactly as above; set it on the F1 editor before each read.
- Wire the GC count from the evaluator’s statistics
  (`i.runtime().statistics()` already exposes counts — see `repl.go:129`).

**Acceptance:**
- `1+1` then observe next prompt like `[0.123ms] Miranda ` (exact format).
- An expression that triggers GC shows `[.., 3 GCs] Miranda `; exactly one GC
  shows `1 GC`.
- After a `/`-command the following prompt has no `[…]` prefix.
- Non-verbose (`/hush`) interactive prompt is empty; piped runs print no prompt.

---

## F5 — Invoke editor (`/e`, `/edit`, `/editor`)

**Behavior (from `commands.zig` `cmdEdit` line 242, `editfile` line 616,
`config.zig`):**
- `/e [file]` / `/edit [file]`: open `file` (default: current script) in the
  configured editor. `.m` extension is added if missing (`addextn`).
- If the target file does not exist, offer to seed it from `~/.mirahdr` or
  `<miralib>/.mirahdr` after a `open new script "<f>"? [ny]` confirmation, then
  copy the header template in (`cmdEdit` lines 254-316).
- The editor command is a **template** with substitutions (`editfile`):
  - `!`  → error line number (decimal)
  - `&`  → error column number (decimal)
  - `%`  → the filename, wrapped in double quotes, in place
  - `\!`, `\%`, `\&` → literal `!`, `%`, `&`
  - If no `%` appears, the quoted filename is appended at the end.
  - Default editor is `vi +!` (Go `Config.Editor` already defaults to
    `"vi +!"`).
- After the editor exits, if the source changed on disk (`srcUpdate`), reload
  it (`editfile` end, line ~697).
- `/editor [name]`: with no argument, print the current editor; with a name,
  confirm `change editor to: "<name>"? [ny]`, validate it (F14), persist to
  `.mirarc` (`writeRc`), and print `editor = <name>`.

**Go target:**
- Remove the stub at `repl.go:202` (`"editor command is unavailable"`).
- Implement `/e`/`/edit` in `internal/application/editor.go`: resolve target
  (default current module), add `.m`, seed-from-header flow with the `[ny]`
  prompt, then call an `editfile(path, line, col)` that performs the template
  substitution above and launches the editor via `platformsvc` process exec
  (inherit tty; restore cooked mode around the child — see F1 note).
- After the child exits, stat the file; if changed, reload
  (`i.LoadProgram(path)`).
- Implement `/editor` including validity check and `.mirarc` persistence (F12).

**Acceptance:**
- `EDITOR`/config `vi +!`, a compile error on line 12 of `foo.m`, then `/e`
  launches `vi +12 "foo.m"` (verify via a fake editor script that records argv).
- `%` template: editor `myed %` on `foo.m` runs `myed "foo.m"`.
- Editing the file and saving triggers an automatic reload on return.
- Terminal is in cooked mode inside the editor and raw mode restored after.

---

## F6 — Go to error (editor positioned at the error location)

**Behavior (from `commands.zig` `cmdEdit` lines 317-319, `editfile`):**
- When opening the **current** script, the editor is positioned at
  `core.errline` / `core.errcol` — the location of the last compile/type error
  (0/1 when there is none).
- When opening a *different* file that has a recorded error, the line comes from
  that file’s error record (`core.errs` / `geterrlin`).
- The line/column feed the `!`/`&` template substitutions in F5.
- `??name` (F7) is a special case: it opens the file **at the definition site**
  of `name` (`repl.zig:193` → `editfile(..., defline, 0)`).

**Go target:**
- Track the last error’s file, line, and column on the interpreter
  (extend the diagnostic path: today `Evaluate` returns `line:col: msg` but the
  REPL does not retain it). Store `lastError{path, line, col}` on the session,
  set whenever a compile/type/parse error is reported.
- `editfile` uses that location for the current script; for other files,
  look up a per-script recorded error line (add a small map keyed by path).
- Feed line/col into the F5 template.

**Acceptance:**
- Load a script with a type error on line 7; `/e` opens the editor at line 7.
- Fix and reload clears the recorded error so a later `/e` opens at line 1.
- `??f` opens the editor at `f`’s definition line (F7 provides the lookup).

---

## F7 — Identifier info / “explain” (`?name`, `??name`, `?`)

**Behavior (from `repl.zig:150-211` and `commands.zig` `finger`, `diagnose`,
`allnamescom`):**
- `?name …` — “finger” one or more names: print type and where each is defined
  (`finger`, iterating over `token()`s, `repl.zig:204-210`).
- `?` alone (then newline) — list **all** user names (`allnamescom`,
  `repl.zig:202`).
- `??name` — locate the definition and **open the editor there** (F6). Special
  cases handled verbatim:
  - identifier needed after `??` → `\x07identifier needed after `??'\n`
    (note the BEL and the backtick-quote style).
  - unknown/undefined name → `diagnose(name)` (the “explain why this name is
    unknown” path).
  - primitive → `<name> -- primitive to Miranda`.
  - aliased name → `originally defined as "<aka>"` before opening.
- `diagnose` is the closest thing to “explain”: it reports *why* a name is
  undefined (misspelling / not exported / not in scope). Keep its wording.

**Go target:**
- Parse the leading `?`/`??` in the interactive branch of `REPL` before the
  command/expression split (today only `/` is special-cased at `repl.go:72`).
- Implement three helpers in `application`:
  - `fingerName(w, name)` → type + definition location line.
  - `allNames(w)` → sorted user names (reuse `printNames`, `repl.go:261`).
  - `diagnose(name)` → the undefined-name explanation.
- `??name` resolves the definition site and calls `editfile` at that line (F6).
- Reproduce the exact BEL/quote/primitive/alias messages.

**Acceptance:**
- `?map` prints `map`’s type and its source location.
- `?` lists all names in scope, matching `/n` output ordering.
- `??` with no name prints the exact BEL error line.
- `??nonesuch` runs the diagnose/explain path, not a bare error.

---

## F8 — The manual (`/m`, `/man`)

**Behavior (from `commands.zig` `manaction` line 610):**
- Runs `"<miralib>/menudriver" "<miralib>/manual"` via the shell.
- `menudriver` is the interactive manual browser; `manual` is its data file.

**Go target:**
- `internal/devtools/menudriver.go` already exists — confirm it is built and
  reachable. Implement `/m`/`/man` to launch the manual browser over
  `<LibraryPath>/manual`, either by exec’ing the `menudriver` asset or by
  invoking the in-tree Go `menudriver` on the manual file.
- Restore cooked/raw terminal state around it as in F5.

**Acceptance:**
- `/man` opens the interactive manual and returns cleanly to the prompt.
- Works with `LibraryPath` pointing at the installed `miralib` (asset `manual`
  exists in the repo).

The Go manual browser pages long menus and sections in the style of `more`.
Press Space for the next page, Enter for the next line, `b` for the previous
page, `/` to search forward, `n` to repeat the search, and `q` to leave the
current display. Escape also leaves the current display. Finishing or leaving
a chapter redisplays the manual menu. At the menu, Escape exits the manual.
Entering `/text` at the menu searches case-insensitively through every manual
chapter and displays the matching chapter, line number, and text.

---

## F9 — Full `/` command-set parity

The Go `runCommand` (`repl.go:142`) implements only: `q/quit`, `h/help`,
`count`, `nocount`, `v/version`, `f/files`, `l/load`, `r/reload`, `n/names`,
`t/type`, `set`, and a stubbed `edit`. The Zig set (`commands.zig` `command`,
line 371) is larger. Implement the missing commands to match Zig behavior and
wording exactly:

| Command | Zig ref | Behavior |
|---|---|---|
| `/a`, `/aux` | `commands.zig:374` | Copy `<miralib>/auxfile` to stdout (asset exists). |
| `/cd [dir]` | `:393` | `chdir` (default `$HOME`); reload current script if its source changed. Error `cannot cd to <d>`. |
| `/dic [n]` | `:410` | No arg: print dictionary size + in-use. With arg: refuse to resize live, tell user to restart with `-dic`. |
| `/gc`, `/nogc` | `:433`,`:518` | Toggle per-evaluation GC-count reporting (`atgc`). |
| `/heap [n]` | `:452` | No arg: print heap limit (+default note). With arg: parse integer, validate, grow heap, persist (`writeRc`), print `heaplimit = <n> cells`; refuse to shrink below live size. |
| `/hush`, `/nohush` | `:484`,`:523` | Silence/restore banners and prompt (`verbosity`, `echoing`). |
| `/list`, `/nolist` | `:492`,`:529` | Toggle listing echo; persist. |
| `/m`, `/man` | `:501` | Manual (F8). |
| `/miralib` | `:506` | Print the library directory path. |
| `/recheck`, `/norecheck` | `:553`,`:536` | Toggle source auto-recheck (F13); persist. |
| `/s`, `/settings` | `:561` | Print the settings block (heap, dic, editor, list/recheck, count, gc, UTF-8, hush, debug) with the `*` “remembered between sessions” legend, verbatim. |
| `/v`, `/version` | `:591` | `versionInfo(0)`. Keep the existing Go version string. |
| `/V` | `:597` | `versionInfo(1)` (verbose build info). |
| `/find name…` | `cmdFiles:204` | Locate where each name is defined across loaded files (finger-like). |
| `/file [name]` | `cmdFiles:167` | Show/switch the current script (alias of the `/f` load path). |

Also: an unknown command prints `\x07unknown command - type /h for help\n`
(the interactive `|` branch, `repl.zig:243`) — match the BEL and wording rather
than the current `unknown command /X; use /help`.

**Go target:** extend `runCommand`/`setOption`; reuse existing config fields
(`Count`, `GC`, `List`, `Recheck`, `Hush`) and add the missing ones. Persist the
“remembered” settings via F12.

**Acceptance:** each command produces output matching the Zig binary for the same
session (capture Zig output, diff). `/s` output matches byte-for-byte modulo the
machine-specific paths.

---

## F10 — Shell escape (`!command`, bare `!`)

**Behavior (from `repl.zig:218-239`):**
- `!cmd` runs `cmd` via `$SHELL` (`-c`), inheriting the terminal.
- SIGINT is **ignored** for the duration so Ctrl-C reaches the child, not mira
  (`repl.zig:228`), then restored.
- After the child returns, if the source changed on disk, reload it.
- Bare `!` with no previous command:
  `No previous shell command to substitute for "!"\n`. (Zig keeps no history
  substitution beyond this message; match it.)

**Go target:** add a `!` branch to interactive `REPL`. Run via `platformsvc`
process exec through `$SHELL -c`, restore terminal cooked mode around it (F1),
mask SIGINT during the child, reload on source change.

**Acceptance:** `!ls` lists files; Ctrl-C during `!sleep 5` interrupts the sleep
but returns to the mira prompt; bare `!` prints the exact message.

---

## F11 — Comment lines (`||`)

**Behavior (from `repl.zig:240-248`):**
- A line beginning with `||` is a comment: consumed and ignored.
- A single leading `|` (not `||`) is an unknown command:
  `\x07unknown command - type /h for help\n`.

**Go target:** handle `||`/`|` in the interactive line classifier before the
expression path. Do not set a timing for comment lines (F4).

**Acceptance:** `|| note` is silently ignored; `| x` prints the BEL unknown-command line.

---

## F12 — Persistent settings (`~/.mirarc`)

**Behavior (from `config.zig` `readHomeRc:179`, `readRc:258`, `writeRc:359`):**
- On startup, read `$HOME/.mirarc` (else `<miralib>/.mirarc`).
- Several commands call `writeRc()` to persist: `/heap`, `/list`, `/nolist`,
  `/recheck`, `/norecheck`, `/editor`. The `/s` legend marks which settings are
  remembered (`*` items: heap, dic, editor, list, recheck).

**Go target:**
- Implement read/write of `~/.mirarc` in `application`/`commandapp` config.
  Match the Zig file format (see `config.zig` `readRc`/`writeRc` — reproduce the
  same keys/encoding so a `.mirarc` written by either binary is readable by the
  other).
- Load at startup; write on the persisting commands above.

**Acceptance:** `/heap 3000000` then restart shows the new heap limit; a
`.mirarc` produced by the Zig binary loads in Go and vice-versa.

---

## F13 — Source auto-recheck

**Behavior (from `repl.zig:143-145`, `commands.zig` `/recheck`/`/norecheck`,
`srcUpdate`):**
- When `rechecking` is on, before reading each interactive line and after any
  `!shell`/editor/`/cd` that could touch files, mira checks whether the current
  script’s source file changed on disk (`srcUpdate`) and reloads it if so.
- `/recheck` sets it (value 2 = also check included files); `/norecheck` clears
  it; both persist (F12).

**Go target:** add a `srcChanged(path)` check (mtime/size, matching Zig’s
`srcUpdate` semantics) and call it at the same points: top of the interactive
loop, and after F5/F8/F10/`/cd`. Reload via `i.LoadProgram`.

**Acceptance:** with `/recheck` on, editing the loaded script in another window
causes an automatic reload before the next prompt; `/norecheck` disables it.

---

## F14 — Editor-validity warning (`baded` / `edWarn`)

**Behavior (from `repl.zig` `badEditor:421`, `edWarn:390`, `commands.zig`
`/editor`):**
- An editor command is “bad” (cannot open at a line) unless it contains one of
  `+!`, `%d`, or `%l` (`badEditor`). Note: the Zig `badEditor` check uses
  `%d`/`%l` as the *validity* markers, while `editfile` substitution uses
  `!`/`&`/`%`; keep both behaviors as-is for parity.
- When the editor is bad, `??` and go-to-error are disabled and `edWarn` prints
  the long explanatory message (verbatim in `repl.zig:392`).
- Setting a bad editor via `/editor` still updates it but records `baded`.

**Go target:** compute a `badEditor` flag from `Config.Editor`; gate `??`/go-to-error on it and print `edWarn`’s exact text when triggered.

**Acceptance:** setting editor to a bare `cat` (no line marker) makes `??name`
print the `edWarn` message instead of opening; `vi +!` does not.

---

## Cross-cutting: parity testing

Interactive features cannot use the non-interactive corpus directly. The local
gate therefore runs `test/integration/test_go_interactive_repl.py`, which drives
the production binary through a pseudo-terminal and checks completion, timed
prompts, comments, legacy diagnostics, and clean logout. Focused Go tests cover
history, editing keys, editor templates and diagnostic positioning, identifier
queries, settings, shell dispatch, rechecking, and manual navigation.

The pseudo-terminal test remains separate from the non-interactive integration
test so piped behavior stays byte-identical and prompt-free.

## Implemented order

F1 → F2 → F3 (the editor stack), then F4 (timing), F9 and F12
(commands/persistence), F5/F6/F14 (editor + go-to-error), F7 (info/explain),
F10/F11 (shell/comments), F13 (recheck), F8 (manual), followed by the final F1
acceptance closure and pseudo-terminal transcript gate. Each unit was landed
with tests while keeping the non-interactive path unchanged.
