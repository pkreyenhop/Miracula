package application

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDefaultScriptPrefersHomeThenWorkingDirectory(t *testing.T) {
	home := t.TempDir()
	working := t.TempDir()
	homeScript := filepath.Join(home, "script.m")
	workingScript := filepath.Join(working, "script.m")
	if err := os.WriteFile(homeScript, []byte("home = 1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(workingScript, []byte("working = 1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	i := New(&editorServices{home: home})
	path, err := i.ensureDefaultScript(working)
	if err != nil || path != homeScript {
		t.Fatalf("path = %q, err = %v", path, err)
	}
	if err = os.Remove(homeScript); err != nil {
		t.Fatal(err)
	}
	path, err = i.ensureDefaultScript(working)
	if err != nil || path != workingScript {
		t.Fatalf("fallback path = %q, err = %v", path, err)
	}
}

func TestDefaultScriptIsCreatedEmptyInWorkingDirectory(t *testing.T) {
	home := t.TempDir()
	working := t.TempDir()
	i := New(&editorServices{home: home})
	path, err := i.ensureDefaultScript(working)
	if err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(working, "script.m")
	if path != want {
		t.Fatalf("path = %q, want %q", path, want)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Size() != 0 || info.Mode().Perm() != 0o644 {
		t.Fatalf("default script size=%d mode=%o", info.Size(), info.Mode().Perm())
	}
}
