package application

import (
	"context"
	"fmt"
	"math"
	"math/big"
	"testing"
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
