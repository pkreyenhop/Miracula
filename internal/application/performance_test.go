package application

import (
	"context"
	"fmt"
	"math"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"unsafe"

	"github.com/pkreyenhop/miracula/internal/platformsvc"
	"github.com/pkreyenhop/miracula/internal/semantics"
	"github.com/pkreyenhop/miracula/internal/syntaxfront"
)

const fibonacciSource = `fib n = 1, if n<=2
      = fib(n-1) + fib(n-2), otherwise
`

const patternFibonacciSource = `fib 0 = 0
fib 1 = 1
fib n = fib (n-1) + fib (n-2)
`

func fibonacciInterpreter(b testing.TB) *Interpreter {
	b.Helper()
	i := New(nil)
	if err := i.runtime().installSource([]byte(fibonacciSource)); err != nil {
		b.Fatal(err)
	}
	for index := 0; index < 1000; index++ {
		i.runtime().globals[fmt.Sprintf("libraryName%d", index)] = immediate(languageValue{kind: valueNumber, num: big.NewInt(int64(index))})
	}
	return i
}

func TestSmallIntegerOverflowChecks(t *testing.T) {
	for _, test := range []struct {
		operation func(int64, int64) (int64, bool)
		a, b      int64
		want      int64
		ok        bool
	}{
		{smallAdd, 20, 22, 42, true},
		{smallAdd, math.MaxInt64, 1, math.MinInt64, false},
		{smallSub, 20, 22, -2, true},
		{smallSub, math.MinInt64, 1, math.MaxInt64, false},
		{smallMul, 6, 7, 42, true},
		{smallMul, math.MaxInt64, 2, -2, false},
	} {
		got, ok := test.operation(test.a, test.b)
		if got != test.want || ok != test.ok {
			t.Errorf("operation(%d,%d) = (%d,%v), want (%d,%v)", test.a, test.b, got, ok, test.want, test.ok)
		}
	}
}

func TestScalarInstructionDisassembly(t *testing.T) {
	operators := []struct {
		source, want string
	}{
		{"+", "add"}, {"-", "subtract"}, {"*", "multiply"},
		{"=", "equal"}, {"~=", "not-equal"}, {"<", "less"},
		{"<=", "less-equal"}, {">", "greater"}, {">=", "greater-equal"},
	}
	for _, test := range operators {
		instruction, ok := compileFastInfixOperator(test.source)
		if !ok || instruction.disassemble() != test.want {
			t.Fatalf("instruction %q disassembled as %q, ok=%v", test.source, instruction.disassemble(), ok)
		}
	}
	if _, ok := compileFastInfixOperator("/"); ok {
		t.Fatal("unsupported operator compiled into the scalar instruction path")
	}
}

func BenchmarkForceEvaluatedThunk(b *testing.B) {
	thunk := immediate(languageValue{kind: valueNumber, small: 42})
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		value, err := thunk.force()
		if err != nil || value.small != 42 {
			b.Fatalf("force = %#v, %v", value, err)
		}
	}
}

type legacyMutexThunk struct {
	mu         sync.Mutex
	value      languageValue
	err        error
	eval       func() (languageValue, error)
	ready      bool
	evaluating bool
}

func TestSpecializedThunkStorageIsCompact(t *testing.T) {
	current, legacy := unsafe.Sizeof(languageThunk{}), unsafe.Sizeof(legacyMutexThunk{})
	t.Logf("specialized thunk=%d bytes, mutex thunk=%d bytes", current, legacy)
	if current >= legacy {
		t.Fatalf("specialized thunk uses %d bytes; mutex representation uses %d", current, legacy)
	}
}

//go:noinline
func forceLegacyMutexThunk(thunk *legacyMutexThunk) (languageValue, error) {
	thunk.mu.Lock()
	value, err := forceLanguageValue(thunk.value, nil)
	thunk.mu.Unlock()
	return value, err
}

func BenchmarkForceEvaluatedThunkLegacyMutex(b *testing.B) {
	thunk := legacyMutexThunk{value: languageValue{kind: valueNumber, small: 42}}
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		value, err := forceLegacyMutexThunk(&thunk)
		if err != nil || value.small != 42 {
			b.Fatalf("force = %#v, %v", value, err)
		}
	}
}

func TestPatternFibonacciUsesIntegerSpecialization(t *testing.T) {
	i := New(nil)
	if err := i.runtime().installSource([]byte(patternFibonacciSource)); err != nil {
		t.Fatal(err)
	}
	result, err := i.Evaluate(context.Background(), "fib 22")
	if err != nil || result != "17711" {
		t.Fatalf("fib 22 = %q, %v", result, err)
	}
	reductions, _ := i.runtime().statistics()
	if reductions > 20 {
		t.Fatalf("fib 22 used interpreted recursion: %d reductions", reductions)
	}
}

func BenchmarkEvaluateFib12(b *testing.B) {
	i := fibonacciInterpreter(b)
	b.ResetTimer()
	for range b.N {
		result, err := i.Evaluate(context.Background(), "fib 12")
		if err != nil || result != "144" {
			b.Fatalf("result=%q err=%v", result, err)
		}
	}
}

func BenchmarkEvaluateFib32(b *testing.B) {
	i := fibonacciInterpreter(b)
	b.ResetTimer()
	for range b.N {
		result, err := i.Evaluate(context.Background(), "fib 32")
		if err != nil || result != "2178309" {
			b.Fatalf("result=%q err=%v", result, err)
		}
	}
}

