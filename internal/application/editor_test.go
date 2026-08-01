package application

import (
	"bytes"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/pkreyenhop/miracula/internal/platformsvc"
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

type editorServices struct {
	request platformsvc.ProcessRequest
}

func (*editorServices) Metadata(string) (platformsvc.FileMetadata, bool) {
	return platformsvc.FileMetadata{ModifiedSeconds: 1}, true
}
func (s *editorServices) Run(request platformsvc.ProcessRequest) (platformsvc.ProcessOutcome, error) {
	s.request = request
	return platformsvc.Exited(0), nil
}
func (*editorServices) Terminal(uint32) platformsvc.TerminalInfo { return platformsvc.TerminalInfo{} }
func (*editorServices) Monotonic() time.Duration                 { return 0 }
func (*editorServices) Environment(string) (string, bool)        { return "", false }
func (*editorServices) FindExecutable(string) (string, bool)     { return "", false }

func TestEditorCommandTemplateSubstitutions(t *testing.T) {
	got := editorCommandTemplate(`vi +! % \! \% \& &`, `/tmp/a b.m`, 12, 3)
	if want := `vi +12 "/tmp/a b.m" ! % & 3`; got != want {
		t.Fatalf("command = %q, want %q", got, want)
	}
	if got = editorCommandTemplate("myed", "foo.m", 1, 1); got != `myed "foo.m"` {
		t.Fatalf("appended command = %q", got)
	}
}

func TestEditorValidityAndWarning(t *testing.T) {
	for editor, bad := range map[string]bool{"vi +!": false, "emacs +%l": false, "ed %d": false, "cat": true} {
		if got := EditorCannotOpenAtLine(editor); got != bad {
			t.Errorf("EditorCannotOpenAtLine(%q) = %v", editor, got)
		}
	}
	i := New(nil)
	i.Config.Editor = "cat"
	var output bytes.Buffer
	if err := i.editorWarning(&output); err != nil {
		t.Fatal(err)
	}
	want := "The currently installed editor command, \"cat\", does not\ninclude a facility for opening a file at a specified line number.  As a\nresult the `??' command and certain other features of the Miranda system\nare disabled.  See manual section 31/5 on changing the editor for more\ninformation.\n"
	if output.String() != want {
		t.Fatalf("warning = %q", output.String())
	}
}

func TestEditCommandRunsConfiguredTemplate(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "sample.m")
	if err := os.WriteFile(path, []byte("answer = 42\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	services := &editorServices{}
	i := New(services)
	i.Config.Editor = "fake-editor +! %"
	i.Repl.Errors = map[string]ErrorLocation{path: {Path: path, Line: 12, Column: 4}}
	if err := i.editCommand([]string{strings.TrimSuffix(path, ".m")}, io.Discard); err != nil {
		t.Fatal(err)
	}
	if services.request.Executable != platformsvc.ShellFallbackPath || len(services.request.Arguments) != 2 {
		t.Fatalf("request = %+v", services.request)
	}
	want := `fake-editor +12 "` + path + `"`
	if services.request.Arguments[1] != want {
		t.Fatalf("shell command = %q, want %q", services.request.Arguments[1], want)
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

func TestLineEditorCompletesIdentifierAtCursor(t *testing.T) {
	input := bytes.NewBufferString("map'\t 1\n")
	editor, err := NewLineEditor(input, io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	editor.SetCompleter(func(prefix string) []string {
		if prefix != "map'" {
			t.Fatalf("prefix = %q", prefix)
		}
		return []string{"map'values"}
	})
	line, err := editor.ReadLine("")
	if err != nil || line != "map'values 1" {
		t.Fatalf("line = %q, err = %v", line, err)
	}
}

func TestLineEditorListsMultipleCompletions(t *testing.T) {
	var output bytes.Buffer
	editor, err := NewLineEditor(bytes.NewBufferString("ma\t\n"), &output)
	if err != nil {
		t.Fatal(err)
	}
	editor.SetCompleter(func(string) []string { return []string{"map", "max"} })
	line, err := editor.ReadLine("Miranda ")
	if err != nil || line != "ma" {
		t.Fatalf("line = %q, err = %v", line, err)
	}
	if !bytes.Contains(output.Bytes(), []byte("map  max")) {
		t.Fatalf("completion output = %q", output.String())
	}
}

func TestLineEditorDoesNotCompleteEmptyOrNonASCIIPrefixes(t *testing.T) {
	for _, input := range []string{"\t\n", "é\t\n"} {
		called := false
		editor, err := NewLineEditor(bytes.NewBufferString(input), io.Discard)
		if err != nil {
			t.Fatal(err)
		}
		editor.SetCompleter(func(string) []string { called = true; return nil })
		if _, err = editor.ReadLine(""); err != nil {
			t.Fatal(err)
		}
		if called {
			t.Fatalf("completer called for %q", input)
		}
	}
}
