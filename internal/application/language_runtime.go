package application

import (
	"context"
	"errors"
	"fmt"
	"io"
	"math"
	"math/big"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"

	"github.com/pkreyenhop/miracula-go/internal/platformsvc"
	"github.com/pkreyenhop/miracula-go/internal/syntaxfront"
)

type valueKind uint8

const (
	valueNumber valueKind = iota
	valueFloat
	valueBool
	valueString
	valueList
	valueTuple
	valueConstructor
	valueMessage
	valueFunction
)

type languageValue struct {
	kind  valueKind
	num   *big.Int
	real  float64
	flag  bool
	text  string
	list  *lazyList
	items []languageValue
	name  string
	fn    func(context.Context, languageValue) (languageValue, error)
}

type lazyList struct {
	mu     sync.Mutex
	values []languageValue
	next   func(context.Context, int) (languageValue, bool, error)
}

func (l *lazyList) at(ctx context.Context, index int) (languageValue, bool, error) {
	for {
		l.mu.Lock()
		if index < len(l.values) {
			value := l.values[index]
			l.mu.Unlock()
			return value, true, nil
		}
		next, nextIndex := l.next, len(l.values)
		l.mu.Unlock()
		if next == nil {
			return languageValue{}, false, nil
		}
		value, ok, err := next(ctx, nextIndex)
		if err != nil || !ok {
			l.mu.Lock()
			if !ok {
				l.next = nil
			}
			l.mu.Unlock()
			return languageValue{}, ok, err
		}
		l.mu.Lock()
		if len(l.values) == nextIndex {
			l.values = append(l.values, value)
		}
		l.mu.Unlock()
	}
}

type languageRuntime struct {
	globals     map[string]*languageThunk
	appendFiles map[string]bool
	output      io.Writer
	reductions  uint64
	cells       uint64
}

type languageThunk struct {
	once  sync.Once
	value languageValue
	err   error
	eval  func() (languageValue, error)
}

func (t *languageThunk) force() (languageValue, error) {
	t.once.Do(func() { t.value, t.err = t.eval(); t.eval = nil })
	return t.value, t.err
}

func newLanguageRuntime(output io.Writer) *languageRuntime {
	r := &languageRuntime{globals: map[string]*languageThunk{}, appendFiles: map[string]bool{}, output: output}
	r.installBuiltins()
	return r
}

func (i *Interpreter) runtime() *languageRuntime {
	if i.language == nil {
		i.language = newLanguageRuntime(i.Output)
	}
	return i.language
}

func immediate(value languageValue) *languageThunk {
	return &languageThunk{eval: func() (languageValue, error) { return value, nil }}
}

func (r *languageRuntime) install(script syntaxfront.Script) error {
	for _, definition := range script.Items {
		if definition.Variant != "definition" {
			continue
		}
		name, parameters, ok := runtimeDefinitionName(definition.LHS)
		if !ok {
			return fmt.Errorf("invalid definition")
		}
		definition, parameters := definition, parameters
		thunk := &languageThunk{}
		thunk.eval = func() (languageValue, error) {
			if len(parameters) == 0 {
				return r.eval(context.Background(), definition.RHS, r.globals)
			}
			return r.function(parameters, definition.RHS, r.globals), nil
		}
		r.globals[name] = thunk
	}
	return nil
}

type runtimeClause struct {
	parameters []syntaxfront.Expr
	body       syntaxfront.Expr
	condition  *syntaxfront.Expr
}

// installSource preserves guarded equations, whose continuation-line shape is
// intentionally richer than the compatibility AST used by the stage oracle.
func (r *languageRuntime) installSource(source []byte) error {
	clauses := map[string][]runtimeClause{}
	currentName := ""
	var currentParameters []syntaxfront.Expr
	for _, rawLine := range logicalSourceLines(source) {
		line := strings.TrimSpace(rawLine)
		if line == "" || strings.HasPrefix(line, "||") || strings.HasPrefix(line, "%") {
			continue
		}
		if marker := strings.Index(line, "::="); marker >= 0 {
			for _, alternative := range strings.Split(line[marker+3:], "|") {
				fields := strings.Fields(strings.TrimSpace(alternative))
				if len(fields) == 0 {
					continue
				}
				r.installConstructor(fields[0], len(fields)-1)
			}
			continue
		}
		separator := strings.Index(line, "=")
		if separator < 0 {
			continue
		}
		left, right := strings.TrimSpace(line[:separator]), strings.TrimSpace(line[separator+1:])
		if left != "" {
			lhsParsed := syntaxfront.Run([]byte(left + " = 0\n"))
			if len(lhsParsed.Diagnostics) != 0 || len(lhsParsed.Script.Items) != 1 {
				continue
			}
			var ok bool
			currentName, currentParameters, ok = runtimePatterns(lhsParsed.Script.Items[0].LHS)
			if !ok {
				continue
			}
		}
		if currentName == "" || right == "" {
			continue
		}
		bodyText, conditionText := right, ""
		if marker := strings.LastIndex(right, ","); marker >= 0 {
			qualifier := strings.TrimSpace(right[marker+1:])
			if strings.HasPrefix(qualifier, "if ") {
				bodyText, conditionText = strings.TrimSpace(right[:marker]), strings.TrimSpace(strings.TrimPrefix(qualifier, "if "))
			} else if qualifier == "otherwise" {
				bodyText = strings.TrimSpace(right[:marker])
			}
		}
		body, err := parseRuntimeExpression(bodyText)
		if err != nil {
			return fmt.Errorf("%s: %w", currentName, err)
		}
		clause := runtimeClause{parameters: append([]syntaxfront.Expr(nil), currentParameters...), body: body}
		if conditionText != "" {
			condition, err := parseRuntimeExpression(conditionText)
			if err != nil {
				return fmt.Errorf("%s guard: %w", currentName, err)
			}
			clause.condition = &condition
		}
		clauses[currentName] = append(clauses[currentName], clause)
	}
	for name, alternatives := range clauses {
		name, alternatives := name, alternatives
		thunk := &languageThunk{}
		thunk.eval = func() (languageValue, error) {
			if len(alternatives[0].parameters) == 0 {
				return r.selectClause(context.Background(), alternatives, nil)
			}
			return r.clauseFunction(alternatives, nil), nil
		}
		r.globals[name] = thunk
	}
	return nil
}