func BenchmarkEvaluatePatternFib32(b *testing.B) {
	i := New(nil)
	if err := i.runtime().installSource([]byte(patternFibonacciSource)); err != nil {
		b.Fatal(err)
	}
	b.ResetTimer()
	for range b.N {
		result, err := i.Evaluate(context.Background(), "fib 32")
		if err != nil || result != "2178309" {
			b.Fatalf("result=%q err=%v", result, err)
		}
	}
}

func BenchmarkColdStartup(b *testing.B) {
	directory := b.TempDir()
	script := filepath.Join(directory, "empty.m")
	if err := os.WriteFile(script, nil, 0o600); err != nil {
		b.Fatal(err)
	}
	library := filepath.Join(repositoryRoot(b), "lib", "miralib")
	b.ReportAllocs()
	for range b.N {
		if err := os.Remove(strings.TrimSuffix(script, ".m") + ".x"); err != nil && !os.IsNotExist(err) {
			b.Fatal(err)
		}
		interpreter := New(platformsvc.NativeServices{})
		interpreter.Config.LibraryPath = library
		interpreter.InitialScript = script
		if err := interpreter.Boot(); err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkWarmStartup(b *testing.B) {
	directory := b.TempDir()
	script := filepath.Join(directory, "empty.m")
	if err := os.WriteFile(script, nil, 0o600); err != nil {
		b.Fatal(err)
	}
	library := filepath.Join(repositoryRoot(b), "lib", "miralib")
	prime := New(platformsvc.NativeServices{})
	prime.Config.LibraryPath, prime.InitialScript = library, script
	if err := prime.Boot(); err != nil {
		b.Fatal(err)
	}
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		interpreter := New(platformsvc.NativeServices{})
		interpreter.Config.LibraryPath, interpreter.InitialScript = library, script
		if err := interpreter.Boot(); err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkParseAndTypecheckLargeSource(b *testing.B) {
	var source strings.Builder
	for index := 0; index < 1000; index++ {
		fmt.Fprintf(&source, "f%d x = x + %d\n", index, index)
	}
	bytes := []byte(source.String())
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		parsed := syntaxfront.Run(bytes)
		if len(parsed.Diagnostics) != 0 {
			b.Fatal(parsed.Diagnostics)
		}
		if _, err := semantics.Check(parsed.Script); err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkRepeatedREPLExpression(b *testing.B) {
	interpreter := New(nil)
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		result, err := interpreter.Evaluate(context.Background(), "sum [1..100]")
		if err != nil || result != "5050" {
			b.Fatalf("result=%q err=%v", result, err)
		}
	}
}

func BenchmarkLargeListSum(b *testing.B) {
	interpreter := New(nil)
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		result, err := interpreter.Evaluate(context.Background(), "sum [1..1000000]")
		if err != nil || result != "500000500000" {
			b.Fatalf("result=%q err=%v", result, err)
		}
	}
}

func BenchmarkLargeIntegerArithmetic(b *testing.B) {
	interpreter := New(nil)
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		result, err := interpreter.Evaluate(context.Background(), "2^256 + 2^128")
		if err != nil || result != "115792089237316195423570985008687907853610267032561502502920958615344897851392" {
			b.Fatalf("result=%q err=%v", result, err)
		}
	}
}

func BenchmarkLargeListReverse(b *testing.B) {
	interpreter := New(nil)
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		value, err := interpreter.evaluateValue(context.Background(), "reverse [1..1000000]")
		if err != nil || value.kind != valueList {
			b.Fatalf("value=%v err=%v", value.kind, err)
		}
		first, ok, err := value.list.at(context.Background(), 0)
		number, numberErr := numberValue(first)
		if err != nil || !ok || numberErr != nil || !number.IsInt64() || number.Int64() != 1000000 {
			b.Fatalf("first=%+v ok=%v err=%v", first, ok, err)
		}
	}
}

func BenchmarkInfiniteListFinitePrefix(b *testing.B) {
	interpreter := New(nil)
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		value, err := interpreter.evaluateValue(context.Background(), "take 100000 [1..]")
		if err != nil || value.kind != valueList {
			b.Fatalf("value=%v err=%v", value.kind, err)
		}
		last, ok, err := value.list.at(context.Background(), 99999)
		number, numberErr := numberValue(last)
		if err != nil || !ok || numberErr != nil || !number.IsInt64() || number.Int64() != 100000 {
			b.Fatalf("last=%+v ok=%v err=%v", last, ok, err)
		}
	}
}

func BenchmarkHigherOrderListPipeline(b *testing.B) {
	interpreter := New(nil)
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		result, err := interpreter.Evaluate(context.Background(), "sum (map (2*) (filter (>50000) [1..100000]))")
		if err != nil || result != "7500050000" {
			b.Fatalf("result=%q err=%v", result, err)
		}
	}
}

func BenchmarkPatternMatching(b *testing.B) {
	interpreter := New(nil)
	if err := interpreter.runtime().installSource([]byte("length [] = 0\nlength (x:xs) = 1 + length xs\n")); err != nil {
		b.Fatal(err)
	}
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		result, err := interpreter.Evaluate(context.Background(), "length [1..1000]")
		if err != nil || result != "1000" {
			b.Fatalf("result=%q err=%v", result, err)
		}
	}
}
