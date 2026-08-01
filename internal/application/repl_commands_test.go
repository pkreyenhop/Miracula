package application

import (
	"bytes"
	"fmt"
	"path/filepath"
	"strings"
	"testing"
)

func TestExtendedReplSettingsCommands(t *testing.T) {
	i := New(nil)
	var output bytes.Buffer
	commands := []string{"/gc", "/list", "/recheck", "/hush", "/heap 3000000", "/s"}
	for _, command := range commands {
		if quit, err := i.runCommand(command, &output); err != nil || quit {
			t.Fatalf("%s: quit=%v err=%v", command, quit, err)
		}
	}
	if !i.Config.GC || !i.Config.List || !i.Config.Recheck || !i.Config.Hush || i.Config.HeapCells != 3000000 {
		t.Fatalf("config = %+v", i.Config)
	}
	for _, text := range []string{"heaplimit = 3000000 cells", "*\theap 3000000", "*\tlist", "*\trecheck", "\tgc", "\thush"} {
		if !strings.Contains(output.String(), text) {
			t.Errorf("settings output lacks %q:\n%s", text, output.String())
		}
	}
}

func TestUnknownReplCommandUsesLegacyDiagnostic(t *testing.T) {
	i := New(nil)
	_, err := i.runCommand("/wat", &bytes.Buffer{})
	if err == nil || err.Error() != "\aunknown command - type /h for help" {
		t.Fatalf("error = %q", err)
	}
}

func TestHeapCommandRejectsIllegalValue(t *testing.T) {
	i := New(nil)
	_, err := i.runCommand("/heap nope", &bytes.Buffer{})
	if err == nil || err.Error() != "illegal value (heap unchanged)" {
		t.Fatalf("error = %v", err)
	}
}

func TestRecordErrorTracksAndClearsSourceLocation(t *testing.T) {
	i := New(nil)
	path := filepath.Join(t.TempDir(), "broken.m")
	i.recordError(path, fmt.Errorf("%s:7:13: type error", path))
	absolute, _ := filepath.Abs(path)
	if got := i.Repl.Errors[absolute]; got.Line != 7 || got.Column != 13 {
		t.Fatalf("location = %+v", got)
	}
	i.recordLoadResult(path, nil)
	if _, ok := i.Repl.Errors[absolute]; ok {
		t.Fatal("successful load did not clear error")
	}
}
