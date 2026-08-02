package application

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"testing"

	"github.com/pkreyenhop/miracula/internal/platformsvc"
)

func TestCheckedInExamples(t *testing.T) {
	root := repositoryRoot(t)
	examples, err := filepath.Glob(filepath.Join(root, "examples", "*.m"))
	if err != nil {
		t.Fatal(err)
	}
	sort.Strings(examples)
	expectations := map[string]map[string]string{
		"basic.m": {
			"add1 2": "3",
			"fib 12": "144",
			"l":      "[1,2,3]",
			"x":      "3",
		},
	}
	var names []string
	for _, path := range examples {
		names = append(names, filepath.Base(path))
	}
	var expectedNames []string
	for name := range expectations {
		expectedNames = append(expectedNames, name)
	}
	sort.Strings(expectedNames)
	if !reflect.DeepEqual(names, expectedNames) {
		t.Fatalf("example expectations need updating: files=%v expectations=%v", names, expectedNames)
	}
	for _, path := range examples {
		name := filepath.Base(path)
		t.Run(name, func(t *testing.T) {
			source, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			copyPath := filepath.Join(t.TempDir(), name)
			if err := os.WriteFile(copyPath, source, 0o600); err != nil {
				t.Fatal(err)
			}
			interpreter := New(platformsvc.NativeServices{})
			interpreter.Config.LibraryPath = filepath.Join(root, "lib", "miralib")
			interpreter.InitialScript = copyPath
			if err := interpreter.Boot(); err != nil {
				t.Fatal(err)
			}
			for expression, want := range expectations[name] {
				got, err := interpreter.Evaluate(context.Background(), expression)
				if err != nil || got != want {
					t.Errorf("%s = %q, %v; want %q", expression, got, err, want)
				}
			}
		})
	}
}
