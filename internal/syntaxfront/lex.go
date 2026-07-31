package syntaxfront

func Tokenize(input []byte) []Token { return Lex(NewSource(input, false)) }
