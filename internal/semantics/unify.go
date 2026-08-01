package semantics

import "fmt"

type TypeKind uint8

const (
	TypeVariable TypeKind = iota
	TypeNamed
	TypeArrow
	TypeList
	TypeTuple
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
		return fmt.Errorf("type mismatch")
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
