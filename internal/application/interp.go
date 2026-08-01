package application

import (
	"github.com/pkreyenhop/miracula/internal/evaluation"
	"github.com/pkreyenhop/miracula/internal/graphstore"
	"github.com/pkreyenhop/miracula/internal/platformsvc"
	"github.com/pkreyenhop/miracula/internal/semantics"
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
	Repl          ReplSession
	Programs      map[string]*semantics.Program
	Scripts       ScriptStore
	InitialScript string
	language      *languageRuntime
	startupFailed bool
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
	i.Repl = ReplSession{}
	i.Programs = nil
	i.language = nil
	i.startupFailed = false
	i.Scripts = ScriptStore{}
	i.Evaluator = evaluation.Evaluator{Heap: i.Heap}
}
