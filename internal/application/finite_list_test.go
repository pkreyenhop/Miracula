package application

import (
	"context"
	"math/big"
	"testing"
)

func TestFiniteListAcceptsExactLimit(t *testing.T) {
	items := []languageValue{
		{kind: valueNumber, num: big.NewInt(1)},
		{kind: valueNumber, num: big.NewInt(2)},
	}
	values, err := finiteList(context.Background(), listValue(items), len(items))
	if err != nil {
		t.Fatal(err)
	}
	if len(values) != len(items) {
		t.Fatalf("length = %d", len(values))
	}
}

func TestFiniteListRejectsLimitPlusOne(t *testing.T) {
	items := []languageValue{
		{kind: valueNumber, num: big.NewInt(1)},
		{kind: valueNumber, num: big.NewInt(2)},
		{kind: valueNumber, num: big.NewInt(3)},
	}
	_, err := finiteList(context.Background(), listValue(items), 2)
	if err == nil || err.Error() != "list output limit exceeded" {
		t.Fatalf("error = %v", err)
	}
}

func TestMillionElementSumBoundary(t *testing.T) {
	i := New(nil)
	result, err := i.Evaluate(context.Background(), "sum [1..1000000]")
	if err != nil {
		t.Fatal(err)
	}
	if result != "500000500000" {
		t.Fatalf("result = %q", result)
	}
}
