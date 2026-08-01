package application

import (
	"fmt"
	"github.com/pkreyenhop/miracula-go/internal/semantics"
	"github.com/pkreyenhop/miracula-go/internal/syntaxfront"
	"os"
	"path/filepath"
)

func (i *Interpreter) LoadModule(path string) (semantics.Module, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return semantics.Module{}, err
	}
	return semantics.ParseModule(string(b)), nil
}

func (i *Interpreter) LoadProgram(path string) (*semantics.Program, error) {
	absolute, err := filepath.Abs(path)
	if err != nil {
		return nil, err
	}
	source, diagnostics := syntaxfront.LoadSource(absolute)
	if len(diagnostics) != 0 {
		return nil, fmt.Errorf("%s:%d:%d: %s", diagnostics[0].File, diagnostics[0].Span.Line, diagnostics[0].Span.Column, diagnostics[0].Message)
	}
	parsed := syntaxfront.Run(source.Bytes)
	if len(parsed.Diagnostics) != 0 {
		return nil, fmt.Errorf("%s:%d:%d: %s", absolute, parsed.Diagnostics[0].Span.Line, parsed.Diagnostics[0].Span.Column, parsed.Diagnostics[0].Message)
	}
	checkpoint := i.Heap.Checkpoint()
	program, err := semantics.Compile(parsed.Script, i.Heap)
	if err != nil {
		i.Heap.Restore(checkpoint)
		return nil, fmt.Errorf("compile %s: %w", absolute, err)
	}
	if i.Programs == nil {
		i.Programs = map[string]*semantics.Program{}
	}
	i.Programs[absolute] = program
	i.Scripts.Put(Script{Path: absolute, Source: append([]byte(nil), source.Bytes...)})
	i.Compiler.CurrentModule = absolute
	return program, nil
}
