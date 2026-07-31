package application

import (
	"github.com/pkreyenhop/miracula-go/internal/semantics"
	"os"
)

func (i *Interpreter) LoadModule(path string) (semantics.Module, error) {
	b, e := os.ReadFile(path)
	if e != nil {
		return semantics.Module{}, e
	}
	return semantics.ParseModule(string(b)), nil
}
