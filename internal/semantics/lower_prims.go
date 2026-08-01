package semantics

func PrimitiveCombinator(name string) (int, bool) {
	codes := map[string]int{
		"I": 6, "hd": 7, "tl": 8, "+": 54, "-": 53, "*": 55,
		"div": 56, "mod": 58, "#": 64,
	}
	v, ok := codes[name]
	return v, ok
}
