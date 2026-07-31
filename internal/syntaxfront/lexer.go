package syntaxfront

import "unicode"

type Span struct{ Start, End, Line, Column int }
type Token struct {
	Kind  string
	Bytes []byte
	Span  Span
}

func Lex(source Source) []Token {
	var out []Token
	b := source.Bytes
	for i := 0; i < len(b); {
		if unicode.IsSpace(rune(b[i])) {
			i++
			continue
		}
		start := i
		p := source.Position(i)
		kind := "error"
		switch c := b[i]; {
		case isLetter(c):
			i++
			for i < len(b) && (isLetter(b[i]) || isDigit(b[i]) || b[i] == '_' || b[i] == '\'') {
				i++
			}
			text := string(b[start:i])
			kind = map[string]string{"div": "kw_div", "where": "kw_where"}[text]
			if kind == "" {
				if c >= 'A' && c <= 'Z' {
					kind = "cname"
				} else {
					kind = "name"
				}
			}
		case isDigit(c):
			i++
			kind = "const_int"
			for i < len(b) && isDigit(b[i]) {
				i++
			}
			if i < len(b) && b[i] == '.' && i+1 < len(b) && isDigit(b[i+1]) {
				kind = "const_float"
				i++
				for i < len(b) && isDigit(b[i]) {
					i++
				}
			}
		case c == '"':
			i++
			for i < len(b) && b[i] != '"' && b[i] != '\n' {
				if b[i] == '\\' && i+1 < len(b) {
					i += 2
				} else {
					i++
				}
			}
			if i < len(b) && b[i] == '"' {
				i++
				kind = "const_str"
			}
		case c == '\'':
			i++
			for i < len(b) && b[i] != '\'' {
				i++
			}
			if i < len(b) {
				i++
				kind = "const_char"
			}
		default:
			i++
			kind = map[byte]string{'=': "eq", '+': "plus", ':': "cons", '[': "lbracket", ']': "rbracket", ',': "comma", ';': "semicolon", '(': "lparen", ')': "rparen"}[c]
			if kind == "" {
				kind = "error"
			}
		}
		out = append(out, Token{kind, append([]byte(nil), b[start:i]...), Span{start, i, p.Line, p.Column}})
	}
	p := source.Position(len(b))
	out = append(out, Token{"eof", []byte{}, Span{len(b), len(b), p.Line, p.Column}})
	return out
}
func isLetter(b byte) bool { return b >= 'a' && b <= 'z' || b >= 'A' && b <= 'Z' }
func isDigit(b byte) bool  { return b >= '0' && b <= '9' }
