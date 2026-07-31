package devtools

import (
	"strings"
	"unicode"
)

func Justify(input string, width, tolerance int) string {
	if width == 0 {
		width = 2400
	}
	var out strings.Builder
	var paragraph []string
	flush := func() {
		if len(paragraph) == 0 {
			return
		}
		words := strings.Fields(strings.Join(paragraph, " "))
		for len(words) > 0 {
			n, size := 0, 0
			for n < len(words) {
				next := size + len(words[n])
				if n > 0 {
					next++
				}
				if n > 0 && next > width {
					break
				}
				size = next
				n++
			}
			out.WriteString(strings.Join(words[:n], " "))
			out.WriteByte('\n')
			words = words[n:]
		}
		paragraph = nil
	}
	for _, line := range strings.Split(strings.TrimSuffix(input, "\n"), "\n") {
		if line == "" || strings.HasPrefix(line, ">") || indent(line) > 7 {
			flush()
			out.WriteString(line)
			out.WriteByte('\n')
		} else {
			paragraph = append(paragraph, strings.Join(strings.FieldsFunc(line, unicode.IsSpace), " "))
		}
	}
	flush()
	return out.String()
}
func indent(s string) int {
	n := 0
	for _, r := range s {
		if r == ' ' {
			n++
		} else if r == '\t' {
			n = 8 * (1 + n/8)
		} else {
			break
		}
	}
	return n
}
