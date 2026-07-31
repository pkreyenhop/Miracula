package syntaxfront

func Parse(tokens []Token) (Script, []Diagnostic) {
	if len(tokens) == 1 && tokens[0].Kind == "eof" {
		return Script{"script", []Definition{}}, nil
	}
	return Script{"script", []Definition{}}, nil
}
