package semantics

import (
	"fmt"
	"strings"
	"unicode"
)

type typeToken struct {
	kind string
	text string
}

func ParseType(text string) (*Type, error) {
	return parseTypeWithVariables(text, nil)
}

func parseTypeWithVariables(text string, variables map[string]*Type) (*Type, error) {
	tokens, err := lexType(text)
	if err != nil {
		return nil, err
	}
	if variables == nil {
		variables = map[string]*Type{}
	}
	parser := typeParser{tokens: tokens, variables: variables, next: 1_000_000}
	result, err := parser.arrow()
	if err != nil {
		return nil, err
	}
	if parser.position != len(tokens) {
		return nil, fmt.Errorf("unexpected type token %q", tokens[parser.position].text)
	}
	return result, nil
}

func lexType(text string) ([]typeToken, error) {
	var tokens []typeToken
	for position := 0; position < len(text); {
		if unicode.IsSpace(rune(text[position])) {
			position++
			continue
		}
		if strings.HasPrefix(text[position:], "->") {
			tokens = append(tokens, typeToken{kind: "arrow", text: "->"})
			position += 2
			continue
		}
		switch text[position] {
		case '[', ']', '(', ')', ',':
			tokens = append(tokens, typeToken{kind: string(text[position]), text: string(text[position])})
			position++
			continue
		case '*':
			start := position
			for position < len(text) && text[position] == '*' {
				position++
			}
			tokens = append(tokens, typeToken{kind: "variable", text: text[start:position]})
			continue
		}
		if unicode.IsLetter(rune(text[position])) || text[position] == '_' {
			start := position
			for position < len(text) && (unicode.IsLetter(rune(text[position])) || unicode.IsDigit(rune(text[position])) || text[position] == '_' || text[position] == '\'') {
				position++
			}
			tokens = append(tokens, typeToken{kind: "name", text: text[start:position]})
			continue
		}
		return nil, fmt.Errorf("invalid type character %q", text[position])
	}
	return tokens, nil
}

type typeParser struct {
	tokens    []typeToken
	position  int
	variables map[string]*Type
	next      int
}

func (p *typeParser) arrow() (*Type, error) {
	left, err := p.application()
	if err != nil {
		return nil, err
	}
	if p.take("arrow") {
		right, err := p.arrow()
		if err != nil {
			return nil, err
		}
		return &Type{Kind: TypeArrow, From: left, To: right}, nil
	}
	return left, nil
}

func (p *typeParser) application() (*Type, error) {
	first, err := p.atom()
	if err != nil {
		return nil, err
	}
	var arguments []*Type
	for p.position < len(p.tokens) && p.tokens[p.position].kind != "arrow" && p.tokens[p.position].kind != ")" && p.tokens[p.position].kind != "]" && p.tokens[p.position].kind != "," {
		argument, atomErr := p.atom()
		if atomErr != nil {
			return nil, atomErr
		}
		arguments = append(arguments, argument)
	}
	if len(arguments) == 0 {
		return first, nil
	}
	if first.Kind != TypeNamed {
		return nil, fmt.Errorf("invalid type application")
	}
	return &Type{Kind: TypeApply, Name: first.Name, Items: arguments}, nil
}

func (p *typeParser) atom() (*Type, error) {
	if p.position >= len(p.tokens) {
		return nil, fmt.Errorf("type expected")
	}
	token := p.tokens[p.position]
	p.position++
	switch token.kind {
	case "name":
		return &Type{Kind: TypeNamed, Name: token.text}, nil
	case "variable":
		if existing := p.variables[token.text]; existing != nil {
			return existing, nil
		}
		value := &Type{Kind: TypeVariable, ID: p.next}
		p.next++
		p.variables[token.text] = value
		return value, nil
	case "[":
		item, err := p.arrow()
		if err != nil || !p.take("]") {
			return nil, fmt.Errorf("unterminated list type")
		}
		return &Type{Kind: TypeList, Items: []*Type{item}}, nil
	case "(":
		if p.take(")") {
			return &Type{Kind: TypeTuple}, nil
		}
		first, err := p.arrow()
		if err != nil {
			return nil, err
		}
		if p.take(")") {
			return first, nil
		}
		items := []*Type{first}
		for p.take(",") {
			item, itemErr := p.arrow()
			if itemErr != nil {
				return nil, itemErr
			}
			items = append(items, item)
		}
		if !p.take(")") {
			return nil, fmt.Errorf("unterminated tuple type")
		}
		return &Type{Kind: TypeTuple, Items: items}, nil
	default:
		return nil, fmt.Errorf("type expected, got %q", token.text)
	}
}

func (p *typeParser) take(kind string) bool {
	if p.position < len(p.tokens) && p.tokens[p.position].kind == kind {
		p.position++
		return true
	}
	return false
}
