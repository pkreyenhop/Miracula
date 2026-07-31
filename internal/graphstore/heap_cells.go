package graphstore

import (
	"errors"

	"github.com/pkreyenhop/miracula-go/internal/protocol"
)

type Word = protocol.Word
type Cell struct {
	Tag        protocol.NodeTag
	Head, Tail Word
}

var ErrHeapExhausted = errors.New("heap exhausted")

type Heap struct {
	cells []Cell
	live  []bool
	free  []protocol.CellRef
	Roots Registry
}

func NewHeap(capacity int) *Heap {
	if capacity < 1 {
		capacity = 1
	}
	h := &Heap{cells: make([]Cell, int(protocol.AtomLimit)+capacity), live: make([]bool, capacity)}
	for i := capacity - 1; i >= 0; i-- {
		h.free = append(h.free, protocol.CellRef(uint32(int(protocol.AtomLimit)+i)))
	}
	return h
}
func (h *Heap) Make(tag protocol.NodeTag, head, tail Word) (protocol.CellRef, error) {
	if len(h.free) == 0 {
		return 0, ErrHeapExhausted
	}
	last := len(h.free) - 1
	r := h.free[last]
	h.free = h.free[:last]
	i := int(r)
	h.cells[i] = Cell{tag, head, tail}
	h.live[i-int(protocol.AtomLimit)] = true
	return r, nil
}
func (h *Heap) Cons(head, tail Word) (protocol.CellRef, error) {
	return h.Make(protocol.NodeCons, head, tail)
}
func (h *Heap) Cell(r protocol.CellRef) (Cell, bool) {
	i := int(r)
	if i < int(protocol.AtomLimit) || i >= len(h.cells) || !h.live[i-int(protocol.AtomLimit)] {
		return Cell{}, false
	}
	return h.cells[i], true
}
func (h *Heap) SetCell(r protocol.CellRef, c Cell) bool {
	i := int(r)
	if i < int(protocol.AtomLimit) || i >= len(h.cells) || !h.live[i-int(protocol.AtomLimit)] {
		return false
	}
	h.cells[i] = c
	return true
}
func (h *Heap) Head(r protocol.CellRef) (Word, bool)            { c, ok := h.Cell(r); return c.Head, ok }
func (h *Heap) Tail(r protocol.CellRef) (Word, bool)            { c, ok := h.Cell(r); return c.Tail, ok }
func (h *Heap) Tag(r protocol.CellRef) (protocol.NodeTag, bool) { c, ok := h.Cell(r); return c.Tag, ok }

type Checkpoint struct {
	cells []Cell
	live  []bool
	free  []protocol.CellRef
}

func (h *Heap) Checkpoint() Checkpoint {
	return Checkpoint{append([]Cell(nil), h.cells...), append([]bool(nil), h.live...), append([]protocol.CellRef(nil), h.free...)}
}
func (h *Heap) Restore(c Checkpoint) {
	h.cells = append(h.cells[:0], c.cells...)
	h.live = append(h.live[:0], c.live...)
	h.free = append(h.free[:0], c.free...)
}