func (i *Interpreter) ValidateCurrent() error {
	script, ok := i.Scripts.Scripts[i.Compiler.CurrentModule]
	if !ok {
		return errors.New("no current script")
	}
	for _, line := range logicalSourceLines(script.Source) {
		trimmed := strings.TrimSpace(line)
		separator := strings.Index(trimmed, "=")
		if separator < 0 || strings.Contains(trimmed[:separator], "::") {
			continue
		}
		left, right := strings.TrimSpace(trimmed[:separator]), strings.TrimSpace(trimmed[separator+1:])
		lhs := syntaxfront.Run([]byte(left + " = 0\n"))
		if len(lhs.Script.Items) != 1 {
			continue
		}
		_, patterns, ok := runtimePatterns(lhs.Script.Items[0].LHS)
		if !ok {
			continue
		}
		bound := map[string]bool{}
		for _, pattern := range patterns {
			collectPatternNames(pattern, bound)
		}
		if comma := strings.LastIndex(right, ","); comma >= 0 {
			right = strings.TrimSpace(right[:comma])
		}
		expression, err := parseRuntimeExpression(right)
		if err != nil {
			return err
		}
		if name := firstUndefined(expression, bound, i.runtime().globals); name != "" {
			return fmt.Errorf("undefined name %s", name)
		}
	}
	return nil
}
func collectPatternNames(pattern syntaxfront.Expr, names map[string]bool) {
	if pattern.Variant == "name" {
		names[pattern.Text] = true
	}
	if pattern.Head != nil {
		collectPatternNames(*pattern.Head, names)
	}
	if pattern.Tail != nil {
		collectPatternNames(*pattern.Tail, names)
	}
	for _, item := range pattern.Items {
		collectPatternNames(item, names)
	}
}
func firstUndefined(expression syntaxfront.Expr, bound map[string]bool, globals map[string]*languageThunk) string {
	if expression.Variant == "name" || expression.Variant == "constructor" {
		if !bound[expression.Text] && globals[expression.Text] == nil {
			return expression.Text
		}
	}
	children := []*syntaxfront.Expr{expression.Func, expression.Arg, expression.Head, expression.Tail, expression.Step, expression.To, expression.Body}
	for _, child := range children {
		if child != nil {
			if name := firstUndefined(*child, bound, globals); name != "" {
				return name
			}
		}
	}
	for _, item := range expression.Items {
		if name := firstUndefined(item, bound, globals); name != "" {
			return name
		}
	}
	return ""
}

func logicalSourceLines(source []byte) []string {
	physical := strings.Split(string(source), "\n")
	result := make([]string, 0, len(physical))
	for index := 0; index < len(physical); index++ {
		line := physical[index]
		trimmed := strings.TrimSpace(line)
		if trimmed != "" && !strings.HasPrefix(trimmed, "||") && !strings.HasPrefix(trimmed, "%") && !strings.Contains(line, "=") && index+1 < len(physical) && strings.HasPrefix(strings.TrimSpace(physical[index+1]), "=") {
			line += " " + strings.TrimSpace(physical[index+1])
			index++
		}
		depth := delimiterBalance(line)
		for depth > 0 && index+1 < len(physical) {
			index++
			line += " " + strings.TrimSpace(physical[index])
			depth += delimiterBalance(physical[index])
		}
		result = append(result, line)
	}
	return result
}
func delimiterBalance(line string) int {
	depth := 0
	quoted := false
	escaped := false
	for _, char := range line {
		if quoted {
			if escaped {
				escaped = false
			} else if char == '\\' {
				escaped = true
			} else if char == '"' {
				quoted = false
			}
			continue
		}
		if char == '"' {
			quoted = true
			continue
		}
		switch char {
		case '[', '(', '{':
			depth++
		case ']', ')', '}':
			depth--
		}
	}
	return depth
}

func (r *languageRuntime) installIncludes(base string, source []byte) error {
	for _, line := range strings.Split(string(source), "\n") {
		directive, ok := syntaxfront.ParseDirective(strings.TrimSpace(line))
		if !ok || directive.Variant != "include" {
			continue
		}
		path := directive.Path
		if directive.FromMiralib {
			return fmt.Errorf("miralib-relative include requires resolved library path")
		}
		if filepath.Ext(path) == "" {
			path += ".m"
		}
		if !filepath.IsAbs(path) {
			path = filepath.Join(base, path)
		}
		included, diagnostics := syntaxfront.LoadSource(path)
		if len(diagnostics) > 0 {
			return errors.New(diagnostics[0].Message)
		}
		before := map[string]bool{}
		for name := range r.globals {
			before[name] = true
		}
		if err := r.installIncludes(filepath.Dir(path), included.Bytes); err != nil {
			return err
		}
		if err := r.installSource(included.Bytes); err != nil {
			return err
		}
		exports := map[string]bool{}
		for _, includedLine := range strings.Split(string(included.Bytes), "\n") {
			if directive, ok := syntaxfront.ParseDirective(strings.TrimSpace(includedLine)); ok && directive.Variant == "export" {
				for _, name := range strings.Fields(directive.Text) {
					exports[name] = true
				}
			}
		}
		if len(exports) > 0 {
			for name := range r.globals {
				if !before[name] && !exports[name] {
					delete(r.globals, name)
				}
			}
		}
		for _, alias := range directive.Aliases {
			if alias.Suppress {
				delete(r.globals, alias.Old)
				continue
			}
			if original := r.globals[alias.Old]; original != nil {
				r.globals[alias.New] = original
			}
		}
		if start := strings.Index(directive.Text, "{"); start >= 0 {
			if end := strings.LastIndex(directive.Text, "}"); end > start {
				for _, binding := range strings.Split(directive.Text[start+1:end], ";") {
					if strings.Contains(binding, "==") {
						continue
					}
					pair := strings.SplitN(strings.TrimSpace(binding), "=", 2)
					if len(pair) != 2 {
						continue
					}
					name := strings.TrimSpace(pair[0])
					expression := strings.TrimSpace(pair[1])
					if expression == "num" || expression == "type" {
						continue
					}
					if _, ok := syntaxfront.InfixBinding(map[string]string{"+": "plus", "-": "minus", "*": "star", "/": "slash", "++": "append"}[expression]); ok {
						expression = "(" + expression + ")"
					}
					parsed, err := parseRuntimeExpression(expression)
					if err != nil {
						return err
					}
					value, err := r.eval(context.Background(), parsed, r.globals)
					if err != nil {
						return err
					}
					r.globals[name] = immediate(value)
				}
			}
		}
	}
	return nil
}

