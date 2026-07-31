package semantics

func PrimitiveCombinator(name string) (int, bool) {
	codes := map[string]int{"+": 54, "div": 56}
	v, ok := codes[name]
	return v, ok
}
