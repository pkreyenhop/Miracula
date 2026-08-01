package application

import (
	"fmt"
	"sort"
	"strings"

	"github.com/pkreyenhop/miracula/internal/semantics"
	"github.com/pkreyenhop/miracula/internal/syntaxfront"
)

type Diagnostic struct {
	Severity   string
	Phase      string
	File       string
	Span       syntaxfront.Span
	Definition string
	Message    string
	Notes      []string
	Order      int
}

type DiagnosticSet []Diagnostic

func (set DiagnosticSet) Error() string {
	if len(set) == 0 {
		return "compilation failed"
	}
	lines := make([]string, 0, len(set))
	for _, diagnostic := range set {
		lines = append(lines, fmt.Sprintf("%s:%d:%d: %s", diagnostic.File, diagnostic.Span.Line, diagnostic.Span.Column, diagnostic.Message))
	}
	return strings.Join(lines, "\n")
}

func (set DiagnosticSet) As(target any) bool {
	switch result := target.(type) {
	case *semantics.TypeErrors:
		*result = nil
		for _, diagnostic := range set {
			if diagnostic.Phase == "type" {
				*result = append(*result, semantics.TypeError{Message: diagnostic.Message, File: diagnostic.File, Definition: diagnostic.Definition, Start: diagnostic.Span.Start, End: diagnostic.Span.End, Line: diagnostic.Span.Line, Column: diagnostic.Span.Column})
			}
		}
		return len(*result) != 0
	case *SourceValidationErrors:
		*result = nil
		for _, diagnostic := range set {
			if diagnostic.Phase == "name" {
				*result = append(*result, SourceValidationError{Path: diagnostic.File, Line: diagnostic.Span.Line, Name: strings.TrimPrefix(diagnostic.Message, "undefined name ")})
			}
		}
		return len(*result) != 0
	}
	return false
}

func stableDiagnostics(diagnostics DiagnosticSet) DiagnosticSet {
	sort.SliceStable(diagnostics, func(left, right int) bool {
		if diagnostics[left].Order != diagnostics[right].Order {
			return diagnostics[left].Order < diagnostics[right].Order
		}
		if diagnostics[left].File != diagnostics[right].File {
			return diagnostics[left].File < diagnostics[right].File
		}
		if diagnostics[left].Span.Line != diagnostics[right].Span.Line {
			return diagnostics[left].Span.Line < diagnostics[right].Span.Line
		}
		return diagnostics[left].Span.Column < diagnostics[right].Span.Column
	})
	return diagnostics
}

func sourceDiagnostic(phase, fallback string, source syntaxfront.Source, raw syntaxfront.Diagnostic, order int) Diagnostic {
	file, span := raw.File, raw.Span
	if file == "" {
		file = fallback
	}
	if raw.File == "" && span.Line > 0 && span.Line <= len(source.Origins) {
		origin := source.Origins[span.Line-1]
		if origin.File != "" {
			file, span.Line = origin.File, origin.Line
		}
	}
	if span.Column == 0 {
		span.Column = 1
	}
	return Diagnostic{Severity: raw.Severity, Phase: phase, File: file, Span: span, Message: raw.Message, Order: order}
}

func typeDiagnostics(fallback string, source syntaxfront.Source, typeErrors semantics.TypeErrors, order int) DiagnosticSet {
	diagnostics := make(DiagnosticSet, 0, len(typeErrors))
	for index, typeErr := range typeErrors {
		file, line := fallback, typeErr.Line
		if line > 0 && line <= len(source.Origins) {
			origin := source.Origins[line-1]
			if origin.File != "" {
				file, line = origin.File, origin.Line
			}
		}
		diagnostics = append(diagnostics, Diagnostic{Severity: "error", Phase: "type", File: file, Span: syntaxfront.Span{Start: typeErr.Start, End: typeErr.End, Line: line, Column: max(1, typeErr.Column)}, Definition: typeErr.Definition, Message: typeErr.Message, Order: order + index})
	}
	return diagnostics
}
