package application

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/pkreyenhop/miracula/internal/semantics"
	"github.com/pkreyenhop/miracula/internal/syntaxfront"
)

func (i *Interpreter) Boot() error {
	if err := i.resolveLibrary(); err != nil {
		return err
	}
	if err := i.Setup(); err != nil {
		return err
	}
	for _, name := range []string{"prelude", "stdenv.m"} {
		if name == "stdenv.m" && i.Config.NoStdEnv {
			continue
		}
		path := filepath.Join(i.Config.LibraryPath, name)
		source, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("load %s: %w", name, err)
		}
		i.Scripts.Put(Script{Path: path, Source: append([]byte(nil), source...)})
		if i.StandardTypes == nil {
			i.StandardTypes = map[string]*semantics.Type{}
		}
		if name == "stdenv.m" {
			for declaredName, declaredType := range semantics.DeclaredTypes(source) {
				i.StandardTypes[declaredName] = declaredType
			}
		}
		runtimeSource := source
		if name == "stdenv.m" {
			runtimeSource = syntaxfront.NewSource(source, true).Bytes
		}
		if err := i.runtime().installSource(runtimeSource); err != nil {
			return fmt.Errorf("install %s: %w", name, err)
		}
	}
	if i.InitialScript == "" {
		workingDirectory, err := os.Getwd()
		if err != nil {
			return err
		}
		if i.InitialScript, err = i.ensureDefaultScript(workingDirectory); err != nil {
			return err
		}
	}
	if i.InitialScript != "" {
		path := i.InitialScript
		if filepath.Ext(path) == "" {
			path += ".m"
		}
		if _, err := i.LoadProgram(path); err != nil {
			if !i.ContinueAfterLoadError {
				return err
			}
			i.startupFailed = true
			destination := i.Error
			if destination == nil {
				destination = i.Output
			}
			if destination != nil {
				fmt.Fprintln(destination, err)
			}
		}
	}
	return nil
}

func (i *Interpreter) ensureDefaultScript(workingDirectory string) (string, error) {
	if home, ok := i.Services.Environment("HOME"); ok && home != "" {
		path := filepath.Join(home, "script.m")
		if info, err := os.Stat(path); err == nil && !info.IsDir() {
			return path, nil
		}
	}
	path := filepath.Join(workingDirectory, "script.m")
	if info, err := os.Stat(path); err == nil && !info.IsDir() {
		return path, nil
	}
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
	if errors.Is(err, os.ErrExist) {
		return path, nil
	}
	if err != nil {
		return "", fmt.Errorf("create default script %s: %w", path, err)
	}
	if err = file.Close(); err != nil {
		return "", fmt.Errorf("create default script %s: %w", path, err)
	}
	return path, nil
}

func (i *Interpreter) resolveLibrary() error {
	candidates := []string{i.Config.LibraryPath, "/usr/lib/miralib", "/usr/local/lib/miralib", "lib/miralib"}
	seen := map[string]bool{}
	for _, candidate := range candidates {
		if candidate == "" || seen[candidate] {
			continue
		}
		seen[candidate] = true
		raw, err := os.ReadFile(filepath.Join(candidate, ".version"))
		if err != nil {
			continue
		}
		version, err := strconv.Atoi(strings.TrimSpace(string(raw)))
		if err == nil && version == Release {
			absolute, absErr := filepath.Abs(candidate)
			if absErr != nil {
				return absErr
			}
			i.Config.LibraryPath = absolute
			return nil
		}
	}
	return fmt.Errorf("fatal error: miralib version %s not found", VersionString())
}
