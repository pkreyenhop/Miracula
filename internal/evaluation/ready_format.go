package evaluation

import (
	"fmt"
	"strconv"
	"strings"
)

func FormatNumber(v float64) string {
	s := strconv.FormatFloat(v, 'g', -1, 64)
	if !strings.ContainsAny(s, ".eE") {
		s += ".0"
	}
	return s
}
func FormatFixed(v float64, places int) string { return strconv.FormatFloat(v, 'f', places, 64) }
func FormatHex(v float64) string               { return fmt.Sprintf("%x", v) }
