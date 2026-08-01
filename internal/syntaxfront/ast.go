package syntaxfront

type Expr struct {
	Variant    string      `json:"variant"`
	Text       string      `json:"text,omitempty"`
	Func       *Expr       `json:"func,omitempty"`
	Arg        *Expr       `json:"arg,omitempty"`
	Head       *Expr       `json:"head,omitempty"`
	Tail       *Expr       `json:"tail,omitempty"`
	Step       *Expr       `json:"step,omitempty"`
	To         *Expr       `json:"to,omitempty"`
	Body       *Expr       `json:"body,omitempty"`
	Qualifiers []Qualifier `json:"qualifiers,omitempty"`
	Items      []Expr      `json:"items,omitempty"`
	Span       Span        `json:"span,omitempty"`
}
type Qualifier struct {
	Pattern    *Expr `json:"pattern,omitempty"`
	Source     *Expr `json:"source,omitempty"`
	Recurrence *Expr `json:"recurrence,omitempty"`
	Guard      *Expr `json:"guard,omitempty"`
}
type Definition struct {
	Variant string `json:"variant"`
	LHS     Expr   `json:"lhs"`
	RHS     Expr   `json:"rhs"`
	Text    string `json:"text,omitempty"`
	Span    Span   `json:"span,omitempty"`
}
type Script struct {
	Variant string       `json:"variant"`
	Items   []Definition `json:"items"`
}
