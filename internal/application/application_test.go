package application

import (
	"bytes"
	"context"
	"github.com/pkreyenhop/miracula-go/internal/platformsvc"
	"github.com/pkreyenhop/miracula-go/internal/protocol"
	"github.com/pkreyenhop/miracula-go/internal/semantics"
	"github.com/pkreyenhop/miracula-go/internal/syntaxfront"
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
