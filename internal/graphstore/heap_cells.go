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
var ErrInvalidNodeTag = errors.New("invalid node tag")

type Heap struct {
	cells        []Cell
	live         []bool
	free         []protocol.CellRef
	Roots        Registry
	forceCollect bool
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
	if tag > protocol.NodeTypeCons {
		return 0, ErrInvalidNodeTag
	}
	if h.forceCollect || len(h.free) == 0 {
		h.Collect(head, tail)
	}
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

// SetForceCollect makes every allocation collect first. All live Go locals
// other than the new cell's head and tail must be registered in Roots.
func (h *Heap) SetForceCollect(enabled bool) { h.forceCollect = enabled }

// Collect reclaims every cell unreachable from registered roots and extra
// values. It is iterative so deep Miranda graphs do not consume the Go stack.
func (h *Heap) Collect(extra ...Word) int {
	marked := make([]bool, len(h.live))
	stack := append([]Word(nil), extra...)
	h.Roots.MarkAll(func(value protocol.Word) { stack = append(stack, value) })
	for len(stack) != 0 {
		value := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		ref, ok := protocol.CellRefOf(value)
		if !ok {
			continue
		}
		index := int(ref) - int(protocol.AtomLimit)
		if index < 0 || index >= len(h.live) || !h.live[index] || marked[index] {
			continue
		}
		marked[index] = true
		cell := h.cells[int(ref)]
		stack = append(stack, cell.Head, cell.Tail)
	}
	reclaimed := 0
	for index, live := range h.live {
		if live && !marked[index] {
			h.live[index] = false
			h.cells[int(protocol.AtomLimit)+index] = Cell{}
			h.free = append(h.free, protocol.CellRef(uint32(int(protocol.AtomLimit)+index)))
			reclaimed++
		}
	}
	return reclaimed
}

func (h *Heap) LiveCount() int {
	count := 0
	for _, live := range h.live {
		if live {
			count++
		}
	}
	return count
}
func (h *Heap) Capacity() int { return len(h.live) }

func (h *Heap) Validate() error {
	free := make(map[protocol.CellRef]bool, len(h.free))
	for _, ref := range h.free {
		index := int(ref) - int(protocol.AtomLimit)
		if index < 0 || index >= len(h.live) || h.live[index] || free[ref] {
			return errors.New("heap free-list invariant violated")
		}
		free[ref] = true
	}
	if len(free)+h.LiveCount() != len(h.live) {
		return errors.New("heap accounting invariant violated")
	}
	return nil
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
