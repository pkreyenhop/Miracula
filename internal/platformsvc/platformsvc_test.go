package platformsvc

import (
	"bufio"
	"bytes"
	"errors"
	"io"
	"math"
	"os"
	"path/filepath"
	"testing"
)

func TestTypedParsing(t *testing.T) {
	if v, e := Integer(" \t-42\n", 64); e != nil || v != -42 {
		t.Fatal(v, e)
	}
	if _, e := Integer("42x", 64); !errors.Is(e, ErrParseInvalid) {
		t.Fatal(e)
	}
	if v, e := IntegerAuto("-0o10", 64); e != nil || v != -8 {
		t.Fatal(v, e)
	}
	if _, e := Integer("9223372036854775808", 64); !errors.Is(e, ErrParseOverflow) {
		t.Fatal(e)
	}
	if v, e := Float(" -1.25e+2"); e != nil || v != -125 {
		t.Fatal(v, e)
	}
	r := bufio.NewReader(bytes.NewBufferString("  a 12345"))
	if v, e := ReadToken(r, 4); e != nil || v != "a" {
		t.Fatal(v, e)
	}
	if _, e := ReadToken(r, 4); !errors.Is(e, ErrTokenTooLong) {
		t.Fatal(e)
	}
}

type byteWriter struct{ bytes.Buffer }

func (w *byteWriter) WriteByte(b byte) error { return w.Buffer.WriteByte(b) }
func TestUTF8(t *testing.T) {
	for _, r := range []rune{'a', 'λ', '界', '😀'} {
		input := bufio.NewReader(bytes.NewBufferString(string(r)))
		got, e := FromUTF8(input)
		if e != nil || rune(got) != r {
			t.Fatal(got, e)
		}
		var out byteWriter
		if e = OutUTF8(&out, uint64(r)); e != nil || out.String() != string(r) {
			t.Fatal(out.String(), e)
		}
	}
	if _, e := FromUTF8(bufio.NewReader(bytes.NewReader([]byte{0xff}))); !errors.Is(e, ErrInvalidUTF8) {
		t.Fatal(e)
	}
	if e := OutUTF8(&byteWriter{}, math.MaxUint64); !errors.Is(e, ErrInvalidUTF8) {
		t.Fatal(e)
	}
}

func TestFilesAndShell(t *testing.T) {
	d := t.TempDir()
	from := filepath.Join(d, "a.m")
	to := filepath.Join(d, "a.x")
	if e := os.WriteFile(from, []byte("abc"), 0644); e != nil {
		t.Fatal(e)
	}
	if !IsMirandaSource(from) || !FileExists(from) {
		t.Fatal("source not recognized")
	}
	if e := CopyFile(from, to); e != nil {
		t.Fatal(e)
	}
	b, e := os.ReadFile(to)
	if e != nil || string(b) != "abc" {
		t.Fatal(string(b), e)
	}
	var out bytes.Buffer
	if e = FileCopy(from, &out); e != nil || out.String() != "abc" {
		t.Fatal(out.String(), e)
	}
	o, e := RunShell(t.Context(), ShellFallbackPath, "exit 7")
	if e != nil || o.ExitCode == nil || *o.ExitCode != 7 {
		t.Fatal(o, e)
	}
	if _, e = RunShell(t.Context(), "/definitely/not/a/shell", "true"); !errors.Is(e, ErrSpawnFailed) {
		t.Fatal(e)
	}
}

var _ io.ByteWriter = (*byteWriter)(nil)
