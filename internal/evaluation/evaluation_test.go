package evaluation

import (
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
func TestUnboundedSpine(t *testing.T) {
	var s Spine
	for i := 0; i < 10000; i++ {
		s.Push(Frame{})
	}
	if s.Depth() != 10000 {
		t.Fatal(s.Depth())
	}
}
