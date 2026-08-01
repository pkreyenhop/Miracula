package application

import (
	"fmt"

	"github.com/pkreyenhop/miracula/internal/platformsvc"
)

// WriteRC persists the subset of Miranda settings historically remembered
// between sessions. The one-line encoding is compatible with legacy mira.
func (i *Interpreter) WriteRC() error {
	if i.Config.RCPath == "" {
		return nil
	}
	flags := "hdve"
	if i.Config.List {
		flags += "l"
	}
	if i.Config.Recheck {
		flags += "r"
	}
	data := []byte(fmt.Sprintf("%s %d %d %d %s\n", flags, i.Config.HeapCells, i.Config.DictionaryCells, Release, i.Config.Editor))
	return platformsvc.AtomicReplace(i.Config.RCPath, data, 0o600)
}
