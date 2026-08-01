package application

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/pkreyenhop/miracula/internal/platformsvc"
	"github.com/pkreyenhop/miracula/internal/semantics"
	"github.com/pkreyenhop/miracula/internal/syntaxfront"
)

func TestExtendedReplSettingsCommands(t *testing.T) {
	i := New(nil)
	var output bytes.Buffer
	commands := []string{"/gc", "/list", "/recheck", "/hush", "/heap 3000000", "/s"}
	for _, command := range commands {
		if quit, err := i.runCommand(command, &output); err != nil || quit {
			t.Fatalf("%s: quit=%v err=%v", command, quit, err)
		}
	}
	if !i.Config.GC || !i.Config.List || !i.Config.Recheck || !i.Config.Hush || i.Config.HeapCells != 3000000 {
		t.Fatalf("config = %+v", i.Config)
	}
	for _, text := range []string{"heaplimit = 3000000 cells", "*\theap 3000000", "*\tlist", "*\trecheck", "\tgc", "\thush"} {
		if !strings.Contains(output.String(), text) {
			t.Errorf("settings output lacks %q:\n%s", text, output.String())
		}
	}
}

func TestRecheckSourceReloadsChangedScript(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "reload.m")
	if err := os.WriteFile(path, []byte("answer = 1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	i := New(platformsvc.NativeServices{})
	if err := i.Setup(); err != nil {
		t.Fatal(err)
	}
	if _, err := i.LoadProgram(path); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("answer = 200\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := i.recheckSource(); err != nil {
		t.Fatal(err)
	}
	absolute, _ := filepath.Abs(path)
	if got := string(i.Scripts.Scripts[absolute].Source); got != "answer = 200\n" {
		t.Fatalf("reloaded source = %q", got)
	}
}

func TestSessionPathResolutionAndQuotedLoad(t *testing.T) {
	directory := t.TempDir()
	library := filepath.Join(directory, "library")
	home := filepath.Join(directory, "home")
	i := New(&editorServices{home: home})
	i.Config.LibraryPath = library
	i.Compiler.CurrentModule = filepath.Join(directory, "current.m")
	for raw, want := range map[string]string{
		"%":          i.Compiler.CurrentModule,
		"~/work":     filepath.Join(home, "work"),
		"<ex/fib.m>": filepath.Join(library, "ex/fib.m"),
		"plain.m":    "plain.m",
	} {
		got, err := i.resolveSessionPath(raw)
		if err != nil || got != want {
			t.Errorf("resolve %q = %q, %v; want %q", raw, got, err, want)
		}
	}

	script := filepath.Join(directory, "space file.m")
	if err := os.WriteFile(script, []byte("answer = 1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	i = New(platformsvc.NativeServices{})
	if err := i.Setup(); err != nil {
		t.Fatal(err)
	}
	if _, err := i.runCommand(`/load "`+script+`"`, &bytes.Buffer{}); err != nil {
		t.Fatal(err)
	}
	if _, err := i.runCommand(`/f %`, &bytes.Buffer{}); err != nil {
		t.Fatal(err)
	}
}

func TestRecheckReloadsChangedTransitiveDependency(t *testing.T) {
	directory := t.TempDir()
	child := filepath.Join(directory, "child.m")
	root := filepath.Join(directory, "root.m")
	if err := os.WriteFile(child, []byte("child = 1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(root, []byte("%include \"child.m\"\nmain = child\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	i := New(platformsvc.NativeServices{})
	if err := i.Setup(); err != nil {
		t.Fatal(err)
	}
	if _, err := i.LoadProgram(root); err != nil {
		t.Fatal(err)
	}
	absoluteChild, _ := filepath.Abs(child)
	if _, tracked := i.Scripts.Scripts[absoluteChild]; !tracked {
		t.Fatal("included source metadata was not tracked")
	}
	if err := os.WriteFile(child, []byte("child = 200\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := i.recheckSource(); err != nil {
		t.Fatal(err)
	}
	if got, err := i.Evaluate(context.Background(), "child"); err != nil || got != "200" {
		t.Fatalf("reloaded child = %q, %v", got, err)
	}
}

func queryInterpreter() *Interpreter {
	i := New(nil)
	i.Compiler.CurrentModule = "/tmp/query.m"
	i.Programs = map[string]*semantics.Program{
		i.Compiler.CurrentModule: {Definitions: []semantics.TypedDefinition{
			{Name: "zeta", Type: &semantics.Type{Kind: semantics.TypeNamed, Name: "num"}, Expression: syntaxfront.Expr{Span: syntaxfront.Span{Line: 9}}},
			{Name: "alpha", Type: &semantics.Type{Kind: semantics.TypeNamed, Name: "char"}, Expression: syntaxfront.Expr{Span: syntaxfront.Span{Line: 3}}},
		}},
	}
	return i
}

func TestIdentifierQueries(t *testing.T) {
	i := queryInterpreter()
	var output bytes.Buffer
	if err := i.handleQuery("?alpha", &output); err != nil {
		t.Fatal(err)
	}
	if got := output.String(); got != "alpha :: char ||defined in \"/tmp/query.m\" line 3\n" {
		t.Fatalf("finger = %q", got)
	}
	output.Reset()
	if err := i.handleQuery("?", &output); err != nil {
		t.Fatal(err)
	}
	if got := output.String(); got != "alpha\nzeta\n" {
		t.Fatalf("all names = %q", got)
	}
}

func TestIdentifierQueriesFindStandardEnvironmentDefinitions(t *testing.T) {
	i := queryInterpreter()
	path := "/tmp/miralib/stdenv.m"
	i.Scripts.Put(Script{Path: path, Source: []byte("Some documentation.\n\n> reverse :: [*]->[*]\n> reverse = foldl (converse(:)) []\n")})
	definition, foundPath, ok := i.findDefinition("reverse")
	if !ok || foundPath != path || definition.Expression.Span.Line != 4 {
		t.Fatalf("definition = %+v, path = %q, ok = %v", definition, foundPath, ok)
	}
	var output bytes.Buffer
	if err := i.handleQuery("?reverse", &output); err != nil {
		t.Fatal(err)
	}
	want := "reverse :: [*]->[*] ||defined in \"/tmp/miralib/stdenv.m\" line 4\n"
	if output.String() != want {
		t.Fatalf("finger = %q, want %q", output.String(), want)
	}
}

func TestScopeIndexUnifiesStandardIncludedAliasedSuppressedAndLocalNames(t *testing.T) {
	i := queryInterpreter()
	standardPath := "/tmp/miralib/stdenv.m"
	includePath := "/tmp/modules/values.m"
	i.Scripts.Put(Script{Path: standardPath, Source: []byte("reverse :: [*]->[*]\nreverse x = x\n")})
	i.Scripts.Put(Script{Path: includePath, Source: []byte("public :: num\npublic = 1\noriginal :: char\noriginal = 'x'\nhidden = 9\nalpha = 99\n")})
	i.StandardTypes = map[string]*semantics.Type{"reverse": {Kind: semantics.TypeArrow, From: &semantics.Type{Kind: semantics.TypeList, Items: []*semantics.Type{{Kind: semantics.TypeVariable, ID: 1}}}, To: &semantics.Type{Kind: semantics.TypeList, Items: []*semantics.Type{{Kind: semantics.TypeVariable, ID: 1}}}}}
	runtime := i.runtime()
	runtime.globals["public"] = immediate(languageValue{kind: valueNumber, small: 1})
	runtime.globals["renamed"] = immediate(languageValue{kind: valueChar, small: 'x'})
	runtime.globals["alpha"] = immediate(languageValue{kind: valueNumber, small: 99})
	runtime.provenance["public"] = sourceProvenance{Path: includePath, Original: "public"}
	runtime.provenance["renamed"] = sourceProvenance{Path: includePath, Original: "original"}
	runtime.provenance["alpha"] = sourceProvenance{Path: includePath, Original: "alpha"}

	var output bytes.Buffer
	if err := i.handleQuery("?", &output); err != nil {
		t.Fatal(err)
	}
	if got, want := output.String(), "alpha\npublic\nrenamed\nreverse\nzeta\n"; got != want {
		t.Fatalf("scope names = %q, want %q", got, want)
	}
	if matches := i.completeIdentifier("re"); !reflect.DeepEqual(matches, []string{"renamed", "reverse"}) {
		t.Fatalf("completion = %v", matches)
	}
	output.Reset()
	if err := i.fingerName(&output, "renamed"); err != nil {
		t.Fatal(err)
	}
	if got := output.String(); !strings.Contains(got, "renamed :: char (alias of original)") || !strings.Contains(got, includePath) {
		t.Fatalf("alias query = %q", got)
	}
	output.Reset()
	if err := i.findAliases(&output, "original"); err != nil {
		t.Fatal(err)
	}
	if got := output.String(); got != "renamed :: char (alias of original)\n" {
		t.Fatalf("find aliases = %q", got)
	}
	if _, _, ok := i.findDefinition("hidden"); ok {
		t.Fatal("suppressed included name is in scope")
	}
	definition, path, ok := i.findDefinition("alpha")
	if !ok || path != i.Compiler.CurrentModule || definition.Expression.Span.Line != 3 {
		t.Fatalf("local shadow = %+v, %q, %v", definition, path, ok)
	}
}

func TestIdentifierQueryDiagnostics(t *testing.T) {
	i := queryInterpreter()
	for query, want := range map[string]string{
		"??":        "\aidentifier needed after `??'\n",
		"?nonesuch": "identifier \"nonesuch\" not in scope\n",
		"?if":       "if -- keyword (see manual, section 15)\n",
		"?not-bad":  "\"not-bad\" -- not an identifier\n",
	} {
		var output bytes.Buffer
		if err := i.handleQuery(query, &output); err != nil {
			t.Fatal(err)
		}
		if output.String() != want {
			t.Errorf("%s = %q, want %q", query, output.String(), want)
		}
	}
}

func TestUnknownReplCommandUsesLegacyDiagnostic(t *testing.T) {
	i := New(nil)
	_, err := i.runCommand("/wat", &bytes.Buffer{})
	if err == nil || err.Error() != "\aunknown command - type /h for help" {
		t.Fatalf("error = %q", err)
	}
}

func TestBarCommentsAndUnknownCommand(t *testing.T) {
	var output bytes.Buffer
	if err := handleBarLine("|| note", &output); err != nil || output.Len() != 0 {
		t.Fatalf("comment output = %q, err = %v", output.String(), err)
	}
	if err := handleBarLine("| note", &output); err != nil {
		t.Fatal(err)
	}
	if output.String() != "\aunknown command - type /h for help\n" {
		t.Fatalf("single bar output = %q", output.String())
	}
}

func TestHeapCommandRejectsIllegalValue(t *testing.T) {
	i := New(nil)
	_, err := i.runCommand("/heap nope", &bytes.Buffer{})
	if err == nil || err.Error() != "illegal value (heap unchanged)" {
		t.Fatalf("error = %v", err)
	}
}

func TestRecordErrorTracksAndClearsSourceLocation(t *testing.T) {
	i := New(nil)
	path := filepath.Join(t.TempDir(), "broken.m")
	i.recordError(path, fmt.Errorf("%s:7:13: type error", path))
	absolute, _ := filepath.Abs(path)
	if got := i.Repl.Errors[absolute]; got.Line != 7 || got.Column != 13 {
		t.Fatalf("location = %+v", got)
	}
	i.recordLoadResult(path, nil)
	if _, ok := i.Repl.Errors[absolute]; ok {
		t.Fatal("successful load did not clear error")
	}
}
