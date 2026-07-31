package semantics

import "testing"

func TestUnify(t *testing.T) {
	v := &Type{Kind: TypeVariable, ID: 0}
	n := &Type{Kind: TypeNamed, Name: "num"}
	s := Substitution{}
	if e := Unify(v, n, s); e != nil || Resolve(v, s) != n {
		t.Fatal(e)
	}
}
func TestSymbolsAndDependencies(t *testing.T) {
	var table SymbolTable
	a := table.Intern("a")
	if table.Intern("a") != a {
		t.Fatal("not interned")
	}
	order, e := TopologicalOrder(map[string][]string{"b": {"a"}, "a": {}})
	if e != nil || len(order) != 2 || order[0] != "a" {
		t.Fatal(order, e)
	}
}
