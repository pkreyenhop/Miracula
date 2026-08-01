package semantics

import (
	"fmt"
	"strings"

	"github.com/pkreyenhop/miracula/internal/syntaxfront"
)

type TypeAlias struct {
	Parameters []*Type
	Type       *Type
}

func installTypeDeclarations(script syntaxfront.Script, state *inferState) error {
	for _, declaration := range script.Items {
		text := normalizedDeclarationText(declaration.Text)
		if strings.HasPrefix(text, "abstype ") {
			fields := strings.Fields(strings.TrimPrefix(text, "abstype "))
			if len(fields) != 0 {
				state.abstract[fields[0]] = true
			}
		}
		if !strings.Contains(text, "==") || strings.Contains(text, "::=") {
			continue
		}
		separator := strings.Index(text, "==")
		left := strings.Fields(strings.TrimSpace(text[:separator]))
		if len(left) == 0 {
			continue
		}
		variables := map[string]*Type{}
		parameters := make([]*Type, len(left)-1)
		for index, name := range left[1:] {
			parameters[index] = state.fresh()
			variables[name] = parameters[index]
		}
		value, err := parseTypeWithVariables(strings.TrimSpace(text[separator+2:]), variables)
		if err != nil {
			return TypeError{Message: err.Error(), Line: declaration.Span.Line, Column: declaration.Span.Column}
		}
		alias := TypeAlias{Parameters: parameters, Type: value}
		if state.abstract[left[0]] {
			state.representations[left[0]] = alias
		} else {
			state.aliases[left[0]] = alias
		}
	}
	for _, declaration := range script.Items {
		if declaration.Variant != "type_declaration" || !strings.Contains(declaration.Text, "::=") {
			continue
		}
		separator := strings.Index(declaration.Text, "::=")
		left := strings.Fields(strings.TrimSpace(declaration.Text[:separator]))
		if len(left) == 0 {
			return TypeError{Message: "typename expected", Line: declaration.Span.Line, Column: declaration.Span.Column}
		}
		typeName := left[0]
		parameters := make([]*Type, len(left)-1)
		parameterByText := map[string]*Type{}
		for index, name := range left[1:] {
			parameter := state.fresh()
			parameters[index] = parameter
			parameterByText[name] = parameter
		}
		result := &Type{Kind: TypeNamed, Name: typeName}
		if len(parameters) != 0 {
			result = &Type{Kind: TypeApply, Name: typeName, Items: parameters}
		}
		for _, alternative := range strings.Split(declaration.Text[separator+3:], "|") {
			fields := splitDeclarationFields(strings.TrimSpace(alternative))
			if len(fields) == 0 || fields[0] == "" || fields[0][0] < 'A' || fields[0][0] > 'Z' {
				return TypeError{Message: "constructor name must begin with an upper-case letter", Line: declaration.Span.Line, Column: declaration.Span.Column}
			}
			constructorType := result
			for index := len(fields) - 1; index >= 1; index-- {
				fieldText := strings.TrimSuffix(fields[index], "!")
				fieldType, err := parseTypeWithVariables(fieldText, parameterByText)
				if err != nil {
					return TypeError{Message: err.Error(), Line: declaration.Span.Line, Column: declaration.Span.Column}
				}
				constructorType = &Type{Kind: TypeArrow, From: state.expandAliases(fieldType), To: constructorType}
			}
			state.schemes[fields[0]] = generalize(constructorType)
		}
	}
	return nil
}

func normalizedDeclarationText(text string) string {
	text = strings.TrimSpace(text)
	text = strings.ReplaceAll(text, "= =", "==")
	return text
}

func (s *inferState) expandAliases(value *Type) *Type {
	return s.expandTypeMap(value, s.aliases)
}

func (s *inferState) expandRepresentations(value *Type) *Type {
	value = s.expandAliases(value)
	return s.expandTypeMap(value, s.representations)
}

func (s *inferState) expandTypeMap(value *Type, aliases map[string]TypeAlias) *Type {
	if value == nil {
		return nil
	}
	alias, found := aliases[value.Name]
	if found && (value.Kind == TypeNamed && len(alias.Parameters) == 0 || value.Kind == TypeApply && len(value.Items) == len(alias.Parameters)) {
		replacements := map[int]*Type{}
		for index, parameter := range alias.Parameters {
			replacements[parameter.ID] = value.Items[index]
		}
		return s.expandTypeMap(substituteAlias(alias.Type, replacements), aliases)
	}
	result := *value
	result.From, result.To = s.expandTypeMap(value.From, aliases), s.expandTypeMap(value.To, aliases)
	result.Items = make([]*Type, len(value.Items))
	for index := range value.Items {
		result.Items[index] = s.expandTypeMap(value.Items[index], aliases)
	}
	return &result
}

func substituteAlias(value *Type, replacements map[int]*Type) *Type {
	if value == nil {
		return nil
	}
	if value.Kind == TypeVariable && replacements[value.ID] != nil {
		return replacements[value.ID]
	}
	result := *value
	result.From, result.To = substituteAlias(value.From, replacements), substituteAlias(value.To, replacements)
	result.Items = make([]*Type, len(value.Items))
	for index := range value.Items {
		result.Items[index] = substituteAlias(value.Items[index], replacements)
	}
	return &result
}

func splitDeclarationFields(text string) []string {
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

func declaredConstructor(state *inferState, name string) (TypeScheme, error) {
	scheme, ok := state.schemes[name]
	if !ok {
		return TypeScheme{}, fmt.Errorf("undefined constructor %s", name)
	}
	return scheme, nil
}
