package semantics

import "strings"

// DeclaredTypes extracts top-level Miranda signatures for use as an imported
// type environment. Literate source markers and trailing comments are handled.
func DeclaredTypes(source []byte) map[string]*Type {
	result := map[string]*Type{}
	for _, raw := range strings.Split(string(source), "\n") {
		line := strings.TrimSpace(raw)
		line = strings.TrimSpace(strings.TrimPrefix(line, ">"))
		if comment := strings.Index(line, "||"); comment >= 0 {
			line = strings.TrimSpace(line[:comment])
		}
		separator := strings.Index(line, "::")
		if separator < 0 || strings.Contains(line, "::=") {
			continue
		}
		value, err := ParseType(strings.TrimSpace(line[separator+2:]))
		if err != nil {
			continue
		}
		left := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(line[:separator]), "with "))
		for _, name := range strings.Split(left, ",") {
			name = strings.TrimSpace(name)
			if name != "" {
				result[name] = value
			}
		}
	}
	return result
}
