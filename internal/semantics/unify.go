package semantics

import (
	"fmt"
	"strings"
)

type TypeKind uint8

const (
	TypeVariable TypeKind = iota
	TypeNamed
	TypeArrow
	TypeList
	TypeTuple
	TypeApply
)

type Type struct {
	Kind     TypeKind
	ID       int
	Name     string
	From, To *Type
	Items    []*Type
}
type Substitution map[int]*Type

func Resolve(t *Type, s Substitution) *Type {
	for t != nil && t.Kind == TypeVariable {
		next, ok := s[t.ID]
		if !ok {
			break
		}
		t = next
	}
	return t
}

func DeepResolve(t *Type, s Substitution) *Type {
	t = Resolve(t, s)
	if t == nil {
		return nil
	}
	result := *t
	result.From = DeepResolve(t.From, s)
	result.To = DeepResolve(t.To, s)
	result.Items = make([]*Type, len(t.Items))
	for index := range t.Items {
		result.Items[index] = DeepResolve(t.Items[index], s)
	}
	return &result
}
func Unify(a, b *Type, s Substitution) error {
	a, b = Resolve(a, s), Resolve(b, s)
	if a == nil || b == nil {
		return fmt.Errorf("type mismatch")
	}
	if a.Kind == TypeVariable {
		if b.Kind == TypeVariable && a.ID == b.ID {
			return nil
		}
		if occurs(a.ID, b, s) {
			return fmt.Errorf("infinite type")
		}
		s[a.ID] = b
		return nil
	}
	if b.Kind == TypeVariable {
		return Unify(b, a, s)
	}
	if a.Kind != b.Kind || a.Name != b.Name || len(a.Items) != len(b.Items) {
		return fmt.Errorf("cannot unify %s with %s", FormatType(a), FormatType(b))
	}
	if a.From != nil {
		if e := Unify(a.From, b.From, s); e != nil {
			return e
		}
		return Unify(a.To, b.To, s)
	}
	for i := range a.Items {
		if e := Unify(a.Items[i], b.Items[i], s); e != nil {
			return e
		}
	}
	return nil
}

func FormatType(t *Type) string {
	return formatType(t, map[int]string{}, new(int))
}

func formatType(t *Type, variables map[int]string, next *int) string {
	if t == nil {
		return "?"
	}
	if t.Kind == TypeVariable {
		name, ok := variables[t.ID]
		if !ok {
			(*next)++
			name = "*" + strings.Repeat("*", *next-1)
			variables[t.ID] = name
		}
		return name
	}
	switch t.Kind {
	case TypeNamed:
		return t.Name
	case TypeArrow:
		left := formatType(t.From, variables, next)
		if t.From != nil && t.From.Kind == TypeArrow {
			left = "(" + left + ")"
		}
		return left + "->" + formatType(t.To, variables, next)
	case TypeList:
		if len(t.Items) == 1 {
			return "[" + formatType(t.Items[0], variables, next) + "]"
		}
	case TypeTuple:
		parts := make([]string, len(t.Items))
		for index := range t.Items {
			parts[index] = formatType(t.Items[index], variables, next)
		}
		return "(" + strings.Join(parts, ",") + ")"
	case TypeApply:
		parts := make([]string, len(t.Items)+1)
		parts[0] = t.Name
		for index := range t.Items {
			part := formatType(t.Items[index], variables, next)
			if t.Items[index].Kind == TypeArrow {
				part = "(" + part + ")"
			}
			parts[index+1] = part
		}
		return strings.Join(parts, " ")
	}
	return "?"
}

func occurs(id int, value *Type, substitutions Substitution) bool {
	value = Resolve(value, substitutions)
	if value == nil {
		return false
	}
	if value.Kind == TypeVariable {
		return value.ID == id
	}
	if occurs(id, value.From, substitutions) || occurs(id, value.To, substitutions) {
		return true
	}
	for _, item := range value.Items {
		if occurs(id, item, substitutions) {
			return true
		}
	}
	return false
}
