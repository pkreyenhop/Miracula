package main

import (
	"bytes"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestDumpStageAvailableAndUntranslatedStageFailsClosed(t *testing.T) {
	binary := filepath.Join(t.TempDir(), "miracula-go-oracle")
	build := exec.Command("go", "build", "-o", binary, ".")
	if output, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build oracle: %v\n%s", err, output)
	}
	dump := exec.Command(binary, "--stage", "dump", "--cases", "../../tests/oracle/fixtures/cases.json")
	stdout, err := dump.Output()
	if err != nil {
		t.Fatalf("dump stage: %v", err)
	}
	if !bytes.Contains(stdout, []byte(`"case_id":"dump-roundtrip"`)) {
		t.Fatal("dump output missing translated case")
	}

	command := exec.Command(binary, "--stage", "lex", "--cases", "../../tests/oracle/fixtures/cases.json")
	stdout, err = command.Output()
	if err == nil {
		t.Fatal("unavailable stage unexpectedly succeeded")
	}
	if len(stdout) != 0 {
		t.Fatalf("unavailable stage emitted stdout: %q", stdout)
	}
	exitError, ok := err.(*exec.ExitError)
	if !ok || exitError.ExitCode() != 3 {
		t.Fatalf("unavailable stage exit = %v, want 3", err)
	}
	if got := string(exitError.Stderr); got != "miracula-go-oracle: stage \"lex\" is not implemented\n" {
		t.Fatalf("unexpected diagnostic: %q", got)
	}
}
