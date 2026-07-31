package syntaxfront

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type Position struct{ Line, Column int }
type Source struct {
	Bytes      []byte
	LineStarts []int
	Literate   bool
}

func NewSource(raw []byte, literateName bool) Source {
	b := append([]byte(nil), raw...)
	lit := literateName || (len(b) > 0 && b[0] == '>')
	if lit {
		blankProse(b)
	}
	starts := []int{0}
	for i, v := range b {
		if v == '\n' {
			starts = append(starts, i+1)
		}
	}
	return Source{b, starts, lit}
}

// LoadSource expands source-local %insert directives recursively. Includes
// remain module declarations and are owned by the semantic/module phase.
func LoadSource(path string) (Source, []Diagnostic) {
	bytes, diagnostics := loadSource(path, map[string]bool{})
	return NewSource(bytes, strings.HasSuffix(path, ".lit.m")), diagnostics
}

func loadSource(path string, active map[string]bool) ([]byte, []Diagnostic) {
	absolute, err := filepath.Abs(path)
	if err != nil {
		return nil, []Diagnostic{{Severity: "error", Message: err.Error(), File: path}}
	}
	if active[absolute] {
		return nil, []Diagnostic{{Severity: "error", Message: "recursive insert", File: path}}
	}
	raw, err := os.ReadFile(absolute)
	if err != nil {
		return nil, []Diagnostic{{Severity: "error", Message: "insert file not found", File: path}}
	}
	active[absolute] = true
	defer delete(active, absolute)
	var output []byte
	var diagnostics []Diagnostic
	lines := strings.SplitAfter(string(raw), "\n")
	offset := 0
	for lineIndex, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "%insert") {
			directive, ok := ParseDirective(strings.TrimSuffix(trimmed, "\n"))
			if !ok || directive.Variant != "insert" {
				diagnostics = append(diagnostics, Diagnostic{"error", "invalid insert directive", path, Span{offset, offset + len(line), lineIndex + 1, 1}})
			} else {
				insertedPath := filepath.Join(filepath.Dir(absolute), directive.Path)
				inserted, nested := loadSource(insertedPath, active)
				output = append(output, inserted...)
				diagnostics = append(diagnostics, nested...)
			}
		} else {
			output = append(output, line...)
		}
		offset += len(line)
	}
	return output, diagnostics
}

func blankProse(b []byte) {
	for start := 0; start < len(b); {
		end := start
		for end < len(b) && b[end] != '\n' {
			end++
		}
		if b[start] == '>' {
			b[start] = ' '
		} else {
			for i := start; i < end; i++ {
				b[i] = ' '
			}
		}
		start = end + 1
	}
}
func (s Source) Position(offset int) Position {
	if offset < 0 {
		offset = 0
	}
	if offset > len(s.Bytes) {
		offset = len(s.Bytes)
	}
	line := sort.Search(len(s.LineStarts), func(i int) bool { return s.LineStarts[i] > offset })
	if line == 0 {
		line = 1
	}
	start := s.LineStarts[line-1]
	column := 1
	for _, b := range s.Bytes[start:offset] {
		if b == '\t' {
			column = ((column-1)/8+1)*8 + 1
		} else {
			column++
		}
	}
	return Position{line, column}
}
