package application

import (
	"github.com/pkreyenhop/miracula-go/internal/evaluation"
	"github.com/pkreyenhop/miracula-go/internal/graphstore"
	"github.com/pkreyenhop/miracula-go/internal/platformsvc"
	"github.com/pkreyenhop/miracula-go/internal/semantics"
	"io"
)

type Interpreter struct {
	Heap          *graphstore.Heap
	Strings       graphstore.StringTable
	Resources     graphstore.ResourceTable
	Symbols       semantics.SymbolTable
	Evaluator     evaluation.Evaluator
	Services      platformsvc.Services
	Config        Config
	Runtime       RuntimeState
	Compiler      CompilerState
	Input         io.Reader
	Output, Error io.Writer
}

func New(services platformsvc.Services) *Interpreter {
	heap := graphstore.NewHeap(125000)
	i := &Interpreter{Heap: heap, Services: services, Config: DefaultConfig()}
	i.Evaluator.Heap = heap
	return i
}
func (i *Interpreter) Reset() {
	i.Strings.Reset()
	i.Resources.Reset()
	i.Symbols = semantics.SymbolTable{}
	i.Runtime = RuntimeState{}
	i.Compiler = CompilerState{}
	i.Evaluator = evaluation.Evaluator{Heap: i.Heap}
}
