package graphstore

import (
	"bufio"
	"fmt"
	"io"
)

type Stream struct {
	Reader *bufio.Reader
	Writer io.Writer
	unread *byte
	Closer io.Closer
}

func NewStream(r io.Reader, w io.Writer, c io.Closer) *Stream {
	var reader *bufio.Reader
	if r != nil {
		reader = bufio.NewReader(r)
	}
	return &Stream{Reader: reader, Writer: w, Closer: c}
}
func (s *Stream) ReadByte() (byte, error) {
	if s.unread != nil {
		b := *s.unread
		s.unread = nil
		return b, nil
	}
	if s.Reader == nil {
		return 0, io.EOF
	}
	return s.Reader.ReadByte()
}
func (s *Stream) UnreadByte(b byte) error {
	if s.unread != nil {
		return fmt.Errorf("stream: pushback occupied")
	}
	s.unread = &b
	return nil
}
func (s *Stream) WriteByte(b byte) error {
	if s.Writer == nil {
		return io.ErrClosedPipe
	}
	_, e := s.Writer.Write([]byte{b})
	return e
}
func (s *Stream) WriteAll(b []byte) error {
	if s.Writer == nil {
		return io.ErrClosedPipe
	}
	_, e := s.Writer.Write(b)
	return e
}
func (s *Stream) Printf(format string, args ...any) error {
	if s.Writer == nil {
		return io.ErrClosedPipe
	}
	_, e := fmt.Fprintf(s.Writer, format, args...)
	return e
}
func (s *Stream) Close() error {
	if s.Closer == nil {
		return nil
	}
	return s.Closer.Close()
}
