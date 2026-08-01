package graphstore

import (
	"bytes"
	"errors"
	"github.com/pkreyenhop/miracula/internal/protocol"
	"testing"
)

func TestHeapCheckpointAndRoots(t *testing.T) {
	h := NewHeap(2)
	r, e := h.Cons(1, protocol.Nil)
	if e != nil {
		t.Fatal(e)
	}
	c := h.Checkpoint()
	cell, _ := h.Cell(r)
	cell.Head = 2
	h.SetCell(r, cell)
	h.Restore(c)
	cell, _ = h.Cell(r)
	if cell.Head != 1 {
		t.Fatal(cell)
	}
	word := protocol.Word(r)
	g := h.Roots.Root(&word)
	var marked []protocol.Word
	h.Roots.MarkAll(func(v protocol.Word) { marked = append(marked, v) })
	g.Close()
	if len(marked) != 1 || marked[0] != word {
		t.Fatal(marked)
	}
}
func TestStringTable(t *testing.T) {
	var table StringTable
	a := table.Intern("alpha")
	if a >= 0 || table.Intern("alpha") != a || table.Resolve(a) != "alpha" {
		t.Fatal(a)
	}
	p := table.Privatize(a)
	if p == a || table.Resolve(p)[1:] != "lpha" {
		t.Fatal(p)
	}
}
func TestBignum(t *testing.T) {
	a, _ := ParseBignum("100000000000000000000", 10)
	b := NewBignum(3)
	if a.Mul(b).String() != "300000000000000000000" {
		t.Fatal(a.Mul(b))
	}
	if _, ok := a.Quo(NewBignum(0)); ok {
		t.Fatal("division by zero")
	}
}
func TestResources(t *testing.T) {
	var table ResourceTable
	stream := NewStream(bytes.NewBufferString("x"), nil, nil)
	id := table.RegisterStream(stream)
	got, e := table.ResolveStream(id)
	if e != nil {
		t.Fatal(e)
	}
	b, e := got.ReadByte()
	if e != nil || b != 'x' {
		t.Fatal(b, e)
	}
	if e = table.CloseStream(id); e != nil {
		t.Fatal(e)
	}
	if _, e = table.ResolveStream(id); !errors.Is(e, ErrResourceClosed) {
		t.Fatal(e)
	}
}
