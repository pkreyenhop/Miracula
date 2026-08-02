package semantics

import (
	"fmt"
	"github.com/pkreyenhop/miracula/internal/graphstore"
	"github.com/pkreyenhop/miracula/internal/syntaxfront"
	"sort"
	"strings"
)

type TypedDefinition struct {
	Name       string
	Expression syntaxfront.Expr
	Type       *Type
	Root       int
}
type Program struct {
	Definitions    []TypedDefinition
	Specifications map[string]*Type
	Symbols        SymbolTable
	Order          []string
}

type inferState struct {
	next            int
	substitutions   Substitution
	environment     map[string]*Type
	schemes         map[string]TypeScheme
	aliases         map[string]TypeAlias
	abstract        map[string]bool
	representations map[string]TypeAlias
}

type TypeScheme struct {
	Type       *Type
	Quantified map[int]bool
}

func (s *inferState) fresh() *Type {
	value := &Type{Kind: TypeVariable, ID: s.next}
	s.next++
	return value
}

func Compile(script syntaxfront.Script, heap *graphstore.Heap) (*Program, error) {
	return compile(script, heap, true, nil)
}

func Check(script syntaxfront.Script) (*Program, error) {
	return CheckWithTypes(script, nil)
}

func CheckWithTypes(script syntaxfront.Script, external map[string]*Type) (*Program, error) {
	return compile(script, nil, false, external)
}

