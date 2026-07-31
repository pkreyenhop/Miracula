package semantics

func MatchName(pattern, value string, mapTo map[string]string) bool {
	if pattern == "_" {
		return true
	}
	if pattern == value {
		return true
	}
	mapTo[pattern] = value
	return true
}
