package application

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"math"
	"math/big"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"unicode/utf8"

	"github.com/pkreyenhop/miracula/internal/platformsvc"
	"github.com/pkreyenhop/miracula/internal/semantics"
	"github.com/pkreyenhop/miracula/internal/syntaxfront"
)

type valueKind uint8

const (
	valueNumber valueKind = iota
	valueFloat
	valueBool
	valueChar
	valueString
	valueList
	valueTuple
	valueConstructor
	valueMessage
	valueFunction
	valueThunk
)

type languageTypeMismatch struct {
	actual, expected string
}

func (e *languageTypeMismatch) Error() string { return "list expected" }

func listTypeMismatch(value languageValue) error {
	actual := "?"
	switch value.kind {
	case valueNumber:
		actual = "num"
	case valueFloat:
		actual = "num"
	case valueBool:
		actual = "bool"
	case valueChar:
		actual = "char"
	case valueString:
		actual = "[char]"
	case valueList:
		actual = "[*]"
	case valueTuple:
		actual = "(**,**)"
	case valueFunction:
		actual = "*->**"
	}
	return &languageTypeMismatch{actual: actual, expected: "[*]"}
}

type languageValue struct {
	kind   valueKind
	num    *big.Int
	small  int64
	real   float64
	flag   bool
	text   string
	list   *lazyList
	items  []languageValue
	name   string
	thunk  *languageThunk
	fn     func(context.Context, languageValue) (languageValue, error)
	lazyFn func(context.Context, *languageThunk) (languageValue, error)
	intFn  func(context.Context, int64) (int64, bool, error)
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
			value, err := forceLanguageValue(value, nil)
			return value, true, err
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
	globals             map[string]*languageThunk
	productConstructors map[string]bool
	appendFiles         map[string]bool
	output              io.Writer
	input               io.Reader
	arguments           []string
	inputMu             sync.Mutex
	inputData           []byte
	inputRead           bool
	inputMode           int
	libraryPath         string
	includeLoading      map[string]bool
	provenance          map[string]sourceProvenance
	nextModuleInstance  uint64
	reductions          uint64
	cells               uint64
}

type sourceProvenance struct {
	Path, Original string
	Instance       uint64
}

type languageThunk struct {
	mu         sync.Mutex
	value      languageValue
	err        error
	eval       func() (languageValue, error)
	ready      bool
	evaluating bool
}

type languageCallFrame struct {
	environment map[string]*languageThunk
	bindings    []languageThunk
}

type environmentStream func(context.Context) (map[string]*languageThunk, bool, error)

func (t *languageThunk) force() (languageValue, error) {
	t.mu.Lock()
	if t.ready {
		value, err := t.value, t.err
		t.mu.Unlock()
		return forceLanguageValue(value, err)
	}
	if t.evaluating {
		t.mu.Unlock()
		return languageValue{}, errors.New("cyclic evaluation")
	}
	t.evaluating = true
	evaluate := t.eval
	t.mu.Unlock()
	value, err := evaluate()
	t.mu.Lock()
	if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		t.evaluating = false
		t.mu.Unlock()
		return value, err
	}
	t.value, t.err, t.eval, t.ready, t.evaluating = value, err, nil, true, false
	t.mu.Unlock()
	return forceLanguageValue(value, err)
}

func forceLanguageValue(value languageValue, err error) (languageValue, error) {
	for err == nil && value.kind == valueThunk && value.thunk != nil {
		value, err = value.thunk.force()
	}
	return value, err
}

func deepForceLanguage(ctx context.Context, value languageValue) error {
	value, err := forceLanguageValue(value, nil)
	if err != nil {
		return err
	}
	switch value.kind {
	case valueTuple, valueConstructor:
		for _, item := range value.items {
			if err := deepForceLanguage(ctx, item); err != nil {
				return err
			}
		}
	case valueList:
		for index := 0; ; index++ {
			item, ok, err := value.list.at(ctx, index)
			if err != nil || !ok {
				return err
			}
			if err := deepForceLanguage(ctx, item); err != nil {
				return err
			}
		}
	}
	return nil
}

func newLanguageRuntime(output io.Writer) *languageRuntime {
	r := &languageRuntime{globals: map[string]*languageThunk{}, productConstructors: map[string]bool{}, appendFiles: map[string]bool{}, output: output, input: strings.NewReader(""), includeLoading: map[string]bool{}, provenance: map[string]sourceProvenance{}}
	r.installBuiltins()
	return r
}

func (i *Interpreter) runtime() *languageRuntime {
	if i.language == nil {
		i.language = newLanguageRuntime(i.Output)
	}
	if i.Input != nil {
		i.language.input = i.Input
	}
	i.language.arguments = append(i.language.arguments[:0], i.Arguments...)
	i.language.libraryPath = i.Config.LibraryPath
	return i.language
}

func (r *languageRuntime) prepareInput(closed bool) {
	r.inputMu.Lock()
	defer r.inputMu.Unlock()
	if closed {
		r.input = strings.NewReader("")
	}
	r.inputData = nil
	r.inputRead = false
	r.inputMode = 0
}

func immediate(value languageValue) *languageThunk {
	return &languageThunk{value: value, ready: true}
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
			return r.function(parameters, definition.RHS, nil), nil
		}
		r.globals[name] = thunk
	}
	return nil
}

type runtimeClause struct {
	parameters  []syntaxfront.Expr
	body        syntaxfront.Expr
	condition   *syntaxfront.Expr
	otherwise   bool
	localSource []byte
	closure     map[string]*languageThunk
}