func compile(script syntaxfront.Script, heap *graphstore.Heap, lower bool, external map[string]*Type) (*Program, error) {
	script.Items = semanticDefinitions(script)
	state := &inferState{substitutions: Substitution{}, environment: map[string]*Type{}, schemes: map[string]TypeScheme{}, aliases: map[string]TypeAlias{}, abstract: map[string]bool{}, representations: map[string]TypeAlias{}}
	for name, value := range external {
		state.schemes[name] = generalize(value)
	}
	program := &Program{Specifications: map[string]*Type{}}
	graph := map[string][]string{}
	signatures := map[string]*Type{}
	definitions := map[string][]syntaxfront.Definition{}
	var sourceOrder []string
	if err := installTypeDeclarations(script, state); err != nil {
		return nil, err
	}
	for _, declaration := range script.Items {
		declarationText := normalizedDeclarationText(declaration.Text)
		if declaration.Variant == "type_signature" && strings.Contains(declarationText, "::") && !strings.Contains(declarationText, "::=") {
			separator := strings.Index(declarationText, "::")
			if separator < 0 {
				continue
			}
			leftText := strings.TrimSpace(declarationText[:separator])
			leftText = strings.TrimSpace(strings.TrimPrefix(leftText, "with "))
			rightText := strings.TrimSpace(declarationText[separator+2:])
			if rightText == "type" {
				continue
			}
			value, err := ParseType(rightText)
			if err != nil {
				return nil, TypeError{Message: err.Error(), Line: declaration.Span.Line, Column: declaration.Span.Column}
			}
			value = state.expandAliases(value)
			for _, name := range strings.Split(leftText, ",") {
				name = strings.TrimSpace(name)
				if signatures[name] != nil {
					return nil, TypeError{Message: "type of " + name + " declared more than once", Line: declaration.Span.Line, Column: declaration.Span.Column}
				}
				signatures[name] = value
				state.schemes[name] = generalize(state.expandRepresentations(value))
				program.Specifications[name] = value
				program.Symbols.Intern(name)
			}
		}
		if declaration.Variant == "definition" && !isTypeAliasText(normalizedDeclarationText(declaration.Text)) {
			name, _, ok := definitionName(declaration.LHS)
			if ok {
				if len(definitions[name]) == 0 {
					sourceOrder = append(sourceOrder, name)
					program.Symbols.Intern(name)
				}
				definitions[name] = append(definitions[name], declaration)
				body, guard, _ := semanticDefinitionExpressions(declaration)
				graph[name] = append(graph[name], expressionNames(body, nil)...)
				if guard != nil {
					graph[name] = append(graph[name], expressionNames(*guard, nil)...)
				}
			}
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
	for _, component := range StronglyConnectedOrder(graph) {
		for _, name := range component {
			state.environment[name] = state.fresh()
		}
		for _, name := range component {
			for _, definition := range definitions[name] {
				_, patterns, ok := definitionPatterns(definition.LHS)
				if !ok {
					return nil, TypeError{Message: "invalid definition pattern", Line: definition.Span.Line, Column: definition.Span.Column}
				}
				local := make(map[string]*Type, len(state.environment)+len(patterns))
				for key, value := range state.environment {
					local[key] = value
				}
				parameterTypes := make([]*Type, len(patterns))
				for index, pattern := range patterns {
					parameterTypes[index] = state.fresh()
					if err := state.inferPattern(pattern, parameterTypes[index], local); err != nil {
						return nil, TypeError{Message: err.Error(), Line: definition.Span.Line, Column: definition.Span.Column}
					}
				}
				body, guard, parseErr := semanticDefinitionExpressions(definition)
				if parseErr != nil {
					return nil, TypeError{Message: parseErr.Error(), Line: definition.Span.Line, Column: definition.Span.Column}
				}
				if guard != nil {
					guardType, guardErr := state.infer(*guard, local)
					if guardErr != nil {
						return nil, TypeError{Message: guardErr.Error(), Definition: name, Line: definition.Span.Line, Column: definition.Span.Column}
					}
					if guardErr = Unify(guardType, &Type{Kind: TypeNamed, Name: "bool"}, state.substitutions); guardErr != nil {
						return nil, TypeError{Message: guardErr.Error(), Definition: name, Line: definition.Span.Line, Column: definition.Span.Column}
					}
				}
				valueType, err := state.infer(body, local)
				if err != nil {
					return nil, TypeError{Message: err.Error(), Definition: name, Line: definition.Span.Line, Column: definition.Span.Column}
				}
				for index := len(parameterTypes) - 1; index >= 0; index-- {
					valueType = &Type{Kind: TypeArrow, From: parameterTypes[index], To: valueType}
				}
				if err = Unify(state.environment[name], valueType, state.substitutions); err != nil {
					return nil, TypeError{Message: err.Error(), Definition: name, Line: definition.Span.Line, Column: definition.Span.Column}
				}
			}
		}
		for _, name := range component {
			if signature := signatures[name]; signature != nil {
				implementationType := state.expandRepresentations(state.instantiate(signature))
				if err := Unify(state.environment[name], implementationType, state.substitutions); err != nil {
					definition := definitions[name][0]
					return nil, TypeError{Message: err.Error(), Definition: name, Line: definition.Span.Line, Column: definition.Span.Column}
				}
			}
		}
		for _, name := range component {
			resolved := DeepResolve(state.environment[name], state.substitutions)
			if signature := signatures[name]; signature != nil {
				resolved = state.expandRepresentations(signature)
			}
			if name != "__repl" && signatures[name] == nil && definitionsUseSpecialShow(definitions[name]) {
				hasVariables := false
				visitType(resolved, func(int) { hasVariables = true })
				if hasVariables {
					definition := definitions[name][0]
					return nil, TypeError{Message: "polymorphic use of show or readvals requires a type declaration", Definition: name, Line: definition.Span.Line, Column: definition.Span.Column}
				}
			}
			state.schemes[name] = generalize(resolved)
			delete(state.environment, name)
		}
	}
	for _, name := range sourceOrder {
		resolved := state.schemes[name].Type
		if signature := signatures[name]; signature != nil {
			resolved = signature
		}
		program.Definitions = append(program.Definitions, TypedDefinition{Name: name, Expression: definitions[name][0].RHS, Type: resolved})
	}
	program.Order = RecursiveOrder(graph)
	if !lower {
		return program, nil
	}
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

func definitionsUseSpecialShow(definitions []syntaxfront.Definition) bool {
	for _, definition := range definitions {
		body, guard, _ := semanticDefinitionExpressions(definition)
		for _, name := range append(expressionNames(body, nil), func() []string {
			if guard == nil {
				return nil
			}
			return expressionNames(*guard, nil)
		}()...) {
			if name == "show" || name == "readvals" {
				return true
			}
		}
	}
	return false
}

func semanticDefinitions(script syntaxfront.Script) []syntaxfront.Definition {
	items := make([]syntaxfront.Definition, 0, len(script.Items))
	currentLeft := ""
	for _, item := range script.Items {
		if item.Variant == "definition" {
			if separator := strings.Index(item.Text, "="); separator >= 0 {
				currentLeft = strings.TrimSpace(item.Text[:separator])
			}
			items = append(items, item)
			continue
		}
		if item.Variant == "continuation" && currentLeft != "" && strings.HasPrefix(strings.TrimSpace(item.Text), "=") {
			parsed := syntaxfront.Run([]byte(currentLeft + " " + item.Text + "\n"))
			if len(parsed.Diagnostics) == 0 && len(parsed.Script.Items) == 1 {
				continuation := parsed.Script.Items[0]
				continuation.Span = item.Span
				items = append(items, continuation)
				continue
			}
		}
		items = append(items, item)
	}
	return items
}

func semanticDefinitionExpressions(definition syntaxfront.Definition) (syntaxfront.Expr, *syntaxfront.Expr, error) {
	separator := strings.Index(definition.Text, "=")
	if separator < 0 {
		return definition.RHS, nil, nil
	}
	right := strings.TrimSpace(definition.Text[separator+1:])
	for _, marker := range []string{"\nwhere\n", "\nwhere ", " where ", "\n="} {
		if index := strings.Index(right, marker); index >= 0 {
			right = strings.TrimSpace(right[:index])
		}
	}
	bodyText := right
	guardText := ""
	if comma := strings.LastIndex(right, ","); comma >= 0 {
		qualifier := strings.TrimSpace(right[comma+1:])
		if strings.HasPrefix(qualifier, "if ") {
			bodyText = strings.TrimSpace(right[:comma])
			guardText = strings.TrimSpace(strings.TrimPrefix(qualifier, "if "))
		} else if qualifier == "otherwise" {
			bodyText = strings.TrimSpace(right[:comma])
		}
	}
	parse := func(text string) (syntaxfront.Expr, error) {
		parsed := syntaxfront.Run([]byte("__semantic_value = " + text + "\n"))
		if len(parsed.Diagnostics) != 0 || len(parsed.Script.Items) != 1 {
			if len(parsed.Diagnostics) != 0 {
				return syntaxfront.Expr{}, fmt.Errorf("%s", parsed.Diagnostics[0].Message)
			}
			return syntaxfront.Expr{}, fmt.Errorf("invalid expression")
		}
		return parsed.Script.Items[0].RHS, nil
	}
	body, err := parse(bodyText)
	if err != nil || guardText == "" {
		return body, nil, err
	}
	guard, err := parse(guardText)
	return body, &guard, err
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
	name, patterns, ok := definitionPatterns(expression)
	var params []string
	for _, pattern := range patterns {
		if pattern.Variant == "name" {
			params = append(params, pattern.Text)
		} else {
			params = append(params, fmt.Sprintf("$pattern%d", len(params)))
		}
	}
	return name, params, ok
}

func definitionPatterns(expression syntaxfront.Expr) (string, []syntaxfront.Expr, bool) {
	if expression.Variant == "infix" && (strings.HasPrefix(expression.Text, "$") || expression.Text == "|>") && expression.Head != nil && expression.Tail != nil {
		return strings.TrimPrefix(expression.Text, "$"), []syntaxfront.Expr{*expression.Head, *expression.Tail}, true
	}
	var patterns []syntaxfront.Expr
	for expression.Variant == "application" {
		patterns = append([]syntaxfront.Expr{*expression.Arg}, patterns...)
		expression = *expression.Func
	}
	return expression.Text, patterns, expression.Variant == "name" && expression.Text != ""
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
	if expression.Body != nil {
		out = expressionNames(*expression.Body, out)
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
		if scheme, ok := s.schemes[expression.Text]; ok {
			return s.instantiateScheme(scheme), nil
		}
		if value, ok := PrimitiveType(expression.Text); ok {
			return s.instantiate(value), nil
		}
		// Undefined-name reporting is a separate scope-validation pass. Keep a
		// fresh type here so one missing name cannot hide independent type errors.
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
		if err = Unify(&Type{Kind: TypeArrow, From: argument, To: result}, function, s.substitutions); err != nil {
			return nil, err
		}
		return Resolve(result, s.substitutions), nil
	case "conditional":
		condition, err := s.infer(*expression.Head, environment)
		if err != nil {
			return nil, err
		}
		if err = Unify(condition, &Type{Kind: TypeNamed, Name: "bool"}, s.substitutions); err != nil {
			return nil, err
		}
		trueType, err := s.infer(*expression.Body, environment)
		if err != nil {
			return nil, err
		}
		falseType, err := s.infer(*expression.Tail, environment)
		if err != nil {
			return nil, err
		}
		if err = Unify(trueType, falseType, s.substitutions); err != nil {
			return nil, err
		}
		return Resolve(trueType, s.substitutions), nil
	case "infix":
		if comparisonOperator(expression.Text) && expression.Head != nil && expression.Head.Variant == "infix" && comparisonOperator(expression.Head.Text) {
			left, err := s.infer(*expression.Head.Head, environment)
			if err != nil {
				return nil, err
			}
			middle, err := s.infer(*expression.Head.Tail, environment)
			if err != nil {
				return nil, err
			}
			right, err := s.infer(*expression.Tail, environment)
			if err != nil {
				return nil, err
			}
			if err = Unify(left, middle, s.substitutions); err != nil {
				return nil, err
			}
			if err = Unify(middle, right, s.substitutions); err != nil {
				return nil, err
			}
			return &Type{Kind: TypeNamed, Name: "bool"}, nil
		}
		name := strings.TrimPrefix(expression.Text, "$")
		function := syntaxfront.Expr{Variant: "application", Func: &syntaxfront.Expr{Variant: "name", Text: name}, Arg: expression.Head}
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
	case "neg":
		argument, err := s.infer(*expression.Arg, environment)
		if err != nil {
			return nil, err
		}
		number := &Type{Kind: TypeNamed, Name: "num"}
		if err = Unify(argument, number, s.substitutions); err != nil {
			return nil, err
		}
		return number, nil
	case "not":
		argument, err := s.infer(*expression.Arg, environment)
		if err != nil {
			return nil, err
		}
		boolean := &Type{Kind: TypeNamed, Name: "bool"}
		if err = Unify(argument, boolean, s.substitutions); err != nil {
			return nil, err
		}
		return boolean, nil
	case "length":
		argument, err := s.infer(*expression.Arg, environment)
		if err != nil {
			return nil, err
		}
		item := s.fresh()
		if err = Unify(argument, &Type{Kind: TypeList, Items: []*Type{item}}, s.substitutions); err != nil {
			return nil, err
		}
		return &Type{Kind: TypeNamed, Name: "num"}, nil
	case "range":
		number := &Type{Kind: TypeNamed, Name: "num"}
		for _, part := range []*syntaxfront.Expr{expression.Head, expression.Step, expression.To} {
			if part == nil {
				continue
			}
			value, err := s.infer(*part, environment)
			if err != nil {
				return nil, err
			}
			if err = Unify(value, number, s.substitutions); err != nil {
				return nil, err
			}
		}
		return &Type{Kind: TypeList, Items: []*Type{number}}, nil
	case "op_func":
		name := strings.TrimPrefix(expression.Text, "$")
		if value, ok := PrimitiveType(name); ok {
			return s.instantiate(value), nil
		}
		if value, ok := environment[name]; ok {
			return value, nil
		}
		if scheme, ok := s.schemes[name]; ok {
			return s.instantiateScheme(scheme), nil
		}
		return nil, fmt.Errorf("undefined operator %s", expression.Text)
	case "section_left", "section_right":
		name := strings.TrimPrefix(expression.Text, "$")
		operator, ok := PrimitiveType(name)
		if !ok {
			operator, ok = environment[name]
		}
		if !ok {
			if scheme, exists := s.schemes[name]; exists {
				operator, ok = s.instantiateScheme(scheme), true
			}
		}
		if !ok {
			return nil, fmt.Errorf("undefined operator %s", expression.Text)
		}
		operatorType := s.instantiate(operator)
		fixed, err := s.infer(*expression.Arg, environment)
		if err != nil {
			return nil, err
		}
		first, second, result := s.fresh(), s.fresh(), s.fresh()
		if err = Unify(operatorType, &Type{Kind: TypeArrow, From: first, To: &Type{Kind: TypeArrow, From: second, To: result}}, s.substitutions); err != nil {
			return nil, err
		}
		if expression.Variant == "section_left" {
			if err = Unify(fixed, first, s.substitutions); err != nil {
				return nil, err
			}
			return &Type{Kind: TypeArrow, From: second, To: result}, nil
		}
		if err = Unify(fixed, second, s.substitutions); err != nil {
			return nil, err
		}
		return &Type{Kind: TypeArrow, From: first, To: result}, nil
	case "listcomp", "diagonal_listcomp":
		local := make(map[string]*Type, len(environment))
		for name, value := range environment {
			local[name] = value
		}
		for _, qualifier := range expression.Qualifiers {
			if qualifier.Guard != nil {
				guard, err := s.infer(*qualifier.Guard, local)
				if err != nil {
					return nil, err
				}
				if err = Unify(guard, &Type{Kind: TypeNamed, Name: "bool"}, s.substitutions); err != nil {
					return nil, err
				}
				continue
			}
			source, err := s.infer(*qualifier.Source, local)
			if err != nil {
				return nil, err
			}
			item := s.fresh()
			if qualifier.Recurrence != nil {
				if err = Unify(source, item, s.substitutions); err != nil {
					return nil, err
				}
				if err = s.inferPattern(*qualifier.Pattern, item, local); err != nil {
					return nil, err
				}
				next, nextErr := s.infer(*qualifier.Recurrence, local)
				if nextErr != nil {
					return nil, nextErr
				}
				if err = Unify(next, item, s.substitutions); err != nil {
					return nil, err
				}
				continue
			}
			if err = Unify(source, &Type{Kind: TypeList, Items: []*Type{item}}, s.substitutions); err != nil {
				return nil, err
			}
			if err = s.inferPattern(*qualifier.Pattern, item, local); err != nil {
				return nil, err
			}
		}
		body, err := s.infer(*expression.Body, local)
		if err != nil {
			return nil, err
		}
		return &Type{Kind: TypeList, Items: []*Type{body}}, nil
	default:
		return nil, fmt.Errorf("unsupported expression %s", expression.Variant)
	}
}

func comparisonOperator(name string) bool {
	switch name {
	case "=", "~=", "<", "<=", ">", ">=":
		return true
	}
	return false
}

func (s *inferState) inferPattern(pattern syntaxfront.Expr, expected *Type, environment map[string]*Type) error {
	switch pattern.Variant {
	case "name":
		if pattern.Text != "_" {
			if previous := environment[pattern.Text]; previous != nil {
				return Unify(previous, expected, s.substitutions)
			}
			environment[pattern.Text] = expected
		}
		return nil
	case "int":
		return Unify(expected, &Type{Kind: TypeNamed, Name: "num"}, s.substitutions)
	case "char":
		return Unify(expected, &Type{Kind: TypeNamed, Name: "char"}, s.substitutions)
	case "string":
		return Unify(expected, &Type{Kind: TypeList, Items: []*Type{{Kind: TypeNamed, Name: "char"}}}, s.substitutions)
	case "tuple":
		items := make([]*Type, len(pattern.Items))
		for index, item := range pattern.Items {
			items[index] = s.fresh()
			if err := s.inferPattern(item, items[index], environment); err != nil {
				return err
			}
		}
		return Unify(expected, &Type{Kind: TypeTuple, Items: items}, s.substitutions)
	case "list":
		itemType := s.fresh()
		for _, item := range pattern.Items {
			if err := s.inferPattern(item, itemType, environment); err != nil {
				return err
			}
		}
		return Unify(expected, &Type{Kind: TypeList, Items: []*Type{itemType}}, s.substitutions)
	case "infix":
		if pattern.Text == ":" {
			itemType := s.fresh()
			if err := s.inferPattern(*pattern.Head, itemType, environment); err != nil {
				return err
			}
			if err := s.inferPattern(*pattern.Tail, &Type{Kind: TypeList, Items: []*Type{itemType}}, environment); err != nil {
				return err
			}
			return Unify(expected, &Type{Kind: TypeList, Items: []*Type{itemType}}, s.substitutions)
		}
		if pattern.Text == "+" && pattern.Head != nil && pattern.Tail != nil && pattern.Tail.Variant == "int" {
			numberType := &Type{Kind: TypeNamed, Name: "num"}
			if err := s.inferPattern(*pattern.Head, numberType, environment); err != nil {
				return err
			}
			return Unify(expected, numberType, s.substitutions)
		}
	case "constructor", "application":
		name, arguments, ok := patternConstructor(pattern)
		if ok {
			scheme, exists := s.schemes[name]
			if !exists {
				return fmt.Errorf("undefined constructor %s", name)
			}
			constructorType := s.instantiateScheme(scheme)
			for _, argument := range arguments {
				argumentType, resultType := s.fresh(), s.fresh()
				if err := Unify(constructorType, &Type{Kind: TypeArrow, From: argumentType, To: resultType}, s.substitutions); err != nil {
					return err
				}
				if err := s.inferPattern(argument, argumentType, environment); err != nil {
					return err
				}
				constructorType = resultType
			}
			return Unify(expected, constructorType, s.substitutions)
		}
	}
	return fmt.Errorf("invalid pattern")
}

func patternConstructor(pattern syntaxfront.Expr) (string, []syntaxfront.Expr, bool) {
	var arguments []syntaxfront.Expr
	for pattern.Variant == "application" {
		arguments = append([]syntaxfront.Expr{*pattern.Arg}, arguments...)
		pattern = *pattern.Func
	}
	return pattern.Text, arguments, pattern.Variant == "constructor"
}

func generalize(value *Type) TypeScheme {
	quantified := map[int]bool{}
	visitType(value, func(variable int) { quantified[variable] = true })
	return TypeScheme{Type: value, Quantified: quantified}
}

func visitType(value *Type, visit func(int)) {
	if value == nil {
		return
	}
	if value.Kind == TypeVariable {
		visit(value.ID)
		return
	}
	visitType(value.From, visit)
	visitType(value.To, visit)
	for _, item := range value.Items {
		visitType(item, visit)
	}
}

func (s *inferState) instantiateScheme(scheme TypeScheme) *Type {
	variables := map[int]*Type{}
	var clone func(*Type) *Type
	clone = func(current *Type) *Type {
		if current == nil {
			return nil
		}
		if current.Kind == TypeVariable && scheme.Quantified[current.ID] {
			if variables[current.ID] == nil {
				variables[current.ID] = s.fresh()
			}
			return variables[current.ID]
		}
		result := *current
		result.From, result.To = clone(current.From), clone(current.To)
		result.Items = make([]*Type, len(current.Items))
		for index := range current.Items {
			result.Items[index] = clone(current.Items[index])
		}
		return &result
	}
	return clone(scheme.Type)
}

func (s *inferState) instantiate(value *Type) *Type {
	variables := map[int]*Type{}
	var clone func(*Type) *Type
	clone = func(current *Type) *Type {
		if current == nil {
			return nil
		}
		if current.Kind == TypeVariable {
			if variables[current.ID] == nil {
				variables[current.ID] = s.fresh()
			}
			return variables[current.ID]
		}
		result := *current
		result.From, result.To = clone(current.From), clone(current.To)
		result.Items = make([]*Type, len(current.Items))
		for index := range current.Items {
			result.Items[index] = clone(current.Items[index])
		}
		return &result
	}
	return clone(value)
}
