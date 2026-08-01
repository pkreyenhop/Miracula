package application

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/pkreyenhop/miracula/internal/platformsvc"
	"github.com/pkreyenhop/miracula/internal/syntaxfront"
)

func TestStructuredDiagnosticsPreserveStableSourceMappedTypeErrors(t *testing.T) {
	directory := t.TempDir()
	fragment := filepath.Join(directory, "fragment.m")
	root := filepath.Join(directory, "root.m")
	if err := os.WriteFile(fragment, []byte("f x = reverse x, if x < 1000\ng x = x + True\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(root, []byte("%insert \"fragment.m\"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	i := New(platformsvc.NativeServices{})
	if err := i.Setup(); err != nil {
		t.Fatal(err)
	}
	_, err := i.LoadProgram(root)
	var diagnostics DiagnosticSet
	if !errors.As(err, &diagnostics) || len(diagnostics) != 2 {
		t.Fatalf("diagnostics = %#v, err = %v", diagnostics, err)
	}
	for index, diagnostic := range diagnostics {
		if diagnostic.Severity != "error" || diagnostic.Phase != "type" || diagnostic.File != fragment || diagnostic.Span.Line != index+1 || diagnostic.Definition == "" {
			t.Errorf("diagnostic %d = %+v", index, diagnostic)
		}
	}
	i.recordLoadResult(root, err)
	if location := i.Repl.Errors[fragment]; location.Line != 1 {
		t.Fatalf("first editor location = %+v", location)
	}
}

func TestStructuredCompilerDiagnosticsRetainAllIndependentErrors(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "broken.m")
	if err := os.WriteFile(path, []byte("a = )\nb = ]\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	i := New(platformsvc.NativeServices{})
	if err := i.Setup(); err != nil {
		t.Fatal(err)
	}
	_, err := i.LoadProgram(path)
	var diagnostics DiagnosticSet
	if !errors.As(err, &diagnostics) || len(diagnostics) < 2 {
		t.Fatalf("diagnostics = %#v, err = %v", diagnostics, err)
	}
	for index, diagnostic := range diagnostics {
		if diagnostic.Phase != "syntax" && diagnostic.Phase != "type" || diagnostic.File != path || index > 0 && diagnostics[index-1].Span.Line > diagnostic.Span.Line {
			t.Errorf("diagnostic %d = %+v", index, diagnostic)
		}
	}
}

func TestStructuredDiagnosticOrderingUsesExpandedSourceOrder(t *testing.T) {
	source := syntaxfront.Source{Origins: []syntaxfront.Origin{{File: "z.m", Line: 8}, {File: "a.m", Line: 2}}}
	set := DiagnosticSet{
		sourceDiagnostic("syntax", "root.m", source, syntaxfront.Diagnostic{Severity: "error", Message: "second", Span: syntaxfront.Span{Line: 2}}, 1),
		sourceDiagnostic("syntax", "root.m", source, syntaxfront.Diagnostic{Severity: "error", Message: "first", Span: syntaxfront.Span{Line: 1}}, 0),
	}
	stableDiagnostics(set)
	if set[0].Message != "first" || set[0].File != "z.m" || set[1].Message != "second" {
		t.Fatalf("ordered diagnostics = %+v", set)
	}
}

func TestModuleFailuresAndEditorNavigationUseStructuredDiagnostics(t *testing.T) {
	directory := t.TempDir()
	root := filepath.Join(directory, "root.m")
	if err := os.WriteFile(root, []byte("%include \"missing.m\"\nmain = 1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	i := New(platformsvc.NativeServices{})
	if err := i.Setup(); err != nil {
		t.Fatal(err)
	}
	_, err := i.LoadProgram(root)
	var diagnostics DiagnosticSet
	if !errors.As(err, &diagnostics) || len(diagnostics) != 1 || diagnostics[0].Phase != "module" || diagnostics[0].File != root {
		t.Fatalf("module diagnostics = %+v, %v", diagnostics, err)
	}

	fragment := filepath.Join(directory, "fragment.m")
	if err := os.WriteFile(fragment, []byte("bad = True + 1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	services := &editorServices{}
	i = New(services)
	i.Compiler.CurrentModule = root
	i.Config.Editor = "fake +! %"
	i.activeEditor = &manualEditor{}
	i.Repl.Diagnostics = DiagnosticSet{{Severity: "error", Phase: "type", File: fragment, Span: syntaxfront.Span{Line: 7, Column: 3}, Message: "bad type"}}
	i.Repl.Errors = map[string]ErrorLocation{fragment: {Path: fragment, Line: 7, Column: 3}}
	if err := i.editCommand(nil, &bytes.Buffer{}); err != nil {
		t.Fatal(err)
	}
	if len(services.request.Arguments) != 2 || !strings.Contains(services.request.Arguments[1], fragment) || !strings.Contains(services.request.Arguments[1], "+7") {
		t.Fatalf("editor request = %+v", services.request)
	}
}
