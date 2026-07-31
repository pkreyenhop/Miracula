package protocol

import (
	"encoding/binary"
	"errors"
	"math"
)

const (
	XVersion      uint8 = 83
	XWordBits     uint8 = 64
	XWordBytes          = 8
	DefinitionEnd uint8 = 202
	IntegerEnd    int32 = -1
)

var (
	ErrTruncated         = errors.New("truncated input")
	ErrWrongVersion      = errors.New("wrong version")
	ErrWrongWordSize     = errors.New("wrong word size")
	ErrInvalidTag        = errors.New("invalid tag")
	ErrMissingTerminator = errors.New("missing terminator")
	ErrTrailingBytes     = errors.New("trailing bytes")
)

type Tag uint8

const (
	TagChar Tag = 191 + iota
	TagShort
	TagInteger
	TagDouble
	TagIdentifier
	TagAlias
	TagHere
	TagConstructor
	TagReadValues
	TagPattern
	TagWidePattern
	TagDefinition
	TagApplication
	TagCons
	TagTypeVariable
	TagUnicode
)

func DecodeTag(b byte) (Tag, error) {
	if b < byte(TagChar) || b > byte(TagUnicode) {
		return 0, ErrInvalidTag
	}
	return Tag(b), nil
}

type Header struct{}

func (Header) Encode(out []byte) error {
	if len(out) < 2 {
		return ErrTruncated
	}
	out[0], out[1] = XWordBits, XVersion
	return nil
}
func (Header) Decode(in []byte) error {
	if len(in) < 2 {
		return ErrTruncated
	}
	if in[0] != XWordBits {
		return ErrWrongWordSize
	}
	if in[1] != XVersion {
		return ErrWrongVersion
	}
	return nil
}

type Reader struct {
	bytes []byte
	pos   int
}

func NewReader(b []byte) *Reader { return &Reader{bytes: b} }
func (r *Reader) Remaining() int { return len(r.bytes) - r.pos }
func (r *Reader) Finish() error {
	if r.Remaining() != 0 {
		return ErrTrailingBytes
	}
	return nil
}
func (r *Reader) take(n int) ([]byte, error) {
	if n < 0 || n > r.Remaining() {
		return nil, ErrTruncated
	}
	b := r.bytes[r.pos : r.pos+n]
	r.pos += n
	return b, nil
}
func (r *Reader) ReadByte() (byte, error) {
	b, e := r.take(1)
	if e != nil {
		return 0, e
	}
	return b[0], nil
}
func (r *Reader) ReadU16() (uint16, error) {
	b, e := r.take(2)
	if e != nil {
		return 0, e
	}
	return binary.LittleEndian.Uint16(b), nil
}
func (r *Reader) ReadI32() (int32, error) {
	b, e := r.take(4)
	if e != nil {
		return 0, e
	}
	return int32(binary.LittleEndian.Uint32(b)), nil
}
func (r *Reader) ReadWord() (int64, error) {
	b, e := r.take(8)
	if e != nil {
		return 0, e
	}
	return int64(binary.LittleEndian.Uint64(b)), nil
}
func (r *Reader) ReadDouble() (float64, error) {
	v, e := r.ReadWord()
	if e != nil {
		return 0, e
	}
	return math.Float64frombits(uint64(v)), nil
}
func (r *Reader) ReadZ() ([]byte, error) {
	start := r.pos
	for r.pos < len(r.bytes) {
		if r.bytes[r.pos] == 0 {
			v := r.bytes[start:r.pos]
			r.pos++
			return v, nil
		}
		r.pos++
	}
	return nil, ErrMissingTerminator
}

type Writer struct {
	bytes []byte
	pos   int
}

func NewWriter(b []byte) *Writer  { return &Writer{bytes: b} }
func (w *Writer) Written() []byte { return w.bytes[:w.pos] }
func (w *Writer) take(n int) ([]byte, error) {
	if n < 0 || n > len(w.bytes)-w.pos {
		return nil, ErrTruncated
	}
	b := w.bytes[w.pos : w.pos+n]
	w.pos += n
	return b, nil
}
func (w *Writer) WriteByte(v byte) error {
	b, e := w.take(1)
	if e == nil {
		b[0] = v
	}
	return e
}
func (w *Writer) WriteU16(v uint16) error {
	b, e := w.take(2)
	if e == nil {
		binary.LittleEndian.PutUint16(b, v)
	}
	return e
}
func (w *Writer) WriteI32(v int32) error {
	b, e := w.take(4)
	if e == nil {
		binary.LittleEndian.PutUint32(b, uint32(v))
	}
	return e
}
func (w *Writer) WriteWord(v int64) error {
	b, e := w.take(8)
	if e == nil {
		binary.LittleEndian.PutUint64(b, uint64(v))
	}
	return e
}
func (w *Writer) WriteDouble(v float64) error { return w.WriteWord(int64(math.Float64bits(v))) }
func (w *Writer) WriteZ(v []byte) error {
	b, e := w.take(len(v) + 1)
	if e != nil {
		return e
	}
	copy(b, v)
	b[len(v)] = 0
	return nil
}

type Record struct {
	Variant string
	Value   any
}
type Reconstructor interface{ Apply(Record) error }
