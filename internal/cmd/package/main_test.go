package main

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
)

func TestArchiveIsDeterministicAndExcludesGeneratedArtifacts(t *testing.T) {
	root, err := repositoryRoot()
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("SOURCE_DATE_EPOCH", "1700000000")
	first := filepath.Join(t.TempDir(), "first.tar.gz")
	second := filepath.Join(t.TempDir(), "second.tar.gz")
	for _, output := range []string{first, second} {
		if err := archive(root, output); err != nil {
			t.Fatal(err)
		}
	}
	firstBytes, err := os.ReadFile(first)
	if err != nil {
		t.Fatal(err)
	}
	secondBytes, err := os.ReadFile(second)
	if err != nil {
		t.Fatal(err)
	}
	if sha256.Sum256(firstBytes) != sha256.Sum256(secondBytes) {
		t.Fatal("archives built from identical inputs differ")
	}
	file, err := os.Open(first)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	compressed, err := gzip.NewReader(file)
	if err != nil {
		t.Fatal(err)
	}
	defer compressed.Close()
	reader := tar.NewReader(compressed)
	foundBinary, foundLibrary := false, false
	for {
		header, err := reader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		if header.Name == "miracula/bin/mira" {
			foundBinary = true
		}
		if header.Name == "miracula/lib/miralib/prelude" {
			foundLibrary = true
		}
		if strings.HasSuffix(header.Name, ".x") || strings.Contains(header.Name, "__pycache__") {
			t.Fatalf("archive contains generated artifact %q", header.Name)
		}
	}
	if !foundBinary || !foundLibrary {
		t.Fatalf("archive contents: binary=%v library=%v", foundBinary, foundLibrary)
	}
}

func TestFindModuleRootFromNestedDirectory(t *testing.T) {
	root := t.TempDir()
	nested := filepath.Join(root, "internal", "cmd")
	if err := os.MkdirAll(nested, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "go.mod"), []byte("module github.com/pkreyenhop/miracula\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := findModuleRoot(nested)
	if err != nil || got != root {
		t.Fatalf("findModuleRoot() = %q, %v; want %q", got, err, root)
	}
}

func TestCopyTreeExcludesGeneratedArtifacts(t *testing.T) {
	source, target := filepath.Join(t.TempDir(), "source"), filepath.Join(t.TempDir(), "target")
	files := map[string]string{
		"prelude":               "keep",
		"nested/module.m":       "keep",
		"nested/module.x":       "drop",
		"preludx":               "drop",
		".DS_Store":             "drop",
		"__pycache__/cache.pyc": "drop",
	}
	for name, contents := range files {
		path := filepath.Join(source, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(contents), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := copyTree(source, target); err != nil {
		t.Fatal(err)
	}
	var got []string
	if err := filepath.WalkDir(target, func(path string, entry os.DirEntry, err error) error {
		if err == nil && !entry.IsDir() {
			relative, relativeErr := filepath.Rel(target, path)
			if relativeErr != nil {
				return relativeErr
			}
			got = append(got, relative)
		}
		return err
	}); err != nil {
		t.Fatal(err)
	}
	sort.Strings(got)
	want := []string{"nested/module.m", "prelude"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("copied files = %v, want %v", got, want)
	}
}

func TestCleanRemovesOnlyBuildArtifacts(t *testing.T) {
	root := t.TempDir()
	files := []string{"build/mira", "script.x", "lib/miralib/preludx", "keep.m"}
	for _, name := range files {
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte("data"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := clean(root); err != nil {
		t.Fatal(err)
	}
	for _, removed := range []string{"build", "script.x", "lib/miralib/preludx"} {
		if _, err := os.Stat(filepath.Join(root, removed)); !os.IsNotExist(err) {
			t.Errorf("%s was not removed", removed)
		}
	}
	if _, err := os.Stat(filepath.Join(root, "keep.m")); err != nil {
		t.Fatalf("source file removed: %v", err)
	}
}
