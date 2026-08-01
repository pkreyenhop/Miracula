package application

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/pkreyenhop/miracula/internal/platformsvc"
)

func TestParseCommandExpressionFacilities(t *testing.T) {
	typeQuery, err := parseCommandExpression("map (+1) ::")
	if err != nil || !typeQuery.TypeQuery || typeQuery.Expression != "map (+1)" {
		t.Fatalf("type query = %+v, %v", typeQuery, err)
	}
	redirect, err := parseCommandExpression(`sum [1..10] &>> "out file" errors`)
	if err != nil || !redirect.Background || !redirect.Append || redirect.Expression != "sum [1..10]" || len(redirect.Paths) != 2 || redirect.Paths[0] != "out file" {
		t.Fatalf("redirection = %+v, %v", redirect, err)
	}
	quoted, err := parseCommandExpression(`"a &> b" ::`)
	if err != nil || !quoted.TypeQuery || quoted.Expression != `"a &> b"` {
		t.Fatalf("quoted expression = %+v, %v", quoted, err)
	}
}

func TestLastExpressionAndExpressionTypeQuery(t *testing.T) {
	i := New(platformsvc.NativeServices{})
	if got, err := i.Evaluate(context.Background(), "40+2"); err != nil || got != "42" {
		t.Fatalf("first result = %q, %v", got, err)
	}
	if got, err := i.Evaluate(context.Background(), "$$+1"); err != nil || got != "43" {
		t.Fatalf("last expression result = %q, %v", got, err)
	}
	if got, err := i.expressionType("$$"); err != nil || got != "num" {
		t.Fatalf("last expression type = %q, %v", got, err)
	}
	if got, err := i.expressionType("map (+1)"); err != nil || got != "[num]->[num]" {
		t.Fatalf("map type = %q, %v", got, err)
	}
}

func TestCurrentScriptExpansionAndEscapedPercent(t *testing.T) {
	i := New(nil)
	i.Compiler.CurrentModule = "/tmp/script.m"
	if got, want := i.expandCurrentScript(`cat % \% x\y`), `cat /tmp/script.m % x\y`; got != want {
		t.Fatalf("expanded command = %q, want %q", got, want)
	}
	if got := i.shellCommand("!cat %"); got != "cat /tmp/script.m" {
		t.Fatalf("shell command = %q", got)
	}
	if got := i.shellCommand("!!"); got != "cat /tmp/script.m" {
		t.Fatalf("repeated shell command = %q", got)
	}
}

func TestBackgroundRedirectionOverwriteAppendErrorsAndClosedInput(t *testing.T) {
	i := New(platformsvc.NativeServices{})
	i.Input = strings.NewReader("must not be read")
	directory := t.TempDir()
	output := filepath.Join(directory, "out")
	errors := filepath.Join(directory, "errors")
	for _, command := range []commandExpression{
		{Expression: "1+1", Background: true, Paths: []string{output, errors}},
		{Expression: "2+2", Background: true, Append: true, Paths: []string{output, errors}},
		{Expression: "$-", Background: true, Append: true, Paths: []string{output, errors}},
		{Expression: "notDefined", Background: true, Append: true, Paths: []string{output, errors}},
	} {
		if err := i.startBackgroundEvaluation(context.Background(), command); err != nil {
			t.Fatal(err)
		}
		waitForFileText(t, output, func(text string) bool {
			switch command.Expression {
			case "1+1":
				return strings.Contains(text, "2")
			case "2+2":
				return strings.Contains(text, "4")
			case "$-":
				return strings.Count(text, "\n") >= 3
			default:
				return true
			}
		})
	}
	waitForFileText(t, errors, func(text string) bool { return strings.Contains(text, "notDefined") })
	data, err := os.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	if got := string(data); !strings.Contains(got, "2\n") || !strings.Contains(got, "4\n") || strings.Contains(got, "must not be read") {
		t.Fatalf("redirected output = %q", got)
	}
}

func waitForFileText(t *testing.T, path string, ready func(string) bool) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if data, err := os.ReadFile(path); err == nil && ready(string(data)) {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	data, _ := os.ReadFile(path)
	t.Fatalf("timed out waiting for %s: %q", path, data)
}
