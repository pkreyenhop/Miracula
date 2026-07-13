# `anytype` inventory — Go resolution per site

Part of [GO_MIGRATION.md](GO_MIGRATION.md) Phase 0 (§5.2). 19 sites, 9 files,
measured 2026-07-13. Each row is a decision, not a suggestion — the real port
should not re-derive these.

Five resolution categories turned up, not the two §5.2 anticipated up front:
most sites (11 of 19) are the single "printf-style formatting" pattern, which
Go's stdlib already has a direct answer for; a further 4 are custom
`sscanf`/`fscanf` machinery that Go's stdlib also already replaces outright
(a deletion, not a translation).

## Category A — printf-style `(comptime fmt, args: anytype)` → `(format string, args ...any)`

The overwhelming majority. Every one of these calls Zig's `std.fmt` under the
hood; Go's `fmt.Sprintf`/`fmt.Fprintf`/`fmt.Fprintln`-family functions already
take exactly this shape (`format string, args ...any`). No design decision
left — this is the single most mechanical resolution in the whole inventory.

| Site | Resolution |
| --- | --- |
| `tools/menudriver.zig:310` `setNextFmt(self, comptime fmt, args)` | `func (d *Driver) setNextFmt(format string, args ...any)` wrapping `fmt.Sprintf` |
| `runtime/errors.zig:87` `fatal(comptime fmt, args) noreturn` | `func fatal(format string, args ...any)` wrapping `fmt.Fprintf(os.Stderr, ...)` then `os.Exit(1)` — Go has no `noreturn` type, callers don't need one (`os.Exit` never returns in practice; `go vet` doesn't require annotating this) |
| `eval/stream.zig:95` `Stream.print(self, comptime fmt, args)` | `func (s *Stream) Print(format string, args ...any)` wrapping `fmt.Fprintf(s.w, ...)` |
| `eval/stream.zig:166` `print(comptime fmt, args)` | package-level `func Print(format string, args ...any)` wrapping `fmt.Printf` |
| `eval/stream.zig:173` `printErr(comptime fmt, args)` | package-level `func PrintErr(format string, args ...any)` wrapping `fmt.Fprintf(os.Stderr, ...)` |
| `eval/stream.zig:182` `fprint(file, comptime fmt, args)` | `func Fprint(s *Stream, format string, args ...any)` wrapping `fmt.Fprintf(s.w, ...)` |
| `syntax/parser.zig:107` `addError(self, sp, comptime fmt, args)` | `func (p *Parser) addError(sp Span, format string, args ...any)` — message built via `fmt.Sprintf`, stored in the `Diagnostics` value per ZIG_NATIVE_PLAN's Phase 2 diagnostics model |
| `syntax/lexer.zig:191` `record(self, span, comptime fmt, args)` | same pattern as `parser.zig:107` |
| `syntax/lexer.zig:201` `recordStdout(self, span, comptime fmt, args)` | same pattern |
| `syntax/directives.zig:89` `record(self, span, comptime fmt, args)` | same pattern |
| `syntax/directives.zig:97` `recordStdout(self, span, comptime fmt, args)` | same pattern |

**Note:** `record`/`recordStdout` appearing identically in both `lexer.zig`
and `directives.zig` (4 sites, same shape) is itself worth a look during the
real port — possibly a shared `Diagnostics.record`/`recordStdout` method
factors out, reducing 4 Go methods to 1. Not decided here (it's a
translation-time simplification opportunity, not a blocking prerequisite);
flagged so it isn't missed.

## Category B — hand-rolled `scanf` family → replace with Go stdlib, don't translate

