package commandapp

import (
	"context"
	"errors"
	"fmt"
	"github.com/pkreyenhop/miracula/internal/application"
	"github.com/pkreyenhop/miracula/internal/buildcfg"
	"github.com/pkreyenhop/miracula/internal/platformsvc"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type Command struct {
	Stdin          io.Reader
	Stdout, Stderr io.Writer
	Services       platformsvc.Services
}

func (c Command) Run(ctx context.Context, args []string) error {
	options, err := ParseOptions(args, resolveDefaults(c.Services))
	if err != nil {
		return err
	}
	switch options.Mode {
	case ModeVersion:
		_, err = fmt.Fprintf(c.Stdout, "%s last revised %s\n", application.VersionString(), buildcfg.VersionDate)
		return err
	case ModeFullVersion:
		_, err = fmt.Fprintf(c.Stdout, "%s last revised %s\n%s\nXVERSION %d\n", application.VersionString(), buildcfg.VersionDate, buildcfg.Host, buildcfg.XVersion)
		return err
	case ModeBuildInfo:
		_, err = fmt.Fprintf(c.Stdout, "implementation=go\nversion=%s\ncommit=%s\ntarget=%s\n", application.VersionString(), buildcfg.Commit, platformsvc.PlatformTarget)
		return err
	case ModeREPL, ModeManual, ModeMake, ModeExports, ModeSources, ModeExec, ModeExec2:
	}
	i := application.New(c.Services)
	i.Config = options.Config
	i.InitialScript = options.Script
	i.Input, i.Output, i.Error = c.Stdin, c.Stdout, c.Stderr
	if options.Mode == ModeMake || options.Mode == ModeExports || options.Mode == ModeSources {
		if len(options.ScriptArgs) == 0 {
			return &UsageError{Message: "mira: at least one script is required"}
		}
		for index := range options.ScriptArgs {
			options.ScriptArgs[index] = normalizeScriptPath(options.ScriptArgs[index])
		}
		i.InitialScript = options.ScriptArgs[0]
	}
	if options.Mode == ModeExec || options.Mode == ModeExec2 {
		i.InitialScript = normalizeScriptPath(options.Script)
		i.Arguments = append([]string{options.Script}, options.ScriptArgs...)
	}
	if err = i.Boot(); err != nil {
		if options.Mode == ModeExec2 {
			logExec2(options.Script, err)
		}
		return err
	}
	switch options.Mode {
	case ModeMake:
		for _, root := range options.ScriptArgs[1:] {
			if _, err := i.LoadProgram(root); err != nil {
				return err
			}
		}
		return nil
	case ModeExports:
		for index, root := range options.ScriptArgs {
			program := i.Programs[absolutePath(root)]
			if index > 0 {
				fmt.Fprintf(c.Stdout, "%s:\n", root)
			}
			profile, profileErr := application.ExportedProfileForPath(root, program)
			if profileErr != nil {
				return profileErr
			}
			names := make([]string, 0, len(profile))
			for name := range profile {
				names = append(names, name)
			}
			sort.Strings(names)
			for _, name := range names {
				fmt.Fprintf(c.Stdout, "%s :: %s\n", name, profile[name])
			}
			if index+1 < len(options.ScriptArgs) {
				fmt.Fprintln(c.Stdout)
			}
			if index+1 < len(options.ScriptArgs) {
				if _, err := i.LoadProgram(options.ScriptArgs[index+1]); err != nil {
					return err
				}
			}
		}
		return nil
	case ModeSources:
		seen := map[string]bool{}
		var paths []string
		for _, root := range options.ScriptArgs {
			relevant, err := application.RelevantSources(root, i.Config.LibraryPath)
			if err != nil {
				return err
			}
			for _, path := range relevant {
				if !seen[path] {
					seen[path] = true
					paths = append(paths, path)
				}
			}
		}
		sort.Strings(paths)
		for _, path := range paths {
			fmt.Fprintln(c.Stdout, path)
		}
		return nil
	case ModeExec, ModeExec2:
		err := i.RunMain(ctx, c.Stdout)
		if err != nil && options.Mode == ModeExec2 {
			logExec2(options.Script, err)
		}
		return err
	}
	return i.REPL(ctx, c.Stdin, c.Stdout)
}

func normalizeScriptPath(path string) string {
	if filepath.Ext(path) == ".x" {
		return strings.TrimSuffix(path, ".x") + ".m"
	}
	if filepath.Ext(path) == "" {
		return path + ".m"
	}
	return path
}
func absolutePath(path string) string { value, _ := filepath.Abs(path); return value }
func logExec2(script string, err error) {
	directory := "miralog"
	if info, statErr := os.Stat(directory); statErr != nil || !info.IsDir() {
		return
	}
	path := filepath.Join(directory, filepath.Base(strings.TrimSuffix(script, filepath.Ext(script))))
	_ = os.WriteFile(path, []byte(err.Error()+"\n"), 0o644)
}

func ExitCode(err error) int {
	if err == nil {
		return 0
	}
	var processExit *application.ProcessExitError
	if errors.As(err, &processExit) {
		return processExit.Status
	}
	return 1
}
