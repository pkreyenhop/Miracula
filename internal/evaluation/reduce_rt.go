package evaluation

import (
	"github.com/pkreyenhop/miracula/internal/graphstore"
	"io"
)

type Runtime struct {
	Resources      graphstore.ResourceTable
	Stdout, Stderr io.Writer
}
