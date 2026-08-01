package evaluation

import (
	"context"
	"errors"
	"github.com/pkreyenhop/miracula-go/internal/graphstore"
	"github.com/pkreyenhop/miracula-go/internal/protocol"
	"testing"
)

func TestCombinators(t *testing.T) {
	e := Evaluator{Heap: graphstore.NewHeap(16)}
	v, err := e.Apply(protocol.ValueComb(protocol.CombPLUS), protocol.ValueImm(2), protocol.ValueImm(3))
	if err != nil || v.ToRaw() != 5 {
		t.Fatal(v, err)
	}
	_, err = e.Apply(protocol.ValueComb(protocol.CombINTDIV), protocol.ValueImm(1), protocol.ValueImm(0))
	if !errors.Is(err, ErrDivisionByZero) {
		t.Fatal(err)
	}
}

func TestGraphReductionComputesArithmetic(t *testing.T) {
	heap := graphstore.NewHeap(32)
	left, _ := heap.Make(protocol.NodeInteger, 7, 0)
	right, _ := heap.Make(protocol.NodeInteger, -3, 0)
	first, _ := heap.Make(protocol.NodeApplication, protocol.CombinatorWord(protocol.CombINTDIV), protocol.Word(left))
	root, _ := heap.Make(protocol.NodeApplication, protocol.Word(first), protocol.Word(right))
	evaluator := Evaluator{Heap: heap}
	result, err := evaluator.Reduce(context.Background(), protocol.ValueCell(root))
	if err != nil {
		t.Fatal(err)
	}
	cell, ok := heap.Cell(protocol.CellRef(result.ToRaw()))
	if !ok || cell.Tag != protocol.NodeInteger || cell.Head != -3 {
		t.Fatalf("%+v, %v", cell, ok)
	}
}

func TestGraphReductionCancellation(t *testing.T) {
	heap := graphstore.NewHeap(20000)
	value := protocol.CombinatorWord(protocol.CombI)
	for i := 0; i < 10000; i++ {
		ref, err := heap.Make(protocol.NodeApplication, value, protocol.Nil)
		if err != nil {
			t.Fatal(err)
		}
		value = protocol.Word(ref)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := (&Evaluator{Heap: heap}).Reduce(ctx, protocol.ValueFromRaw(value))
	if !errors.Is(err, protocol.ErrInterrupted) {
		t.Fatal(err)
	}
}

func TestGraphCombinatorsAndListPrimitives(t *testing.T) {
	heap := graphstore.NewHeap(128)
	evaluator := Evaluator{Heap: heap}
	integer := func(value int64) protocol.Word {
		ref, err := heap.Make(protocol.NodeInteger, protocol.Word(value), 0)
		if err != nil {
			t.Fatal(err)
		}
		return protocol.Word(ref)
	}
	apply := func(function protocol.Word, arguments ...protocol.Word) protocol.Word {
		for _, argument := range arguments {
			ref, err := heap.Make(protocol.NodeApplication, function, argument)
			if err != nil {
				t.Fatal(err)
			}
			function = protocol.Word(ref)
		}
		return function
	}
	// B (+ 1) (* 2) 10 == 21.
	plusOne := apply(protocol.CombinatorWord(protocol.CombPLUS), integer(1))
	timesTwo := apply(protocol.CombinatorWord(protocol.CombTIMES), integer(2))
	root := apply(protocol.CombinatorWord(protocol.CombB), plusOne, timesTwo, integer(10))
	result, err := evaluator.Reduce(context.Background(), protocol.ValueFromRaw(root))
	if err != nil {
		t.Fatal(err)
	}
	cell, _ := heap.Cell(protocol.CellRef(result.ToRaw()))
	if cell.Head != 21 {
		t.Fatalf("B result: %+v", cell)
	}
	listTail, _ := heap.Cons(integer(2), protocol.Nil)
	listHead, _ := heap.Cons(integer(1), protocol.Word(listTail))
	length := apply(protocol.CombinatorWord(protocol.CombLENGTH), protocol.Word(listHead))
	result, err = evaluator.Reduce(context.Background(), protocol.ValueFromRaw(length))
	if err != nil {
		t.Fatal(err)
	}
	cell, _ = heap.Cell(protocol.CellRef(result.ToRaw()))
	if cell.Head != 2 {
		t.Fatalf("length result: %+v", cell)
	}
	text, err := evaluator.Render(context.Background(), protocol.ValueFromRaw(protocol.Word(listHead)), 10)
	if err != nil || text != "[1,2]" {
		t.Fatalf("render = %q, %v", text, err)
	}
}
func TestUnboundedSpine(t *testing.T) {
	var s Spine
	for i := 0; i < 10000; i++ {
		s.Push(Frame{})
	}
	if s.Depth() != 10000 {
		t.Fatal(s.Depth())
	}
}
