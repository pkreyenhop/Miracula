package semantics

func PrimitiveType(name string) (*Type, bool) {
	if name == "+" {
		n := &Type{Kind: TypeNamed, Name: "num"}
		return &Type{Kind: TypeArrow, From: n, To: &Type{Kind: TypeArrow, From: n, To: n}}, true
	}
	return nil, false
}
