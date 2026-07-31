package graphstore

import (
	"fmt"
	"strconv"
	"strings"
)

func CharName(r rune) string {
	switch r {
	case '\n':
		return "\\n"
	case '\t':
		return "\\t"
	case '\r':
		return "\\r"
	case '\\':
		return "\\\\"
	case '\'':
		return "\\'"
	}
	if r < 32 || r == 127 {
		return fmt.Sprintf("\\x%02x", r)
	}
	return string(r)
}
func FormatReal(v float64) string       { return strconv.FormatFloat(v, 'g', -1, 64) }
func FormatList(values []string) string { return "[" + strings.Join(values, ",") + "]" }
