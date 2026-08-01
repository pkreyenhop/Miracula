package commandapp

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/pkreyenhop/miracula/internal/application"
	"github.com/pkreyenhop/miracula/internal/platformsvc"
)

func TestSpecialCommandModesDoNotEnterREPL(t *testing.T) {
	directory := t.TempDir()
	dependency := filepath.Join(directory, "dep.m")
	root := filepath.Join(directory, "root.m")
	if err := os.WriteFile(dependency, []byte("dep = 1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(root, []byte("%export + -hidden\n%include \"dep\"\npublic = dep+1\nhidden = 9\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	run := func(arguments ...string) (string, error) {
		var output, stderr bytes.Buffer
		command := Command{Stdin: strings.NewReader(""), Stdout: &output, Stderr: &stderr, Services: platformsvc.NativeServices{}}
		err := command.Run(context.Background(), append([]string{"-lib", filepath.Join(repositoryRoot(t), "lib/miralib")}, arguments...))
		return output.String(), err
	}
	if output, err := run("-make", root, dependency); err != nil || output != "" {
		t.Fatalf("make output=%q err=%v", output, err)
	}
	if _, err := os.Stat(strings.TrimSuffix(root, ".m") + ".x"); err != nil {
		t.Fatal(err)
	}
	if output, err := run("-exports", root); err != nil || !strings.Contains(output, "public :: num") || strings.Contains(output, "hidden") {
		t.Fatalf("exports output=%q err=%v", output, err)
	}
	if output, err := run("-sources", root); err != nil || !strings.Contains(output, root) || !strings.Contains(output, dependency) || strings.Contains(output, "stdenv") {
		t.Fatalf("sources output=%q err=%v", output, err)
	}

	executable := filepath.Join(directory, "exec.m")
	if err := os.WriteFile(executable, []byte("main = [Stdout (show (# $*))]\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	if output, err := run("-exec", executable, "a", "b"); err != nil || output != "3" {
		t.Fatalf("exec output=%q err=%v", output, err)
	}
	exitScript := filepath.Join(directory, "exit.m")
	if err := os.WriteFile(exitScript, []byte("main = [Exit 5]\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	_, err := run("-exec", exitScript)
	var processExit *application.ProcessExitError
	if !errors.As(err, &processExit) || ExitCode(err) != 5 {
		t.Fatalf("exit error=%v code=%d", err, ExitCode(err))
	}
}

func TestExec2LogsRuntimeFailure(t *testing.T) {
	library := filepath.Join(repositoryRoot(t), "lib/miralib")
	directory := t.TempDir()
	t.Chdir(directory)
	if err := os.Mkdir("miralog", 0o700); err != nil {
		t.Fatal(err)
	}
	script := filepath.Join(directory, "broken.m")
	if err := os.WriteFile(script, []byte("main = 1 div 0\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	command := Command{Stdin: strings.NewReader(""), Stdout: &bytes.Buffer{}, Stderr: &bytes.Buffer{}, Services: platformsvc.NativeServices{}}
	if err := command.Run(context.Background(), []string{"-lib", library, "-exec2", script}); err == nil {
		t.Fatal("-exec2 runtime failure succeeded")
	}
	content, err := os.ReadFile(filepath.Join("miralog", "broken"))
	if err != nil || !strings.Contains(string(content), "division by zero") {
		t.Fatalf("log=%q err=%v", content, err)
	}
}

func repositoryRoot(t *testing.T) string {
	working, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	return filepath.Clean(filepath.Join(working, "../.."))
}
