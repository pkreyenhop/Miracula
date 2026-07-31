package graphstore

import (
	"encoding/json"
	"io"
)

func EncodeGraph(w io.Writer, graph DumpGraph) error { return json.NewEncoder(w).Encode(graph) }
func DecodeGraph(r io.Reader) (DumpGraph, error) {
	var graph DumpGraph
	e := json.NewDecoder(r).Decode(&graph)
	return graph, e
}
