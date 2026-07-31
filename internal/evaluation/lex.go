package evaluation

func CharacterInClass(r rune, ranges [][2]rune) bool {
	for _, p := range ranges {
		if r >= p[0] && r <= p[1] {
			return true
		}
	}
	return false
}
