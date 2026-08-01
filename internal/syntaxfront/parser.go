package syntaxfront

import "strings"

type parser struct {
	tokens      []Token
	position    int
	diagnostics []Diagnostic
}

func Parse(tokens []Token) (Script, []Diagnostic) {
	p := parser{tokens: tokens}
	script := Script{Variant: "script", Items: []Definition{}}
	for !p.at("eof") {
		for p.at("offside") || p.at("semicolon") {
			p.position++
		}
		if p.at("eof") {
			break
		}
		start := p.position
		end := start
		depth := 0
		for end < len(tokens) {
			kind := tokens[end].Kind
			if depth == 0 && (kind == "offside" || kind == "semicolon" || kind == "eof") {
				break
			}
			switch kind {
			case "lparen", "lbracket", "lbrace":
				depth++
			case "rparen", "rbracket", "rbrace":
				depth--
			}
			end++
		}
		if end == start {
			p.position++
			continue
		}
		statement := tokens[start:end]
		if bad := firstKind(statement, "error"); bad >= 0 {
			p.diagnostics = append(p.diagnostics, Diagnostic{"error", "unexpected token", "", statement[bad].Span})
			p.position = end
			continue
		}
		definition, diagnostic := parseStatement(statement)
		if diagnostic != nil {
			p.diagnostics = append(p.diagnostics, *diagnostic)
		} else {
			script.Items = append(script.Items, definition)
		}
		p.position = end
	}
	return script, p.diagnostics
}

func parseStatement(tokens []Token) (Definition, *Diagnostic) {
	span := tokens[0].Span
	span.End = tokens[len(tokens)-1].Span.End
	var textBuilder strings.Builder
	for index := range tokens {
		if index != 0 {
			if tokens[index].Span.Line > tokens[index-1].Span.Line {
				textBuilder.WriteByte('\n')
			} else {
				textBuilder.WriteByte(' ')
			}
		}
		textBuilder.Write(tokens[index].Bytes)
	}
	text := textBuilder.String()
	if tokens[0].Kind == "directive" {
		return Definition{Variant: "directive", LHS: Expr{Variant: "directive", Text: string(tokens[0].Bytes), Span: span}, Text: text, Span: span}, nil
	}
	separator := firstKind(tokens, "eq")
	variant := "definition"
	if separator < 0 {
		separator = firstKind(tokens, "type_annotation")
		variant = "type_signature"
	}
	if separator < 0 {
		separator = firstKind(tokens, "type_def")
		variant = "type_declaration"
	}
	if separator < 0 {
		if strings.HasPrefix(tokens[0].Kind, "kw_") {
			return Definition{Variant: "declaration", LHS: Expr{Variant: "raw", Text: text, Span: span}, Text: text, Span: span}, nil
		}
		// Offside can separate guarded equations, declaration bodies, and
		// comprehension continuations. Preserve them for semantic ownership;
		// only lexical errors and structurally incomplete separators are parser
		// diagnostics.
		return Definition{Variant: "continuation", LHS: Expr{Variant: "raw", Text: text, Span: span}, Text: text, Span: span}, nil
	}
	lhsTokens, rhsTokens := tokens[:separator], tokens[separator+1:]
	if len(lhsTokens) == 0 || len(rhsTokens) == 0 {
		return Definition{}, &Diagnostic{"error", "incomplete definition", "", span}
	}
	lhs := parseExpression(lhsTokens)
	rhs := parseExpression(rhsTokens)
	return Definition{Variant: variant, LHS: lhs, RHS: rhs, Text: text, Span: span}, nil
}

func parseExpression(tokens []Token) Expr {
	value, _ := parsePratt(tokens, 0, 0)
	return value
}

