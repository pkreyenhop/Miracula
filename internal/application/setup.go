package application

import (
	"errors"
	"github.com/pkreyenhop/miracula-go/internal/graphstore"
	"github.com/pkreyenhop/miracula-go/internal/semantics"
)

var ErrAlreadySetup = errors.New("interpreter already set up")

func (i *Interpreter) Setup() error {
	if i.Heap == nil || i.Config.HeapCells <= 0 {
		return errors.New("invalid heap configuration")
	}
	if i.Programs != nil {
		return ErrAlreadySetup
	}
	if i.Config.HeapCells != i.Heap.Capacity() {
		i.Heap = graphstore.NewHeap(i.Config.HeapCells)
		i.Evaluator.Heap = i.Heap
	}
	i.Programs = map[string]*semantics.Program{}
	i.Repl.Prompt = i.Config.Prompt
	return nil
}
