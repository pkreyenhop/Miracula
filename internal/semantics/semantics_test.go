package semantics

import (
	"github.com/pkreyenhop/miracula/internal/graphstore"
	"github.com/pkreyenhop/miracula/internal/syntaxfront"
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

func TestCompileEnforcesDeclaredType(t *testing.T) {
	parsed := syntaxfront.Run([]byte("id :: *->*\nid x = x\n"))
	program, err := Compile(parsed.Script, graphstore.NewHeap(64))
	if err != nil {
		t.Fatal(err)
	}
	if got := FormatType(program.Definitions[0].Type); got != "*->*" {
		t.Fatalf("id type = %q", got)
	}

	parsed = syntaxfront.Run([]byte("bad :: num->num\nbad x = [x]\n"))
	if _, err = Compile(parsed.Script, graphstore.NewHeap(64)); err == nil {
		t.Fatal("inconsistent declaration accepted")
	}
}

func TestCompileSharesForwardReferenceTypes(t *testing.T) {
	parsed := syntaxfront.Run([]byte("first x = second x\nsecond y = y+1\n"))
	program, err := Compile(parsed.Script, graphstore.NewHeap(128))
	if err != nil {
		t.Fatal(err)
	}
	for _, definition := range program.Definitions {
		if got := FormatType(definition.Type); got != "num->num" {
			t.Fatalf("%s type = %q", definition.Name, got)
		}
	}
}

func TestCompileGeneralizesTopLevelBindings(t *testing.T) {
	parsed := syntaxfront.Run([]byte("id x = x\nboth = (id 1,id True)\n"))
	program, err := Compile(parsed.Script, graphstore.NewHeap(128))
	if err != nil {
		t.Fatal(err)
	}
	if got := FormatType(program.Definitions[0].Type); got != "*->*" {
		t.Fatalf("id type = %q", got)
	}
	if got := FormatType(program.Definitions[1].Type); got != "(num,bool)" {
		t.Fatalf("both type = %q", got)
	}
}

func TestCompileTypesParameterizedAlgebraicConstructors(t *testing.T) {
	parsed := syntaxfront.Run([]byte("tree * ::= Nilt | Node * (tree *) (tree *)\nleaf x = Node x Nilt Nilt\nsize Nilt = 0\nsize (Node a left right) = 1+size left+size right\n"))
	program, err := Check(parsed.Script)
	if err != nil {
		t.Fatal(err)
	}
	if got := FormatType(program.Definitions[0].Type); got != "*->tree *" {
		t.Fatalf("leaf type = %q", got)
	}
	if got := FormatType(program.Definitions[1].Type); got != "tree *->num" {
		t.Fatalf("size type = %q", got)
	}
}

func TestCompileExpandsTypeSynonyms(t *testing.T) {
	parsed := syntaxfront.Run([]byte("string == [char]\nplural :: string->string\nplural x = x++\"s\"\n"))
	program, err := Compile(parsed.Script, graphstore.NewHeap(128))
	if err != nil {
		t.Fatal(err)
	}
	if got := FormatType(program.Definitions[0].Type); got != "[char]->[char]" {
		t.Fatalf("plural type = %q", got)
	}
}

func TestCompileKeepsAbstractTypeNominalOutsideRepresentation(t *testing.T) {
	parsed := syntaxfront.Run([]byte("abstype stack\nwith empty :: stack\nstack == [num]\nempty = []\n"))
	program, err := Compile(parsed.Script, graphstore.NewHeap(128))
	if err != nil {
		t.Fatal(err)
	}
	if got := FormatType(program.Definitions[0].Type); got != "stack" {
		t.Fatalf("empty type = %q", got)
	}
}

func TestCompileChecksGuardsAcrossContinuationEquations(t *testing.T) {
	parsed := syntaxfront.Run([]byte("choose x = reverse x, if x < 1000\n         = x, otherwise\n"))
	if _, err := Compile(parsed.Script, graphstore.NewHeap(128)); err == nil {
		t.Fatal("guard/body type conflict accepted")
	}

	parsed = syntaxfront.Run([]byte("sign x = 2, if x < 0\n       = 0, if x = 0\n       = 1, otherwise\n"))
	program, err := Compile(parsed.Script, graphstore.NewHeap(128))
	if err != nil {
		t.Fatal(err)
	}
	if got := FormatType(program.Definitions[0].Type); got != "num->num" {
		t.Fatalf("sign type = %q", got)
	}
}

func TestCompileInfersRangesSectionsAndComprehensions(t *testing.T) {
	parsed := syntaxfront.Run([]byte("reciprocal = (1/)\nlengths xs = [#x|x<-xs]\nrange = [1,3..9]\n"))
	program, err := Check(parsed.Script)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"num->num", "[[*]]->[num]", "[num]"}
	for index, definition := range program.Definitions {
		if got := FormatType(definition.Type); got != want[index] {
			t.Fatalf("%s type = %q, want %q", definition.Name, got, want[index])
		}
	}
}

func TestCheckAllReportsIndependentTypeErrorsInSourceOrder(t *testing.T) {
	parsed := syntaxfront.Run([]byte("first x = reverse x, if x < 1\ngood x = x\nsecond x = x+1, if reverse x = []\n"))
	errors := CheckAll(parsed.Script)
	if len(errors) != 2 || errors[0].Line != 1 || errors[1].Line != 3 {
		t.Fatalf("errors = %+v", errors)
	}
}

func TestCompileRequiresMonomorphicScriptUseOfShow(t *testing.T) {
	parsed := syntaxfront.Run([]byte("bad x = show x\n"))
	if _, err := Check(parsed.Script); err == nil {
		t.Fatal("polymorphic show accepted without declaration")
	}
	parsed = syntaxfront.Run([]byte("good :: num->[char]\ngood x = show x\n"))
	if _, err := Check(parsed.Script); err != nil {
		t.Fatal(err)
	}
}

func TestCheckUsesImportedStandardTypes(t *testing.T) {
	types := DeclaredTypes([]byte("> fst :: (*,**)->*\n> reverse :: [*]->[*]\n"))
	parsed := syntaxfront.Run([]byte("first pair = fst pair\n"))
	program, err := CheckWithTypes(parsed.Script, types)
	if err != nil {
		t.Fatal(err)
	}
	if got := FormatType(program.Definitions[0].Type); got != "(*,**)->*" {
		t.Fatalf("first type = %q", got)
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
