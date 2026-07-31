package main

import (
	"errors"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestUnavailableStageFailsClosed(t *testing.T) {
	binary := filepath.Join(t.TempDir(), "miracula-go-oracle")
	build := exec.Command("go", "build", "-o", binary, ".")
	if output, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build oracle: %v\n%s", err, output)
	}
	command := exec.Command(binary, "--stage", "dump", "--cases", "../../tests/oracle/fixtures/cases.json")
	stdout, err := command.Output()
	if err == nil {
		t.Fatal("unavailable stage unexpectedly succeeded")
	}
	if len(stdout) != 0 {
		t.Fatalf("unavailable stage emitted stdout: %q", stdout)
	}
	var exitError *exec.ExitError
	if !errors.As(err, &exitError) || exitError.ExitCode() != 3 {
		t.Fatalf("unavailable stage exit = %v, want 3", err)
	}
	if got := string(exitError.Stderr); got != "miracula-go-oracle: stage \"dump\" is not implemented\n" {
		t.Fatalf("unexpected diagnostic: %q", got)
	}
}
