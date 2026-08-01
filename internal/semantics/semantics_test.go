package semantics

import (
	"github.com/pkreyenhop/miracula-go/internal/graphstore"
	"github.com/pkreyenhop/miracula-go/internal/syntaxfront"
	"testing"
)

func TestUnify(t *testing.T) {
	v := &Type{Kind: TypeVariable, ID: 0}
	n := &Type{Kind: TypeNamed, Name: "num"}
	s := Substitution{}
	if e := Unify(v, n, s); e != nil || Resolve(v, s) != n {
		t.Fatal(e)
	}
}

func TestOccursCheckRejectsInfiniteType(t *testing.T) {
	variable := &Type{Kind: TypeVariable, ID: 7}
	function := &Type{Kind: TypeArrow, From: variable, To: &Type{Kind: TypeNamed, Name: "num"}}
	if err := Unify(variable, function, Substitution{}); err == nil {
		t.Fatal("infinite type accepted")
	}
}

func TestCompileTypedDefinitionsAndLowerRoots(t *testing.T) {
	parsed := syntaxfront.Run([]byte("id x = x\none = 1\n"))
	if len(parsed.Diagnostics) != 0 {
		t.Fatal(parsed.Diagnostics)
	}
	heap := graphstore.NewHeap(64)
	program, err := Compile(parsed.Script, heap)
	if err != nil {
		t.Fatal(err)
	}
	if len(program.Definitions) != 2 || len(program.Order) != 2 {
		t.Fatalf("%+v", program)
	}
	for _, definition := range program.Definitions {
		if definition.Root == 0 || definition.Type == nil {
			t.Fatalf("incomplete definition: %+v", definition)
		}
	}
	if err := heap.Validate(); err != nil {
		t.Fatal(err)
	}
}

func TestCompileRollsBackHeapOnLoweringFailure(t *testing.T) {
	heap := graphstore.NewHeap(1)
	parsed := syntaxfront.Run([]byte("f = g 1\n"))
	before := heap.LiveCount()
	if _, err := Compile(parsed.Script, heap); err == nil {
		t.Fatal("expected heap exhaustion")
	}
	if heap.LiveCount() != before {
		t.Fatalf("heap was not rolled back: %d", heap.LiveCount())
	}
}

func TestRecursiveOrderAllowsMutualRecursion(t *testing.T) {
	order := RecursiveOrder(map[string][]string{"even": {"odd"}, "odd": {"even"}})
	if len(order) != 2 {
		t.Fatal(order)
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
