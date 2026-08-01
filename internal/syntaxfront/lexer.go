package syntaxfront

import "unicode"

type Span struct{ Start, End, Line, Column int }
type Token struct {
	Kind  string
	Bytes []byte
	Span  Span
}

var keywords = map[string]string{
	"abstype": "kw_abstype", "div": "kw_div", "if": "kw_if",
	"mod": "kw_mod", "otherwise": "kw_otherwise", "readvals": "kw_readvals",
	"show": "kw_show", "type": "kw_type", "where": "kw_where", "with": "kw_with",
}

var operators = []struct{ text, kind string }{
	{"::=", "type_def"}, {"***", "typevar"}, {"$$", "dollars"},
	{"$:-", "stdin_binary"}, {"$-", "stdin_text"}, {"$+", "stdin_values"}, {"$*", "arguments"},
	{"->", "arrow"}, {"<-", "left_arrow"}, {"::", "type_annotation"},
	{"++", "append"}, {"--", "difference"}, {"..", "range"},
	{"~=", "not_equal"}, {"<=", "less_equal"}, {">=", "greater_equal"},
	{"//", "diagonal"}, {"\\/", "or"}, {"/\\", "and"}, {"**", "typevar"},
}

func Lex(source Source) []Token {
	var out []Token
	b := source.Bytes
	for i := 0; i < len(b); {
		if i == 0 && len(b) >= 2 && b[0] == '#' && b[1] == '!' {
			for i < len(b) && b[i] != '\n' {
				i++
			}
			continue
		}
		if unicode.IsSpace(rune(b[i])) {
			i++
			continue
		}
		if i+1 < len(b) && b[i] == '|' && b[i+1] == '|' {
			for i < len(b) && b[i] != '\n' {
				i++
			}
			continue
		}
		start := i
		position := source.Position(i)
		kind := "error"
		switch c := b[i]; {
		case c == '%':
			for i < len(b) && b[i] != '\n' {
				i++
			}
			kind = "directive"
		case isLetter(c) || c == '_':
			i++
			for i < len(b) && (isLetter(b[i]) || isDigit(b[i]) || b[i] == '_' || b[i] == '\'') {
				i++
			}
			text := string(b[start:i])
			kind = keywords[text]
			if kind == "" {
				if c >= 'A' && c <= 'Z' {
					kind = "cname"
				} else {
					kind = "name"
				}
			}
		case isDigit(c) || c == '.' && i+1 < len(b) && isDigit(b[i+1]):
			kind, i = scanNumber(b, i)
		case c == '"':
			i, kind = scanQuoted(b, i, '"', "const_str")
		case c == '\'':
			i, kind = scanQuoted(b, i, '\'', "const_char")
		case c == '$' && i+1 < len(b) && isLetter(b[i+1]):
			i += 2
			for i < len(b) && (isLetter(b[i]) || isDigit(b[i]) || b[i] == '_' || b[i] == '\'') {
				i++
			}
			kind = "custom_infix"
		default:
			matched := false
			for _, operator := range operators {
				if len(b)-i >= len(operator.text) && string(b[i:i+len(operator.text)]) == operator.text {
					i += len(operator.text)
					kind = operator.kind
					matched = true
					break
				}
			}
			if !matched {
				i++
				kind = map[byte]string{
					'=': "eq", '+': "plus", '-': "minus", '*': "star", '/': "slash",
					':': "cons", '[': "lbracket", ']': "rbracket", ',': "comma",
					';': "semicolon", '(': "lparen", ')': "rparen", '{': "lbrace", '}': "rbrace",
					'|': "bar", '<': "less", '>': "greater", '~': "not", '#': "length",
					'&': "ampersand", '^': "power", '!': "subscript", '.': "dot", '$': "dollar",
				}[c]
				if kind == "" {
					kind = "error"
				}
			}
		}
		out = append(out, Token{kind, append([]byte(nil), b[start:i]...), Span{start, i, position.Line, position.Column}})
	}
	position := source.Position(len(b))
	out = append(out, Token{"eof", []byte{}, Span{len(b), len(b), position.Line, position.Column}})
	return out
}

func scanQuoted(input []byte, start int, quote byte, kind string) (int, string) {
	i := start + 1
	for i < len(input) && input[i] != quote {
		if input[i] == '\n' {
			return i, "error"
		}
		if input[i] == '\\' && i+1 < len(input) {
			if input[i+1] == '\n' && quote != '"' {
				return i + 1, "error"
			}
			i += 2
		} else {
			i++
		}
	}
	if i >= len(input) || input[i] != quote {
		return i, "error"
	}
	return i + 1, kind
}

func scanNumber(input []byte, start int) (string, int) {
	i, kind := start, "const_int"
	if input[i] == '.' {
		kind = "const_float"
		i++
	}
	if i+1 < len(input) && input[i] == '0' && (input[i+1] == 'x' || input[i+1] == 'X') {
		i += 2
		for i < len(input) && (isDigit(input[i]) || input[i] >= 'a' && input[i] <= 'f' || input[i] >= 'A' && input[i] <= 'F') {
			i++
		}
		if i < len(input) && input[i] == '.' && !(i+1 < len(input) && input[i+1] == '.') {
			kind = "const_float"
			i++
			for i < len(input) && (isDigit(input[i]) || input[i] >= 'a' && input[i] <= 'f' || input[i] >= 'A' && input[i] <= 'F') {
				i++
			}
		}
		if i < len(input) && (input[i] == 'p' || input[i] == 'P') {
			kind = "const_float"
			i++
			if i < len(input) && (input[i] == '+' || input[i] == '-') {
				i++
			}
			for i < len(input) && isDigit(input[i]) {
				i++
			}
		}
		return kind, i
	}
	if i+1 < len(input) && input[i] == '0' && (input[i+1] == 'o' || input[i+1] == 'O') {
		i += 2
		for i < len(input) && input[i] >= '0' && input[i] <= '7' {
			i++
		}
		return kind, i
	}
	for i < len(input) && isDigit(input[i]) {
		i++
	}
	if i < len(input) && input[i] == '.' && !(i+1 < len(input) && input[i+1] == '.') {
		kind = "const_float"
		i++
		for i < len(input) && isDigit(input[i]) {
			i++
		}
	}
	if i < len(input) && (input[i] == 'e' || input[i] == 'E') {
		kind = "const_float"
		i++
		if i < len(input) && (input[i] == '+' || input[i] == '-') {
			i++
		}
		for i < len(input) && isDigit(input[i]) {
			i++
		}
	}
	return kind, i
}

func isLetter(b byte) bool { return b >= 'a' && b <= 'z' || b >= 'A' && b <= 'Z' }
func isDigit(b byte) bool  { return b >= '0' && b <= '9' }
