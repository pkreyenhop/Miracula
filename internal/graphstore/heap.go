package graphstore

import "github.com/pkreyenhop/miracula-go/internal/protocol"

func H(heap *Heap, value protocol.Word) protocol.Word {
	r, ok := protocol.CellRefOf(value)
	if !ok {
		return 0
	}
	head, _ := heap.Head(r)
	return head
}
func T(heap *Heap, value protocol.Word) protocol.Word {
	r, ok := protocol.CellRefOf(value)
	if !ok {
		return 0
	}
	tail, _ := heap.Tail(r)
	return tail
}
func GetTag(heap *Heap, value protocol.Word) (protocol.NodeTag, bool) {
	r, ok := protocol.CellRefOf(value)
	if !ok {
		return 0, false
	}
	return heap.Tag(r)
}
func Cons(heap *Heap, head, tail protocol.Word) (protocol.Word, error) {
	r, e := heap.Cons(head, tail)
	return protocol.Word(r), e
}
func Make(heap *Heap, tag protocol.NodeTag, head, tail protocol.Word) (protocol.Word, error) {
	r, e := heap.Make(tag, head, tail)
	return protocol.Word(r), e
}