`os.zig`'s `sscanf`/`fscanf` and their `scanVal`/`scanValFromFile` helpers
are a hand-rolled C `scanf`-format-string interpreter, built because Zig's
standard library has no `scanf` equivalent. **Go's standard library does**:
`fmt.Sscanf(str, format, args...)` and `fmt.Fscanf(reader, format, args...)`
implement the same C-style format-string scanning directly, taking
`args ...any` (pointers, exactly like the C convention these were built to
match). Recommend **deleting this ~200-line subsystem outright** rather than
porting it — a rare case in this project where "mechanical" means "delete
the custom code and call the stdlib function it was standing in for."

| Site | Resolution |
| --- | --- |
| `os.zig:296` `scanVal(str, s_idx, spec, width, ptr: anytype) bool` | deleted — folded into `fmt.Sscanf`'s own implementation |
| `os.zig:404` `sscanf(buf, format, args: anytype) c_int` | deleted — call sites use `fmt.Sscanf` directly |
| `os.zig:503` `scanValFromFile(f, spec, width, ptr: anytype) bool` | deleted — folded into `fmt.Fscanf`'s own implementation |
| `os.zig:668` `fscanf(file, format, args: anytype) c_int` | deleted — call sites use `fmt.Fscanf` directly |

**Caveat, to verify before deleting:** confirm every existing call site's
format-string usage is within the subset `fmt.Sscanf`/`fmt.Fscanf` actually
support (Go's implementation is not a full C `scanf` — e.g. field widths and
some conversion specifiers differ). Audit call sites during Phase 1 of this
inventory's own use (i.e. when the real port reaches `os.zig`), not assumed
here from the format strings alone.

## Category C — variadic C-style call → concrete slice parameter

| Site | Resolution |
| --- | --- |
| `os.zig:900` `execl(path, args: anytype) c_int` | `func execl(path string, args []string) int32` — Go's `os/exec` already takes `[]string`; the C `execl`'s variadic-args-terminated-by-null convention has no reason to survive the port, every call site already knows its argument list length statically |

## Category D — small fixed set of concrete types → split into named functions

| Site | Resolution |
| --- | --- |
| `graph/heap.zig:1386` `constructor(self, n: Word, x: anytype) Word` (dispatches on `Word`/`c_int`/`[*:0]const u8`) | three named methods: `func (h *Heap) ConstructorWord(n, x Value) Value`, `ConstructorInt(n Value, x int32) Value`, `ConstructorStr(n Value, x string) Value` — the direct Go analogue of what Zig's comptime dispatch already compiles down to |
| `os.zig:33` `syscallResult(rc: anytype) c_int` | inline at each of its (small, `os.zig`-local) call sites as a concrete numeric conversion — this function exists only to smooth over Zig's `std.posix` call return types (`usize`/`isize`/error unions); Go's `syscall`/`os` package call conventions differ enough that this helper likely has no 1:1 Go shape at all, resolve during the `os.zig`→`platform.go` translation itself, not before |

## Category E — collapses once Phase 1 (c-string cleanup) lands

| Site | Resolution |
| --- | --- |
| `graph/strtab.zig:84` `strBits(self: *StringTable, p: anytype) Word` (accepts `[*:0]const u8` and `[]const u8` call sites today) | once [GO_MIGRATION.md Phase 1](GO_MIGRATION.md) finishes converting `[*:0]const u8` call sites to `[]const u8`/`[:0]u8`, every caller passes the same Zig type — re-audit at that point; if truly single-typed by then, `anytype` becomes a plain `p []const u8` parameter and this row is closed with no Go-side decision needed at all |

## Summary

| Category | Count | Go shape |
| --- | ---: | --- |
| A — printf-style | 11 | `(format string, args ...any)`, direct stdlib match |
| B — scanf family | 4 | deleted, replaced by `fmt.Sscanf`/`fmt.Fscanf` |
| C — variadic C call | 1 | concrete `[]string` |
| D — fixed type set | 2 | split into named functions / resolved locally in `os.zig`'s own port |
| E — pending Phase 1 | 1 | expected to collapse to a single concrete type before the port starts |
| **Total** | **19** | all resolved, zero left open |
