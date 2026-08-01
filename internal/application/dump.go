package application

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"github.com/pkreyenhop/miracula/internal/graphstore"
	"github.com/pkreyenhop/miracula/internal/semantics"
	"github.com/pkreyenhop/miracula/internal/syntaxfront"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
)

func DumpGraph(w io.Writer, g graphstore.DumpGraph) error { return graphstore.EncodeGraph(w, g) }

type CompiledDump struct {
	Version      int                `json:"version"`
	Target       string             `json:"target"`
	SourceSHA256 string             `json:"source_sha256"`
	Source       []byte             `json:"source"`
	Dependencies map[string]string  `json:"dependencies,omitempty"`
	Script       syntaxfront.Script `json:"script"`
	Program      *semantics.Program `json:"program,omitempty"`
	Exports      map[string]string  `json:"exports,omitempty"`
	Diagnostics  []string           `json:"diagnostics,omitempty"`
}

func dependencyHashes(root, libraryPath string) (map[string]string, error) {
	result, visited := map[string]string{}, map[string]bool{}
	var visit func(string) error
	visit = func(path string) error {
		absolute, err := filepath.Abs(path)
		if err != nil {
			return err
		}
		if visited[absolute] {
			return nil
		}
		visited[absolute] = true
		content, err := os.ReadFile(absolute)
		if err != nil {
			return err
		}
		if absolute != root {
			digest := sha256.Sum256(content)
			result[absolute] = hex.EncodeToString(digest[:])
		}
		for _, line := range strings.Split(string(content), "\n") {
			directive, ok := syntaxfront.ParseDirective(strings.TrimSpace(line))
			if !ok || directive.Variant != "include" && directive.Variant != "insert" {
				continue
			}
			child := directive.Path
			if directive.FromMiralib {
				child = filepath.Join(libraryPath, child)
			} else if !filepath.IsAbs(child) {
				child = filepath.Join(filepath.Dir(absolute), child)
			}
			if filepath.Ext(child) == "" {
				child += ".m"
			}
			if err := visit(child); err != nil {
				return err
			}
		}
		return nil
	}
	if err := visit(root); err != nil {
		return nil, err
	}
	return result, nil
}

func RelevantSources(root, libraryPath string) ([]string, error) {
	hashes, err := dependencyHashes(root, libraryPath)
	if err != nil {
		return nil, err
	}
	root, _ = filepath.Abs(root)
	paths := []string{root}
	for path := range hashes {
		if filepath.Base(path) != "stdenv.m" {
			paths = append(paths, path)
		}
	}
	sort.Strings(paths)
	return paths, nil
}

func exportedTypeProfile(script syntaxfront.Script, program *semantics.Program) map[string]string {
	all := map[string]string{}
	if program == nil {
		return all
	}
	for _, definition := range program.Definitions {
		all[definition.Name] = semantics.FormatType(definition.Type)
	}
	for name, value := range program.Specifications {
		all[name] = semantics.FormatType(value)
	}
	profile, explicit, negative := map[string]string{}, false, map[string]bool{}
	for _, item := range script.Items {
		directive, ok := syntaxfront.ParseDirective(item.Text)
		if !ok || directive.Variant != "export" {
			continue
		}
		explicit = true
		for _, part := range strings.Fields(directive.Text) {
			if part == "+" {
				for name, value := range all {
					profile[name] = value
				}
			} else if strings.HasPrefix(part, "-") {
				negative[strings.TrimPrefix(part, "-")] = true
			} else if !strings.HasPrefix(part, "\"") && !strings.HasPrefix(part, "<") {
				if value, ok := all[part]; ok {
					profile[part] = value
				}
			}
		}
	}
	if !explicit {
		profile = all
	}
	for name := range negative {
		delete(profile, name)
	}
	return profile
}

func ExportedTypeProfile(script syntaxfront.Script, program *semantics.Program) map[string]string {
	return exportedTypeProfile(script, program)
}

func ExportedProfileForPath(path string, program *semantics.Program) (map[string]string, error) {
	source, diagnostics := syntaxfront.LoadSource(path)
	if len(diagnostics) != 0 {
		return nil, errors.New(diagnostics[0].Message)
	}
	parsed := syntaxfront.Run(source.Bytes)
	if len(parsed.Diagnostics) != 0 {
		return nil, errors.New(parsed.Diagnostics[0].Message)
	}
	return exportedTypeProfile(parsed.Script, program), nil
}

var ErrStaleDump = errors.New("stale compiled dump")

func WriteCompiledDump(path string, source []byte) error {
	return WriteCompiledArtifact(path, CompiledDump{Source: source})
}

func WriteCompiledArtifact(path string, dump CompiledDump) error {
	source := dump.Source
	digest := sha256.Sum256(source)
	dump.Version, dump.Target, dump.SourceSHA256, dump.Source = Release, runtime.GOOS+"/"+runtime.GOARCH, hex.EncodeToString(digest[:]), append([]byte(nil), source...)
	temporary, err := os.CreateTemp(filepath.Dir(path), ".mira-dump-*")
	if err != nil {
		return err
	}
	name := temporary.Name()
	defer os.Remove(name)
	encoder := json.NewEncoder(temporary)
	if err = encoder.Encode(dump); err != nil {
		temporary.Close()
		return err
	}
	if err = temporary.Sync(); err != nil {
		temporary.Close()
		return err
	}
	if err = temporary.Close(); err != nil {
		return err
	}
	if err = os.Chmod(name, 0o644); err != nil {
		return err
	}
	return os.Rename(name, path)
}
func ReadCompiledDump(path string, source []byte) (CompiledDump, error) {
	file, err := os.Open(path)
	if err != nil {
		return CompiledDump{}, err
	}
	defer file.Close()
	var dump CompiledDump
	if err = json.NewDecoder(file).Decode(&dump); err != nil {
		return CompiledDump{}, err
	}
	digest := sha256.Sum256(source)
	if dump.Version != Release || dump.Target != runtime.GOOS+"/"+runtime.GOARCH || dump.SourceSHA256 != hex.EncodeToString(digest[:]) {
		return CompiledDump{}, ErrStaleDump
	}
	for path, expected := range dump.Dependencies {
		content, readErr := os.ReadFile(path)
		if readErr != nil {
			return CompiledDump{}, ErrStaleDump
		}
		actual := sha256.Sum256(content)
		if hex.EncodeToString(actual[:]) != expected {
			return CompiledDump{}, ErrStaleDump
		}
	}
	return dump, nil
}