func parsePratt(tokens []Token, position, minimum int) (Expr, int) {
	if len(tokens) == 0 {
		return Expr{Variant: "empty"}, position
	}
	if position >= len(tokens) {
		return Expr{Variant: "empty"}, position
	}
	start := position
	var result Expr
	token := tokens[position]
	position++
	switch token.Kind {
	case "minus", "not", "length":
		argument, next := parsePratt(tokens, position, map[string]int{"minus": 65, "not": 35, "length": 85}[token.Kind])
		result, position = Expr{Variant: map[string]string{"minus": "neg", "not": "not", "length": "length"}[token.Kind], Arg: exprPtr(argument), Span: token.Span}, next
	case "lparen":
		close := matchingClose(tokens, start, "lparen", "rparen")
		if close < 0 {
			return Expr{Variant: "empty", Span: token.Span}, len(tokens)
		}
		inside := tokens[position:close]
		if len(inside) == 1 {
			if _, ok := InfixBinding(inside[0].Kind); ok && inside[0].Kind != "minus" {
				result = Expr{Variant: "op_func", Text: string(inside[0].Bytes), Span: mergeSpan(tokens[start : close+1])}
				position = close + 1
				break
			}
		}
		if len(inside) > 1 {
			if _, ok := InfixBinding(inside[0].Kind); ok && inside[0].Kind != "minus" {
				arg := parseExpression(inside[1:])
				result = Expr{Variant: "section_right", Text: string(inside[0].Bytes), Arg: &arg, Span: mergeSpan(tokens[start : close+1])}
				position = close + 1
				break
			}
			if _, ok := InfixBinding(inside[len(inside)-1].Kind); ok {
				arg := parseExpression(inside[:len(inside)-1])
				result = Expr{Variant: "section_left", Text: string(inside[len(inside)-1].Bytes), Arg: &arg, Span: mergeSpan(tokens[start : close+1])}
				position = close + 1
				break
			}
		}
		parts := splitTopLevel(inside, "comma")
		if len(parts) > 1 {
			items := make([]Expr, len(parts))
			for i := range parts {
				items[i] = parseExpression(parts[i])
			}
			result = Expr{Variant: "tuple", Items: items, Span: mergeSpan(tokens[start : close+1])}
		} else {
			result = parseExpression(inside)
		}
		position = close + 1
	case "lbracket":
		close := matchingClose(tokens, start, "lbracket", "rbracket")
		if close < 0 {
			return Expr{Variant: "empty", Span: token.Span}, len(tokens)
		}
		inside := tokens[position:close]
		barAt, variant := topLevelIndex(inside, "bar"), "listcomp"
		if diagonalAt := topLevelIndex(inside, "diagonal"); barAt < 0 && diagonalAt >= 0 {
			barAt, variant = diagonalAt, "diagonal_listcomp"
		}
		if barAt >= 0 {
			body := parseExpression(inside[:barAt])
			result = Expr{Variant: variant, Body: &body, Span: mergeSpan(tokens[start : close+1])}
			for _, part := range splitTopLevel(inside[barAt+1:], "semicolon") {
				if len(part) == 0 {
					continue
				}
				if arrow := topLevelIndex(part, "left_arrow"); arrow >= 0 {
					patternTokens := part[:arrow]
					patternParts := splitTopLevel(patternTokens, "comma")
					sourceTokens := part[arrow+1:]
					var recurrence *Expr
					if rangeAt := topLevelIndex(sourceTokens, "range"); rangeAt >= 0 {
						starts := splitTopLevel(sourceTokens[:rangeAt], "comma")
						if len(starts) == 2 {
							sourceTokens = starts[0]
							next := parseExpression(starts[1])
							recurrence = &next
						}
					}
					source := parseExpression(sourceTokens)
					for _, patternTokens := range patternParts {
						pattern := parseExpression(patternTokens)
						result.Qualifiers = append(result.Qualifiers, Qualifier{Pattern: &pattern, Source: &source, Recurrence: recurrence})
					}
				} else {
					guard := parseExpression(part)
					result.Qualifiers = append(result.Qualifiers, Qualifier{Guard: &guard})
				}
			}
		} else if rangeAt := topLevelIndex(inside, "range"); rangeAt >= 0 {
			left, right := inside[:rangeAt], inside[rangeAt+1:]
			starts := splitTopLevel(left, "comma")
			result = Expr{Variant: "range", Span: mergeSpan(tokens[start : close+1])}
			if len(starts) > 0 && len(starts[0]) > 0 {
				from := parseExpression(starts[0])
				result.Head = &from
			}
			if len(starts) > 1 {
				step := parseExpression(starts[1])
				result.Step = &step
			}
			if len(right) > 0 {
				to := parseExpression(right)
				result.To = &to
			}
		} else {
			parts := splitTopLevel(inside, "comma")
			items := make([]Expr, 0, len(parts))
			for _, part := range parts {
				if len(part) > 0 {
					items = append(items, parseExpression(part))
				}
			}
			result = Expr{Variant: "list", Items: items, Span: mergeSpan(tokens[start : close+1])}
		}
		position = close + 1
	default:
		result = atom(token)
	}
	for position < len(tokens) {
		next := tokens[position]
		if binding, ok := InfixBinding(next.Kind); ok {
			if binding.Left <= minimum {
				break
			}
			position++
			right, after := parsePratt(tokens, position, binding.Right)
			result = Expr{Variant: "infix", Text: string(next.Bytes), Head: exprPtr(result), Tail: exprPtr(right), Span: Span{Start: result.Span.Start, End: right.Span.End, Line: result.Span.Line, Column: result.Span.Column}}
			position = after
			continue
		}
		if isExpressionStart(next.Kind) && 100 > minimum {
			right, after := parsePratt(tokens, position, 100)
			result = Expr{Variant: "application", Func: exprPtr(result), Arg: exprPtr(right), Span: Span{Start: result.Span.Start, End: right.Span.End, Line: result.Span.Line, Column: result.Span.Column}}
			position = after
			continue
		}
		break
	}
	return result, position
}

