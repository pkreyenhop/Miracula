package syntaxfront

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestRepositoryMirandaCorpusProducesSyntaxTrees(t *testing.T) {
	_, file, _, _ := runtime.Caller(0)
	root := filepath.Clean(filepath.Join(filepath.Dir(file), "../.."))
	for _, directory := range []string{"lib/miralib", "testdata/golden", "testdata/spine"} {
		err := filepath.WalkDir(filepath.Join(root, directory), func(path string, entry os.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if entry.IsDir() || !(strings.HasSuffix(path, ".m") || strings.HasSuffix(path, ".lit.m")) {
				return nil
			}
			raw, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			source := NewSource(raw, strings.HasSuffix(path, ".lit.m"))
			script, diagnostics := Parse(ApplyLayout(Lex(source)))
			if len(diagnostics) != 0 {
				t.Errorf("%s produced %d diagnostics; first: %s", path, len(diagnostics), diagnostics[0].Message)
			}
			if len(script.Items) == 0 && len(strings.TrimSpace(string(source.Bytes))) != 0 && len(diagnostics) == 0 {
				t.Errorf("%s produced neither syntax nor diagnostics", path)
			}
			return nil
		})
		if err != nil {
			t.Fatal(err)
		}
	}
}

func TestParseDefinitionVariants(t *testing.T) {
	result := Run([]byte("id (c:xs) = c:xs\npair = (1,2)\n"))
	if len(result.Diagnostics) != 0 {
		t.Fatal(result.Diagnostics)
	}
	if len(result.Script.Items) != 2 {
		t.Fatalf("got %d definitions", len(result.Script.Items))
	}
	if result.Script.Items[0].RHS.Variant != "infix" || result.Script.Items[1].RHS.Variant != "tuple" {
		t.Fatalf("unexpected AST: %+v", result.Script)
	}
}

func TestInvalidTokenProducesDiagnostic(t *testing.T) {
	result := Run([]byte{0xff, 'x', '=', '1'})
	if len(result.Diagnostics) == 0 {
		t.Fatal("invalid byte accepted")
	}
}
