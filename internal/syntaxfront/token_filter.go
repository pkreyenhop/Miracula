package syntaxfront

type Diagnostic struct {
	Severity, Message, File string
	Span                    Span
}
type TokenFilter func([]Token) ([]Token, []Diagnostic)
