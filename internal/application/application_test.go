package application

import (
	"bytes"
	"context"
	"errors"
	"github.com/pkreyenhop/miracula-go/internal/platformsvc"
	"github.com/pkreyenhop/miracula-go/internal/protocol"
	"github.com/pkreyenhop/miracula-go/internal/semantics"
	"github.com/pkreyenhop/miracula-go/internal/syntaxfront"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestInterpreterIsolation(t *testing.T) {
	a, b := New(platformsvc.NativeServices{}), New(platformsvc.NativeServices{})
	a.Strings.Intern("a")
	if b.Strings.Resolve(-1) != "" {
		t.Fatal("state leaked")
	}
}

func repositoryRoot(t *testing.T) string {
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("caller")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(file), "../.."))
}

func TestBootLoadsLibraryAndUserProgram(t *testing.T) {
	i := New(platformsvc.NativeServices{})
	i.Config.LibraryPath = filepath.Join(repositoryRoot(t), "miralib")
	directory := t.TempDir()
	script := filepath.Join(directory, "sample.m")
	if err := os.WriteFile(script, []byte("main = 1+2\n"), 0600); err != nil {
		t.Fatal(err)
	}
	i.InitialScript = script
	if err := i.Boot(); err != nil {
		t.Fatal(err)
	}
	if len(i.Scripts.Scripts) < 3 || len(i.Programs) != 1 {
		t.Fatalf("scripts=%d programs=%d", len(i.Scripts.Scripts), len(i.Programs))
	}
}

func TestCompiledDumpRejectsStaleSource(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sample.x")
	source := []byte("main = 1\n")
	if err := WriteCompiledDump(path, source); err != nil {
		t.Fatal(err)
	}
	if _, err := ReadCompiledDump(path, source); err != nil {
		t.Fatal(err)
	}
	if _, err := ReadCompiledDump(path, []byte("main = 2\n")); !errors.Is(err, ErrStaleDump) {
		t.Fatal(err)
	}
}

func TestProductionPipelineComputesExpression(t *testing.T) {
	i := New(platformsvc.NativeServices{})
	parsed := syntaxfront.Run([]byte("main = 1+2\n"))
	if len(parsed.Diagnostics) != 0 {
		t.Fatal(parsed.Diagnostics)
	}
	program, err := semantics.Compile(parsed.Script, i.Heap)
	if err != nil {
		t.Fatal(err)
	}
	if len(program.Definitions) != 1 {
		t.Fatal(program.Definitions)
	}
	result, err := i.Evaluator.Reduce(context.Background(), protocol.ValueFromRaw(protocol.Word(program.Definitions[0].Root)))
	if err != nil {
		t.Fatal(err)
	}
	text, err := i.Evaluator.Render(context.Background(), result, 100)
	if err != nil || text != "3" {
		t.Fatalf("result = %q, %v", text, err)
	}
}
func TestREPLQuit(t *testing.T) {
	i := New(platformsvc.NativeServices{})
	var out bytes.Buffer
	if e := i.REPL(context.Background(), strings.NewReader("/q\n"), &out); e != nil {
		t.Fatal(e)
	}
}

func TestREPLEvaluatesPipedExpressionWithoutPrompt(t *testing.T) {
	i := New(platformsvc.NativeServices{})
	var out bytes.Buffer
	if err := i.REPL(context.Background(), strings.NewReader("1+2\n/q\n"), &out); err != nil {
		t.Fatal(err)
	}
	if out.String() != "3\n" {
		t.Fatalf("output = %q", out.String())
	}
}

func TestREPLRecoversAfterEvaluationError(t *testing.T) {
	i := New(platformsvc.NativeServices{})
	var out bytes.Buffer
	if err := i.REPL(context.Background(), strings.NewReader("1 div 0\n2+2\n/q\n"), &out); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "division by zero\n4\n") {
		t.Fatalf("output = %q", out.String())
	}
}
