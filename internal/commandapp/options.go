package commandapp

import (
	"errors"
	"fmt"
	"github.com/pkreyenhop/miracula-go/internal/application"
	"strconv"
	"strings"
)

type Mode uint8

const (
	ModeREPL Mode = iota
	ModeVersion
	ModeFullVersion
	ModeBuildInfo
	ModeManual
	ModeMake
	ModeExports
	ModeSources
	ModeExec
	ModeExec2
)

type Options struct {
	Config      application.Config
	Mode        Mode
	Script      string
	ScriptArgs  []string
	ExplicitLib bool
}

type UsageError struct{ Message string }

func (e *UsageError) Error() string { return e.Message }

func parseNumber(flag, value string) (int, error) {
	n, err := strconv.ParseInt(value, 10, 64)
	if err != nil || n < 100 || n > 50000000 {
		return 0, &UsageError{Message: fmt.Sprintf("mira: bad value after flag %q", flag)}
	}
	return int(n), nil
}

func ParseOptions(args []string, defaults application.Config) (Options, error) {
	opts := Options{Config: defaults}
	parameter := func(index *int, flag string) (string, error) {
		*index = *index + 1
		if *index >= len(args) {
			return "", &UsageError{Message: fmt.Sprintf("mira: missing param after flag %q", flag)}
		}
		return args[*index], nil
	}
	index := 0
	for index < len(args) && strings.HasPrefix(args[index], "-") {
		flag := args[index]
		switch flag {
		case "--build-info":
			opts.Mode = ModeBuildInfo
		case "-version":
			opts.Mode = ModeVersion
		case "-V":
			opts.Mode = ModeFullVersion
		case "-stdenv":
			opts.Config.NoStdEnv = true
		case "-count":
			opts.Config.Count = true
		case "-list":
			opts.Config.List = true
		case "-nolist":
			opts.Config.List = false
		case "-nostrictif":
			opts.Config.StrictIf = false
		case "-gc":
			opts.Config.GC = true
		case "-object":
			opts.Config.Object = true
		case "-hush":
			opts.Config.Hush = true
		case "-nohush":
			opts.Config.Hush = false
		case "-UTF-8":
			opts.Config.UTF8 = true
		case "-noUTF-8":
			opts.Config.UTF8 = false
		case "-man":
			opts.Mode = ModeManual
		case "-make":
			opts.Mode, opts.Config.Hush = ModeMake, true
		case "-exports":
			opts.Mode, opts.Config.Hush = ModeExports, true
		case "-sources":
			opts.Mode, opts.Config.Hush = ModeSources, true
		case "-exp", "-log":
			return Options{}, &UsageError{Message: fmt.Sprintf("mira: obsolete flag %q\nuse \"-exec\" or \"-exec2\", see manual", flag)}
		case "-lib", "-editor", "-dic", "-heap":
			value, err := parameter(&index, strings.TrimPrefix(flag, "-"))
			if err != nil {
				return Options{}, err
			}
			switch flag {
			case "-lib":
				opts.Config.LibraryPath, opts.ExplicitLib = value, true
			case "-editor":
				opts.Config.Editor = value
			case "-dic":
				opts.Config.DictionaryCells, err = parseNumber(flag, value)
			case "-heap":
				opts.Config.HeapCells, err = parseNumber(flag, value)
			}
			if err != nil {
				return Options{}, err
			}
		case "-exec", "-exec2":
			if index+1 >= len(args) {
				if flag == "-exec2" {
					return Options{}, &UsageError{Message: "incorrect use of -exec2 flag, missing filename"}
				}
				return Options{}, &UsageError{Message: "mira: missing script after flag \"-exec\""}
			}
			opts.Mode = ModeExec
			if flag == "-exec2" {
				opts.Mode = ModeExec2
			}
			opts.Config.Hush = true
			opts.Script = args[index+1]
			opts.ScriptArgs = append([]string(nil), args[index+2:]...)
			return opts, nil
		default:
			return Options{}, &UsageError{Message: fmt.Sprintf("mira: unknown flag %q", flag)}
		}
		index++
	}
	remaining := args[index:]
	if opts.Mode == ModeMake || opts.Mode == ModeExports || opts.Mode == ModeSources {
		opts.ScriptArgs = append([]string(nil), remaining...)
		if len(remaining) > 0 {
			opts.Script = remaining[0]
		}
		return opts, nil
	}
	if len(remaining) > 1 {
		return Options{}, &UsageError{Message: "mira: too many args"}
	}
	if len(remaining) == 1 {
		opts.Script = remaining[0]
	}
	return opts, nil
}

func IsUsage(err error) bool {
	var usage *UsageError
	return errors.As(err, &usage)
}
