package syntaxfront

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type Position struct{ Line, Column int }
type Origin struct {
	File string
	Line int
}
type Source struct {
	Bytes      []byte
	LineStarts []int
	Literate   bool
	Origins    []Origin
}

func NewSource(raw []byte, literateName bool) Source {
	b := normalizeNroffUnderlining(raw)
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
	return Source{Bytes: b, LineStarts: starts, Literate: lit}
}

// LoadSource expands source-local %insert directives recursively. Includes
// remain module declarations and are owned by semantic module loading.
func LoadSource(path string) (Source, []Diagnostic) {
	bytes, origins, diagnostics := loadSource(path, map[string]bool{}, "")
	literate := strings.HasSuffix(path, ".lit.m") || len(bytes) > 0 && bytes[0] == '>'
	if literate {
		diagnostics = append(diagnostics, validateLiterateSeparation(bytes, path)...)
	}
	source := NewSource(bytes, literate)
	source.Origins = origins
	return source, diagnostics
}

func loadSource(path string, active map[string]bool, inheritedIndent string) ([]byte, []Origin, []Diagnostic) {
	absolute, err := filepath.Abs(path)
	if err != nil {
		return nil, nil, []Diagnostic{{Severity: "error", Message: err.Error(), File: path}}
	}
	if active[absolute] {
		return nil, nil, []Diagnostic{{Severity: "error", Message: "recursive insert", File: path}}
	}
	raw, err := os.ReadFile(absolute)
	if err != nil {
		return nil, nil, []Diagnostic{{Severity: "error", Message: "insert file not found", File: path}}
	}
	active[absolute] = true
	defer delete(active, absolute)
	var output []byte
	var origins []Origin
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
				indent := line[:len(line)-len(strings.TrimLeft(line, " \t"))]
				inserted, insertedOrigins, nested := loadSource(insertedPath, active, inheritedIndent+indent)
				output = append(output, inserted...)
				origins = append(origins, insertedOrigins...)
				diagnostics = append(diagnostics, nested...)
			}
		} else {
			if inheritedIndent != "" && strings.TrimSpace(line) != "" {
				line = inheritedIndent + line
			}
			output = append(output, line...)
			origins = append(origins, Origin{File: absolute, Line: lineIndex + 1})
		}
		offset += len(line)
	}
	return output, origins, diagnostics
}

func normalizeNroffUnderlining(raw []byte) []byte {
	result := make([]byte, 0, len(raw))
	for index := 0; index < len(raw); {
		if index+2 < len(raw) && raw[index] == '_' && raw[index+1] == '\b' {
			symbol := raw[index+2]
			if symbol == '>' {
				result = append(result, '>', '=')
			} else if symbol == '<' {
				result = append(result, '<', '=')
			} else {
				result = append(result, symbol)
			}
			index += 3
			continue
		}
		result = append(result, raw[index])
		index++
	}
	return result
}

func validateLiterateSeparation(raw []byte, path string) []Diagnostic {
	lines := strings.Split(string(raw), "\n")
	previousKind, blank := -1, true
	var diagnostics []Diagnostic
	for index, line := range lines {
		if strings.TrimSpace(line) == "" {
			blank = true
			continue
		}
		kind := 0
		if strings.HasPrefix(line, ">") {
			kind = 1
		}
		if previousKind >= 0 && kind != previousKind && !blank {
			diagnostics = append(diagnostics, Diagnostic{Severity: "error", Message: "literate narrative and formal text must be separated by a blank line", File: path, Span: Span{Line: index + 1, Column: 1}})
		}
		previousKind, blank = kind, false
	}
	return diagnostics
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
