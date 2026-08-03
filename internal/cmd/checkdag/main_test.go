package main

import (
	"os"
	"os/exec"
	"strings"
	"testing"
)

func TestLinuxTargetCompilesAtBuildTime(t *testing.T) {
	command := exec.Command("go", "build", "./internal/platformsvc")
	command.Dir = "../../.."
	command.Env = append(os.Environ(), "GOOS=linux", "GOARCH=amd64", "CGO_ENABLED=0")
	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("linux/amd64 target failed to compile: %v\n%s", err, output)
	}
}

func TestUnsupportedWindowsTargetFailsAtBuildTime(t *testing.T) {
	command := exec.Command("go", "build", "./internal/platformsvc")
	command.Dir = "../../.."
	command.Env = append(os.Environ(), "GOOS=windows", "GOARCH=amd64", "CGO_ENABLED=0")
	output, err := command.CombinedOutput()
	if err == nil {
		t.Fatal("unsupported windows/amd64 target compiled")
	}
	if !strings.Contains(string(output), "requires_darwin_or_linux") {
		t.Fatalf("unexpected unsupported-target failure: %v\n%s", err, output)
	}
}
