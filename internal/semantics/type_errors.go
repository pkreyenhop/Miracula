package semantics

import (
	"errors"
	"fmt"
	"sort"

	"github.com/pkreyenhop/miracula/internal/syntaxfront"
)

type TypeError struct {
	Message, File            string
	Definition               string
	Start, End, Line, Column int
}

func (e TypeError) Error() string { return e.Message }

type TypeErrors []TypeError

func (e TypeErrors) Error() string {
	if len(e) == 0 {
		return "type checking failed"
	}
	return e[0].Error()
}

// CheckAll recovers after a bad definition by removing that binding from the
// next checking pass, allowing independent later errors to surface. Removing
// the complete source item is important for malformed expressions: merely
// replacing RHS leaves continuation text that can be parsed as the same error.
func CheckAll(script syntaxfront.Script) TypeErrors {
	return CheckAllWithTypes(script, nil)
}

func CheckAllWithTypes(script syntaxfront.Script, external map[string]*Type) TypeErrors {
	working := script
	working.Items = semanticDefinitions(script)
	seen := map[string]bool{}
	var diagnostics TypeErrors
	for attempts := 0; attempts <= len(working.Items); attempts++ {
		_, err := CheckWithTypes(working, external)
		if err == nil {
			break
		}
		var typeErr TypeError
		if !errors.As(err, &typeErr) {
			break
		}
		key := fmt.Sprintf("%d:%s:%s", typeErr.Line, typeErr.Definition, typeErr.Message)
		if seen[key] {
			break
		}
		seen[key] = true
		diagnostics = append(diagnostics, typeErr)
		masked := false
		for index := range working.Items {
			item := working.Items[index]
			name, _, ok := definitionName(item.LHS)
			if item.Variant == "definition" && ok && (typeErr.Definition != "" && name == typeErr.Definition || typeErr.Definition == "" && item.Span.Line == typeErr.Line) {
				working.Items = append(working.Items[:index], working.Items[index+1:]...)
				masked = true
				break
			}
		}
		if !masked {
			break
		}
	}
	sort.SliceStable(diagnostics, func(left, right int) bool { return diagnostics[left].Line < diagnostics[right].Line })
	return diagnostics
}
