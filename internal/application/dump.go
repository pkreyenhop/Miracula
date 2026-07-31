package application

import (
	"github.com/pkreyenhop/miracula-go/internal/graphstore"
	"io"
)

func DumpGraph(w io.Writer, g graphstore.DumpGraph) error { return graphstore.EncodeGraph(w, g) }