func (r *languageRuntime) installConstructor(name string, arity int) {
	if arity == 0 {
		r.builtin(name, languageValue{kind: valueConstructor, name: name})
		return
	}
	var build func([]languageValue) languageValue
	build = func(arguments []languageValue) languageValue {
		return languageValue{kind: valueFunction, fn: func(_ context.Context, argument languageValue) (languageValue, error) {
			values := append(append([]languageValue(nil), arguments...), argument)
			if len(values) == arity {
				return languageValue{kind: valueConstructor, name: name, items: values}, nil
			}
			return build(values), nil
		}}
	}
	r.builtin(name, build(nil))
}

func parseRuntimeExpression(text string) (syntaxfront.Expr, error) {
	parsed := syntaxfront.Run([]byte("__value = " + text + "\n"))
	if len(parsed.Diagnostics) != 0 {
		return syntaxfront.Expr{}, errors.New(parsed.Diagnostics[0].Message)
	}
	if len(parsed.Script.Items) != 1 {
		return syntaxfront.Expr{}, errors.New("invalid expression")
	}
	return parsed.Script.Items[0].RHS, nil
}

func runtimePatterns(expression syntaxfront.Expr) (string, []syntaxfront.Expr, bool) {
	var parameters []syntaxfront.Expr
	for expression.Variant == "application" {
		if expression.Arg == nil {
			return "", nil, false
		}
		parameters = append([]syntaxfront.Expr{*expression.Arg}, parameters...)
		expression = *expression.Func
	}
	return expression.Text, parameters, expression.Variant == "name" && expression.Text != ""
}

func (r *languageRuntime) clauseFunction(clauses []runtimeClause, arguments []languageValue) languageValue {
	return languageValue{kind: valueFunction, fn: func(ctx context.Context, argument languageValue) (languageValue, error) {
		values := append(append([]languageValue(nil), arguments...), argument)
		if len(values) < len(clauses[0].parameters) {
			return r.clauseFunction(clauses, values), nil
		}
		return r.selectClause(ctx, clauses, values)
	}}
}

func (r *languageRuntime) selectClause(ctx context.Context, clauses []runtimeClause, arguments []languageValue) (languageValue, error) {
	for _, clause := range clauses {
		if len(clause.parameters) != len(arguments) {
			continue
		}
		environment := cloneEnvironment(r.globals)
		matched := true
		for index, pattern := range clause.parameters {
			if !matchRuntimePattern(pattern, arguments[index], environment) {
				matched = false
				break
			}
		}
		if !matched {
			continue
		}
		if clause.condition != nil {
			condition, err := r.eval(ctx, *clause.condition, environment)
			if err != nil {
				return languageValue{}, err
			}
			if condition.kind != valueBool {
				return languageValue{}, errors.New("truthvalue expected")
			}
			if !condition.flag {
				continue
			}
		}
		return r.eval(ctx, clause.body, environment)
	}
	return languageValue{}, errors.New("no matching equation")
}

func matchRuntimePattern(pattern syntaxfront.Expr, value languageValue, environment map[string]*languageThunk) bool {
	switch pattern.Variant {
	case "name":
		if pattern.Text != "_" {
			environment[pattern.Text] = immediate(value)
		}
		return true
	case "int":
		expected := new(big.Int)
		if _, ok := expected.SetString(pattern.Text, 0); !ok {
			return false
		}
		return value.kind == valueNumber && value.num.Cmp(expected) == 0
	case "tuple":
		if value.kind != valueTuple || len(value.items) != len(pattern.Items) {
			return false
		}
		for index, item := range pattern.Items {
			if !matchRuntimePattern(item, value.items[index], environment) {
				return false
			}
		}
		return true
	case "list":
		if value.kind != valueList {
			return false
		}
		items, err := finiteList(context.Background(), value, len(pattern.Items)+1)
		if err != nil || len(items) != len(pattern.Items) {
			return false
		}
		for index, item := range pattern.Items {
			if !matchRuntimePattern(item, items[index], environment) {
				return false
			}
		}
		return true
	case "infix":
		if pattern.Text != ":" || value.kind != valueList {
			return false
		}
		head, ok, err := value.list.at(context.Background(), 0)
		if err != nil || !ok {
			return false
		}
		tail := languageValue{kind: valueList, list: &lazyList{next: func(ctx context.Context, index int) (languageValue, bool, error) { return value.list.at(ctx, index+1) }}}
		return matchRuntimePattern(*pattern.Head, head, environment) && matchRuntimePattern(*pattern.Tail, tail, environment)
	case "application", "constructor":
		name, patterns, ok := constructorPattern(pattern)
		if !ok || value.kind != valueConstructor || value.name != name || len(value.items) != len(patterns) {
			return false
		}
		for index, item := range patterns {
			if !matchRuntimePattern(item, value.items[index], environment) {
				return false
			}
		}
		return true
	default:
		return false
	}
}
func constructorPattern(pattern syntaxfront.Expr) (string, []syntaxfront.Expr, bool) {
	var arguments []syntaxfront.Expr
	for pattern.Variant == "application" {
		arguments = append([]syntaxfront.Expr{*pattern.Arg}, arguments...)
		pattern = *pattern.Func
	}
	return pattern.Text, arguments, pattern.Variant == "constructor"
}

func runtimeDefinitionName(expression syntaxfront.Expr) (string, []string, bool) {
	var parameters []string
	for expression.Variant == "application" {
		if expression.Arg == nil || expression.Arg.Variant != "name" {
			return "", nil, false
		}
		parameters = append([]string{expression.Arg.Text}, parameters...)
		expression = *expression.Func
	}
	return expression.Text, parameters, expression.Variant == "name" && expression.Text != ""
}

