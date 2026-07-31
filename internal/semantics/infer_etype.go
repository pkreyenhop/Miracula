package semantics

func ExpressionType(name string) (*Type, error) { _, t := InferIdentity(name); return t, nil }
