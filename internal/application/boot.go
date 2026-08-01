package application

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
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
	}
	if i.InitialScript != "" {
		path := i.InitialScript
		if filepath.Ext(path) == "" {
			path += ".m"
		}
		if _, err := i.LoadProgram(path); err != nil {
			return err
		}
	}
	return nil
}

func (i *Interpreter) resolveLibrary() error {
	candidates := []string{i.Config.LibraryPath, "/usr/lib/miralib", "/usr/local/lib/miralib", "miralib"}
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