func (r *languageRuntime) function(parameters []string, body syntaxfront.Expr, closure map[string]*languageThunk) languageValue {
	if len(parameters) == 0 {
		return languageValue{kind: valueFunction, fn: func(ctx context.Context, ignored languageValue) (languageValue, error) {
			return r.eval(ctx, body, closure)
		}}
	}
	return languageValue{kind: valueFunction, fn: func(ctx context.Context, argument languageValue) (languageValue, error) {
		environment := cloneEnvironment(closure)
		environment[parameters[0]] = immediate(argument)
		if len(parameters) == 1 {
			return r.eval(ctx, body, environment)
		}
		return r.function(parameters[1:], body, environment), nil
	}}
}

func cloneEnvironment(source map[string]*languageThunk) map[string]*languageThunk {
	out := make(map[string]*languageThunk, len(source)+1)
	for name, value := range source {
		out[name] = value
	}
	return out
}

func (r *languageRuntime) evaluate(ctx context.Context, expression syntaxfront.Expr) (languageValue, error) {
	r.cells = 0
	return r.eval(ctx, expression, r.globals)
}

func (r *languageRuntime) statistics() (uint64, uint64) {
	return r.reductions, r.cells
}

func (r *languageRuntime) eval(ctx context.Context, expression syntaxfront.Expr, environment map[string]*languageThunk) (languageValue, error) {
	// These are Go-runtime work counters. A reduction is one interpreted AST
	// node and a claimed cell is one value-producing node. They deliberately
	// measure useful work without pretending that Go allocates the reference
	// implementation's pointer-tagged graph cells.
	r.reductions++
	r.cells++
	select {
	case <-ctx.Done():
		return languageValue{}, ctx.Err()
	default:
	}
	switch expression.Variant {
	case "int":
		value := new(big.Int)
		if _, ok := value.SetString(expression.Text, 0); !ok {
			return languageValue{}, fmt.Errorf("invalid integer %s", expression.Text)
		}
		return languageValue{kind: valueNumber, num: value}, nil
	case "string":
		value, err := strconv.Unquote(expression.Text)
		if err != nil {
			return languageValue{}, err
		}
		return languageValue{kind: valueString, text: value}, nil
	case "float":
		value, err := strconv.ParseFloat(expression.Text, 64)
		if err != nil {
			return languageValue{}, err
		}
		return languageValue{kind: valueFloat, real: value}, nil
	case "name", "constructor":
		value := environment[expression.Text]
		if value == nil {
			return languageValue{}, fmt.Errorf("undefined name %s", expression.Text)
		}
		return value.force()
	case "application":
		function, err := r.eval(ctx, *expression.Func, environment)
		if err != nil {
			return languageValue{}, err
		}
		argument, err := r.eval(ctx, *expression.Arg, environment)
		if err != nil {
			return languageValue{}, err
		}
		return applyLanguage(ctx, function, argument)
	case "infix":
		if expression.Text == ":" {
			head, err := r.eval(ctx, *expression.Head, environment)
			if err != nil {
				return languageValue{}, err
			}
			var tail languageValue
			var tailErr error
			var once sync.Once
			return languageValue{kind: valueList, list: &lazyList{next: func(ctx context.Context, index int) (languageValue, bool, error) {
				if index == 0 {
					return head, true, nil
				}
				once.Do(func() { tail, tailErr = r.eval(ctx, *expression.Tail, environment) })
				if tailErr != nil {
					return languageValue{}, false, tailErr
				}
				if tail.kind != valueList {
					return languageValue{}, false, errors.New("list expected")
				}
				return tail.list.at(ctx, index-1)
			}}}, nil
		}
		if isComparison(expression.Text) && expression.Head != nil && expression.Head.Variant == "infix" && isComparison(expression.Head.Text) {
			left, err := r.eval(ctx, *expression.Head.Head, environment)
			if err != nil {
				return languageValue{}, err
			}
			middle, err := r.eval(ctx, *expression.Head.Tail, environment)
			if err != nil {
				return languageValue{}, err
			}
			right, err := r.eval(ctx, *expression.Tail, environment)
			if err != nil {
				return languageValue{}, err
			}
			first, err := compareLanguage(expression.Head.Text, left, middle)
			if err != nil {
				return languageValue{}, err
			}
			second, err := compareLanguage(expression.Text, middle, right)
			if err != nil {
				return languageValue{}, err
			}
			return languageValue{kind: valueBool, flag: first && second}, nil
		}
		function := environment[expression.Text]
		if function == nil {
			return languageValue{}, fmt.Errorf("undefined operator %s", expression.Text)
		}
		value, err := function.force()
		if err != nil {
			return languageValue{}, err
		}
		left, err := r.eval(ctx, *expression.Head, environment)
		if err != nil {
			return languageValue{}, err
		}
		value, err = applyLanguage(ctx, value, left)
		if err != nil {
			return languageValue{}, err
		}
		right, err := r.eval(ctx, *expression.Tail, environment)
		if err != nil {
			return languageValue{}, err
		}
		return applyLanguage(ctx, value, right)
	case "section_left", "section_right":
		operator := environment[expression.Text]
		if operator == nil {
			return languageValue{}, fmt.Errorf("undefined operator %s", expression.Text)
		}
		fixed, err := r.eval(ctx, *expression.Arg, environment)
		if err != nil {
			return languageValue{}, err
		}
		return languageValue{kind: valueFunction, fn: func(ctx context.Context, argument languageValue) (languageValue, error) {
			fn, err := operator.force()
			if err != nil {
				return languageValue{}, err
			}
			first, second := fixed, argument
			if expression.Variant == "section_right" {
				first, second = argument, fixed
			}
			fn, err = applyLanguage(ctx, fn, first)
			if err != nil {
				return languageValue{}, err
			}
			return applyLanguage(ctx, fn, second)
		}}, nil
	case "op_func":
		value := environment[expression.Text]
		if value == nil {
			return languageValue{}, fmt.Errorf("undefined operator %s", expression.Text)
		}
		return value.force()
	case "neg":
		value, err := r.eval(ctx, *expression.Arg, environment)
		if err != nil {
			return languageValue{}, err
		}
		if value.kind == valueFloat {
			return languageValue{kind: valueFloat, real: -value.real}, nil
		}
		n, err := numberValue(value)
		if err != nil {
			return languageValue{}, err
		}
		return languageValue{kind: valueNumber, num: new(big.Int).Neg(n)}, nil
	case "list":
		values := make([]languageValue, len(expression.Items))
		for index := range expression.Items {
			value, err := r.eval(ctx, expression.Items[index], environment)
			if err != nil {
				return languageValue{}, err
			}
			values[index] = value
		}
		return listValue(values), nil
	case "tuple":
		values := make([]languageValue, len(expression.Items))
		for index := range expression.Items {
			value, err := r.eval(ctx, expression.Items[index], environment)
			if err != nil {
				return languageValue{}, err
			}
			values[index] = value
		}
		return languageValue{kind: valueTuple, items: values}, nil
	case "range":
		start, err := r.eval(ctx, *expression.Head, environment)
		if err != nil {
			return languageValue{}, err
		}
		from, err := numberValue(start)
		if err != nil {
			return languageValue{}, err
		}
		step := big.NewInt(1)
		if expression.Step != nil {
			value, e := r.eval(ctx, *expression.Step, environment)
			if e != nil {
				return languageValue{}, e
			}
			second, e := numberValue(value)
			if e != nil {
				return languageValue{}, e
			}
			step = new(big.Int).Sub(second, from)
		}
		var end *big.Int
		if expression.To != nil {
			value, e := r.eval(ctx, *expression.To, environment)
			if e != nil {
				return languageValue{}, e
			}
			end, e = numberValue(value)
			if e != nil {
				return languageValue{}, e
			}
		}
		origin, increment := new(big.Int).Set(from), new(big.Int).Set(step)
		return languageValue{kind: valueList, list: &lazyList{next: func(ctx context.Context, index int) (languageValue, bool, error) {
			current := new(big.Int).Add(origin, new(big.Int).Mul(increment, big.NewInt(int64(index))))
			if end != nil && (increment.Sign() >= 0 && current.Cmp(end) > 0 || increment.Sign() < 0 && current.Cmp(end) < 0) {
				return languageValue{}, false, nil
			}
			return languageValue{kind: valueNumber, num: current}, true, nil
		}}}, nil
	case "length":
		value, err := r.eval(ctx, *expression.Arg, environment)
		if err != nil {
			return languageValue{}, err
		}
		if value.kind == valueString {
			return languageValue{kind: valueNumber, num: big.NewInt(int64(len([]rune(value.text))))}, nil
		}
		items, err := finiteList(ctx, value, 1_000_000)
		if err != nil {
			return languageValue{}, err
		}
		return languageValue{kind: valueNumber, num: big.NewInt(int64(len(items)))}, nil
	case "listcomp":
		environments := []map[string]*languageThunk{cloneEnvironment(environment)}
		for _, qualifier := range expression.Qualifiers {
			var next []map[string]*languageThunk
			for _, candidate := range environments {
				if qualifier.Guard != nil {
					guard, err := r.eval(ctx, *qualifier.Guard, candidate)
					if err != nil {
						return languageValue{}, err
					}
					if guard.kind == valueBool && guard.flag {
						next = append(next, candidate)
					}
					continue
				}
				source, err := r.eval(ctx, *qualifier.Source, candidate)
				if err != nil {
					return languageValue{}, err
				}
				values, err := finiteList(ctx, source, 1_000_000)
				if err != nil {
					return languageValue{}, err
				}
				for _, value := range values {
					bound := cloneEnvironment(candidate)
					if matchRuntimePattern(*qualifier.Pattern, value, bound) {
						next = append(next, bound)
					}
				}
			}
			environments = next
		}
		values := make([]languageValue, 0, len(environments))
		for _, candidate := range environments {
			value, err := r.eval(ctx, *expression.Body, candidate)
			if err != nil {
				return languageValue{}, err
			}
			values = append(values, value)
		}
		return listValue(values), nil
	default:
		return languageValue{}, fmt.Errorf("unsupported expression %s", expression.Variant)
	}
}

