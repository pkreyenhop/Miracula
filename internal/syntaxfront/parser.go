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
		for end < len(tokens) && tokens[end].Kind != "offside" && tokens[end].Kind != "semicolon" && tokens[end].Kind != "eof" {
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
	textParts := make([]string, len(tokens))
	for i := range tokens {
		textParts[i] = string(tokens[i].Bytes)
	}
	text := strings.Join(textParts, " ")
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
	if len(tokens) == 0 {
		return Expr{Variant: "empty"}
	}
	if len(tokens) == 1 {
		return atom(tokens[0])
	}
	if tokens[0].Kind == "lparen" && matchingClose(tokens, 0, "lparen", "rparen") == len(tokens)-1 {
		inside := tokens[1 : len(tokens)-1]
		parts := splitTopLevel(inside, "comma")
		if len(parts) > 1 {
			items := make([]Expr, len(parts))
			for i := range parts {
				items[i] = parseExpression(parts[i])
			}
			return Expr{Variant: "tuple", Items: items, Span: mergeSpan(tokens)}
		}
		return parseExpression(inside)
	}
	if tokens[0].Kind == "lbracket" && matchingClose(tokens, 0, "lbracket", "rbracket") == len(tokens)-1 {
		parts := splitTopLevel(tokens[1:len(tokens)-1], "comma")
		items := make([]Expr, 0, len(parts))
		for _, part := range parts {
			if len(part) > 0 {
				items = append(items, parseExpression(part))
			}
		}
		return Expr{Variant: "list", Items: items, Span: mergeSpan(tokens)}
	}
	for _, kind := range []string{"cons", "bar", "comma", "eq", "not_equal", "less", "greater", "less_equal", "greater_equal", "append", "difference", "plus", "minus", "star", "slash", "kw_div", "kw_mod", "power"} {
		if index := lastTopLevel(tokens, kind); index > 0 && index < len(tokens)-1 {
			return Expr{Variant: "infix", Text: string(tokens[index].Bytes), Head: exprPtr(parseExpression(tokens[:index])), Tail: exprPtr(parseExpression(tokens[index+1:])), Span: mergeSpan(tokens)}
		}
	}
	result, consumed := parsePrimary(tokens)
	for consumed < len(tokens) {
		next, count := parsePrimary(tokens[consumed:])
		result = Expr{Variant: "application", Func: exprPtr(result), Arg: exprPtr(next), Span: mergeSpan(tokens)}
		consumed += count
	}
	return result
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