// installSource preserves guarded equations, whose continuation-line shape is
// intentionally models the complete language syntax needed by evaluation.
func (r *languageRuntime) installSource(source []byte) error {
	clauses := map[string][]runtimeClause{}
	type conformalBinding struct{ pattern, body syntaxfront.Expr }
	var conformals []conformalBinding
	currentName := ""
	var currentParameters []syntaxfront.Expr
	closed := map[string]bool{}
	previousAlternativeWasOtherwise := false
	lines := logicalSourceLines(source)
	currentIndent := 0
	for lineIndex := 0; lineIndex < len(lines); lineIndex++ {
		rawLine := lines[lineIndex]
		line := strings.TrimSpace(rawLine)
		if line == "" || strings.HasPrefix(line, "||") || strings.HasPrefix(line, "%") {
			continue
		}
		if line == "where" {
			var localLines []string
			minimum := -1
			for lineIndex+1 < len(lines) {
				next := lines[lineIndex+1]
				trimmed := strings.TrimSpace(next)
				if trimmed == "" {
					lineIndex++
					continue
				}
				indent := leadingIndent(next)
				if indent <= currentIndent {
					break
				}
				lineIndex++
				if minimum < 0 || indent < minimum {
					minimum = indent
				}
				localLines = append(localLines, next)
			}
			if currentName == "" || len(localLines) == 0 {
				return errors.New("where must qualify a definition")
			}
			for index := range localLines {
				if len(localLines[index]) >= minimum {
					localLines[index] = localLines[index][minimum:]
				}
			}
			localSource := []byte(strings.Join(localLines, "\n") + "\n")
			for index := range clauses[currentName] {
				clauses[currentName][index].localSource = localSource
			}
			continue
		}
		if marker := strings.Index(line, "::="); marker >= 0 {
			alternatives := strings.Split(line[marker+3:], "|")
			for _, alternative := range alternatives {
				fields := runtimeConstructorFields(strings.TrimSpace(alternative))
				if len(fields) == 0 {
					continue
				}
				strict := make([]bool, len(fields)-1)
				for index, field := range fields[1:] {
					strict[index] = strings.HasSuffix(field, "!")
				}
				r.installConstructor(fields[0], strict)
				if len(alternatives) == 1 && len(strict) > 0 {
					r.productConstructors[fields[0]] = true
				}
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
			name, parameters, parsed := runtimePatterns(lhsParsed.Script.Items[0].LHS)
			if !parsed {
				pattern := lhsParsed.Script.Items[0].LHS
				if patternBindingCount(pattern) == 0 {
					return errors.New("conformal definition must bind at least one name")
				}
				body, err := parseRuntimeExpression(right)
				if err != nil {
					return err
				}
				conformals = append(conformals, conformalBinding{pattern: pattern, body: body})
				currentName = ""
				continue
			}
			if currentName != "" && name != currentName {
				closed[currentName] = true
			}
			if closed[name] {
				return fmt.Errorf("non-contiguous or duplicate top-level binding %s", name)
			}
			if existing := clauses[name]; len(existing) > 0 && len(existing[0].parameters) != len(parameters) {
				return fmt.Errorf("inconsistent arity in definition of %s", name)
			}
			for _, pattern := range parameters {
				if err := validateRuntimePattern(pattern); err != nil {
					return fmt.Errorf("%s: %w", name, err)
				}
			}
			currentName, currentParameters, ok = name, parameters, true
			currentIndent = leadingIndent(rawLine)
			previousAlternativeWasOtherwise = false
			if !ok {
				continue
			}
		}
		if currentName == "" || right == "" {
			continue
		}
		if left == "" && previousAlternativeWasOtherwise {
			return fmt.Errorf("otherwise must be the final alternative of %s", currentName)
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
		clause := runtimeClause{parameters: append([]syntaxfront.Expr(nil), currentParameters...), body: body, otherwise: strings.HasSuffix(right, ", otherwise")}
		if conditionText != "" {
			condition, err := parseRuntimeExpression(conditionText)
			if err != nil {
				return fmt.Errorf("%s guard: %w", currentName, err)
			}
			clause.condition = &condition
		}
		clauses[currentName] = append(clauses[currentName], clause)
		previousAlternativeWasOtherwise = clause.otherwise
	}
	moduleScope := cloneEnvironment(r.globals)
	for name, alternatives := range clauses {
		name, alternatives := name, alternatives
		for index := range alternatives {
			alternatives[index].closure = moduleScope
		}
		thunk := &languageThunk{}
		thunk.eval = func() (languageValue, error) {
			if len(alternatives[0].parameters) == 0 {
				return r.selectClause(context.Background(), alternatives, nil)
			}
			return r.clauseFunction(alternatives, nil), nil
		}
		r.globals[name] = thunk
		moduleScope[name] = thunk
	}
	for _, conformal := range conformals {
		conformal := conformal
		bindings := map[string]*languageThunk{}
		match := &languageThunk{eval: func() (languageValue, error) {
			value, err := r.eval(context.Background(), conformal.body, r.globals)
			if err != nil {
				return languageValue{}, err
			}
			captured := map[string]*languageThunk{}
			if !r.matchRuntimePattern(conformal.pattern, value, captured) {
				return languageValue{}, errors.New("conformal definition pattern mismatch")
			}
			for name, value := range captured {
				bindings[name] = value
			}
			return languageValue{kind: valueBool, flag: true}, nil
		}}
		names := map[string]bool{}
		collectPatternNames(conformal.pattern, names)
		for name := range names {
			name := name
			if r.globals[name] != nil {
				return fmt.Errorf("duplicate top-level binding %s", name)
			}
			r.globals[name] = &languageThunk{eval: func() (languageValue, error) {
				if _, err := match.force(); err != nil {
					return languageValue{}, err
				}
				return bindings[name].force()
			}}
		}
	}
	return nil
}

func runtimeConstructorFields(text string) []string {
	var fields []string
	start, depth := 0, 0
	for index, char := range text {
		switch char {
		case '(', '[':
			depth++
		case ')', ']':
			depth--
		case ' ', '\t':
			if depth == 0 && start < index {
				fields = append(fields, text[start:index])
				start = index + 1
			} else if depth == 0 {
				start = index + 1
			}
		}
	}
	if start < len(text) {
		fields = append(fields, text[start:])
	}
	return fields
}

func (i *Interpreter) ValidateCurrent() error {
	script, ok := i.Scripts.Scripts[i.Compiler.CurrentModule]
	if !ok {
		return errors.New("no current script")
	}
	var validationErrors SourceValidationErrors
	for _, sourceLine := range logicalSourceLineRecords(script.Source) {
		line := sourceLine.text
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
		for _, name := range undefinedNames(expression, bound, i.runtime().globals) {
			errorPath, errorLine := script.Path, sourceLine.number
			if errorLine > 0 && errorLine <= len(script.Origins) {
				origin := script.Origins[errorLine-1]
				if origin.File != "" {
					errorPath, errorLine = origin.File, origin.Line
				}
			}
			validationErrors = append(validationErrors, SourceValidationError{Path: errorPath, Line: errorLine, Name: name})
		}
	}
	sort.SliceStable(validationErrors, func(left, right int) bool { return validationErrors[left].Line < validationErrors[right].Line })
	if len(validationErrors) != 0 {
		diagnostics := make(DiagnosticSet, 0, len(validationErrors))
		for index, validationErr := range validationErrors {
			diagnostics = append(diagnostics, Diagnostic{Severity: "error", Phase: "name", File: validationErr.Path, Span: syntaxfront.Span{Line: validationErr.Line, Column: 1}, Message: validationErr.Error(), Order: index})
		}
		return diagnostics
	}
	return nil
}

type SourceValidationError struct {
	Path string
	Line int
	Name string
}

func (e SourceValidationError) Error() string { return "undefined name " + e.Name }

type SourceValidationErrors []SourceValidationError

func (e SourceValidationErrors) Error() string {
	if len(e) == 0 {
		return "source validation failed"
	}
	return e[0].Error()
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
	names := undefinedNames(expression, bound, globals)
	if len(names) != 0 {
		return names[0]
	}
	return ""
}

func undefinedNames(expression syntaxfront.Expr, bound map[string]bool, globals map[string]*languageThunk) []string {
	seen := map[string]bool{}
	var names []string
	var visit func(syntaxfront.Expr)
	visit = func(expression syntaxfront.Expr) {
		if expression.Variant == "name" || expression.Variant == "constructor" {
			if !bound[expression.Text] && globals[expression.Text] == nil && !seen[expression.Text] {
				seen[expression.Text] = true
				names = append(names, expression.Text)
			}
		}
		children := []*syntaxfront.Expr{expression.Func, expression.Arg, expression.Head, expression.Tail, expression.Step, expression.To, expression.Body}
		for _, child := range children {
			if child != nil {
				visit(*child)
			}
		}
		for _, item := range expression.Items {
			visit(item)
		}
	}
	visit(expression)
	return names
}

func logicalSourceLines(source []byte) []string {
	records := logicalSourceLineRecords(source)
	result := make([]string, len(records))
	for index := range records {
		result[index] = records[index].text
	}
	return result
}

type logicalSourceLine struct {
	text   string
	number int
}

func logicalSourceLineRecords(source []byte) []logicalSourceLine {
	physical := strings.Split(string(source), "\n")
	result := make([]logicalSourceLine, 0, len(physical))
	for index := 0; index < len(physical); index++ {
		lineNumber := index + 1
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
		result = append(result, logicalSourceLine{text: line, number: lineNumber})
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
			path = filepath.Join(r.libraryPath, path)
		}
		if filepath.Ext(path) == "" {
			path += ".m"
		}
		if !filepath.IsAbs(path) {
			path = filepath.Join(base, path)
		}
		path, _ = filepath.Abs(path)
		if resolved, err := filepath.EvalSymlinks(path); err == nil {
			path = resolved
		}
		if r.includeLoading[path] {
			return fmt.Errorf("cyclic include involving %s", path)
		}
		r.includeLoading[path] = true
		r.nextModuleInstance++
		moduleInstance := r.nextModuleInstance
		included, diagnostics := syntaxfront.LoadSource(path)
		if len(diagnostics) > 0 {
			delete(r.includeLoading, path)
			return errors.New(diagnostics[0].Message)
		}
		before := map[string]*languageThunk{}
		for name, value := range r.globals {
			before[name] = value
		}
		free, err := parseFreeParameters(included.Bytes)
		if err != nil {
			delete(r.includeLoading, path)
			return fmt.Errorf("%s: %w", path, err)
		}
		valueBindings, typeBindings, err := parseIncludeBindings(directive.Bindings)
		if err != nil {
			delete(r.includeLoading, path)
			return err
		}
		if len(free) == 0 && (len(valueBindings) != 0 || len(typeBindings) != 0) {
			delete(r.includeLoading, path)
			return fmt.Errorf("bindings supplied to non-parameterized script %s", path)
		}
		for name, signature := range free {
			if signature == "type" {
				if typeBindings[name] == "" {
					delete(r.includeLoading, path)
					return fmt.Errorf("missing type binding for free identifier %s", name)
				}
				continue
			}
			expressionText, exists := valueBindings[name]
			if !exists {
				delete(r.includeLoading, path)
				return fmt.Errorf("missing value binding for free identifier %s", name)
			}
			if _, ok := syntaxfront.InfixBinding(map[string]string{"+": "plus", "-": "minus", "*": "star", "/": "slash", "&": "ampersand", "\\/": "or"}[expressionText]); ok {
				expressionText = "(" + expressionText + ")"
			}
			for typeName, replacement := range typeBindings {
				signature = strings.ReplaceAll(signature, typeName, replacement)
			}
			if err := checkBoundExpression(expressionText, signature); err != nil {
				delete(r.includeLoading, path)
				return fmt.Errorf("binding %s: %w", name, err)
			}
			expression, err := parseRuntimeExpression(expressionText)
			if err != nil {
				delete(r.includeLoading, path)
				return err
			}
			value, err := r.eval(context.Background(), expression, r.globals)
			if err != nil {
				delete(r.includeLoading, path)
				return err
			}
			r.globals[name] = immediate(value)
		}
		for name := range valueBindings {
			if _, ok := free[name]; !ok {
				delete(r.includeLoading, path)
				return fmt.Errorf("unknown free binding %s", name)
			}
		}
		for name := range typeBindings {
			if free[name] != "type" {
				delete(r.includeLoading, path)
				return fmt.Errorf("unknown free type binding %s", name)
			}
		}
		if parsed := syntaxfront.Run(included.Bytes); len(parsed.Diagnostics) != 0 {
			delete(r.includeLoading, path)
			return fmt.Errorf("included script %s: %s", path, parsed.Diagnostics[0].Message)
		}
		if err := r.installIncludes(filepath.Dir(path), included.Bytes); err != nil {
			delete(r.includeLoading, path)
			return err
		}
		dependencyNames := map[string]bool{}
		for name, value := range r.globals {
			if before[name] != value {
				dependencyNames[name] = true
			}
		}
		beforeLocal := map[string]*languageThunk{}
		for name, value := range r.globals {
			beforeLocal[name] = value
		}
		if err := r.installSource(included.Bytes); err != nil {
			delete(r.includeLoading, path)
			return err
		}
		localNames := map[string]bool{}
		for name, value := range r.globals {
			if beforeLocal[name] != value {
				localNames[name] = true
			}
		}
		exports, explicit := map[string]bool{}, false
		negativeExports := map[string]bool{}
		for _, includedLine := range strings.Split(string(included.Bytes), "\n") {
			exportDirective, ok := syntaxfront.ParseDirective(strings.TrimSpace(includedLine))
			if !ok || exportDirective.Variant != "export" {
				continue
			}
			if explicit {
				delete(r.includeLoading, path)
				return fmt.Errorf("multiple %%export directives in %s", path)
			}
			explicit = true
			fields := strings.Fields(exportDirective.Text)
			for _, part := range fields {
				switch {
				case part == "+":
					for name := range localNames {
						exports[name] = true
					}
				case strings.HasPrefix(part, "-"):
					negativeExports[strings.TrimPrefix(part, "-")] = true
				case strings.HasPrefix(part, "\"") || strings.HasPrefix(part, "<"):
					for name := range dependencyNames {
						exports[name] = true
					}
				default:
					exports[part] = true
				}
			}
		}
		if !explicit {
			exports = localNames
		}
		for name := range negativeExports {
			delete(exports, name)
		}
		for name, value := range r.globals {
			if before[name] != value && !exports[name] {
				if old := before[name]; old != nil {
					r.globals[name] = old
				} else {
					delete(r.globals, name)
				}
			}
		}
		for _, alias := range directive.Aliases {
			if alias.Suppress {
				if exports[alias.Old] {
					delete(r.globals, alias.Old)
					delete(exports, alias.Old)
				}
				continue
			}
			if original := r.globals[alias.Old]; original != nil {
				if existing := r.globals[alias.New]; existing != nil && existing != original {
					previous, reloading := r.provenance[alias.New]
					if !reloading || previous.Path != path || previous.Original != alias.Old {
						delete(r.includeLoading, path)
						return fmt.Errorf("include alias %s clashes with an existing name", alias.New)
					}
				}
				r.globals[alias.New] = original
				delete(r.globals, alias.Old)
				delete(exports, alias.Old)
				exports[alias.New] = true
				r.provenance[alias.New] = sourceProvenance{Path: path, Original: alias.Old, Instance: moduleInstance}
			}
		}
		for name := range exports {
			if old := before[name]; old != nil && old != r.globals[name] {
				if previous, reloading := r.provenance[name]; !reloading || previous.Path != path {
					delete(r.includeLoading, path)
					return fmt.Errorf("included name %s clashes with an existing binding", name)
				}
			}
			if previous, aliased := r.provenance[name]; aliased && previous.Path == path && previous.Original != name {
				previous.Instance = moduleInstance
				r.provenance[name] = previous
			} else {
				r.provenance[name] = sourceProvenance{Path: path, Original: name, Instance: moduleInstance}
			}
		}
		delete(r.includeLoading, path)
	}
	return nil
}

func parseFreeParameters(source []byte) (map[string]string, error) {
	text := string(source)
	marker := strings.Index(text, "%free")
	if marker < 0 {
		return map[string]string{}, nil
	}
	if strings.Index(text[marker+5:], "%free") >= 0 {
		return nil, errors.New("multiple %free directives")
	}
	start := strings.Index(text[marker:], "{")
	if start < 0 {
		return nil, errors.New("malformed %free directive")
	}
	start += marker
	end := strings.Index(text[start+1:], "}")
	if end < 0 {
		return nil, errors.New("unterminated %free directive")
	}
	body := text[start+1 : start+1+end]
	parameters := map[string]string{}
	for _, declaration := range strings.FieldsFunc(body, func(r rune) bool { return r == ';' || r == '\n' }) {
		parts := strings.SplitN(strings.TrimSpace(declaration), "::", 2)
		if len(parts) != 2 {
			continue
		}
		signature := strings.TrimSpace(parts[1])
		for _, rawName := range strings.Split(parts[0], ",") {
			fields := strings.Fields(strings.TrimSpace(rawName))
			if len(fields) == 0 {
				continue
			}
			name := fields[0]
			if parameters[name] != "" {
				return nil, fmt.Errorf("duplicate free identifier %s", name)
			}
			parameters[name] = signature
		}
	}
	return parameters, nil
}

func parseIncludeBindings(text string) (map[string]string, map[string]string, error) {
	values, types := map[string]string{}, map[string]string{}
	start, end := strings.Index(text, "{"), strings.LastIndex(text, "}")
	if start < 0 || end < start {
		return values, types, nil
	}
	for _, raw := range strings.Split(text[start+1:end], ";") {
		binding := strings.TrimSpace(raw)
		if binding == "" {
			continue
		}
		if parts := strings.SplitN(binding, "==", 2); len(parts) == 2 {
			fields := strings.Fields(strings.TrimSpace(parts[0]))
			if len(fields) == 0 {
				return nil, nil, errors.New("invalid type binding")
			}
			types[fields[0]] = strings.TrimSpace(parts[1])
			continue
		}
		parts := strings.SplitN(binding, "=", 2)
		if len(parts) != 2 {
			return nil, nil, fmt.Errorf("invalid free binding %q", binding)
		}
		values[strings.TrimSpace(parts[0])] = strings.TrimSpace(parts[1])
	}
	return values, types, nil
}

func checkBoundExpression(expression, signature string) error {
	parsed := syntaxfront.Run([]byte("__free :: " + signature + "\n__free = " + expression + "\n"))
	if len(parsed.Diagnostics) != 0 {
		return errors.New(parsed.Diagnostics[0].Message)
	}
	if typeErrors := semantics.CheckAll(parsed.Script); len(typeErrors) != 0 {
		return typeErrors
	}
	return nil
}

func (r *languageRuntime) installConstructor(name string, strict []bool) {
	arity := len(strict)
	if arity == 0 {
		r.builtin(name, languageValue{kind: valueConstructor, name: name})
		return
	}
	var build func([]languageValue) languageValue
	build = func(arguments []languageValue) languageValue {
		return languageValue{kind: valueFunction, lazyFn: func(_ context.Context, argument *languageThunk) (languageValue, error) {
			lazyArgument := languageValue{kind: valueThunk, thunk: argument}
			if strict[len(arguments)] {
				forced, err := argument.force()
				if err != nil {
					return languageValue{}, err
				}
				lazyArgument = forced
			}
			values := append(append([]languageValue(nil), arguments...), lazyArgument)
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

func decodeMirandaQuoted(text string, quote byte) (string, error) {
	if len(text) < 2 || text[0] != quote || text[len(text)-1] != quote {
		return "", errors.New("unterminated quoted literal")
	}
	input := text[1 : len(text)-1]
	var output strings.Builder
	for position := 0; position < len(input); {
		if input[position] != '\\' {
			r, size := utf8.DecodeRuneInString(input[position:])
			if r == utf8.RuneError && size == 1 {
				return "", errors.New("illegal UTF-8 character")
			}
			output.WriteRune(r)
			position += size
			continue
		}
		position++
		if position >= len(input) {
			return "", errors.New("incomplete escape sequence")
		}
		if input[position] == '\n' {
			if quote != '"' {
				return "", errors.New("newline is not allowed in a character literal")
			}
			position++
			continue
		}
		escapes := map[byte]rune{'a': '\a', 'b': '\b', 'f': '\f', 'n': '\n', 'r': '\r', 't': '\t', 'v': '\v', '\\': '\\', '\'': '\'', '"': '"'}
		if decoded, ok := escapes[input[position]]; ok {
			output.WriteRune(decoded)
			position++
			continue
		}
		base, maximum := 10, 3
		if input[position] == 'x' || input[position] == 'X' {
			if input[position] == 'x' {
				maximum = 4
			} else {
				maximum = 6
			}
			base = 16
			position++
		}
		start := position
		for position < len(input) && position-start < maximum && (base == 10 && input[position] >= '0' && input[position] <= '9' || base == 16 && isHexDigit(input[position])) {
			position++
		}
		if start == position {
			return "", errors.New("numeric escape requires at least one digit")
		}
		code, err := strconv.ParseInt(input[start:position], base, 32)
		if err != nil || !utf8.ValidRune(rune(code)) {
			return "", errors.New("numeric escape is outside the Unicode range")
		}
		output.WriteRune(rune(code))
	}
	return output.String(), nil
}

func isHexDigit(value byte) bool {
	return value >= '0' && value <= '9' || value >= 'a' && value <= 'f' || value >= 'A' && value <= 'F'
}

func quoteMirandaChar(value rune) string {
	switch value {
	case '\a':
		return "'\\a'"
	case '\b':
		return "'\\b'"
	case '\f':
		return "'\\f'"
	case '\n':
		return "'\\n'"
	case '\r':
		return "'\\r'"
	case '\t':
		return "'\\t'"
	case '\v':
		return "'\\v'"
	case '\\':
		return "'\\\\'"
	case '\'':
		return "'\\''"
	}
	if value >= 0x20 && value != 0x7f {
		return "'" + string(value) + "'"
	}
	return fmt.Sprintf("'\\x%x'", value)
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
	value := languageValue{kind: valueFunction, lazyFn: func(ctx context.Context, argument *languageThunk) (languageValue, error) {
		lazyArgument := languageValue{kind: valueThunk, thunk: argument}
		if len(arguments) == 0 && len(clauses[0].parameters) == 1 {
			values := [1]languageValue{lazyArgument}
			return r.selectClause(ctx, clauses, values[:])
		}
		values := make([]languageValue, len(arguments)+1)
		copy(values, arguments)
		values[len(arguments)] = lazyArgument
		if len(values) < len(clauses[0].parameters) {
			return r.clauseFunction(clauses, values), nil
		}
		return r.selectClause(ctx, clauses, values)
	}}
	if len(arguments) == 0 {
		value.intFn = r.compileUnaryIntegerClauses(clauses)
	}
	return value
}

type fastScalar struct {
	integer int64
	boolean bool
	isBool  bool
}

func (r *languageRuntime) compileUnaryIntegerClauses(clauses []runtimeClause) func(context.Context, int64) (int64, bool, error) {
	if len(clauses) == 0 {
		return nil
	}
	for _, clause := range clauses {
		if len(clause.parameters) != 1 || clause.parameters[0].Variant != "name" && clause.parameters[0].Variant != "int" || clause.parameters[0].Text == "_" {
			return nil
		}
	}
	var compiled func(context.Context, int64) (int64, bool, error)
	compiled = func(ctx context.Context, argument int64) (int64, bool, error) {
		select {
		case <-ctx.Done():
			return 0, false, ctx.Err()
		default:
		}
		for _, clause := range clauses {
			pattern := clause.parameters[0]
			parameter := ""
			if pattern.Variant == "int" {
				expected, err := strconv.ParseInt(pattern.Text, 0, 64)
				if err != nil {
					return 0, false, nil
				}
				if argument != expected {
					continue
				}
			} else {
				parameter = pattern.Text
			}
			if clause.condition != nil {
				condition, ok, err := r.evalFastScalar(ctx, *clause.condition, parameter, argument)
				if err != nil || !ok {
					return 0, false, err
				}
				if !condition.isBool || !condition.boolean {
					continue
				}
			}
			result, ok, err := r.evalFastScalar(ctx, clause.body, parameter, argument)
			if err != nil || !ok || result.isBool {
				return 0, false, err
			}
			return result.integer, true, nil
		}
		return 0, false, nil
	}
	return compiled
}

func (r *languageRuntime) evalFastScalar(ctx context.Context, expression syntaxfront.Expr, parameter string, argument int64) (fastScalar, bool, error) {
	switch expression.Variant {
	case "int":
		value, err := strconv.ParseInt(expression.Text, 0, 64)
		return fastScalar{integer: value}, err == nil, nil
	case "name":
		if expression.Text == parameter {
			return fastScalar{integer: argument}, true, nil
		}
	case "neg":
		value, ok, err := r.evalFastScalar(ctx, *expression.Arg, parameter, argument)
		if err != nil || !ok || value.isBool || value.integer == math.MinInt64 {
			return fastScalar{}, false, err
		}
		return fastScalar{integer: -value.integer}, true, nil
	case "infix":
		left, ok, err := r.evalFastScalar(ctx, *expression.Head, parameter, argument)
		if err != nil || !ok || left.isBool {
			return fastScalar{}, false, err
		}
		right, ok, err := r.evalFastScalar(ctx, *expression.Tail, parameter, argument)
		if err != nil || !ok || right.isBool {
			return fastScalar{}, false, err
		}
		if isComparison(expression.Text) {
			comparison := 0
			if left.integer < right.integer {
				comparison = -1
			} else if left.integer > right.integer {
				comparison = 1
			}
			matched := false
			switch expression.Text {
			case "=":
				matched = comparison == 0
			case "~=":
				matched = comparison != 0
			case "<":
				matched = comparison < 0
			case "<=":
				matched = comparison <= 0
			case ">":
				matched = comparison > 0
			case ">=":
				matched = comparison >= 0
			}
			return fastScalar{isBool: true, boolean: matched}, true, nil
		}
		var result int64
		switch expression.Text {
		case "+":
			result, ok = smallAdd(left.integer, right.integer)
		case "-":
			result, ok = smallSub(left.integer, right.integer)
		case "*":
			result, ok = smallMul(left.integer, right.integer)
		default:
			return fastScalar{}, false, nil
		}
		return fastScalar{integer: result}, ok, nil
	case "application":
		if expression.Func == nil || expression.Func.Variant != "name" || expression.Arg == nil {
			return fastScalar{}, false, nil
		}
		input, ok, err := r.evalFastScalar(ctx, *expression.Arg, parameter, argument)
		if err != nil || !ok || input.isBool {
			return fastScalar{}, false, err
		}
		thunk := r.globals[expression.Func.Text]
		if thunk == nil {
			return fastScalar{}, false, nil
		}
		function, err := thunk.force()
		if err != nil || function.intFn == nil {
			return fastScalar{}, false, err
		}
		result, ok, err := function.intFn(ctx, input.integer)
		return fastScalar{integer: result}, ok, err
	}
	return fastScalar{}, false, nil
}

func (r *languageRuntime) selectClause(ctx context.Context, clauses []runtimeClause, arguments []languageValue) (languageValue, error) {
	for _, clause := range clauses {
		if len(clause.parameters) != len(arguments) {
			continue
		}
		frame := r.acquireCallFrame(clause.parameters)
		environment := frame.environment
		for name, value := range clause.closure {
			environment[name] = value
		}
		matched := true
		seen := map[string]languageValue{}
		for index, pattern := range clause.parameters {
			if !r.matchRuntimePatternBound(pattern, arguments[index], environment, frame.bind, seen) {
				matched = false
				break
			}
		}
		if !matched {
			r.releaseCallFrame(frame)
			continue
		}
		if len(clause.localSource) != 0 {
			if err := r.installLocalSource(clause.localSource, environment); err != nil {
				r.releaseCallFrame(frame)
				return languageValue{}, err
			}
		}
		if clause.condition != nil {
			condition, err := r.eval(ctx, *clause.condition, environment)
			if err != nil {
				r.releaseCallFrame(frame)
				return languageValue{}, err
			}
			if condition.kind != valueBool {
				r.releaseCallFrame(frame)
				return languageValue{}, errors.New("truthvalue expected")
			}
			if !condition.flag {
				r.releaseCallFrame(frame)
				continue
			}
		}
		result, err := r.eval(ctx, clause.body, environment)
		r.releaseCallFrame(frame)
		return result, err
	}
	return languageValue{}, errors.New("no matching equation")
}

func (r *languageRuntime) installLocalSource(source []byte, environment map[string]*languageThunk) error {
	child := &languageRuntime{globals: map[string]*languageThunk{}, productConstructors: r.productConstructors, appendFiles: r.appendFiles, output: r.output}
	for name, value := range r.globals {
		child.globals[name] = value
	}
	for name, value := range environment {
		child.globals[name] = value
	}
	before := map[string]*languageThunk{}
	for name, value := range child.globals {
		before[name] = value
	}
	if err := child.installSource(source); err != nil {
		return err
	}
	for name, value := range child.globals {
		if before[name] != value {
			environment[name] = value
		}
	}
	return nil
}

func leadingIndent(line string) int {
	indent := 0
	for _, char := range line {
		if char == ' ' {
			indent++
		} else if char == '\t' {
			indent += 8
		} else {
			break
		}
	}
	return indent
}

func (r *languageRuntime) acquireCallFrame(patterns []syntaxfront.Expr) *languageCallFrame {
	count := 0
	for _, pattern := range patterns {
		count += patternBindingCount(pattern)
	}
	return &languageCallFrame{environment: make(map[string]*languageThunk, max(4, count)), bindings: make([]languageThunk, 0, count)}
}

func (f *languageCallFrame) bind(name string, value languageValue) {
	f.bindings = append(f.bindings, languageThunk{value: value, ready: true})
	f.environment[name] = &f.bindings[len(f.bindings)-1]
}

func (r *languageRuntime) releaseCallFrame(frame *languageCallFrame) {
	// Results may contain lazy closures pointing into this environment. Let the
	// frame follow normal Go reachability instead of recycling it prematurely.
}

func patternBindingCount(pattern syntaxfront.Expr) int {
	if pattern.Variant == "name" {
		if pattern.Text == "_" {
			return 0
		}
		return 1
	}
	count := 0
	for _, item := range pattern.Items {
		count += patternBindingCount(item)
	}
	for _, child := range []*syntaxfront.Expr{pattern.Head, pattern.Tail, pattern.Func, pattern.Arg} {
		if child != nil {
			count += patternBindingCount(*child)
		}
	}
	return count
}

func (r *languageRuntime) matchRuntimePattern(pattern syntaxfront.Expr, value languageValue, environment map[string]*languageThunk) bool {
	return r.matchRuntimePatternBound(pattern, value, environment, func(name string, value languageValue) { environment[name] = immediate(value) }, map[string]languageValue{})
}

func (r *languageRuntime) matchRuntimePatternBound(pattern syntaxfront.Expr, value languageValue, environment map[string]*languageThunk, bind func(string, languageValue), seen map[string]languageValue) bool {
	if pattern.Variant == "name" {
		if pattern.Text != "_" {
			if previous, exists := seen[pattern.Text]; exists {
				equal, err := compareLanguage(context.Background(), "=", previous, value)
				return err == nil && equal
			}
			seen[pattern.Text] = value
			bind(pattern.Text, value)
		}
		return true
	}
	if pattern.Variant == "tuple" && value.kind == valueThunk && irrefutableRuntimePattern(pattern) {
		for index, item := range pattern.Items {
			itemIndex := index
			projection := languageValue{kind: valueThunk, thunk: &languageThunk{eval: func() (languageValue, error) {
				outer, err := value.thunk.force()
				if err != nil {
					return languageValue{}, err
				}
				if outer.kind != valueTuple || itemIndex >= len(outer.items) {
					return languageValue{}, errors.New("tuple pattern mismatch")
				}
				return outer.items[itemIndex], nil
			}}}
			if !r.matchRuntimePatternBound(item, projection, environment, bind, seen) {
				return false
			}
		}
		return true
	}
	if name, patterns, ok := constructorPattern(pattern); ok && r.productConstructors[name] && value.kind == valueThunk {
		for index, item := range patterns {
			itemIndex := index
			projection := languageValue{kind: valueThunk, thunk: &languageThunk{eval: func() (languageValue, error) {
				outer, err := value.thunk.force()
				if err != nil {
					return languageValue{}, err
				}
				if outer.kind != valueConstructor || outer.name != name || itemIndex >= len(outer.items) {
					return languageValue{}, errors.New("constructor pattern mismatch")
				}
				return outer.items[itemIndex], nil
			}}}
			if !r.matchRuntimePatternBound(item, projection, environment, bind, seen) {
				return false
			}
		}
		return true
	}
	var forceErr error
	value, forceErr = forceLanguageValue(value, nil)
	if forceErr != nil {
		return false
	}
	switch pattern.Variant {
	case "name":
		return true
	case "int":
		expected := new(big.Int)
		if _, ok := expected.SetString(pattern.Text, 0); !ok {
			return false
		}
		return value.kind == valueNumber && integerPointer(value).Cmp(expected) == 0
	case "char":
		expected, err := decodeMirandaQuoted(pattern.Text, '\'')
		runes := []rune(expected)
		return err == nil && len(runes) == 1 && value.kind == valueChar && value.small == int64(runes[0])
	case "string":
		expected, err := decodeMirandaQuoted(pattern.Text, '"')
		return err == nil && value.kind == valueString && value.text == expected
	case "tuple":
		if value.kind != valueTuple || len(value.items) != len(pattern.Items) {
			return false
		}
		for index, item := range pattern.Items {
			if !r.matchRuntimePatternBound(item, value.items[index], environment, bind, seen) {
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
			if !r.matchRuntimePatternBound(item, items[index], environment, bind, seen) {
				return false
			}
		}
		return true
	case "infix":
		if pattern.Text == "+" && pattern.Tail != nil && pattern.Tail.Variant == "int" && value.kind == valueNumber {
			offset := new(big.Int)
			if _, ok := offset.SetString(pattern.Tail.Text, 0); !ok || offset.Sign() < 0 {
				return false
			}
			actual := integerPointer(value)
			if actual.Cmp(offset) < 0 {
				return false
			}
			remainder := numberFromBig(new(big.Int).Sub(actual, offset))
			return r.matchRuntimePatternBound(*pattern.Head, remainder, environment, bind, seen)
		}
		if strings.HasPrefix(pattern.Text, "$") && value.kind == valueConstructor && value.name == strings.TrimPrefix(pattern.Text, "$") && len(value.items) == 2 {
			return r.matchRuntimePatternBound(*pattern.Head, value.items[0], environment, bind, seen) && r.matchRuntimePatternBound(*pattern.Tail, value.items[1], environment, bind, seen)
		}
		if pattern.Text != ":" || value.kind != valueList {
			return false
		}
		head, ok, err := value.list.at(context.Background(), 0)
		if err != nil || !ok {
			return false
		}
		tail := languageValue{kind: valueList, list: &lazyList{next: func(ctx context.Context, index int) (languageValue, bool, error) { return value.list.at(ctx, index+1) }}}
		return r.matchRuntimePatternBound(*pattern.Head, head, environment, bind, seen) && r.matchRuntimePatternBound(*pattern.Tail, tail, environment, bind, seen)
	case "neg":
		if pattern.Arg == nil || pattern.Arg.Variant != "int" || value.kind != valueNumber {
			return false
		}
		expected := new(big.Int)
		if _, ok := expected.SetString(pattern.Arg.Text, 0); !ok {
			return false
		}
		expected.Neg(expected)
		return integerPointer(value).Cmp(expected) == 0
	case "application", "constructor":
		name, patterns, ok := constructorPattern(pattern)
		if !ok || value.kind != valueConstructor || value.name != name || len(value.items) != len(patterns) {
			return false
		}
		for index, item := range patterns {
			if !r.matchRuntimePatternBound(item, value.items[index], environment, bind, seen) {
				return false
			}
		}
		return true
	default:
		return false
	}
}

func validateRuntimePattern(pattern syntaxfront.Expr) error {
	if pattern.Variant == "float" {
		return errors.New("floating-point constants are not permitted in patterns")
	}
	if pattern.Variant == "infix" && pattern.Text == "+" && (pattern.Tail == nil || pattern.Tail.Variant != "int") {
		return errors.New("natural-number pattern offset must be a literal integer")
	}
	for _, child := range []*syntaxfront.Expr{pattern.Head, pattern.Tail, pattern.Func, pattern.Arg} {
		if child != nil {
			if err := validateRuntimePattern(*child); err != nil {
				return err
			}
		}
	}
	for _, item := range pattern.Items {
		if err := validateRuntimePattern(item); err != nil {
			return err
		}
	}
	return nil
}

func irrefutableRuntimePattern(pattern syntaxfront.Expr) bool {
	if pattern.Variant == "name" {
		return true
	}
	if pattern.Variant != "tuple" || len(pattern.Items) == 0 {
		return false
	}
	for _, item := range pattern.Items {
		if !irrefutableRuntimePattern(item) {
			return false
		}
	}
	return true
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
	return languageValue{kind: valueFunction, lazyFn: func(ctx context.Context, argument *languageThunk) (languageValue, error) {
		environment := make(map[string]*languageThunk, len(closure)+1)
		for name, value := range closure {
			environment[name] = value
		}
		environment[parameters[0]] = argument
		if len(parameters) == 1 {
			return r.eval(ctx, body, environment)
		}
		return r.function(parameters[1:], body, environment), nil
	}}
}

func (r *languageRuntime) lookup(environment map[string]*languageThunk, name string) *languageThunk {
	if value := environment[name]; value != nil {
		return value
	}
	return r.globals[name]
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
	// measure useful work without pretending that Go allocates raw graph cells.
	r.reductions++
	r.cells++
	select {
	case <-ctx.Done():
		return languageValue{}, ctx.Err()
	default:
	}
	switch expression.Variant {
	case "int":
		if small, err := strconv.ParseInt(expression.Text, 0, 64); err == nil {
			return languageValue{kind: valueNumber, small: small}, nil
		}
		value := new(big.Int)
		if _, ok := value.SetString(expression.Text, 0); !ok {
			return languageValue{}, fmt.Errorf("invalid integer %s", expression.Text)
		}
		return languageValue{kind: valueNumber, num: value}, nil
	case "string":
		value, err := decodeMirandaQuoted(expression.Text, '"')
		if err != nil {
			return languageValue{}, err
		}
		return languageValue{kind: valueString, text: value}, nil
	case "char":
		value, err := decodeMirandaQuoted(expression.Text, '\'')
		if err != nil {
			return languageValue{}, err
		}
		runes := []rune(value)
		if len(runes) != 1 {
			return languageValue{}, errors.New("character literal must contain exactly one character")
		}
		return languageValue{kind: valueChar, small: int64(runes[0])}, nil
	case "float":
		value, err := strconv.ParseFloat(expression.Text, 64)
		if err != nil {
			return languageValue{}, err
		}
		return languageValue{kind: valueFloat, real: value}, nil
	case "name", "constructor":
		value := r.lookup(environment, expression.Text)
		if value == nil {
			return languageValue{}, fmt.Errorf("undefined name %s", expression.Text)
		}
		return value.force()
	case "application":
		function, err := r.eval(ctx, *expression.Func, environment)
		if err != nil {
			return languageValue{}, err
		}
		if function.lazyFn != nil {
			argumentExpression := *expression.Arg
			argumentEnvironment := cloneEnvironment(environment)
			argument := &languageThunk{eval: func() (languageValue, error) { return r.eval(ctx, argumentExpression, argumentEnvironment) }}
			return function.lazyFn(ctx, argument)
		}
		argument, err := r.eval(ctx, *expression.Arg, environment)
		if err != nil {
			return languageValue{}, err
		}
		return applyLanguage(ctx, function, argument)
	case "infix":
		if expression.Text == ":" {
			headExpression := *expression.Head
			headEnvironment := cloneEnvironment(environment)
			head := languageValue{kind: valueThunk, thunk: &languageThunk{eval: func() (languageValue, error) { return r.eval(ctx, headExpression, headEnvironment) }}}
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
					return languageValue{}, false, listTypeMismatch(tail)
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
			first, err := compareLanguage(ctx, expression.Head.Text, left, middle)
			if err != nil {
				return languageValue{}, err
			}
			second, err := compareLanguage(ctx, expression.Text, middle, right)
			if err != nil {
				return languageValue{}, err
			}
			return languageValue{kind: valueBool, flag: first && second}, nil
		}
		if expression.Text == "&" || expression.Text == "/\\" || expression.Text == "\\/" {
			left, err := r.eval(ctx, *expression.Head, environment)
			if err != nil {
				return languageValue{}, err
			}
			left, err = forceLanguageValue(left, nil)
			if err != nil || left.kind != valueBool {
				if err != nil {
					return languageValue{}, err
				}
				return languageValue{}, errors.New("boolean expected")
			}
			isAnd := expression.Text == "&" || expression.Text == "/\\"
			if isAnd && !left.flag {
				return languageValue{kind: valueBool}, nil
			}
			if !isAnd && left.flag {
				return languageValue{kind: valueBool, flag: true}, nil
			}
			right, err := r.eval(ctx, *expression.Tail, environment)
			if err != nil {
				return languageValue{}, err
			}
			right, err = forceLanguageValue(right, nil)
			if err != nil || right.kind != valueBool {
				if err != nil {
					return languageValue{}, err
				}
				return languageValue{}, errors.New("boolean expected")
			}
			return right, nil
		}
		if isDirectNumericOperator(expression.Text) {
			left, err := r.eval(ctx, *expression.Head, environment)
			if err != nil {
				return languageValue{}, err
			}
			right, err := r.eval(ctx, *expression.Tail, environment)
			if err != nil {
				return languageValue{}, err
			}
			return directNumericInfix(expression.Text, left, right)
		}
		operatorName := strings.TrimPrefix(expression.Text, "$")
		function := r.lookup(environment, operatorName)
		if function == nil {
			return languageValue{}, fmt.Errorf("undefined operator %s", expression.Text)
		}
		value, err := function.force()
		if err != nil {
			return languageValue{}, err
		}
		leftExpression, leftEnvironment := *expression.Head, cloneEnvironment(environment)
		left := &languageThunk{eval: func() (languageValue, error) { return r.eval(ctx, leftExpression, leftEnvironment) }}
		value, err = applyLanguageThunk(ctx, value, left)
		if err != nil {
			return languageValue{}, err
		}
		rightExpression, rightEnvironment := *expression.Tail, cloneEnvironment(environment)
		right := &languageThunk{eval: func() (languageValue, error) { return r.eval(ctx, rightExpression, rightEnvironment) }}
		return applyLanguageThunk(ctx, value, right)
	case "section_left", "section_right":
		operator := r.lookup(environment, strings.TrimPrefix(expression.Text, "$"))
		if operator == nil {
			return languageValue{}, fmt.Errorf("undefined operator %s", expression.Text)
		}
		fixedExpression, fixedEnvironment := *expression.Arg, cloneEnvironment(environment)
		fixed := &languageThunk{eval: func() (languageValue, error) { return r.eval(ctx, fixedExpression, fixedEnvironment) }}
		return languageValue{kind: valueFunction, lazyFn: func(ctx context.Context, argument *languageThunk) (languageValue, error) {
			fn, err := operator.force()
			if err != nil {
				return languageValue{}, err
			}
			first, second := fixed, argument
			if expression.Variant == "section_right" {
				first, second = argument, fixed
			}
			fn, err = applyLanguageThunk(ctx, fn, first)
			if err != nil {
				return languageValue{}, err
			}
			return applyLanguageThunk(ctx, fn, second)
		}}, nil
	case "op_func":
		value := r.lookup(environment, strings.TrimPrefix(expression.Text, "$"))
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
		if value.kind == valueNumber && value.num == nil && value.small != math.MinInt64 {
			return languageValue{kind: valueNumber, small: -value.small}, nil
		}
		n, err := numberValue(value)
		if err != nil {
			return languageValue{}, err
		}
		return languageValue{kind: valueNumber, num: new(big.Int).Neg(n)}, nil
	case "not":
		value, err := r.eval(ctx, *expression.Arg, environment)
		if err != nil {
			return languageValue{}, err
		}
		value, err = forceLanguageValue(value, nil)
		if err != nil {
			return languageValue{}, err
		}
		if value.kind != valueBool {
			return languageValue{}, errors.New("boolean expected")
		}
		return languageValue{kind: valueBool, flag: !value.flag}, nil
	case "list":
		items := append([]syntaxfront.Expr(nil), expression.Items...)
		captured := cloneEnvironment(environment)
		return languageValue{kind: valueList, list: &lazyList{next: func(ctx context.Context, index int) (languageValue, bool, error) {
			if index >= len(items) {
				return languageValue{}, false, nil
			}
			item := items[index]
			return languageValue{kind: valueThunk, thunk: &languageThunk{eval: func() (languageValue, error) { return r.eval(ctx, item, captured) }}}, true, nil
		}}}, nil
	case "tuple":
		values := make([]languageValue, len(expression.Items))
		for index := range expression.Items {
			item := expression.Items[index]
			captured := cloneEnvironment(environment)
			values[index] = languageValue{kind: valueThunk, thunk: &languageThunk{eval: func() (languageValue, error) { return r.eval(ctx, item, captured) }}}
		}
		return languageValue{kind: valueTuple, items: values}, nil
	case "range":
		start, err := r.eval(ctx, *expression.Head, environment)
		if err != nil {
			return languageValue{}, err
		}
		floating := start.kind == valueFloat
		var stepValue, endValue languageValue
		if expression.Step != nil {
			stepValue, err = r.eval(ctx, *expression.Step, environment)
			if err != nil {
				return languageValue{}, err
			}
			floating = floating || stepValue.kind == valueFloat
		}
		if expression.To != nil {
			endValue, err = r.eval(ctx, *expression.To, environment)
			if err != nil {
				return languageValue{}, err
			}
			floating = floating || endValue.kind == valueFloat
		}
		if floating {
			from, e := realValue(start)
			if e != nil {
				return languageValue{}, e
			}
			increment := 1.0
			if expression.Step != nil {
				second, e := realValue(stepValue)
				if e != nil {
					return languageValue{}, e
				}
				increment = second - from
			}
			var end *float64
			if expression.To != nil {
				limit, e := realValue(endValue)
				if e != nil {
					return languageValue{}, e
				}
				end = &limit
			}
			precision := rangeDecimalPrecision(expression)
			scale := math.Pow10(precision)
			return languageValue{kind: valueList, list: &lazyList{next: func(_ context.Context, index int) (languageValue, bool, error) {
				current := from + float64(index)*increment
				if precision > 0 {
					current = math.Round(current*scale) / scale
				}
				if end != nil && (increment >= 0 && current > *end+math.Abs(increment)*1e-12 || increment < 0 && current < *end-math.Abs(increment)*1e-12) {
					return languageValue{}, false, nil
				}
				return languageValue{kind: valueFloat, real: current}, true, nil
			}}}, nil
		}
		from, err := numberValue(start)
		if err != nil {
			return languageValue{}, err
		}
		step := big.NewInt(1)
		if expression.Step != nil {
			second, e := numberValue(stepValue)
			if e != nil {
				return languageValue{}, e
			}
			step = new(big.Int).Sub(second, from)
		}
		var end *big.Int
		if expression.To != nil {
			end, err = numberValue(endValue)
			if err != nil {
				return languageValue{}, err
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
	case "listcomp", "diagonal_listcomp":
		stream := r.comprehensionEnvironments(expression.Qualifiers, environment)
		if expression.Variant == "diagonal_listcomp" {
			stream = r.diagonalComprehensionEnvironments(expression.Qualifiers, environment)
		}
		body := *expression.Body
		return languageValue{kind: valueList, list: &lazyList{next: func(nextCtx context.Context, _ int) (languageValue, bool, error) {
			candidate, ok, err := stream(nextCtx)
			if err != nil || !ok {
				return languageValue{}, ok, err
			}
			captured := cloneEnvironment(candidate)
			return languageValue{kind: valueThunk, thunk: &languageThunk{eval: func() (languageValue, error) { return r.eval(nextCtx, body, captured) }}}, true, nil
		}}}, nil
	default:
		return languageValue{}, fmt.Errorf("unsupported expression %s", expression.Variant)
	}
}

func rangeDecimalPrecision(expression syntaxfront.Expr) int {
	maximum := 0
	for _, part := range []*syntaxfront.Expr{expression.Head, expression.Step, expression.To} {
		if part == nil || part.Variant != "float" || strings.HasPrefix(strings.ToLower(part.Text), "0x") {
			continue
		}
		text := part.Text
		if exponent := strings.IndexAny(text, "eE"); exponent >= 0 {
			text = text[:exponent]
		}
		if dot := strings.IndexByte(text, '.'); dot >= 0 && len(text)-dot-1 > maximum {
			maximum = len(text) - dot - 1
		}
	}
	return maximum
}

func isComparison(operator string) bool {
	switch operator {
	case "=", "~=", "<", "<=", ">", ">=":
		return true
	}
	return false
}

func isDirectNumericOperator(operator string) bool {
	return isComparison(operator) || operator == "+" || operator == "-" || operator == "*"
}

func directNumericInfix(operator string, left, right languageValue) (languageValue, error) {
	if isComparison(operator) {
		comparison, err := compareLanguage(context.Background(), operator, left, right)
		return languageValue{kind: valueBool, flag: comparison}, err
	}
	if left.kind == valueFloat || right.kind == valueFloat {
		a, err := realValue(left)
		if err != nil {
			return languageValue{}, err
		}
		b, err := realValue(right)
		if err != nil {
			return languageValue{}, err
		}
		switch operator {
		case "+":
			return languageValue{kind: valueFloat, real: a + b}, nil
		case "*":
			return languageValue{kind: valueFloat, real: a * b}, nil
		case "-":
			return languageValue{kind: valueFloat, real: a - b}, nil
		}
	}
	if left.kind != valueNumber || right.kind != valueNumber {
		return languageValue{}, errors.New("number expected")
	}
	if left.num == nil && right.num == nil {
		var result int64
		var ok bool
		switch operator {
		case "+":
			result, ok = smallAdd(left.small, right.small)
		case "-":
			result, ok = smallSub(left.small, right.small)
		case "*":
			result, ok = smallMul(left.small, right.small)
		}
		if ok {
			return languageValue{kind: valueNumber, small: result}, nil
		}
	}
	a, b := integerPointer(left), integerPointer(right)
	switch operator {
	case "+":
		return numberFromBig(new(big.Int).Add(a, b)), nil
	case "-":
		return numberFromBig(new(big.Int).Sub(a, b)), nil
	case "*":
		return numberFromBig(new(big.Int).Mul(a, b)), nil
	}
	return languageValue{}, errors.New("unknown numeric operator")
}
func compareLanguage(ctx context.Context, operator string, left, right languageValue) (bool, error) {
	comparison, err := compareLanguageValues(ctx, left, right)
	if err != nil {
		return false, err
	}
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
	return false, errors.New("unknown comparison operator")
}

func compareLanguageValues(ctx context.Context, left, right languageValue) (int, error) {
	var err error
	left, err = forceLanguageValue(left, nil)
	if err != nil {
		return 0, err
	}
	right, err = forceLanguageValue(right, nil)
	if err != nil {
		return 0, err
	}
	if left.kind == valueFunction || right.kind == valueFunction {
		return 0, errors.New("cannot compare functions")
	}
	if (left.kind == valueNumber || left.kind == valueFloat) && (right.kind == valueNumber || right.kind == valueFloat) {
		if left.kind == valueNumber && right.kind == valueNumber {
			return integerPointer(left).Cmp(integerPointer(right)), nil
		}
		a, _ := realValue(left)
		b, _ := realValue(right)
		if a < b {
			return -1, nil
		}
		if a > b {
			return 1, nil
		}
		return 0, nil
	}
	if left.kind != right.kind {
		return 0, errors.New("values of different types cannot be compared")
	}
	switch left.kind {
	case valueBool:
		if left.flag == right.flag {
			return 0, nil
		}
		if !left.flag {
			return -1, nil
		}
		return 1, nil
	case valueChar:
		if left.small < right.small {
			return -1, nil
		}
		if left.small > right.small {
			return 1, nil
		}
		return 0, nil
	case valueString:
		return strings.Compare(left.text, right.text), nil
	case valueTuple, valueConstructor:
		if left.kind == valueConstructor {
			if c := strings.Compare(left.name, right.name); c != 0 {
				return c, nil
			}
		}
		for i := 0; i < len(left.items) && i < len(right.items); i++ {
			c, e := compareLanguageValues(ctx, left.items[i], right.items[i])
			if e != nil || c != 0 {
				return c, e
			}
		}
		if len(left.items) < len(right.items) {
			return -1, nil
		}
		if len(left.items) > len(right.items) {
			return 1, nil
		}
		return 0, nil
	case valueList:
		for i := 0; ; i++ {
			a, aok, e := left.list.at(ctx, i)
			if e != nil {
				return 0, e
			}
			b, bok, e := right.list.at(ctx, i)
			if e != nil {
				return 0, e
			}
			if !aok || !bok {
				if aok {
					return 1, nil
				}
				if bok {
					return -1, nil
				}
				return 0, nil
			}
			c, e := compareLanguageValues(ctx, a, b)
			if e != nil || c != 0 {
				return c, e
			}
		}
	}
	return 0, errors.New("comparable values expected")
}

func applyLanguage(ctx context.Context, function, argument languageValue) (languageValue, error) {
	if function.kind != valueFunction || function.fn == nil && function.lazyFn == nil {
		return languageValue{}, errors.New("function expected")
	}
	if function.lazyFn != nil {
		return function.lazyFn(ctx, immediate(argument))
	}
	if function.intFn != nil && argument.kind == valueNumber && argument.num == nil {
		if result, ok, err := function.intFn(ctx, argument.small); err != nil {
			return languageValue{}, err
		} else if ok {
			return languageValue{kind: valueNumber, small: result}, nil
		}
	}
	return function.fn(ctx, argument)
}

func numberValue(value languageValue) (*big.Int, error) {
	if value.kind != valueNumber {
		return nil, errors.New("number expected")
	}
	if value.num == nil {
		return big.NewInt(value.small), nil
	}
	return new(big.Int).Set(value.num), nil
}

func integerPointer(value languageValue) *big.Int {
	if value.num != nil {
		return value.num
	}
	return big.NewInt(value.small)
}

func numberFromBig(value *big.Int) languageValue {
	if value.IsInt64() {
		return languageValue{kind: valueNumber, small: value.Int64()}
	}
	return languageValue{kind: valueNumber, num: value}
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

func applyLanguageThunk(ctx context.Context, function languageValue, argument *languageThunk) (languageValue, error) {
	function, err := forceLanguageValue(function, nil)
	if err != nil {
		return languageValue{}, err
	}
	if function.kind != valueFunction {
		return languageValue{}, errors.New("function expected")
	}
	if function.lazyFn != nil {
		return function.lazyFn(ctx, argument)
	}
	value, err := argument.force()
	if err != nil {
		return languageValue{}, err
	}
	return function.fn(ctx, value)
}

func lazyBooleanOperator(and bool) languageValue {
	return languageValue{kind: valueFunction, lazyFn: func(ctx context.Context, first *languageThunk) (languageValue, error) {
		left, err := first.force()
		if err != nil {
			return languageValue{}, err
		}
		if left.kind != valueBool {
			return languageValue{}, errors.New("boolean expected")
		}
		return languageValue{kind: valueFunction, lazyFn: func(_ context.Context, second *languageThunk) (languageValue, error) {
			if and && !left.flag {
				return languageValue{kind: valueBool}, nil
			}
			if !and && left.flag {
				return languageValue{kind: valueBool, flag: true}, nil
			}
			right, err := second.force()
			if err != nil {
				return languageValue{}, err
			}
			if right.kind != valueBool {
				return languageValue{}, errors.New("boolean expected")
			}
			return right, nil
		}}, nil
	}}
}

func mirandaDivMod(a, b *big.Int) (*big.Int, *big.Int) {
	q, remainder := new(big.Int), new(big.Int)
	q.QuoRem(a, b, remainder)
	if remainder.Sign() != 0 && remainder.Sign() != b.Sign() {
		q.Sub(q, big.NewInt(1))
		remainder.Add(remainder, b)
	}
	return q, remainder
}

func listDifference(ctx context.Context, left, right languageValue) (languageValue, error) {
	if left.kind == valueString && right.kind == valueString {
		remaining := []rune(left.text)
		for _, remove := range []rune(right.text) {
			for i, item := range remaining {
				if item == remove {
					remaining = append(remaining[:i], remaining[i+1:]...)
					break
				}
			}
		}
		return languageValue{kind: valueString, text: string(remaining)}, nil
	}
	if left.kind != valueList {
		return languageValue{}, listTypeMismatch(left)
	}
	rightItems, err := finiteList(ctx, right, maxMaterializedList)
	if err != nil {
		return languageValue{}, err
	}
	removals := append([]languageValue(nil), rightItems...)
	sourceIndex := 0
	return languageValue{kind: valueList, list: &lazyList{next: func(nextCtx context.Context, _ int) (languageValue, bool, error) {
		for {
			item, ok, e := left.list.at(nextCtx, sourceIndex)
			sourceIndex++
			if e != nil || !ok {
				return languageValue{}, ok, e
			}
			removed := false
			for index, remove := range removals {
				equal, e := compareLanguage(nextCtx, "=", item, remove)
				if e != nil {
					return languageValue{}, false, e
				}
				if equal {
					removals = append(removals[:index], removals[index+1:]...)
					removed = true
					break
				}
			}
			if !removed {
				return item, true, nil
			}
		}
	}}}, nil
}

func (r *languageRuntime) comprehensionEnvironments(qualifiers []syntaxfront.Qualifier, root map[string]*languageThunk) environmentStream {
	emitted := false
	stream := environmentStream(func(context.Context) (map[string]*languageThunk, bool, error) {
		if emitted {
			return nil, false, nil
		}
		emitted = true
		return cloneEnvironment(root), true, nil
	})
	for _, qualifier := range qualifiers {
		parent := stream
		qualifier := qualifier
		if qualifier.Guard != nil {
			stream = func(ctx context.Context) (map[string]*languageThunk, bool, error) {
				for {
					candidate, ok, err := parent(ctx)
					if err != nil || !ok {
						return nil, ok, err
					}
					guard, err := r.eval(ctx, *qualifier.Guard, candidate)
					if err != nil {
						return nil, false, err
					}
					guard, err = forceLanguageValue(guard, nil)
					if err != nil {
						return nil, false, err
					}
					if guard.kind != valueBool {
						return nil, false, errors.New("boolean guard expected")
					}
					if guard.flag {
						return candidate, true, nil
					}
				}
			}
			continue
		}
		var candidate map[string]*languageThunk
		var source languageValue
		position := 0
		haveCandidate := false
		var recurrenceValue languageValue
		stream = func(ctx context.Context) (map[string]*languageThunk, bool, error) {
			for {
				if !haveCandidate {
					var ok bool
					var err error
					candidate, ok, err = parent(ctx)
					if err != nil || !ok {
						return nil, ok, err
					}
					position = 0
					if qualifier.Recurrence != nil {
						recurrenceValue, err = r.eval(ctx, *qualifier.Source, candidate)
					} else {
						source, err = r.eval(ctx, *qualifier.Source, candidate)
					}
					if err != nil {
						return nil, false, err
					}
					if qualifier.Recurrence == nil && source.kind != valueList {
						return nil, false, listTypeMismatch(source)
					}
					haveCandidate = true
				}
				var value languageValue
				var ok bool
				var err error
				if qualifier.Recurrence != nil {
					value, ok = recurrenceValue, true
				} else {
					value, ok, err = source.list.at(ctx, position)
				}
				if err != nil {
					return nil, false, err
				}
				if !ok {
					haveCandidate = false
					continue
				}
				position++
				bound := cloneEnvironment(candidate)
				if !r.matchRuntimePattern(*qualifier.Pattern, value, bound) {
					if qualifier.Recurrence != nil {
						return nil, false, errors.New("recurrence value does not match its pattern")
					}
					continue
				}
				if qualifier.Recurrence != nil {
					recurrenceValue, err = r.eval(ctx, *qualifier.Recurrence, bound)
					if err != nil {
						return nil, false, err
					}
				}
				return bound, true, nil
			}
		}
	}
	return stream
}

func (r *languageRuntime) diagonalComprehensionEnvironments(qualifiers []syntaxfront.Qualifier, root map[string]*languageThunk) environmentStream {
	generatorCount := 0
	for _, qualifier := range qualifiers {
		if qualifier.Pattern != nil {
			generatorCount++
		}
	}
	if generatorCount < 2 {
		return r.comprehensionEnvironments(qualifiers, root)
	}
	total, combination := 0, 0
	vectors := indexCompositions(0, generatorCount)
	maximumTotal, allFinite := 0, true
	for _, qualifier := range qualifiers {
		if qualifier.Pattern == nil {
			continue
		}
		if qualifier.Recurrence != nil || qualifier.Source == nil || qualifier.Source.Variant != "range" && qualifier.Source.Variant != "list" {
			allFinite = false
			break
		}
		length, err := r.staticGeneratorLength(context.Background(), *qualifier.Source, root)
		if err != nil {
			allFinite = false
			break
		}
		if length == 0 {
			maximumTotal = -1
			break
		}
		maximumTotal += length - 1
	}
	return func(ctx context.Context) (map[string]*languageThunk, bool, error) {
		for {
			if combination >= len(vectors) {
				total++
				if allFinite && total > maximumTotal {
					return nil, false, nil
				}
				vectors = indexCompositions(total, generatorCount)
				combination = 0
			}
			indices := vectors[combination]
			combination++
			environment := cloneEnvironment(root)
			generator := 0
			valid := true
			for _, qualifier := range qualifiers {
				if qualifier.Guard != nil {
					guard, err := r.eval(ctx, *qualifier.Guard, environment)
					if err != nil {
						return nil, false, err
					}
					guard, err = forceLanguageValue(guard, nil)
					if err != nil {
						return nil, false, err
					}
					if guard.kind != valueBool {
						return nil, false, errors.New("boolean guard expected")
					}
					if !guard.flag {
						valid = false
						break
					}
					continue
				}
				value, ok, err := r.comprehensionGeneratorAt(ctx, qualifier, environment, indices[generator])
				generator++
				if err != nil {
					return nil, false, err
				}
				if !ok {
					valid = false
					break
				}
				if !r.matchRuntimePattern(*qualifier.Pattern, value, environment) {
					valid = false
					break
				}
			}
			if valid {
				return environment, true, nil
			}
		}
	}
}

func (r *languageRuntime) staticGeneratorLength(ctx context.Context, expression syntaxfront.Expr, environment map[string]*languageThunk) (int, error) {
	if expression.Variant == "list" {
		return len(expression.Items), nil
	}
	if expression.Variant != "range" || expression.To == nil {
		return 0, errors.New("not statically finite")
	}
	start, err := r.eval(ctx, *expression.Head, environment)
	if err != nil {
		return 0, err
	}
	end, err := r.eval(ctx, *expression.To, environment)
	if err != nil {
		return 0, err
	}
	var second languageValue
	if expression.Step != nil {
		second, err = r.eval(ctx, *expression.Step, environment)
		if err != nil {
			return 0, err
		}
	}
	if start.kind == valueFloat || end.kind == valueFloat || expression.Step != nil && second.kind == valueFloat {
		from, _ := realValue(start)
		limit, _ := realValue(end)
		increment := 1.0
		if expression.Step != nil {
			value, _ := realValue(second)
			increment = value - from
		}
		if increment == 0 || increment > 0 && from > limit || increment < 0 && from < limit {
			return 0, nil
		}
		return int(math.Floor((limit-from)/increment+1e-12)) + 1, nil
	}
	from, _ := numberValue(start)
	limit, _ := numberValue(end)
	increment := big.NewInt(1)
	if expression.Step != nil {
		value, _ := numberValue(second)
		increment.Sub(value, from)
	}
	if increment.Sign() == 0 || increment.Sign() > 0 && from.Cmp(limit) > 0 || increment.Sign() < 0 && from.Cmp(limit) < 0 {
		return 0, nil
	}
	count := new(big.Int).Quo(new(big.Int).Sub(limit, from), increment)
	count.Add(count, big.NewInt(1))
	if !count.IsInt64() || count.Int64() > int64(^uint(0)>>1) {
		return 0, errors.New("finite range is too large for host indexing")
	}
	return int(count.Int64()), nil
}

func (r *languageRuntime) comprehensionGeneratorAt(ctx context.Context, qualifier syntaxfront.Qualifier, environment map[string]*languageThunk, index int) (languageValue, bool, error) {
	value, err := r.eval(ctx, *qualifier.Source, environment)
	if err != nil {
		return languageValue{}, false, err
	}
	if qualifier.Recurrence == nil {
		if value.kind != valueList {
			return languageValue{}, false, listTypeMismatch(value)
		}
		return value.list.at(ctx, index)
	}
	for position := 0; position < index; position++ {
		bound := cloneEnvironment(environment)
		if !r.matchRuntimePattern(*qualifier.Pattern, value, bound) {
			return languageValue{}, false, nil
		}
		value, err = r.eval(ctx, *qualifier.Recurrence, bound)
		if err != nil {
			return languageValue{}, false, err
		}
	}
	return value, true, nil
}

func indexCompositions(total, dimensions int) [][]int {
	if dimensions == 1 {
		return [][]int{{total}}
	}
	var result [][]int
	for first := 0; first <= total; first++ {
		for _, tail := range indexCompositions(total-first, dimensions-1) {
			result = append(result, append([]int{first}, tail...))
		}
	}
	return result
}

func realValue(value languageValue) (float64, error) {
	if value.kind == valueFloat {
		return value.real, nil
	}
	if value.kind == valueNumber {
		if value.num == nil {
			return float64(value.small), nil
		}
		result, _ := new(big.Float).SetInt(value.num).Float64()
		return result, nil
	}
	return 0, errors.New("number expected")
}

func (r *languageRuntime) builtin(name string, value languageValue) {
	r.globals[name] = immediate(value)
}

func (r *languageRuntime) standardInput(binary bool) ([]byte, error) {
	r.inputMu.Lock()
	defer r.inputMu.Unlock()
	mode := 1
	if binary {
		mode = 2
	}
	if r.inputMode != 0 && r.inputMode != mode {
		return nil, errors.New("$- and $:- cannot be used in the same evaluation")
	}
	r.inputMode = mode
	if !r.inputRead {
		data, err := io.ReadAll(r.input)
		if err != nil {
			return nil, err
		}
		r.inputData, r.inputRead = data, true
	}
	return append([]byte(nil), r.inputData...), nil
}

func (r *languageRuntime) readValues(ctx context.Context, data []byte) languageValue {
	lines := strings.Split(string(data), "\n")
	lineIndex := 0
	return languageValue{kind: valueList, list: &lazyList{next: func(nextCtx context.Context, _ int) (languageValue, bool, error) {
		for lineIndex < len(lines) {
			line := strings.TrimSpace(lines[lineIndex])
			lineIndex++
			if line == "" || strings.HasPrefix(line, "||") {
				continue
			}
			expression, err := parseRuntimeExpression(line)
			if err != nil {
				return languageValue{}, false, err
			}
			captured := expression
			return languageValue{kind: valueThunk, thunk: &languageThunk{eval: func() (languageValue, error) { return r.eval(nextCtx, captured, r.globals) }}}, true, nil
		}
		return languageValue{}, false, nil
	}}}
}

func (r *languageRuntime) installBuiltins() {
	r.globals["undef"] = &languageThunk{eval: func() (languageValue, error) { return languageValue{}, errors.New("undefined") }}
	for name, arity := range map[string]int{"Stdout": 1, "Stderr": 1, "Tofile": 2, "Closefile": 1, "Appendfile": 1, "System": 1, "Exit": 1, "Stdoutb": 1, "Tofileb": 2, "Appendfileb": 1} {
		r.installConstructor(name, make([]bool, arity))
	}
	r.globals["$-"] = &languageThunk{eval: func() (languageValue, error) {
		data, err := r.standardInput(false)
		if err != nil {
			return languageValue{}, err
		}
		if !utf8.Valid(data) {
			return languageValue{}, errors.New("illegal UTF-8 input")
		}
		return languageValue{kind: valueString, text: string(data)}, nil
	}}
	r.globals["$:-"] = &languageThunk{eval: func() (languageValue, error) {
		data, err := r.standardInput(true)
		if err != nil {
			return languageValue{}, err
		}
		return languageValue{kind: valueString, text: string(data)}, nil
	}}
	r.globals["$+"] = &languageThunk{eval: func() (languageValue, error) {
		data, err := r.standardInput(false)
		if err != nil {
			return languageValue{}, err
		}
		return r.readValues(context.Background(), data), nil
	}}
	r.globals["$*"] = &languageThunk{eval: func() (languageValue, error) {
		values := make([]languageValue, len(r.arguments))
		for index, argument := range r.arguments {
			values[index] = languageValue{kind: valueString, text: argument}
		}
		return listValue(values), nil
	}}
	integer := func(small func(int64, int64) (int64, bool), op func(*big.Int, *big.Int) *big.Int) languageValue {
		return curry2(func(_ context.Context, a, b languageValue) (languageValue, error) {
			if a.kind == valueNumber && b.kind == valueNumber && a.num == nil && b.num == nil {
				if result, ok := small(a.small, b.small); ok {
					return languageValue{kind: valueNumber, small: result}, nil
				}
			}
			x, e := numberValue(a)
			if e != nil {
				return languageValue{}, e
			}
			y, e := numberValue(b)
			if e != nil {
				return languageValue{}, e
			}
			return numberFromBig(op(x, y)), nil
		})
	}
	r.builtin("+", numericBinary(smallAdd, func(a, b *big.Int) *big.Int { return new(big.Int).Add(a, b) }, func(a, b float64) float64 { return a + b }))
	r.builtin("-", integer(smallSub, func(a, b *big.Int) *big.Int { return new(big.Int).Sub(a, b) }))
	r.builtin("*", numericBinary(smallMul, func(a, b *big.Int) *big.Int { return new(big.Int).Mul(a, b) }, func(a, b float64) float64 { return a * b }))
	r.builtin("^", curry2(func(_ context.Context, a, b languageValue) (languageValue, error) {
		if a.kind == valueNumber && b.kind == valueNumber {
			exponent := integerPointer(b)
			if exponent.Sign() >= 0 && exponent.IsInt64() {
				return numberFromBig(new(big.Int).Exp(integerPointer(a), exponent, nil)), nil
			}
		}
		x, e := realValue(a)
		if e != nil {
			return languageValue{}, e
		}
		y, e := realValue(b)
		if e != nil {
			return languageValue{}, e
		}
		return languageValue{kind: valueFloat, real: math.Pow(x, y)}, nil
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
		q, _ := mirandaDivMod(x, y)
		return numberFromBig(q), nil
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
		_, remainder := mirandaDivMod(x, y)
		return numberFromBig(remainder), nil
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
	r.builtin("code", languageValue{kind: valueFunction, fn: func(_ context.Context, value languageValue) (languageValue, error) {
		if value.kind != valueChar {
			return languageValue{}, errors.New("character expected")
		}
		return languageValue{kind: valueNumber, small: value.small}, nil
	}})
	r.builtin("decode", languageValue{kind: valueFunction, fn: func(_ context.Context, value languageValue) (languageValue, error) {
		number, err := numberValue(value)
		if err != nil || !number.IsInt64() || !utf8.ValidRune(rune(number.Int64())) {
			return languageValue{}, errors.New("valid Unicode code point expected")
		}
		return languageValue{kind: valueChar, small: number.Int64()}, nil
	}})
	r.builtin("&", lazyBooleanOperator(true))
	r.builtin("/\\", lazyBooleanOperator(true))
	r.builtin("\\/", lazyBooleanOperator(false))
	for name, comparison := range map[string]func(int) bool{"=": func(c int) bool { return c == 0 }, "~=": func(c int) bool { return c != 0 }, "<": func(c int) bool { return c < 0 }, "<=": func(c int) bool { return c <= 0 }, ">": func(c int) bool { return c > 0 }, ">=": func(c int) bool { return c >= 0 }} {
		compare := comparison
		r.builtin(name, curry2(func(ctx context.Context, a, b languageValue) (languageValue, error) {
			comparison, e := compareLanguageValues(ctx, a, b)
			if e != nil {
				return languageValue{}, e
			}
			return languageValue{kind: valueBool, flag: compare(comparison)}, nil
		}))
	}
	r.builtin("!", curry2(func(ctx context.Context, sequence, position languageValue) (languageValue, error) {
		index, e := numberValue(position)
		if e != nil || !index.IsInt64() || index.Sign() < 0 {
			return languageValue{}, errors.New("non-negative integer subscript expected")
		}
		if sequence.kind == valueString {
			chars := []rune(sequence.text)
			if index.Int64() >= int64(len(chars)) {
				return languageValue{}, errors.New("subscript out of range")
			}
			return languageValue{kind: valueChar, small: int64(chars[index.Int64()])}, nil
		}
		if sequence.kind != valueList {
			return languageValue{}, listTypeMismatch(sequence)
		}
		value, ok, e := sequence.list.at(ctx, int(index.Int64()))
		if e != nil {
			return languageValue{}, e
		}
		if !ok {
			return languageValue{}, errors.New("subscript out of range")
		}
		return value, nil
	}))
	r.builtin(".", curry2(func(_ context.Context, outer, inner languageValue) (languageValue, error) {
		return languageValue{kind: valueFunction, lazyFn: func(ctx context.Context, argument *languageThunk) (languageValue, error) {
			middle, e := applyLanguageThunk(ctx, inner, argument)
			if e != nil {
				return languageValue{}, e
			}
			return applyLanguage(ctx, outer, middle)
		}}, nil
	}))
	r.builtin("--", curry2(listDifference))
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
			return languageValue{}, listTypeMismatch(input)
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
			return languageValue{}, listTypeMismatch(input)
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
		return r.readValues(ctx, data), nil
	}})
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
	for name, function := range map[string]func(float64) float64{"arctan": math.Atan, "exp": math.Exp, "log": math.Log, "log10": math.Log10, "sqrt": math.Sqrt} {
		function := function
		r.builtin(name, languageValue{kind: valueFunction, fn: func(_ context.Context, value languageValue) (languageValue, error) {
			number, err := realValue(value)
			if err != nil {
				return languageValue{}, err
			}
			return languageValue{kind: valueFloat, real: function(number)}, nil
		}})
	}
	r.builtin("hugenum", languageValue{kind: valueFloat, real: math.MaxFloat64})
	r.builtin("tinynum", languageValue{kind: valueFloat, real: math.SmallestNonzeroFloat64})
	r.builtin("integer", languageValue{kind: valueFunction, fn: func(_ context.Context, value languageValue) (languageValue, error) {
		if value.kind == valueNumber {
			return languageValue{kind: valueBool, flag: true}, nil
		}
		if value.kind == valueFloat {
			return languageValue{kind: valueBool, flag: value.real == math.Trunc(value.real)}, nil
		}
		return languageValue{}, errors.New("number expected")
	}})
	r.builtin("error", languageValue{kind: valueFunction, fn: func(_ context.Context, value languageValue) (languageValue, error) {
		if value.kind != valueString {
			return languageValue{}, errors.New("string expected")
		}
		return languageValue{}, errors.New(value.text)
	}})
	r.builtin("drop", curry2(func(_ context.Context, count, input languageValue) (languageValue, error) {
		number, err := numberValue(count)
		if err != nil || !number.IsInt64() {
			return languageValue{}, errors.New("integer count expected")
		}
		offset := number.Int64()
		if offset < 0 {
			offset = 0
		}
		if input.kind != valueList {
			return languageValue{}, listTypeMismatch(input)
		}
		return languageValue{kind: valueList, list: &lazyList{next: func(ctx context.Context, index int) (languageValue, bool, error) {
			return input.list.at(ctx, int(offset)+index)
		}}}, nil
	}))
	r.builtin("last", languageValue{kind: valueFunction, fn: func(ctx context.Context, input languageValue) (languageValue, error) {
		values, err := finiteList(ctx, input, maxMaterializedList)
		if err != nil {
			return languageValue{}, err
		}
		if len(values) == 0 {
			return languageValue{}, errors.New("last of empty list")
		}
		return values[len(values)-1], nil
	}})
	r.builtin("foldl1", curry2(func(ctx context.Context, operation, input languageValue) (languageValue, error) {
		values, err := finiteList(ctx, input, maxMaterializedList)
		if err != nil {
			return languageValue{}, err
		}
		if len(values) == 0 {
			return languageValue{}, errors.New("foldl1 applied to []")
		}
		result := values[0]
		for _, value := range values[1:] {
			fn, err := applyLanguage(ctx, operation, result)
			if err != nil {
				return languageValue{}, err
			}
			result, err = applyLanguage(ctx, fn, value)
			if err != nil {
				return languageValue{}, err
			}
		}
		return result, nil
	}))
	r.builtin("shownum", languageValue{kind: valueFunction, fn: func(_ context.Context, value languageValue) (languageValue, error) {
		if value.kind == valueNumber {
			return languageValue{kind: valueString, text: integerPointer(value).String()}, nil
		}
		if value.kind == valueFloat {
			return languageValue{kind: valueString, text: strconv.FormatFloat(value.real, 'g', -1, 64)}, nil
		}
		return languageValue{}, errors.New("number expected")
	}})
	r.builtin("seq", languageValue{kind: valueFunction, lazyFn: func(_ context.Context, first *languageThunk) (languageValue, error) {
		if _, err := first.force(); err != nil {
			return languageValue{}, err
		}
		return languageValue{kind: valueFunction, lazyFn: func(_ context.Context, second *languageThunk) (languageValue, error) {
			return languageValue{kind: valueThunk, thunk: second}, nil
		}}, nil
	}})
	r.builtin("force", languageValue{kind: valueFunction, fn: func(ctx context.Context, value languageValue) (languageValue, error) {
		if err := deepForceLanguage(ctx, value); err != nil {
			return languageValue{}, err
		}
		return value, nil
	}})
	r.builtin("showfloat", curry2(formatMirandaFloat('f')))
	r.builtin("showscaled", curry2(formatMirandaFloat('e')))
	r.builtin("getenv", languageValue{kind: valueFunction, fn: func(_ context.Context, value languageValue) (languageValue, error) {
		if value.kind != valueString {
			return languageValue{}, errors.New("string expected")
		}
		return languageValue{kind: valueString, text: os.Getenv(value.text)}, nil
	}})
	readFile := func(binary bool) func(context.Context, languageValue) (languageValue, error) {
		return func(_ context.Context, value languageValue) (languageValue, error) {
			if value.kind != valueString {
				return languageValue{}, errors.New("string expected")
			}
			content, err := os.ReadFile(value.text)
			if err != nil {
				return languageValue{}, err
			}
			if !binary && !utf8.Valid(content) {
				return languageValue{}, errors.New("illegal UTF-8 input")
			}
			return languageValue{kind: valueString, text: string(content)}, nil
		}
	}
	r.builtin("read", languageValue{kind: valueFunction, fn: readFile(false)})
	r.builtin("readb", languageValue{kind: valueFunction, fn: readFile(true)})
	r.builtin("filemode", languageValue{kind: valueFunction, fn: func(_ context.Context, value languageValue) (languageValue, error) {
		if value.kind != valueString {
			return languageValue{}, errors.New("string expected")
		}
		info, err := os.Stat(value.text)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				return languageValue{kind: valueString}, nil
			}
			return languageValue{}, err
		}
		mode := []byte("----")
		if info.IsDir() {
			mode[0] = 'd'
		}
		if file, err := os.Open(value.text); err == nil {
			mode[1] = 'r'
			_ = file.Close()
		}
		if file, err := os.OpenFile(value.text, os.O_WRONLY, 0); err == nil {
			mode[2] = 'w'
			_ = file.Close()
		}
		if info.Mode()&0111 != 0 {
			mode[3] = 'x'
		}
		return languageValue{kind: valueString, text: string(mode)}, nil
	}})
	r.builtin("filestat", languageValue{kind: valueFunction, fn: func(_ context.Context, value languageValue) (languageValue, error) {
		if value.kind != valueString {
			return languageValue{}, errors.New("string expected")
		}
		info, err := os.Stat(value.text)
		if err != nil {
			return languageValue{kind: valueTuple, items: []languageValue{{kind: valueTuple, items: []languageValue{{kind: valueNumber}, {kind: valueNumber, small: -1}}}, {kind: valueNumber}}}, nil
		}
		stat, _ := info.Sys().(*syscall.Stat_t)
		inode, device := int64(0), int64(0)
		if stat != nil {
			inode, device = int64(stat.Ino), int64(stat.Dev)
		}
		return languageValue{kind: valueTuple, items: []languageValue{{kind: valueTuple, items: []languageValue{{kind: valueNumber, small: inode}, {kind: valueNumber, small: device}}}, {kind: valueNumber, small: info.ModTime().Unix()}}}, nil
	}})
	r.builtin("merge", curry2(mergeLanguageLists))
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

func numericBinary(small func(int64, int64) (int64, bool), integer func(*big.Int, *big.Int) *big.Int, floating func(float64, float64) float64) languageValue {
	return curry2(func(_ context.Context, a, b languageValue) (languageValue, error) {
		if a.kind == valueNumber && b.kind == valueNumber {
			if a.num == nil && b.num == nil {
				if result, ok := small(a.small, b.small); ok {
					return languageValue{kind: valueNumber, small: result}, nil
				}
			}
			return numberFromBig(integer(integerPointer(a), integerPointer(b))), nil
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

func formatMirandaFloat(format byte) func(context.Context, languageValue, languageValue) (languageValue, error) {
	return func(_ context.Context, precisionValue, numberValue languageValue) (languageValue, error) {
		precision, err := numberValueInteger(precisionValue)
		if err != nil || !precision.IsInt64() || precision.Sign() < 0 {
			return languageValue{}, errors.New("non-negative integer precision expected")
		}
		number, err := realValue(numberValue)
		if err != nil {
			return languageValue{}, err
		}
		return languageValue{kind: valueString, text: strconv.FormatFloat(number, format, int(precision.Int64()), 64)}, nil
	}
}

func numberValueInteger(value languageValue) (*big.Int, error) { return numberValue(value) }

func mergeLanguageLists(ctx context.Context, left, right languageValue) (languageValue, error) {
	if left.kind != valueList || right.kind != valueList {
		return languageValue{}, errors.New("list expected")
	}
	leftIndex, rightIndex := 0, 0
	return languageValue{kind: valueList, list: &lazyList{next: func(nextCtx context.Context, _ int) (languageValue, bool, error) {
		a, aok, err := left.list.at(nextCtx, leftIndex)
		if err != nil {
			return languageValue{}, false, err
		}
		b, bok, err := right.list.at(nextCtx, rightIndex)
		if err != nil {
			return languageValue{}, false, err
		}
		if !aok {
			if bok {
				rightIndex++
				return b, true, nil
			}
			return languageValue{}, false, nil
		}
		if !bok {
			leftIndex++
			return a, true, nil
		}
		comparison, err := compareLanguageValues(ctx, a, b)
		if err != nil {
			return languageValue{}, false, err
		}
		if comparison <= 0 {
			leftIndex++
			return a, true, nil
		}
		rightIndex++
		return b, true, nil
	}}}, nil
}

func smallAdd(a, b int64) (int64, bool) {
	result := a + b
	return result, (b <= 0 || result >= a) && (b >= 0 || result <= a)
}
func smallSub(a, b int64) (int64, bool) {
	result := a - b
	return result, (b <= 0 || result <= a) && (b >= 0 || result >= a)
}
func smallMul(a, b int64) (int64, bool) {
	if a == 0 || b == 0 {
		return 0, true
	}
	if a == math.MinInt64 && b == -1 || b == math.MinInt64 && a == -1 {
		return 0, false
	}
	result := a * b
	return result, result/b == a
}

const maxMaterializedList = 1_000_000

func finiteList(ctx context.Context, value languageValue, limit int) ([]languageValue, error) {
	if value.kind != valueList || value.list == nil {
		return nil, listTypeMismatch(value)
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
	_, ok, err := value.list.at(ctx, limit)
	if err != nil {
		return nil, err
	}
	if !ok {
		return out, nil
	}
	return nil, errors.New("list output limit exceeded")
}

func renderLanguage(ctx context.Context, value languageValue) (string, error) {
	var forceErr error
	value, forceErr = forceLanguageValue(value, nil)
	if forceErr != nil {
		return "", forceErr
	}
	switch value.kind {
	case valueNumber:
		if value.num == nil {
			return strconv.FormatInt(value.small, 10), nil
		}
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
	case valueChar:
		return quoteMirandaChar(rune(value.small)), nil
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
		values, e := finiteList(ctx, value, maxMaterializedList)
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

func streamLanguageList(ctx context.Context, destination io.Writer, value languageValue) error {
	if value.kind != valueList || value.list == nil {
		return errors.New("list expected")
	}
	writer := bufio.NewWriterSize(destination, 16*1024)
	defer writer.Flush()
	opened := false
	written := 0
	for index := 0; ; index++ {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		item, ok, err := value.list.at(ctx, index)
		if err != nil {
			return err
		}
		if !ok {
			if opened {
				_, err = writer.WriteString("]")
			}
			return err
		}
		if item.kind == valueMessage {
			continue
		}
		text, err := renderLanguage(ctx, item)
		if err != nil {
			return err
		}
		if !opened {
			if _, err = writer.WriteString("["); err != nil {
				return err
			}
			opened = true
		} else if _, err = writer.WriteString(","); err != nil {
			return err
		}
		if _, err = writer.WriteString(text); err != nil {
			return err
		}
		written++
		if written%256 == 0 {
			if err = writer.Flush(); err != nil {
				return err
			}
		}
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
	var err error
	value, err = forceLanguageValue(value, nil)
	if err != nil {
		return "", err
	}
	if value.kind == valueString {
		return strconv.Quote(value.text), nil
	}
	return renderLanguage(ctx, value)
}

func renderNestedLanguage(ctx context.Context, value languageValue) (string, error) {
	var err error
	value, err = forceLanguageValue(value, nil)
	if err != nil {
		return "", err
	}
	if value.kind == valueString {
		return strconv.Quote(value.text), nil
	}
	if value.kind == valueConstructor {
		return renderConstructor(ctx, value, true)
	}
	return renderLanguage(ctx, value)
}
