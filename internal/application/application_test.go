package application

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"github.com/pkreyenhop/miracula/internal/platformsvc"
	"github.com/pkreyenhop/miracula/internal/protocol"
	"github.com/pkreyenhop/miracula/internal/semantics"
	"github.com/pkreyenhop/miracula/internal/syntaxfront"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
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
	var missing []string
	for name := range i.StandardTypes {
		if name == "char" || name == "num" {
			continue
		}
		if i.runtime().globals[name] == nil {
			missing = append(missing, name)
		}
	}
	if len(missing) != 0 {
		sort.Strings(missing)
		t.Fatalf("standard names missing at runtime: %v", missing)
	}
	for expression, want := range map[string]string{"fst (1,2)": "1", "abs (-3)": "3", "concat [[1,2],[],[3,4]]": "[1,2,3,4]", "digit '7'": "True", "const 3 undef": "3"} {
		got, err := i.Evaluate(context.Background(), expression)
		if err != nil || got != want {
			t.Fatalf("%s = %q, %v; want %q", expression, got, err, want)
		}
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

func TestCompiledArtifactWarmLoadAndDependencyInvalidation(t *testing.T) {
	directory := t.TempDir()
	dependency := filepath.Join(directory, "dep.m")
	root := filepath.Join(directory, "root.m")
	artifact := filepath.Join(directory, "root.x")
	if err := os.WriteFile(dependency, []byte("dep = 1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(root, []byte("%include \"dep\"\nmain = 2\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	first := New(platformsvc.NativeServices{})
	if _, err := first.LoadProgram(root); err != nil || first.Compiler.UsedCompiledArtifact {
		t.Fatalf("cold load used artifact=%v err=%v", first.Compiler.UsedCompiledArtifact, err)
	}
	dump, err := ReadCompiledDump(artifact, []byte("%include \"dep\"\nmain = 2\n"))
	if err != nil || dump.Program == nil || len(dump.Dependencies) != 1 || dump.Target == "" {
		t.Fatalf("artifact = %+v, %v", dump, err)
	}
	second := New(platformsvc.NativeServices{})
	if _, err := second.LoadProgram(root); err != nil || !second.Compiler.UsedCompiledArtifact {
		t.Fatalf("warm load used artifact=%v err=%v", second.Compiler.UsedCompiledArtifact, err)
	}
	if err := os.WriteFile(dependency, []byte("dep = 3\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	third := New(platformsvc.NativeServices{})
	if _, err := third.LoadProgram(root); err != nil || third.Compiler.UsedCompiledArtifact {
		t.Fatalf("dependency-stale load used artifact=%v err=%v", third.Compiler.UsedCompiledArtifact, err)
	}
	if err := os.WriteFile(artifact, []byte("corrupt"), 0o600); err != nil {
		t.Fatal(err)
	}
	fourth := New(platformsvc.NativeServices{})
	if _, err := fourth.LoadProgram(root); err != nil || fourth.Compiler.UsedCompiledArtifact {
		t.Fatalf("corrupt load used artifact=%v err=%v", fourth.Compiler.UsedCompiledArtifact, err)
	}
	if err := os.Remove(root); err != nil {
		t.Fatal(err)
	}
	if _, err := fourth.LoadProgram(root); err == nil {
		t.Fatal("missing source loaded")
	}
	if _, err := os.Stat(artifact); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("orphan artifact remains: %v", err)
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

func TestDefinitionAndPatternSemantics(t *testing.T) {
	runtime := newLanguageRuntime(io.Discard)
	source := "equal x x = True\nequal x y = False\npred (n+1) = n\npred 0 = 0\nnegative (-2) = True\nnegative x = False\n[a,b,3] = [1,2,3]\nforward = later+1\nlater = 4\nfoo x = p+q, if p<q\n      = p-q, otherwise\n  where\n  p = x^2+1\n  q = 3*x\nouter x = local x\n  where\n  local y = helper y\n    where\n    helper z = z+1\n"
	if err := runtime.installSource([]byte(source)); err != nil {
		t.Fatal(err)
	}
	for expression, want := range map[string]string{"equal 3 3": "True", "equal 3 4": "False", "pred 9": "8", "pred 0": "0", "negative (-2)": "True", "negative 2": "False", "a+b": "3", "forward": "5", "foo 2": "11", "outer 4": "5"} {
		parsed, _ := parseRuntimeExpression(expression)
		value, err := runtime.evaluate(context.Background(), parsed)
		if err != nil {
			t.Fatalf("%s: %v", expression, err)
		}
		got, err := renderLanguage(context.Background(), value)
		if err != nil || got != want {
			t.Fatalf("%s = %q, %v; want %q", expression, got, err, want)
		}
	}
	for _, invalid := range []string{"f x = x\ng = 1\nf y = y\n", "f x = x\nf x y = x\n", "f x = 1, otherwise\n = 2, if x=0\n", "f 1.5 = 2\n", "1 = 2\n"} {
		if err := newLanguageRuntime(io.Discard).installSource([]byte(invalid)); err == nil {
			t.Fatalf("invalid definitions accepted: %q", invalid)
		}
	}
	failed := newLanguageRuntime(io.Discard)
	if err := failed.installSource([]byte("(x,x) = (1,2)\n")); err != nil {
		t.Fatal(err)
	}
	parsed, _ := parseRuntimeExpression("x")
	if _, err := failed.evaluate(context.Background(), parsed); err == nil {
		t.Fatal("failed conformal match defined x")
	}
}

func TestSystemMessageIOAndInputValues(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "messages.txt")
	if err := os.WriteFile(path, []byte("old"), 0o600); err != nil {
		t.Fatal(err)
	}
	i := New(platformsvc.NativeServices{})
	var stdout, stderr bytes.Buffer
	i.Error = &stderr
	expression := fmt.Sprintf("[Tofile %q \"a\",Tofile %q \"b\",Closefile %q,Appendfile %q,Tofile %q \"c\",Stdout \"out\",Stderr \"err\",Exit 7,Stdout \"never\"]", path, path, path, path, path)
	streamed, err := i.evaluateTo(context.Background(), expression, &stdout)
	if err != nil || !streamed {
		t.Fatalf("messages: streamed=%v err=%v", streamed, err)
	}
	content, _ := os.ReadFile(path)
	if string(content) != "abc" || stdout.String() != "out" || stderr.String() != "err" || !i.Repl.ExitRequested || i.Repl.ExitStatus != 7 {
		t.Fatalf("content=%q stdout=%q stderr=%q exit=%v/%d", content, stdout.String(), stderr.String(), i.Repl.ExitRequested, i.Repl.ExitStatus)
	}
	binaryInput, binaryOutput := filepath.Join(directory, "input.bin"), filepath.Join(directory, "output.bin")
	binary := []byte{0, 0xff, 0x80, 'x'}
	if err := os.WriteFile(binaryInput, binary, 0o600); err != nil {
		t.Fatal(err)
	}
	binaryInterpreter := New(platformsvc.NativeServices{})
	binaryExpression := fmt.Sprintf("[Tofileb %q (readb %q)]", binaryOutput, binaryInput)
	if _, err := binaryInterpreter.evaluateTo(context.Background(), binaryExpression, io.Discard); err != nil {
		t.Fatal(err)
	}
	written, _ := os.ReadFile(binaryOutput)
	if !bytes.Equal(written, binary) {
		t.Fatalf("binary output = %v, want %v", written, binary)
	}
	if _, err := binaryInterpreter.Evaluate(context.Background(), fmt.Sprintf("read %q", binaryInput)); err == nil {
		t.Fatal("text read accepted invalid UTF-8")
	}

	input := New(platformsvc.NativeServices{})
	input.Input = strings.NewReader("hello")
	value, err := input.Evaluate(context.Background(), "$- ++ $-")
	if err != nil || value != "hellohello" {
		t.Fatalf("shared stdin = %q, %v", value, err)
	}
	conflict := New(platformsvc.NativeServices{})
	conflict.Input = strings.NewReader("x")
	if _, err := conflict.Evaluate(context.Background(), "($-, $:-)"); err == nil {
		t.Fatal("mixed text and binary stdin accepted")
	}

	values := newLanguageRuntime(io.Discard)
	values.input = strings.NewReader("1\n|| ignored\n2+3\n")
	parsed, _ := parseRuntimeExpression("sum $+")
	result, err := values.evaluate(context.Background(), parsed)
	if err != nil {
		t.Fatal(err)
	}
	rendered, err := renderLanguage(context.Background(), result)
	if err != nil || rendered != "6" {
		t.Fatalf("sum $+ = %q, %v", rendered, err)
	}
}

func TestIncludeGraphExportsAliasesAndCycles(t *testing.T) {
	directory := t.TempDir()
	library := filepath.Join(directory, "miralib")
	if err := os.Mkdir(library, 0o700); err != nil {
		t.Fatal(err)
	}
	write := func(path, source string) {
		if err := os.WriteFile(path, []byte(source), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	write(filepath.Join(directory, "a.m"), "%export + -private\npublic = 41\nprivate = 99\n")
	write(filepath.Join(directory, "b.m"), "%export \"a\" +\n%include \"a\"\nb = public+1\n")
	write(filepath.Join(library, "angle.m"), "angle = 7\n")
	runtime := newLanguageRuntime(io.Discard)
	runtime.libraryPath = library
	root := []byte("%include \"b\" rootpub/public\n%include <angle>\nanswer = rootpub+b+angle\n")
	if err := runtime.installIncludes(directory, root); err != nil {
		t.Fatal(err)
	}
	if err := runtime.installSource(root); err != nil {
		t.Fatal(err)
	}
	parsed, _ := parseRuntimeExpression("answer")
	value, err := runtime.evaluate(context.Background(), parsed)
	if err != nil {
		t.Fatal(err)
	}
	got, err := renderLanguage(context.Background(), value)
	if err != nil || got != "90" {
		t.Fatalf("answer = %q, %v", got, err)
	}
	if runtime.globals["private"] != nil || runtime.globals["public"] != nil {
		t.Fatal("private or pre-alias name escaped export boundary")
	}
	if provenance := runtime.provenance["rootpub"]; !strings.HasSuffix(provenance.Path, "b.m") || provenance.Original != "public" {
		t.Fatalf("provenance = %+v", provenance)
	}

	write(filepath.Join(directory, "cycle1.m"), "%include \"cycle2\"\nx=1\n")
	write(filepath.Join(directory, "cycle2.m"), "%include \"cycle1\"\ny=2\n")
	if err := newLanguageRuntime(io.Discard).installIncludes(directory, []byte("%include \"cycle1\"\n")); err == nil || !strings.Contains(err.Error(), "cyclic") {
		t.Fatalf("cycle error = %v", err)
	}
}

func TestParameterizedFreeModuleInstantiations(t *testing.T) {
	directory := t.TempDir()
	module := "%export pair\n%free { elem::type; zero::elem; combine::elem->elem->elem; }\npair x y = combine x y\n"
	if err := os.WriteFile(filepath.Join(directory, "parameterized.m"), []byte(module), 0o600); err != nil {
		t.Fatal(err)
	}
	source := []byte("%include \"parameterized\" {elem==num;zero=0;combine=+;} addpair/pair\n%include \"parameterized\" {elem==bool;zero=False;combine=&;} andpair/pair\nanswer = (addpair 2 3,andpair True False)\n")
	runtime := newLanguageRuntime(io.Discard)
	if err := runtime.installIncludes(directory, source); err != nil {
		t.Fatal(err)
	}
	if err := runtime.installSource(source); err != nil {
		t.Fatal(err)
	}
	parsed, _ := parseRuntimeExpression("answer")
	value, err := runtime.evaluate(context.Background(), parsed)
	if err != nil {
		t.Fatal(err)
	}
	got, err := renderLanguage(context.Background(), value)
	if err != nil || got != "(5,False)" {
		t.Fatalf("answer = %q, %v", got, err)
	}
	if runtime.provenance["addpair"].Instance == runtime.provenance["andpair"].Instance {
		t.Fatal("repeated parameterized modules reused a nominal instance")
	}
	for _, bad := range []string{"%include \"parameterized\" {elem==num;zero=0;}\n", "%include \"parameterized\" {elem==num;zero=False;combine=+;}\n", "%include \"parameterized\" {elem==num;zero=0;combine=+;extra=1;}\n"} {
		if err := newLanguageRuntime(io.Discard).installIncludes(directory, []byte(bad)); err == nil {
			t.Fatalf("invalid free instantiation accepted: %s", bad)
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
