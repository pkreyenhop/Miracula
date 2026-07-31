package semantics

func InferIdentity(name string) (string, *Type) {
	v := &Type{Kind: TypeVariable, ID: 0}
	return name, &Type{Kind: TypeArrow, From: v, To: v}
}
