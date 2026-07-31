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
	if a.Kind == TypeVariable {
		s[a.ID] = b
		return nil
	}
	if b.Kind == TypeVariable {
		s[b.ID] = a
		return nil
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
