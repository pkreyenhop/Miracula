package semantics

import (
	"fmt"
	"github.com/pkreyenhop/miracula-go/internal/graphstore"
	"github.com/pkreyenhop/miracula-go/internal/syntaxfront"
	"sort"
)

type TypedDefinition struct {
	Name       string
	Expression syntaxfront.Expr
	Type       *Type
	Root       int
}
type Program struct {
	Definitions []TypedDefinition
	Symbols     SymbolTable
	Order       []string
}

type inferState struct {
	next          int
	substitutions Substitution
	environment   map[string]*Type
}

func (s *inferState) fresh() *Type {
	value := &Type{Kind: TypeVariable, ID: s.next}
	s.next++
	return value
}

func Compile(script syntaxfront.Script, heap *graphstore.Heap) (*Program, error) {
	state := &inferState{substitutions: Substitution{}, environment: map[string]*Type{}}
	program := &Program{}
	graph := map[string][]string{}
	for _, definition := range script.Items {
		if definition.Variant != "definition" {
			continue
		}
		name, parameters, ok := definitionName(definition.LHS)
		if !ok {
			return nil, TypeError{Message: "invalid definition pattern", Line: definition.Span.Line, Column: definition.Span.Column}
		}
		_, exists := state.environment[name]
		if !exists {
			state.environment[name] = state.fresh()
			program.Symbols.Intern(name)
		}
		graph[name] = expressionNames(definition.RHS, nil)
		local := make(map[string]*Type, len(state.environment)+len(parameters))
		for key, value := range state.environment {
			local[key] = value
		}
		for _, parameter := range parameters {
			local[parameter] = state.fresh()
		}
		valueType, err := state.infer(definition.RHS, local)
		if err != nil {
			return nil, TypeError{Message: err.Error(), Line: definition.Span.Line, Column: definition.Span.Column}
		}
		for index := len(parameters) - 1; index >= 0; index-- {
			valueType = &Type{Kind: TypeArrow, From: local[parameters[index]], To: valueType}
		}
		if err = Unify(state.environment[name], valueType, state.substitutions); err != nil {
			return nil, err
		}
		if !exists {
			program.Definitions = append(program.Definitions, TypedDefinition{Name: name, Expression: definition.RHS, Type: Resolve(valueType, state.substitutions)})
		}
	}
	for name, deps := range graph {
		filtered := deps[:0]
		for _, dep := range deps {
			if _, ok := graph[dep]; ok && dep != name {
				filtered = append(filtered, dep)
			}
		}
		graph[name] = filtered
	}
	program.Order = RecursiveOrder(graph)
	roots, err := Lower(script, heap)
	if err != nil {
		return nil, err
	}
	for index := range program.Definitions {
		if index < len(roots) {
			program.Definitions[index].Root = roots[index]
		}
	}
	return program, nil
}

// RecursiveOrder is deterministic and permits mutually recursive SCCs. Names
// within an SCC are emitted lexically after their external dependencies.
func RecursiveOrder(graph map[string][]string) []string {
	names := make([]string, 0, len(graph))
	for name := range graph {
		names = append(names, name)
	}
	sort.Strings(names)
	state := map[string]uint8{}
	var order []string
	var visit func(string)
	visit = func(name string) {
		if state[name] != 0 {
			return
		}
		state[name] = 1
		dependencies := append([]string(nil), graph[name]...)
		sort.Strings(dependencies)
		for _, dependency := range dependencies {
			visit(dependency)
		}
		state[name] = 2
		order = append(order, name)
	}
	for _, name := range names {
		visit(name)
	}
	return order
}

func definitionName(expression syntaxfront.Expr) (string, []string, bool) {
	var params []string
	for expression.Variant == "application" {
		if expression.Arg.Variant == "name" {
			params = append([]string{expression.Arg.Text}, params...)
		} else {
			params = append([]string{fmt.Sprintf("$pattern%d", len(params))}, params...)
		}
		expression = *expression.Func
	}
	return expression.Text, params, expression.Variant == "name" && expression.Text != ""
}
func expressionNames(expression syntaxfront.Expr, out []string) []string {
	if expression.Variant == "name" {
		out = append(out, expression.Text)
	}
	if expression.Func != nil {
		out = expressionNames(*expression.Func, out)
	}
	if expression.Arg != nil {
		out = expressionNames(*expression.Arg, out)
	}
	if expression.Head != nil {
		out = expressionNames(*expression.Head, out)
	}
	if expression.Tail != nil {
		out = expressionNames(*expression.Tail, out)
	}
	for _, item := range expression.Items {
		out = expressionNames(item, out)
	}
	return out
}

func (s *inferState) infer(expression syntaxfront.Expr, environment map[string]*Type) (*Type, error) {
	switch expression.Variant {
	case "int", "float":
		return &Type{Kind: TypeNamed, Name: "num"}, nil
	case "string":
		return &Type{Kind: TypeList, Items: []*Type{{Kind: TypeNamed, Name: "char"}}}, nil
	case "char":
		return &Type{Kind: TypeNamed, Name: "char"}, nil
	case "name", "constructor":
		if value, ok := environment[expression.Text]; ok {
			return value, nil
		}
		if value, ok := PrimitiveType(expression.Text); ok {
			return value, nil
		}
		return s.fresh(), nil
	case "application":
		function, err := s.infer(*expression.Func, environment)
		if err != nil {
			return nil, err
		}
		argument, err := s.infer(*expression.Arg, environment)
		if err != nil {
			return nil, err
		}
		result := s.fresh()
		if err = Unify(function, &Type{Kind: TypeArrow, From: argument, To: result}, s.substitutions); err != nil {
			return nil, err
		}
		return Resolve(result, s.substitutions), nil
	case "infix":
		function := syntaxfront.Expr{Variant: "application", Func: &syntaxfront.Expr{Variant: "name", Text: expression.Text}, Arg: expression.Head}
		return s.infer(syntaxfront.Expr{Variant: "application", Func: &function, Arg: expression.Tail}, environment)
	case "list":
		element := s.fresh()
		for _, item := range expression.Items {
			actual, err := s.infer(item, environment)
			if err != nil {
				return nil, err
			}
			if err = Unify(element, actual, s.substitutions); err != nil {
				return nil, err
			}
		}
		return &Type{Kind: TypeList, Items: []*Type{Resolve(element, s.substitutions)}}, nil
	case "tuple":
		items := make([]*Type, len(expression.Items))
		for i, item := range expression.Items {
			value, err := s.infer(item, environment)
			if err != nil {
				return nil, err
			}
			items[i] = value
		}
		return &Type{Kind: TypeTuple, Items: items}, nil
	default:
		return s.fresh(), nil
	}
}
