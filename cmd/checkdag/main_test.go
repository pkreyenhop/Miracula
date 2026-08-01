package main

import (
	"os"
	"os/exec"
	"strings"
	"testing"
)

func TestUnsupportedLinuxTargetFailsAtBuildTime(t *testing.T) {
	command := exec.Command("go", "test", "./internal/platformsvc")
	command.Dir = "../.."
	command.Env = append(os.Environ(), "GOOS=linux", "GOARCH=amd64", "CGO_ENABLED=0")
	output, err := command.CombinedOutput()
	if err == nil {
		t.Fatal("unsupported linux/amd64 target compiled")
	}
	if !strings.Contains(string(output), "requires_darwin_arm64") {
		t.Fatalf("unexpected unsupported-target failure: %v\n%s", err, output)
	}
}