func isComparison(operator string) bool {
	switch operator {
	case "=", "~=", "<", "<=", ">", ">=":
		return true
	}
	return false
}
func compareLanguage(operator string, left, right languageValue) (bool, error) {
	if left.kind == valueNumber && right.kind == valueNumber {
		comparison := left.num.Cmp(right.num)
		switch operator {
		case "=":
			return comparison == 0, nil
		case "~=":
			return comparison != 0, nil
		case "<":
			return comparison < 0, nil
		case "<=":
			return comparison <= 0, nil
		case ">":
			return comparison > 0, nil
		case ">=":
			return comparison >= 0, nil
		}
	}
	return false, errors.New("comparable values expected")
}

func applyLanguage(ctx context.Context, function, argument languageValue) (languageValue, error) {
	if function.kind != valueFunction || function.fn == nil {
		return languageValue{}, errors.New("function expected")
	}
	return function.fn(ctx, argument)
}

func numberValue(value languageValue) (*big.Int, error) {
	if value.kind != valueNumber || value.num == nil {
		return nil, errors.New("number expected")
	}
	return new(big.Int).Set(value.num), nil
}

func listValue(values []languageValue) languageValue {
	return languageValue{kind: valueList, list: &lazyList{values: append([]languageValue(nil), values...)}}
}

func curry2(operation func(context.Context, languageValue, languageValue) (languageValue, error)) languageValue {
	return languageValue{kind: valueFunction, fn: func(ctx context.Context, first languageValue) (languageValue, error) {
		return languageValue{kind: valueFunction, fn: func(ctx context.Context, second languageValue) (languageValue, error) {
			return operation(ctx, first, second)
		}}, nil
	}}
}

func curry3(operation func(context.Context, languageValue, languageValue, languageValue) (languageValue, error)) languageValue {
	return languageValue{kind: valueFunction, fn: func(ctx context.Context, a languageValue) (languageValue, error) {
		return curry2(func(ctx context.Context, b, c languageValue) (languageValue, error) { return operation(ctx, a, b, c) }), nil
	}}
}

func realValue(value languageValue) (float64, error) {
	if value.kind == valueFloat {
		return value.real, nil
	}
	if value.kind == valueNumber {
		result, _ := new(big.Float).SetInt(value.num).Float64()
		return result, nil
	}
	return 0, errors.New("number expected")
}