func isExpressionStart(kind string) bool {
	switch kind {
	case "name", "cname", "const_int", "const_float", "const_str", "const_char", "lparen", "lbracket", "minus", "not", "length", "kw_show", "kw_readvals", "dollars":
		return true
	}
	return false
}

func topLevelIndex(tokens []Token, kind string) int {
	depth := 0
	for index, token := range tokens {
		switch token.Kind {
		case "lparen", "lbracket", "lbrace":
			depth++
		case "rparen", "rbracket", "rbrace":
			depth--
		}
		if depth == 0 && token.Kind == kind {
			return index
		}
	}
	return -1
}

func parsePrimary(tokens []Token) (Expr, int) {
	if len(tokens) == 0 {
		return Expr{Variant: "empty"}, 0
	}
	if tokens[0].Kind == "lparen" {
		if close := matchingClose(tokens, 0, "lparen", "rparen"); close > 0 {
			return parseExpression(tokens[:close+1]), close + 1
		}
	}
	if tokens[0].Kind == "lbracket" {
		if close := matchingClose(tokens, 0, "lbracket", "rbracket"); close > 0 {
			return parseExpression(tokens[:close+1]), close + 1
		}
	}
	return atom(tokens[0]), 1
}

func atom(token Token) Expr {
	variant := map[string]string{"name": "name", "cname": "constructor", "const_int": "int", "const_float": "float", "const_str": "string", "const_char": "char"}[token.Kind]
	if token.Kind == "kw_show" || token.Kind == "kw_readvals" {
		variant = "name"
	}
	if variant == "" {
		variant = "token"
	}
	return Expr{Variant: variant, Text: string(token.Bytes), Span: token.Span}
}
func exprPtr(value Expr) *Expr { return &value }
func (p *parser) at(kind string) bool {
	return p.position >= len(p.tokens) || p.tokens[p.position].Kind == kind
}
func firstKind(tokens []Token, kind string) int {
	for i, t := range tokens {
		if t.Kind == kind {
			return i
		}
	}
	return -1
}
func mergeSpan(tokens []Token) Span {
	s := tokens[0].Span
	s.End = tokens[len(tokens)-1].Span.End
	return s
}
func matchingClose(tokens []Token, start int, open, close string) int {
	depth := 0
	for i := start; i < len(tokens); i++ {
		if tokens[i].Kind == open {
			depth++
		}
		if tokens[i].Kind == close {
			depth--
			if depth == 0 {
				return i
			}
		}
	}
	return -1
}
func splitTopLevel(tokens []Token, kind string) [][]Token {
	var out [][]Token
	start, depth := 0, 0
	for i, t := range tokens {
		if t.Kind == "lparen" || t.Kind == "lbracket" || t.Kind == "lbrace" {
			depth++
		}
		if t.Kind == "rparen" || t.Kind == "rbracket" || t.Kind == "rbrace" {
			depth--
		}
		if depth == 0 && t.Kind == kind {
			out = append(out, tokens[start:i])
			start = i + 1
		}
	}
	return append(out, tokens[start:])
}
func lastTopLevel(tokens []Token, kind string) int {
	depth, index := 0, -1
	for i, t := range tokens {
		if t.Kind == "lparen" || t.Kind == "lbracket" || t.Kind == "lbrace" {
			depth++
		}
		if t.Kind == "rparen" || t.Kind == "rbracket" || t.Kind == "rbrace" {
			depth--
		}
		if depth == 0 && t.Kind == kind {
			index = i
		}
	}
	return index
}
