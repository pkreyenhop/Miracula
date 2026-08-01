package application

import (
	"bytes"
	"fmt"
	"path/filepath"
	"strings"
	"testing"

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