func (r *languageRuntime) builtin(name string, value languageValue) {
	r.globals[name] = immediate(value)
}

func (r *languageRuntime) installBuiltins() {
	integer := func(op func(*big.Int, *big.Int) *big.Int) languageValue {
		return curry2(func(_ context.Context, a, b languageValue) (languageValue, error) {
			x, e := numberValue(a)
			if e != nil {
				return languageValue{}, e
			}
			y, e := numberValue(b)
			if e != nil {
				return languageValue{}, e
			}
			return languageValue{kind: valueNumber, num: op(x, y)}, nil
		})
	}
	r.builtin("+", numericBinary(func(a, b *big.Int) *big.Int { return new(big.Int).Add(a, b) }, func(a, b float64) float64 { return a + b }))
	r.builtin("-", integer(func(a, b *big.Int) *big.Int { return new(big.Int).Sub(a, b) }))
	r.builtin("*", numericBinary(func(a, b *big.Int) *big.Int { return new(big.Int).Mul(a, b) }, func(a, b float64) float64 { return a * b }))
	r.builtin("^", integer(func(a, b *big.Int) *big.Int {
		if !b.IsInt64() || b.Sign() < 0 {
			return big.NewInt(0)
		}
		return new(big.Int).Exp(a, b, nil)
	}))
	r.builtin("div", curry2(func(_ context.Context, a, b languageValue) (languageValue, error) {
		x, e := numberValue(a)
		if e != nil {
			return languageValue{}, e
		}
		y, e := numberValue(b)
		if e != nil {
			return languageValue{}, e
		}
		if y.Sign() == 0 {
			return languageValue{}, errors.New("division by zero")
		}
		return languageValue{kind: valueNumber, num: new(big.Int).Div(x, y)}, nil
	}))
	r.builtin("mod", curry2(func(_ context.Context, a, b languageValue) (languageValue, error) {
		x, e := numberValue(a)
		if e != nil {
			return languageValue{}, e
		}
		y, e := numberValue(b)
		if e != nil {
			return languageValue{}, e
		}
		if y.Sign() == 0 {
			return languageValue{}, errors.New("division by zero")
		}
		return languageValue{kind: valueNumber, num: new(big.Int).Mod(x, y)}, nil
	}))
	r.builtin("/", curry2(func(_ context.Context, a, b languageValue) (languageValue, error) {
		x, e := realValue(a)
		if e != nil {
			return languageValue{}, e
		}
		y, e := realValue(b)
		if e != nil {
			return languageValue{}, e
		}
		if y == 0 {
			return languageValue{}, errors.New("division by zero")
		}
		return languageValue{kind: valueFloat, real: x / y}, nil
	}))
	r.builtin("True", languageValue{kind: valueBool, flag: true})
	r.builtin("False", languageValue{kind: valueBool, flag: false})
	for name, comparison := range map[string]func(int) bool{"=": func(c int) bool { return c == 0 }, "~=": func(c int) bool { return c != 0 }, "<": func(c int) bool { return c < 0 }, "<=": func(c int) bool { return c <= 0 }, ">": func(c int) bool { return c > 0 }, ">=": func(c int) bool { return c >= 0 }} {
		compare := comparison
		r.builtin(name, curry2(func(_ context.Context, a, b languageValue) (languageValue, error) {
			x, e := numberValue(a)
			if e != nil {
				return languageValue{}, e
			}
			y, e := numberValue(b)
			if e != nil {
				return languageValue{}, e
			}
			return languageValue{kind: valueBool, flag: compare(x.Cmp(y))}, nil
		}))
	}
	r.builtin("product", languageValue{kind: valueFunction, fn: func(ctx context.Context, input languageValue) (languageValue, error) {
		values, e := finiteList(ctx, input, 1_000_000)
		if e != nil {
			return languageValue{}, e
		}
		total := big.NewInt(1)
		for _, v := range values {
			n, e := numberValue(v)
			if e != nil {
				return languageValue{}, e
			}
			total.Mul(total, n)
		}
		return languageValue{kind: valueNumber, num: total}, nil
	}})
	r.builtin("sum", languageValue{kind: valueFunction, fn: func(ctx context.Context, input languageValue) (languageValue, error) {
		values, err := finiteList(ctx, input, 1_000_000)
		if err != nil {
			return languageValue{}, err
		}
		total := big.NewInt(0)
		for _, value := range values {
			number, err := numberValue(value)
			if err != nil {
				return languageValue{}, err
			}
			total.Add(total, number)
		}
		return languageValue{kind: valueNumber, num: total}, nil
	}})
	r.builtin("max", languageValue{kind: valueFunction, fn: func(ctx context.Context, input languageValue) (languageValue, error) {
		values, err := finiteList(ctx, input, 1_000_000)
		if err != nil {
			return languageValue{}, err
		}
		if len(values) == 0 {
			return languageValue{}, errors.New("non-empty list expected")
		}
		result, err := numberValue(values[0])
		if err != nil {
			return languageValue{}, err
		}
		for _, value := range values[1:] {
			number, err := numberValue(value)
			if err != nil {
				return languageValue{}, err
			}
			if number.Cmp(result) > 0 {
				result = number
			}
		}
		return languageValue{kind: valueNumber, num: result}, nil
	}})
	r.builtin("reverse", languageValue{kind: valueFunction, fn: func(ctx context.Context, input languageValue) (languageValue, error) {
		if input.kind == valueString {
			runes := []rune(input.text)
			for left, right := 0, len(runes)-1; left < right; left, right = left+1, right-1 {
				runes[left], runes[right] = runes[right], runes[left]
			}
			return languageValue{kind: valueString, text: string(runes)}, nil
		}
		values, e := finiteList(ctx, input, 1_000_000)
		if e != nil {
			return languageValue{}, e
		}
		for l, h := 0, len(values)-1; l < h; l, h = l+1, h-1 {
			values[l], values[h] = values[h], values[l]
		}
		return listValue(values), nil
	}})
	r.builtin("take", curry2(func(ctx context.Context, count, input languageValue) (languageValue, error) {
		if input.kind != valueList || input.list == nil {
			return languageValue{}, errors.New("list expected")
		}
		n, e := numberValue(count)
		if e != nil {
			return languageValue{}, e
		}
		if !n.IsInt64() || n.Sign() < 0 {
			return languageValue{}, errors.New("invalid take count")
		}
		values := make([]languageValue, 0, n.Int64())
		for index := 0; index < int(n.Int64()); index++ {
			v, ok, e := input.list.at(ctx, index)
			if e != nil {
				return languageValue{}, e
			}
			if !ok {
				break
			}
			values = append(values, v)
		}
		return listValue(values), nil
	}))
	r.builtin("map", curry2(func(ctx context.Context, function, input languageValue) (languageValue, error) {
		if input.kind != valueList {
			return languageValue{}, errors.New("list expected")
		}
		return languageValue{kind: valueList, list: &lazyList{next: func(ctx context.Context, index int) (languageValue, bool, error) {
			v, ok, e := input.list.at(ctx, index)
			if e != nil || !ok {
				return languageValue{}, ok, e
			}
			mapped, e := applyLanguage(ctx, function, v)
			return mapped, e == nil, e
		}}}, nil
	}))
	r.builtin("filter", curry2(func(ctx context.Context, predicate, input languageValue) (languageValue, error) {
		values, e := finiteList(ctx, input, 1_000_000)
		if e != nil {
			return languageValue{}, e
		}
		out := make([]languageValue, 0, len(values))
		for _, value := range values {
			keep, e := applyLanguage(ctx, predicate, value)
			if e != nil {
				return languageValue{}, e
			}
			if keep.kind != valueBool {
				return languageValue{}, errors.New("truthvalue expected")
			}
			if keep.flag {
				out = append(out, value)
			}
		}
		return listValue(out), nil
	}))
	r.builtin("foldl", curry3(func(ctx context.Context, function, initial, input languageValue) (languageValue, error) {
		values, e := finiteList(ctx, input, 1_000_000)
		if e != nil {
			return languageValue{}, e
		}
		result := initial
		for _, value := range values {
			step, e := applyLanguage(ctx, function, result)
			if e != nil {
				return languageValue{}, e
			}
			result, e = applyLanguage(ctx, step, value)
			if e != nil {
				return languageValue{}, e
			}
		}
		return result, nil
	}))
	r.builtin("foldr", curry3(func(ctx context.Context, function, initial, input languageValue) (languageValue, error) {
		values, e := finiteList(ctx, input, 1_000_000)
		if e != nil {
			return languageValue{}, e
		}
		result := initial
		for index := len(values) - 1; index >= 0; index-- {
			step, e := applyLanguage(ctx, function, values[index])
			if e != nil {
				return languageValue{}, e
			}
			result, e = applyLanguage(ctx, step, result)
			if e != nil {
				return languageValue{}, e
			}
		}
		return result, nil
	}))
	r.builtin("show", languageValue{kind: valueFunction, fn: func(ctx context.Context, value languageValue) (languageValue, error) {
		text, e := showLanguage(ctx, value)
		if e != nil {
			return languageValue{}, e
		}
		return languageValue{kind: valueString, text: text}, nil
	}})
	r.builtin("showhex", languageValue{kind: valueFunction, fn: func(_ context.Context, value languageValue) (languageValue, error) {
		number, err := numberValue(value)
		if err != nil {
			return languageValue{}, err
		}
		return languageValue{kind: valueString, text: "0x" + number.Text(16)}, nil
	}})
	r.builtin("showoct", languageValue{kind: valueFunction, fn: func(_ context.Context, value languageValue) (languageValue, error) {
		number, err := numberValue(value)
		if err != nil {
			return languageValue{}, err
		}
		return languageValue{kind: valueString, text: "0o" + number.Text(8)}, nil
	}})
	r.builtin("numval", languageValue{kind: valueFunction, fn: func(_ context.Context, value languageValue) (languageValue, error) {
		if value.kind != valueString {
			return languageValue{}, errors.New("string expected")
		}
		number := new(big.Int)
		if _, ok := number.SetString(value.text, 0); !ok {
			return languageValue{}, errors.New("invalid numeral")
		}
		return languageValue{kind: valueNumber, num: number}, nil
	}})
	r.builtin("entier", languageValue{kind: valueFunction, fn: func(_ context.Context, value languageValue) (languageValue, error) {
		number, err := realValue(value)
		if err != nil {
			return languageValue{}, err
		}
		result := new(big.Int)
		new(big.Float).SetFloat64(math.Floor(number)).Int(result)
		return languageValue{kind: valueNumber, num: result}, nil
	}})
	r.builtin("and", languageValue{kind: valueFunction, fn: func(ctx context.Context, value languageValue) (languageValue, error) {
		items, err := finiteList(ctx, value, 1_000_000)
		if err != nil {
			return languageValue{}, err
		}
		for _, item := range items {
			if item.kind != valueBool {
				return languageValue{}, errors.New("truthvalue expected")
			}
			if !item.flag {
				return languageValue{kind: valueBool, flag: false}, nil
			}
		}
		return languageValue{kind: valueBool, flag: true}, nil
	}})
	r.builtin("system", languageValue{kind: valueFunction, fn: func(ctx context.Context, value languageValue) (languageValue, error) {
		if value.kind != valueString {
			return languageValue{}, errors.New("string expected")
		}
		stdout, stderr, status, err := platformsvc.CaptureShell(ctx, value.text)
		if err != nil {
			return languageValue{}, err
		}
		return languageValue{kind: valueTuple, items: []languageValue{{kind: valueString, text: stdout}, {kind: valueString, text: stderr}, {kind: valueNumber, num: big.NewInt(int64(status))}}}, nil
	}})
	r.builtin("readvals", languageValue{kind: valueFunction, fn: func(ctx context.Context, path languageValue) (languageValue, error) {
		if path.kind != valueString {
			return languageValue{}, errors.New("string expected")
		}
		data, err := os.ReadFile(path.text)
		if err != nil {
			return languageValue{}, err
		}
		var values []languageValue
		for _, line := range strings.Split(strings.TrimSpace(string(data)), "\n") {
			expression, err := parseRuntimeExpression(strings.TrimSpace(line))
			if err != nil {
				return languageValue{}, err
			}
			value, err := r.eval(ctx, expression, r.globals)
			if err != nil {
				return languageValue{}, err
			}
			values = append(values, value)
			if r.output != nil {
				text, err := renderLanguage(ctx, value)
				if err != nil {
					return languageValue{}, err
				}
				fmt.Fprintln(r.output, text)
			}
		}
		return listValue(values), nil
	}})
	r.builtin("Appendfile", languageValue{kind: valueFunction, fn: func(_ context.Context, path languageValue) (languageValue, error) {
		if path.kind != valueString {
			return languageValue{}, errors.New("string expected")
		}
		r.appendFiles[path.text] = true
		return languageValue{kind: valueMessage}, nil
	}})
	r.builtin("Tofile", curry2(func(_ context.Context, path, message languageValue) (languageValue, error) {
		if path.kind != valueString || message.kind != valueString {
			return languageValue{}, errors.New("string expected")
		}
		appendMode := r.appendFiles[path.text]
		delete(r.appendFiles, path.text)
		if err := platformsvc.WriteText(path.text, message.text, appendMode); err != nil {
			return languageValue{}, err
		}
		return languageValue{kind: valueMessage}, nil
	}))
	for name, function := range map[string]func(float64) float64{"sin": math.Sin, "cos": math.Cos, "tan": math.Tan} {
		function := function
		r.builtin(name, languageValue{kind: valueFunction, fn: func(_ context.Context, value languageValue) (languageValue, error) {
			number, e := realValue(value)
			if e != nil {
				return languageValue{}, e
			}
			return languageValue{kind: valueFloat, real: function(number)}, nil
		}})
	}
	r.builtin("zip2", curry2(func(ctx context.Context, a, b languageValue) (languageValue, error) {
		return languageValue{kind: valueList, list: &lazyList{next: func(ctx context.Context, index int) (languageValue, bool, error) {
			x, ok, e := a.list.at(ctx, index)
			if e != nil || !ok {
				return languageValue{}, ok, e
			}
			y, ok, e := b.list.at(ctx, index)
			if e != nil || !ok {
				return languageValue{}, ok, e
			}
			return languageValue{kind: valueTuple, items: []languageValue{x, y}}, true, nil
		}}}, nil
	}))
	r.builtin("++", curry2(func(ctx context.Context, a, b languageValue) (languageValue, error) {
		if a.kind == valueString && b.kind == valueString {
			return languageValue{kind: valueString, text: a.text + b.text}, nil
		}
		if a.kind == valueString && b.kind == valueList {
			empty, err := finiteList(ctx, b, 1)
			if err == nil && len(empty) == 0 {
				return a, nil
			}
		}
		left, e := finiteList(ctx, a, 1_000_000)
		if e != nil {
			return languageValue{}, e
		}
		right, e := finiteList(ctx, b, 1_000_000)
		if e != nil {
			return languageValue{}, e
		}
		return listValue(append(left, right...)), nil
	}))
}

