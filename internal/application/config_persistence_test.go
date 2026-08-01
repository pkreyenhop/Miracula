package application

import (
	"os"
	"path/filepath"
	"testing"
)

func TestWriteRCLegacyCompatibleEncoding(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".mirarc")
	i := New(nil)
	i.Config.RCPath = path
	i.Config.HeapCells = 3000000
	i.Config.DictionaryCells = 200000
	i.Config.Editor = "vi +!"
	i.Config.List = true
	i.Config.Recheck = true
	if err := i.WriteRC(); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	want := "hdvelr 3000000 200000 2067 vi +!\n"
	if string(data) != want {
		t.Fatalf("rc = %q, want %q", data, want)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("mode = %o", info.Mode().Perm())
	}
}

func TestWriteRCWithoutHomePathIsNoOp(t *testing.T) {
	i := New(nil)
	if err := i.WriteRC(); err != nil {
		t.Fatal(err)
	}
}
