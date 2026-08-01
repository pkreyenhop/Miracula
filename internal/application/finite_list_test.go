package application

import (
	"context"
	"strings"
	"testing"
)

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

func TestSemanticListsHaveNoMillionElementBoundary(t *testing.T) {
	i := New(nil)
	for expression, want := range map[string]string{
		"# [1..1000001]":                   "1000001",
		"sum [1..1000001]":                 "500001500001",
		"take 5 ([1..] ++ [99])":           "[1,2,3,4,5]",
		"take 3 (filter (>1000000) [1..])": "[1000001,1000002,1000003]",
		"and [False | n <- [1..]]":         "False",
	} {
		result, err := i.Evaluate(context.Background(), expression)
		if err != nil || result != want {
			t.Errorf("%s = %q, %v; want %q", expression, result, err, want)
		}
	}
}

func TestMillionElementReverseCanBeRendered(t *testing.T) {
	i := New(nil)
	result, err := i.Evaluate(context.Background(), "reverse [1..1000000]")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(result, "[1000000,999999,999998") || !strings.HasSuffix(result, ",3,2,1]") {
		t.Fatalf("unexpected reverse output boundaries: length=%d", len(result))
	}
}
