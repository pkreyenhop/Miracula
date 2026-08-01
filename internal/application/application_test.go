package application

import (
	"bytes"
	"context"
	"errors"
	"github.com/pkreyenhop/miracula/internal/platformsvc"
	"github.com/pkreyenhop/miracula/internal/protocol"
	"github.com/pkreyenhop/miracula/internal/semantics"
	"github.com/pkreyenhop/miracula/internal/syntaxfront"
	"io"
	"os"
	"path/filepath"
	"regexp"
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

func repositoryRoot(t testing.TB) string {
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("caller")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(file), "../.."))
}

func TestBootLoadsLibraryAndUserProgram(t *testing.T) {
	i := New(platformsvc.NativeServices{})
	i.Config.LibraryPath = filepath.Join(repositoryRoot(t), "lib/miralib")
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
	info, err := os.Stat(path)
	if err != nil || info.Mode().Perm() != 0o644 {
		t.Fatalf("dump mode = %v, %v", info.Mode().Perm(), err)
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

func TestREPLCountReportsGoRuntimeWork(t *testing.T) {
	i := New(platformsvc.NativeServices{})
	i.Config.Count = true
	var out, diagnostics bytes.Buffer
	i.Error = &diagnostics
	if err := i.REPL(context.Background(), strings.NewReader("1+2\n2+3\n/q\n"), &out); err != nil {
		t.Fatal(err)
	}
	pattern := regexp.MustCompile(`(?m)^\|\|reductions = [1-9][0-9]*, cells claimed = [1-9][0-9]*, no of gc's = 0, cpu = 0\.00$`)
	if len(pattern.FindAllString(diagnostics.String(), -1)) != 2 {
		t.Fatalf("count diagnostics = %q", diagnostics.String())
	}
}

func TestREPLRecoversAfterEvaluationError(t *testing.T) {
	i := New(platformsvc.NativeServices{})
	var out bytes.Buffer
	if err := i.REPL(context.Background(), strings.NewReader("1 div 0\n2+2\n/q\n"), &out); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "\nprogram error: attempt to divide by zero\n4\n") {
		t.Fatalf("output = %q", out.String())
	}
}

func TestREPLReportsActualTypeForReverseNonList(t *testing.T) {
	i := New(platformsvc.NativeServices{})
	var out bytes.Buffer
	if err := i.REPL(context.Background(), strings.NewReader("reverse 2\n/q\n"), &out); err != nil {
		t.Fatal(err)
	}
	want := "type error in expression\ncannot unify num with [*]\n"
	if out.String() != want {
		t.Fatalf("output = %q, want %q", out.String(), want)
	}
}

func TestLanguageRuntimeSupportsLazyHigherOrderAndBignumValues(t *testing.T) {
	i := New(platformsvc.NativeServices{})
	for expression, expected := range map[string]string{
		"product [1..10]":    "3628800",
		"map (2*) [1..5]":    "[2,4,6,8,10]",
		"2^80":               "1208925819614629174706176",
		"take 5 [1..]":       "[1,2,3,4,5]",
		"zip2 [1,2] [3,4]":   "[(1,3),(2,4)]",
		"\"abc\" ++ \"def\"": "abcdef",
	} {
		actual, err := i.Evaluate(context.Background(), expression)
		if err != nil || actual != expected {
			t.Fatalf("%s = %q, %v; want %q", expression, actual, err, expected)
		}
	}
}

func TestLanguageRuntimeUsesCallByNeed(t *testing.T) {
	runtime := newLanguageRuntime(io.Discard)
	if err := runtime.installSource([]byte("constant x = 1\ndouble x = x+x\nignorePair (x,y) = 7\n")); err != nil {
		t.Fatal(err)
	}
	for expression, want := range map[string]string{
		"constant (1 div 0)":      "1",
		"ignorePair (1 div 0, 2)": "7",
		"ignorePair undef":        "7",
	} {
		parsed, err := parseRuntimeExpression(expression)
		if err != nil {
			t.Fatal(err)
		}
		value, err := runtime.evaluate(context.Background(), parsed)
		if err != nil {
			t.Fatalf("%s: %v", expression, err)
		}
		if got, err := renderLanguage(context.Background(), value); err != nil || got != want {
			t.Fatalf("%s = %q, %v; want %q", expression, got, err, want)
		}
	}
	forces := 0
	runtime.globals["counted"] = &languageThunk{eval: func() (languageValue, error) {
		forces++
		return languageValue{kind: valueNumber, small: 3}, nil
	}}
	parsed, _ := parseRuntimeExpression("double counted")
	value, err := runtime.evaluate(context.Background(), parsed)
	if err != nil {
		t.Fatal(err)
	}
	if got, err := renderLanguage(context.Background(), value); err != nil || got != "6" || forces != 1 {
		t.Fatalf("double counted = %q, %v; forces = %d", got, err, forces)
	}
}

func TestMirandaOperatorSemantics(t *testing.T) {
	runtime := newLanguageRuntime(io.Discard)
	if err := runtime.installSource([]byte("join x y = x*10+y\nbox ::= Box num\n")); err != nil {
		t.Fatal(err)
	}
	tests := map[string]string{
		"False & (1 div 0 = 0)": "False", "True \\/ (1 div 0 = 0)": "True", "~False": "True",
		"[1,2,1,3]--[1,3]": "[2,1]", "[10,20,30]!1": "20", "((2*) . (1+)) 3": "8", "2 $join 7": "27",
		"take 3 ([1..]--[2])": "[1,3,4]",
		"[1,2] < [1,3]":       "True", "(1,False) < (1,True)": "True", "Box 2 = Box 2": "True",
		"2^(-2)": "0.25", "4.0^0.5": "2.0", "(-7) div 2": "-4", "(-7) mod 2": "1", "7 div (-2)": "-4", "7 mod (-2)": "-1",
		"(+) 2 3": "5", "(2+) 3": "5", "(+2) 3": "5",
	}
	for expression, want := range tests {
		parsed, err := parseRuntimeExpression(expression)
		if err != nil {
			t.Fatalf("parse %s: %v", expression, err)
		}
		value, err := runtime.evaluate(context.Background(), parsed)
		if err != nil {
			t.Fatalf("%s: %v", expression, err)
		}
		got, err := renderLanguage(context.Background(), value)
		if err != nil || got != want {
			t.Fatalf("%s = %q, %v; want %q", expression, got, err, want)
		}
	}
	for _, expression := range []string{"(1,(+)) = (1,(+))", "[1,(+)] = [1,(+)]"} {
		parsed, _ := parseRuntimeExpression(expression)
		if _, err := runtime.evaluate(context.Background(), parsed); err == nil || !strings.Contains(err.Error(), "functions") {
			t.Fatalf("%s error = %v; want nested function comparison error", expression, err)
		}
	}
}

func TestMirandaLiteralAndCharacterSemantics(t *testing.T) {
	runtime := newLanguageRuntime(io.Discard)
	tests := map[string]string{
		"'a'": "'a'", "'\\n'": "'\\n'", "'\\127'": "'\\x7f'", "'\\x3b3'": "'γ'", "'\\X0020ac'": "'€'",
		"\"\\0078\"": "\a8", "\"\\78\"": "N", "\"hello \\\ndolly\"": "hello dolly",
		"code 'a'": "97", "decode 8364": "'€'", "decode (code 'γ')": "'γ'",
		"0x1.0p-2": "0.25", "0x1p4": "16.0", "'a' < 'b'": "True", "\"abc\"!1": "'b'",
	}
	for expression, want := range tests {
		parsed, err := parseRuntimeExpression(expression)
		if err != nil {
			t.Fatalf("parse %q: %v", expression, err)
		}
		value, err := runtime.evaluate(context.Background(), parsed)
		if err != nil {
			t.Fatalf("%q: %v", expression, err)
		}
		got, err := renderLanguage(context.Background(), value)
		if err != nil || got != want {
			t.Fatalf("%q = %q, %v; want %q", expression, got, err, want)
		}
	}
	for _, expression := range []string{"'\\x'", "'\\X110000'", "'ab'", "decode (-1)"} {
		parsed, _ := parseRuntimeExpression(expression)
		value, err := runtime.evaluate(context.Background(), parsed)
		if err == nil {
			_, err = renderLanguage(context.Background(), value)
		}
		if err == nil {
			t.Fatalf("%q unexpectedly succeeded", expression)
		}
	}
}

func TestLazyRangesAndComprehensions(t *testing.T) {
	runtime := newLanguageRuntime(io.Discard)
	tests := map[string]string{
		"[1.0,1.1..1.3]":                    "[1.0,1.1,1.2,1.3]",
		"[3,2..-1]":                         "[3,2,1,0,-1]",
		"take 5 [n*n | n<-[1..]]":           "[1,4,9,16,25]",
		"[10*x+y | x<-[1..2]; y<-[1..3]]":   "[11,12,13,21,22,23]",
		"take 5 [n | n<-1,2*n..]":           "[1,2,4,8,16]",
		"take 6 [(x,y)//x<-[1..];y<-[1..]]": "[(1,1),(1,2),(2,1),(1,3),(2,2),(3,1)]",
		"take 4 [(a,b)//a,b<-[1..]]":        "[(1,1),(1,2),(2,1),(1,3)]",
		"[(x,y)//x<-[1..2];y<-[1..2]]":      "[(1,1),(1,2),(2,1),(2,2)]",
	}
	for expression, want := range tests {
		parsed, err := parseRuntimeExpression(expression)
		if err != nil {
			t.Fatalf("parse %s: %v", expression, err)
		}
		value, err := runtime.evaluate(context.Background(), parsed)
		if err != nil {
			t.Fatalf("%s: %v", expression, err)
		}
		got, err := renderLanguage(context.Background(), value)
		if err != nil || got != want {
			t.Fatalf("%s = %q, %v; want %q", expression, got, err, want)
		}
	}
}

func TestStrictConstructorFieldForcesArgument(t *testing.T) {
	runtime := newLanguageRuntime(io.Discard)
	if err := runtime.installSource([]byte("box ::= Lazy num | Strict num!\ntag (Lazy x) = 1\ntag (Strict x) = 1\n")); err != nil {
		t.Fatal(err)
	}
	for expression, wantError := range map[string]bool{"tag (Lazy (1 div 0))": false, "tag (Strict (1 div 0))": true} {
		parsed, _ := parseRuntimeExpression(expression)
		value, err := runtime.evaluate(context.Background(), parsed)
		if err == nil {
			_, err = renderLanguage(context.Background(), value)
		}
		if (err != nil) != wantError {
			t.Fatalf("%s error = %v, wantError = %v", expression, err, wantError)
		}
	}
}

func TestLazyResultsRetainCallEnvironment(t *testing.T) {
	runtime := newLanguageRuntime(io.Discard)
	if err := runtime.installSource([]byte("pair x = (x,x)\ntree ::= Node num tree\nbig = Node 1 big\nroot (Node x rest) = x\nproduct ::= Product num bool\nignoreProduct (Product x y) = 9\nloop = loop\n")); err != nil {
		t.Fatal(err)
	}
	for expression, want := range map[string]string{"pair (2+3)": "(5,5)", "root big": "1", "ignoreProduct undef": "9"} {
		parsed, _ := parseRuntimeExpression(expression)
		value, err := runtime.evaluate(context.Background(), parsed)
		if err != nil {
			t.Fatal(err)
		}
		if got, err := renderLanguage(context.Background(), value); err != nil || got != want {
			t.Fatalf("%s = %q, %v; want %q", expression, got, err, want)
		}
	}
	parsed, _ := parseRuntimeExpression("loop")
	if _, err := runtime.evaluate(context.Background(), parsed); err == nil || !strings.Contains(err.Error(), "cyclic") {
		t.Fatalf("loop error = %v", err)
	}
}

func TestLanguageRuntimeLoadsRecursiveGuardedDefinitions(t *testing.T) {
	root := repositoryRoot(t)
	i := New(platformsvc.NativeServices{})
	if _, err := i.LoadProgram(filepath.Join(root, "lib/miralib/ex/fib.m")); err != nil {
		t.Fatal(err)
	}
	actual, err := i.Evaluate(context.Background(), "fib 10")
	if err != nil || actual != "55" {
		t.Fatalf("fib 10 = %q, %v", actual, err)
	}
}

func BenchmarkLanguageRuntimeFibonacci(b *testing.B) {
	i := New(platformsvc.NativeServices{})
	if _, err := i.LoadProgram(filepath.Join(repositoryRoot(b), "lib/miralib/ex/fib.m")); err != nil {
		b.Fatal(err)
	}
	for n := 0; n < b.N; n++ {
		if _, err := i.Evaluate(context.Background(), "fib 20"); err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkLanguageRuntimeLargeListAndBignum(b *testing.B) {
	i := New(platformsvc.NativeServices{})
	for n := 0; n < b.N; n++ {
		if _, err := i.Evaluate(context.Background(), "(sum (take 1000 [1..])) + 2^80"); err != nil {
			b.Fatal(err)
		}
	}
}

func TestLanguageRuntimeLoadsAlgebraicValues(t *testing.T) {
	root := repositoryRoot(t)
	i := New(platformsvc.NativeServices{})
	if _, err := i.LoadProgram(filepath.Join(root, "testdata/golden/algebraic_param.m")); err != nil {
		t.Fatal(err)
	}
	for expression, expected := range map[string]string{"t1": "Branch (Leaf 1) (Leaf 2)"} {
		actual, err := i.Evaluate(context.Background(), expression)
		if err != nil || actual != expected {
			t.Fatalf("%s = %q, %v", expression, actual, err)
		}
	}
}
