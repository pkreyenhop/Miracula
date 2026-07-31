package syntaxfront

import "sort"

type Position struct{ Line, Column int }
type Source struct {
	Bytes      []byte
	LineStarts []int
	Literate   bool
}

func NewSource(raw []byte, literateName bool) Source {
	b := append([]byte(nil), raw...)
	lit := literateName || (len(b) > 0 && b[0] == '>')
	if lit {
		blankProse(b)
	}
	starts := []int{0}
	for i, v := range b {
		if v == '\n' {
			starts = append(starts, i+1)
		}
	}
	return Source{b, starts, lit}
}
func blankProse(b []byte) {
	for start := 0; start < len(b); {
		end := start
		for end < len(b) && b[end] != '\n' {
			end++
		}
		if b[start] == '>' {
			b[start] = ' '
		} else {
			for i := start; i < end; i++ {
				b[i] = ' '
			}
		}
		start = end + 1
	}
}
func (s Source) Position(offset int) Position {
	if offset < 0 {
		offset = 0
	}
	if offset > len(s.Bytes) {
		offset = len(s.Bytes)
	}
	line := sort.Search(len(s.LineStarts), func(i int) bool { return s.LineStarts[i] > offset })
	if line == 0 {
		line = 1
	}
	start := s.LineStarts[line-1]
	column := 1
	for _, b := range s.Bytes[start:offset] {
		if b == '\t' {
			column = ((column-1)/8+1)*8 + 1
		} else {
			column++
		}
	}
	return Position{line, column}
}
