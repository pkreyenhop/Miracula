package application

import (
	"bytes"
	"errors"
	"io"
	"os"
	"path/filepath"
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

func TestLineEditorPersistsAndRecallsHistory(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".miranda_history")
	first, err := NewLineEditor(bytes.NewBufferString("1+1\n"), io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	if err = first.LoadHistory(path); err != nil {
		t.Fatal(err)
	}
	if line, readErr := first.ReadLine(""); readErr != nil || line != "1+1" {
		t.Fatalf("line = %q, err = %v", line, readErr)
	}
	if err = first.SaveHistory(); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil || string(data) != "1+1\n" {
		t.Fatalf("history = %q, err = %v", data, err)
	}
	second, err := NewLineEditor(bytes.NewReader([]byte{27, '[', 'A', '\n'}), io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	if err = second.LoadHistory(path); err != nil {
		t.Fatal(err)
	}
	line, err := second.ReadLine("")
	if err != nil || line != "1+1" {
		t.Fatalf("recalled line = %q, err = %v", line, err)
	}
}
