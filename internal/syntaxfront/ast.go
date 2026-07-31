package syntaxfront

type Expr struct {
	Variant string `json:"variant"`
	Text    string `json:"text,omitempty"`
	Func    *Expr  `json:"func,omitempty"`
	Arg     *Expr  `json:"arg,omitempty"`
	Head    *Expr  `json:"head,omitempty"`
	Tail    *Expr  `json:"tail,omitempty"`
	Items   []Expr `json:"items,omitempty"`
}
type Definition struct {
	Variant string `json:"variant"`
	LHS     Expr   `json:"lhs"`
	RHS     Expr   `json:"rhs"`
}
type Script struct {
	Variant string       `json:"variant"`
	Items   []Definition `json:"items"`
}
