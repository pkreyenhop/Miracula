package syntaxfront

// ApplyLayout inserts offside separators at equal/dedented margins. Explicit
// semicolons remain authoritative. Where and with tokens open a margin on the
// first token of the following line.
func ApplyLayout(tokens []Token) []Token {
	if len(tokens) == 0 {
		return nil
	}
	result := make([]Token, 0, len(tokens)+8)
	var margins []int
	previousLine := 0
	openWhere := false
	for _, token := range tokens {
		if token.Kind == "eof" {
			for range margins {
				result = append(result, offsideAt(token))
			}
			result = append(result, token)
			return result
		}
		newLine := previousLine != 0 && token.Span.Line > previousLine
		if len(margins) == 0 {
			margins = append(margins, token.Span.Column)
		}
		if openWhere {
			margins = append(margins, token.Span.Column)
			openWhere = false
		} else if newLine {
			for len(margins) > 1 && token.Span.Column < margins[len(margins)-1] {
				result = append(result, offsideAt(token))
				margins = margins[:len(margins)-1]
			}
			if token.Span.Column == margins[len(margins)-1] && token.Kind != "eq" {
				result = append(result, offsideAt(token))
			}
		}
		result = append(result, token)
		if token.Kind == "kw_where" || token.Kind == "kw_with" {
			openWhere = true
		}
		previousLine = token.Span.Line
	}
	return result
}

func offsideAt(token Token) Token {
	span := token.Span
	span.End = span.Start
	return Token{Kind: "offside", Bytes: []byte{}, Span: span}
}
