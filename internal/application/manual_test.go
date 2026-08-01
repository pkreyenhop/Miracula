package application

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"testing"
)

type manualEditor struct{ lines []string }

func (e *manualEditor) ReadLine(string) (string, error) {
	if len(e.lines) == 0 {
		return "", io.EOF
	}
	line := e.lines[0]
	e.lines = e.lines[1:]
	return line, nil
}
func (*manualEditor) SetCompleter(func(string) []string) {}
func (*manualEditor) LoadHistory(string) error           { return nil }
func (*manualEditor) SaveHistory() error                 { return nil }
func (*manualEditor) Suspend() error                     { return nil }
func (*manualEditor) Resume() error                      { return nil }
func (*manualEditor) Close() error                       { return nil }

func TestRunManualDisplaysMenuAndSelection(t *testing.T) {
	library := t.TempDir()
	manual := filepath.Join(library, "manual")
	if err := os.Mkdir(manual, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(manual, "contents"), []byte("CONTENTS\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(manual, "1"), []byte("PAGE ONE\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	i := New(nil)
	i.Config.LibraryPath = library
	i.activeEditor = &manualEditor{lines: []string{"1", "q"}}
	var output bytes.Buffer
	if err := i.runManual(&output); err != nil {
		t.Fatal(err)
	}
	if output.String() != "CONTENTS\nPAGE ONE\n" {
		t.Fatalf("manual output = %q", output.String())
	}
}

func TestManualPagePathRejectsTraversal(t *testing.T) {
	if _, ok := manualPagePath("/manual", "../secret"); ok {
		t.Fatal("manual traversal accepted")
	}
}
