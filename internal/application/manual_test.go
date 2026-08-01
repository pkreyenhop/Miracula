package application

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

type manualEditor struct {
	lines []string
	keys  []byte
}

func (e *manualEditor) ReadLine(string) (string, error) {
	if len(e.lines) == 0 {
		return "", io.EOF
	}
	line := e.lines[0]
	e.lines = e.lines[1:]
	return line, nil
}
func (e *manualEditor) ReadKey(string) (byte, error) {
	if len(e.keys) == 0 {
		return 0, io.EOF
	}
	key := e.keys[0]
	e.keys = e.keys[1:]
	return key, nil
}
func (e *manualEditor) ReadChoice(prompt string) (string, error) { return e.ReadLine(prompt) }
func (*manualEditor) SetCompleter(func(string) []string)         {}
func (*manualEditor) LoadHistory(string) error                   { return nil }
func (*manualEditor) SaveHistory() error                         { return nil }
func (*manualEditor) Suspend() error                             { return nil }
func (*manualEditor) Resume() error                              { return nil }
func (*manualEditor) Close() error                               { return nil }

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
	if output.String() != "CONTENTS\nPAGE ONE\nCONTENTS\n" {
		t.Fatalf("manual output = %q", output.String())
	}
}

func TestManualPagePathRejectsTraversal(t *testing.T) {
	if _, ok := manualPagePath("/manual", "../secret"); ok {
		t.Fatal("manual traversal accepted")
	}
}

func TestManualPagerPagesScrollsAndSearches(t *testing.T) {
	lines := make([]string, 60)
	for index := range lines {
		lines[index] = fmt.Sprintf("line %02d\n", index+1)
	}
	lines[49] = "SEARCH TARGET\n"
	i := New(nil)
	i.activeEditor = &manualEditor{keys: []byte{'\n', ' ', '/'}, lines: []string{"target"}}
	var output bytes.Buffer
	if err := i.pageManual([]byte(strings.Join(lines, "")), &output); err != nil {
		t.Fatal(err)
	}
	got := output.String()
	for _, want := range []string{"line 01\n", "line 24\n", "SEARCH TARGET\n"} {
		if !strings.Contains(got, want) {
			t.Fatalf("pager output does not contain %q: %q", want, got)
		}
	}
}

func TestManualPagerEscapeLeavesDisplay(t *testing.T) {
	data := []byte(strings.Repeat("line\n", manualPageLines+1))
	i := New(nil)
	i.activeEditor = &manualEditor{keys: []byte{27}}
	var output bytes.Buffer
	if err := i.pageManual(data, &output); err != nil {
		t.Fatal(err)
	}
	if lines := strings.Count(output.String(), "line\n"); lines != manualPageLines {
		t.Fatalf("displayed %d lines after Escape, want %d", lines, manualPageLines)
	}
}

