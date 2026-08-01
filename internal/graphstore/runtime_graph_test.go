package graphstore

import (
	"bytes"
	"errors"
	"github.com/pkreyenhop/miracula/internal/protocol"
	"io"
	"testing"
)

func TestFloorDivisionAndModuloLaws(t *testing.T) {
	tests := []struct{ n, d, q, r int64 }{
		{7, 3, 2, 1}, {-7, 3, -3, 2}, {7, -3, -3, -2}, {-7, -3, 2, -1},
	}
	for _, test := range tests {
		q, r, ok := NewBignum(test.n).DivMod(NewBignum(test.d))
		if !ok || q.String() != NewBignum(test.q).String() || r.String() != NewBignum(test.r).String() {
			t.Errorf("%d divMod %d = %v, %v, %v", test.n, test.d, q, r, ok)
		}
	}
}

func TestCollectorPreservesRootedGraphAndReclaimsGarbage(t *testing.T) {
	heap := NewHeap(4)
	tail, _ := heap.Cons(2, protocol.Nil)
	head, _ := heap.Cons(1, protocol.Word(tail))
	garbage, _ := heap.Cons(99, protocol.Nil)
	root := protocol.Word(head)
	guard := heap.Roots.Root(&root)
	defer guard.Close()
	if reclaimed := heap.Collect(); reclaimed != 1 {
		t.Fatalf("reclaimed %d cells", reclaimed)
	}
	if _, ok := heap.Cell(head); !ok {
		t.Fatal("root was reclaimed")
	}
	if _, ok := heap.Cell(tail); !ok {
		t.Fatal("reachable tail was reclaimed")
	}
	if _, ok := heap.Cell(garbage); ok {
		t.Fatal("garbage survived")
	}
	if err := heap.Validate(); err != nil {
		t.Fatal(err)
	}
}

func TestForcedCollectionNeedsExplicitRoots(t *testing.T) {
	heap := NewHeap(3)
	heap.SetForceCollect(true)
	root := protocol.Nil
	guard := heap.Roots.Root(&root)
	defer guard.Close()
	for i := 0; i < 100; i++ {
		ref, err := heap.Cons(protocol.Word(i), root)
		if err != nil {
			t.Fatal(err)
		}
		root = protocol.Word(ref)
		if i >= 2 {
			rootCell, _ := heap.Cell(ref)
			rootCell.Tail = protocol.Nil
			heap.SetCell(ref, rootCell)
		}
	}
	if err := heap.Validate(); err != nil {
		t.Fatal(err)
	}
}

type countCloser struct{ closes int }

func (c *countCloser) Close() error { c.closes++; return nil }

func TestResourceIDsAreNotReusedAfterReset(t *testing.T) {
	var table ResourceTable
	firstCloser := new(countCloser)
	first := table.RegisterStream(NewStream(nil, io.Discard, firstCloser))
	table.Reset()
	second := table.RegisterStream(NewStream(nil, io.Discard, nil))
	if first == second {
		t.Fatalf("resource ID %d was reused", first)
	}
	if firstCloser.closes != 1 {
		t.Fatalf("resource closed %d times", firstCloser.closes)
	}
	if _, err := table.ResolveStream(first); !errors.Is(err, ErrResourceMissing) {
		t.Fatal(err)
	}
}

func TestCheckpointRestoreClosesNewResources(t *testing.T) {
	var table ResourceTable
	checkpoint := table.Checkpoint()
	closer := new(countCloser)
	id := table.RegisterStream(NewStream(bytes.NewReader(nil), nil, closer))
	table.Restore(checkpoint)
	if closer.closes != 1 {
		t.Fatalf("resource closed %d times", closer.closes)
	}
	if _, err := table.ResolveStream(id); !errors.Is(err, ErrResourceMissing) {
		t.Fatal(err)
	}
}
