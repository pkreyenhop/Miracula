package semantics

func ApplySubstitution(t *Type, s Substitution) *Type { return Resolve(t, s) }
