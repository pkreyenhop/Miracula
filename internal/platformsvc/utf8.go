package platformsvc

import (
	"errors"
	"io"
	"unicode/utf8"
)

var ErrInvalidUTF8 = errors.New("invalid UTF-8 sequence")

func FromUTF8(r io.ByteReader) (uint64, error) {
	b0, e := r.ReadByte()
	if e != nil {
		return ^uint64(0), e
	}
	buf := [4]byte{b0}
	n := 1
	switch {
	case b0 < 0x80:
		return uint64(b0), nil
	case b0&0xe0 == 0xc0:
		n = 2
	case b0&0xf0 == 0xe0:
		n = 3
	case b0&0xf8 == 0xf0:
		n = 4
	default:
		return 0, ErrInvalidUTF8
	}
	for i := 1; i < n; i++ {
		buf[i], e = r.ReadByte()
		if e != nil {
			return 0, ErrInvalidUTF8
		}
	}
	v, size := utf8.DecodeRune(buf[:n])
	if v == utf8.RuneError || size != n {
		return 0, ErrInvalidUTF8
	}
	return uint64(v), nil
}
func OutUTF8(w io.ByteWriter, u uint64) error {
	if u > utf8.MaxRune {
		return ErrInvalidUTF8
	}
	var b [4]byte
	n := utf8.EncodeRune(b[:], rune(u))
	for _, value := range b[:n] {
		if err := w.WriteByte(value); err != nil {
			return err
		}
	}
	return nil
}
