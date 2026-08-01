package application

import (
	"bytes"
	"errors"
	"io"
	"testing"
)

func TestLineEditorNavigationAndEditing(t *testing.T) {
	input := bytes.NewBuffer([]byte{'a', 'b', 27, '[', 'D', 'X', 1, 'Y', 5, 127, 11, '\n'})
	var output bytes.Buffer
	editor, err := NewLineEditor(input, &output)
	if err != nil {
		t.Fatal(err)
	}
	defer editor.Close()
	line, err := editor.ReadLine("Miranda ")
	if err != nil {
		t.Fatal(err)
	}
	if line != "YaX" {
		t.Fatalf("edited line = %q", line)
	}
}

func TestLineEditorDeleteHomeAndEnd(t *testing.T) {
	input := bytes.NewBuffer([]byte{'a', 'c', 27, '[', 'H', 27, '[', 'C', 'b', 27, '[', 'F', 27, '[', 'D', 27, '[', '3', '~', '\n'})
	editor, err := NewLineEditor(input, io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	defer editor.Close()
	line, err := editor.ReadLine("")
	if err != nil || line != "ab" {
		t.Fatalf("line = %q, err = %v", line, err)
	}
}

func TestLineEditorControlDOnEmptyLineIsEOF(t *testing.T) {
	editor, err := NewLineEditor(bytes.NewReader([]byte{4}), io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	defer editor.Close()
	_, err = editor.ReadLine("")
	if !errors.Is(err, io.EOF) {
		t.Fatalf("Ctrl-D error = %v", err)
	}
}