func TestEscapeLeavesManualMenu(t *testing.T) {
	library := t.TempDir()
	manual := filepath.Join(library, "manual")
	if err := os.Mkdir(manual, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(manual, "contents"), []byte("CONTENTS\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	i := New(nil)
	i.Config.LibraryPath = library
	i.activeEditor = &manualEditor{lines: []string{"\x1b"}}
	var output bytes.Buffer
	if err := i.runManual(&output); err != nil {
		t.Fatal(err)
	}
	if output.String() != "CONTENTS\n" {
		t.Fatalf("manual output = %q", output.String())
	}
}

func TestManualMenuSearchesAllChapters(t *testing.T) {
	library := t.TempDir()
	manual := filepath.Join(library, "manual")
	if err := os.Mkdir(manual, 0o700); err != nil {
		t.Fatal(err)
	}
	for name, data := range map[string]string{
		"contents": "CONTENTS\n",
		"1":        "Peter appears here.\nNothing else.\n",
		"2":        "lowercase peter is here too.\n",
		"3":        "No match.\n",
	} {
		if err := os.WriteFile(filepath.Join(manual, name), []byte(data), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	i := New(nil)
	i.Config.LibraryPath = library
	i.activeEditor = &manualEditor{lines: []string{"/peter", "q"}}
	var output bytes.Buffer
	if err := i.runManual(&output); err != nil {
		t.Fatal(err)
	}
	want := "CONTENTS\n1:1: Peter appears here.\n2:1: lowercase peter is here too.\nCONTENTS\n"
	if output.String() != want {
		t.Fatalf("manual output = %q, want %q", output.String(), want)
	}
}

func TestManualTraversesRecursiveMenusAndReturnsThroughParents(t *testing.T) {
	library := t.TempDir()
	manual := filepath.Join(library, "manual")
	if err := os.MkdirAll(filepath.Join(manual, "13"), 0o700); err != nil {
		t.Fatal(err)
	}
	for path, text := range map[string]string{
		filepath.Join(manual, "contents"):       "ROOT\n",
		filepath.Join(manual, "13", "contents"): "SUBMENU 13\n",
		filepath.Join(manual, "13", "2"):        "CHAPTER 13/2\n",
	} {
		if err := os.WriteFile(path, []byte(text), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	i := New(nil)
	i.Config.LibraryPath = library
	i.activeEditor = &manualEditor{lines: []string{"13", "2", "", ""}}
	var output bytes.Buffer
	if err := i.runManual(&output); err != nil {
		t.Fatal(err)
	}
	if got, want := output.String(), "ROOT\nSUBMENU 13\nCHAPTER 13/2\nSUBMENU 13\nROOT\n"; got != want {
		t.Fatalf("recursive manual = %q, want %q", got, want)
	}
}

func TestManualDotNextPreviousAndPagerBackwardSearchHelpAndHeight(t *testing.T) {
	library := t.TempDir()
	manual := filepath.Join(library, "manual")
	if err := os.Mkdir(manual, 0o700); err != nil {
		t.Fatal(err)
	}
	for name, text := range map[string]string{"contents": "MENU\n", "1": "ONE\n", "2": "TWO\n"} {
		if err := os.WriteFile(filepath.Join(manual, name), []byte(text), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	i := New(nil)
	i.Config.LibraryPath = library
	i.activeEditor = &manualEditor{lines: []string{"1", ".", "+", "-", "q"}}
	var output bytes.Buffer
	if err := i.runManual(&output); err != nil {
		t.Fatal(err)
	}
	if strings.Count(output.String(), "ONE\n") != 3 || strings.Count(output.String(), "TWO\n") != 1 {
		t.Fatalf("selection navigation = %q", output.String())
	}

	rows := uint16(6)
	i = New(&editorServices{rows: &rows})
	i.activeEditor = &manualEditor{keys: []byte{' ', '?', 'h', 'q'}, lines: []string{"line 02"}}
	var lines []string
	for index := 1; index <= 14; index++ {
		lines = append(lines, fmt.Sprintf("line %02d\n", index))
	}
	output.Reset()
	if err := i.pageManual([]byte(strings.Join(lines, "")), &output); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(output.String(), "line 02\n") || !strings.Contains(output.String(), "?text backward search") {
		t.Fatalf("pager navigation = %q", output.String())
	}
	if firstPageLines := strings.Index(output.String(), "line 06\n"); firstPageLines >= 0 && firstPageLines < strings.Index(output.String(), "line 05\n") {
		t.Fatalf("terminal height was ignored: %q", output.String())
	}
}

func TestManualShellEscapeAndEffectiveViewerSettings(t *testing.T) {
	library := t.TempDir()
	manual := filepath.Join(library, "manual")
	if err := os.Mkdir(manual, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(manual, "contents"), []byte("MENU\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	services := &editorServices{shell: "/bin/test-shell"}
	i := New(services)
	i.Config.LibraryPath = library
	i.activeEditor = &manualEditor{lines: []string{"???", "!echo hello", "q"}}
	var output bytes.Buffer
	if err := i.runManual(&output); err != nil {
		t.Fatal(err)
	}
	if services.request.Executable != "/bin/test-shell" || !reflect.DeepEqual(services.request.Arguments, []string{"-c", "echo hello"}) {
		t.Fatalf("shell request = %+v", services.request)
	}
	for _, setting := range []string{"VIEWER=internal Go pager", "MENUVIEWER=internal Go pager", "RETURNTOMENU=YES"} {
		if !strings.Contains(output.String(), setting) {
			t.Fatalf("viewer settings = %q", output.String())
		}
	}
}
