package graphstore

import (
	"github.com/pkreyenhop/miracula-go/internal/protocol"
)

type DumpCell struct {
	ID    int    `json:"id"`
	Tag   string `json:"tag"`
	Head  any    `json:"head,omitempty"`
	Tail  any    `json:"tail,omitempty"`
	Value any    `json:"value,omitempty"`
	Name  string `json:"name,omitempty"`
}
type DumpGraph struct {
	Roots []int      `json:"roots"`
	Cells []DumpCell `json:"cells"`
}

func NodeTagName(tag protocol.NodeTag) string {
	names := []string{"atom", "double", "data_pair", "file_info", "type_variable", "integer", "constructor", "string_cons", "identifier", "application", "lambda", "cons", "tries", "label", "show", "start_read_values", "let", "letrec", "share", "lexer", "pair", "unicode", "type_cons"}
	if int(tag) >= len(names) {
		return "unknown"
	}
	return names[tag]
}
