package syntaxfront

type PipelineResult struct {
	Source      Source
	Tokens      []Token
	Script      Script
	Diagnostics []Diagnostic
}

func Run(input []byte) PipelineResult {
	s := NewSource(input, false)
	tokens := ApplyLayout(Lex(s))
	script, d := Parse(tokens)
	return PipelineResult{s, tokens, script, d}
}
