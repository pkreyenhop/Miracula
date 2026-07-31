package platformsvc

import (
	"bufio"
	"errors"
	"io"
	"strconv"
	"strings"
)

var (
	ErrParseEmpty    = errors.New("empty")
	ErrParseInvalid  = errors.New("invalid")
	ErrParseOverflow = errors.New("overflow")
	ErrTokenTooLong  = errors.New("token too long")
)

type IntegerResult struct {
	Value    int64
	Consumed int
}

func IntegerPrefix(input string, bitSize int) (IntegerResult, error) {
	i := 0
	for i < len(input) && isSpace(input[i]) {
		i++
	}
	start := i
	if i < len(input) && (input[i] == '+' || input[i] == '-') {
		i++
	}
	digits := i
	for i < len(input) && input[i] >= '0' && input[i] <= '9' {
		i++
	}
	if i == digits {
		if start == len(input) {
			return IntegerResult{}, ErrParseEmpty
		}
		return IntegerResult{}, ErrParseInvalid
	}
	v, e := strconv.ParseInt(input[start:i], 10, bitSize)
	if e != nil {
		return IntegerResult{}, parseNumError(e)
	}
	return IntegerResult{v, i}, nil
}
func Integer(input string, bitSize int) (int64, error) {
	p, e := IntegerPrefix(input, bitSize)
	if e != nil {
		return 0, e
	}
	if strings.TrimSpace(input[p.Consumed:]) != "" {
		return 0, ErrParseInvalid
	}
	return p.Value, nil
}
func IntegerAuto(input string, bitSize int) (int64, error) {
	s := strings.TrimSpace(input)
	if s == "" {
		return 0, ErrParseEmpty
	}
	v, e := strconv.ParseInt(s, 0, bitSize)
	if e != nil {
		return 0, parseNumError(e)
	}
	return v, nil
}
func Float(input string) (float64, error) {
	if input == "" || strings.TrimLeft(input, " \t\r\n") == "" {
		return 0, ErrParseEmpty
	}
	if input != strings.TrimRight(input, " \t\r\n") {
		return 0, ErrParseInvalid
	}
	v, e := strconv.ParseFloat(strings.TrimLeft(input, " \t\r\n"), 64)
	if e != nil {
		return 0, parseNumError(e)
	}
	return v, nil
}
func ReadToken(r *bufio.Reader, max int) (string, error) {
	for {
		b, e := r.ReadByte()
		if e == io.EOF {
			return "", io.EOF
		}
		if e != nil {
			return "", ErrParseInvalid
		}
		if !isSpace(b) {
			buf := []byte{b}
			for {
				b, e = r.ReadByte()
				if e == io.EOF {
					return string(buf), nil
				}
				if e != nil {
					return "", ErrParseInvalid
				}
				if isSpace(b) {
					return string(buf), nil
				}
				if len(buf) == max {
					return "", ErrTokenTooLong
				}
				buf = append(buf, b)
			}
		}
	}
}
func parseNumError(e error) error {
	var n *strconv.NumError
	if errors.As(e, &n) && errors.Is(n.Err, strconv.ErrRange) {
		return ErrParseOverflow
	}
	return ErrParseInvalid
}
func isSpace(b byte) bool {
	return b == ' ' || b == '\t' || b == '\n' || b == '\r' || b == '\v' || b == '\f'
}