func numericBinary(integer func(*big.Int, *big.Int) *big.Int, floating func(float64, float64) float64) languageValue {
	return curry2(func(_ context.Context, a, b languageValue) (languageValue, error) {
		if a.kind == valueNumber && b.kind == valueNumber {
			return languageValue{kind: valueNumber, num: integer(new(big.Int).Set(a.num), new(big.Int).Set(b.num))}, nil
		}
		x, err := realValue(a)
		if err != nil {
			return languageValue{}, err
		}
		y, err := realValue(b)
		if err != nil {
			return languageValue{}, err
		}
		return languageValue{kind: valueFloat, real: floating(x, y)}, nil
	})
}

func finiteList(ctx context.Context, value languageValue, limit int) ([]languageValue, error) {
	if value.kind != valueList || value.list == nil {
		return nil, errors.New("list expected")
	}
	var out []languageValue
	for index := 0; index < limit; index++ {
		item, ok, err := value.list.at(ctx, index)
		if err != nil {
			return nil, err
		}
		if !ok {
			return out, nil
		}
		out = append(out, item)
	}
	return nil, errors.New("list output limit exceeded")
}

func renderLanguage(ctx context.Context, value languageValue) (string, error) {
	switch value.kind {
	case valueNumber:
		return value.num.String(), nil
	case valueFloat:
		text := strconv.FormatFloat(value.real, 'f', -1, 64)
		if !strings.ContainsAny(text, ".eE") {
			text += ".0"
		}
		return text, nil
	case valueBool:
		if value.flag {
			return "True", nil
		}
		return "False", nil
	case valueString:
		return value.text, nil
	case valueTuple:
		parts := make([]string, len(value.items))
		for i, item := range value.items {
			text, e := renderNestedLanguage(ctx, item)
			if e != nil {
				return "", e
			}
			parts[i] = text
		}
		return "(" + strings.Join(parts, ",") + ")", nil
	case valueConstructor:
		return renderConstructor(ctx, value, false)
	case valueList:
		values, e := finiteList(ctx, value, 100000)
		if e != nil {
			return "", e
		}
		parts := make([]string, 0, len(values))
		for _, item := range values {
			if item.kind == valueMessage {
				continue
			}
			text, e := renderLanguage(ctx, item)
			if e != nil {
				return "", e
			}
			parts = append(parts, text)
		}
		if len(parts) == 0 && len(values) > 0 {
			return "", nil
		}
		return "[" + strings.Join(parts, ",") + "]", nil
	default:
		return "", errors.New("cannot display function")
	}
}

func renderConstructor(ctx context.Context, value languageValue, nested bool) (string, error) {
	parts := []string{value.name}
	for _, argument := range value.items {
		text, err := renderNestedLanguage(ctx, argument)
		if err != nil {
			return "", err
		}
		parts = append(parts, text)
	}
	result := strings.Join(parts, " ")
	if nested && len(value.items) > 0 {
		return "(" + result + ")", nil
	}
	return result, nil
}

func showLanguage(ctx context.Context, value languageValue) (string, error) {
	if value.kind == valueString {
		return strconv.Quote(value.text), nil
	}
	return renderLanguage(ctx, value)
}

func renderNestedLanguage(ctx context.Context, value languageValue) (string, error) {
	if value.kind == valueString {
		return strconv.Quote(value.text), nil
	}
	if value.kind == valueConstructor {
		return renderConstructor(ctx, value, true)
	}
	return renderLanguage(ctx, value)
}
