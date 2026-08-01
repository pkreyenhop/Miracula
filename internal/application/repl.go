package application

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/pkreyenhop/miracula-go/internal/platformsvc"
	"github.com/pkreyenhop/miracula-go/internal/protocol"
	"github.com/pkreyenhop/miracula-go/internal/semantics"
	"github.com/pkreyenhop/miracula-go/internal/syntaxfront"
)

var ErrEvaluationReported = errors.New("evaluation error already reported")

// Evaluate compiles and evaluates one Miranda expression. Temporary graph
// cells are always reclaimed, including after parse, type, or runtime errors.
func (i *Interpreter) Evaluate(ctx context.Context, expression string) (string, error) {
	parsed := syntaxfront.Run([]byte("__repl = " + expression + "\n"))
	if len(parsed.Diagnostics) != 0 {
		d := parsed.Diagnostics[0]
		return "", fmt.Errorf("%d:%d: %s", d.Span.Line, d.Span.Column, d.Message)
	}
	if len(parsed.Script.Items) != 1 {
		return "", fmt.Errorf("expression did not produce a value")
	}
	languageValue, languageErr := i.runtime().evaluate(ctx, parsed.Script.Items[0].RHS)
	if languageErr != nil {
		return "", languageErr
	}
	return renderLanguage(ctx, languageValue)
}

func (i *Interpreter) REPL(ctx context.Context, in io.Reader, out io.Writer) error {
	scanner := bufio.NewScanner(in)
	interactive := i.Services.Terminal(0).Interactive
	hadError := i.startupFailed
	for {
		if interactive {
			prompt := i.Config.Prompt
			if prompt == "" {
				prompt = "Miranda "
			}
			if _, err := fmt.Fprint(out, prompt); err != nil {
				return err
			}
		}
		if !scanner.Scan() {
			if err := scanner.Err(); err != nil {
				return err
			}
			if hadError {
				return ErrEvaluationReported
			}
			return nil
		}
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		if strings.HasPrefix(line, "/") {
			quit, err := i.runCommand(line, out)
			if err != nil {
				if _, writeErr := fmt.Fprintln(out, err); writeErr != nil {
					return writeErr
				}
			}
			if quit {
				if hadError {
					return ErrEvaluationReported
				}
				return nil
			}
			continue
		}
		evaluationContext, cancel := context.WithCancel(ctx)
		registration, registrationErr := platformsvc.Register(platformsvc.SignalInterrupt, platformsvc.SignalNotify, cancel)
		result, err := i.Evaluate(evaluationContext, line)
		cancel()
		if registrationErr == nil {
			registration.Restore()
		}
		if errors.Is(err, context.Canceled) || errors.Is(err, protocol.ErrInterrupted) {
			destination := i.Error
			if destination == nil {
				destination = out
			}
			fmt.Fprintln(destination, "<<...interrupt>>")
			hadError = i.startupFailed
			continue
		}
		if err != nil {
			diagnostic := legacyEvaluationError(err)
			if strings.HasPrefix(err.Error(), "undefined name ") && !i.startupFailed {
				name := strings.TrimPrefix(err.Error(), "undefined name ")
				if line, path := i.definitionReference(name); line > 0 {
					fmt.Fprintf(out, "(line  +%d of %q) undefined name %q\n", line, path, name)
				}
			}
			destination := out
			if diagnosticToErrorStream(err) {
				destination = i.Error
				if destination == nil {
					destination = out
				}
			}
			if _, writeErr := fmt.Fprintln(destination, diagnostic); writeErr != nil {
				return writeErr
			}
			hadError = hadError || isFatalEvaluation(err)
			continue
		}
		hadError = i.startupFailed
		if _, err = fmt.Fprintln(out, result); err != nil {
			return err
		}
		if i.Config.Count {
			reductions, cells := i.runtime().statistics()
			destination := i.Error
			if destination == nil {
				destination = out
			}
			fmt.Fprintf(destination, "||reductions = %d, cells claimed = %d, no of gc's = 0, cpu = 0.00\n", reductions, cells)
		}
		if i.Config.GC && i.Error != nil {
			fmt.Fprintln(i.Error, "<<gc after Go evaluation>>")
		}
	}
}

func (i *Interpreter) runCommand(line string, out io.Writer) (bool, error) {
	fields := strings.Fields(strings.TrimPrefix(line, "/"))
	if len(fields) == 0 {
		return false, nil
	}
	i.Repl.LastCommand = line
	switch fields[0] {
	case "q", "quit":
		i.Repl.ExitRequested = true
		return true, nil
	case "h", "help":
		data, err := os.ReadFile(filepath.Join(i.Config.LibraryPath, "helpfile"))
		if err != nil {
			return false, err
		}
		_, err = out.Write(data)
		return false, err
	case "count":
		i.Config.Count = true
		return false, nil
	case "nocount":
		i.Config.Count = false
		return false, nil
	case "v", "version":
		_, err := fmt.Fprintln(out, VersionString())
		return false, err
	case "f", "files":
		paths := make([]string, 0, len(i.Scripts.Scripts))
		for path := range i.Scripts.Scripts {
			paths = append(paths, path)
		}
		sort.Strings(paths)
		for _, path := range paths {
			if _, err := fmt.Fprintln(out, path); err != nil {
				return false, err
			}
		}
		return false, nil
	case "l", "load":
		if len(fields) != 2 {
			return false, fmt.Errorf("usage: /load file")
		}
		_, err := i.LoadProgram(fields[1])
		return false, err
	case "r", "reload":
		path := i.Compiler.CurrentModule
		if path == "" {
			return false, fmt.Errorf("no current script")
		}
		_, err := i.LoadProgram(path)
		return false, err
	case "n", "names":
		return false, i.printNames(out, false, "")
	case "t", "type":
		if len(fields) != 2 {
			return false, fmt.Errorf("usage: /type name")
		}
		return false, i.printNames(out, true, fields[1])
	case "set":
		return false, i.setOption(fields[1:])
	case "edit", "e":
		return false, fmt.Errorf("editor command is unavailable in this session")
	default:
		return false, fmt.Errorf("unknown command /%s; use /help", fields[0])
	}
}

func legacyEvaluationError(err error) string {
	if strings.Contains(err.Error(), "division by zero") {
		return "\nprogram error: attempt to divide by zero"
	}
	if err.Error() == "undefined name readvals" {
		return "type error in expression\ncannot unify [char]->[*] with [**]"
	}
	if strings.HasPrefix(err.Error(), "undefined name ") {
		return "\nUNDEFINED NAME - " + strings.TrimPrefix(err.Error(), "undefined name ")
	}
	if err.Error() == "number expected" {
		return "type error in expression\ncannot unify [char] with num"
	}
	if err.Error() == "list expected" {
		return "type error in expression\ncannot unify [char]->[*] with [**]"
	}
	if err.Error() == "unsupported expression empty" {
		return "syntax error - unexpected newline"
	}
	if strings.Contains(err.Error(), "invalid syntax") {
		return "unrecognised escape \\q in string"
	}
	if strings.Contains(err.Error(), "unexpected token") {
		return "syntax error: non-escaped newline encountered inside string quotes"
	}
	return err.Error()
}
func isFatalEvaluation(err error) bool {
	return strings.Contains(err.Error(), "division by zero") || strings.Contains(err.Error(), "undefined name") && err.Error() != "undefined name readvals"
}
func diagnosticToErrorStream(err error) bool {
	return strings.Contains(err.Error(), "division by zero") || strings.HasPrefix(err.Error(), "undefined name ") && err.Error() != "undefined name readvals" || strings.Contains(err.Error(), "unexpected token")
}

func (i *Interpreter) definitionReference(name string) (int, string) {
	script, ok := i.Scripts.Scripts[i.Compiler.CurrentModule]
	if !ok {
		return 0, ""
	}
	for index, line := range strings.Split(string(script.Source), "\n") {
		if strings.Contains(line, name) {
			path := script.Path
			workingDirectory, _ := os.Getwd()
			if relative, err := filepath.Rel(workingDirectory, path); err == nil {
				path = relative
			}
			return index + 1, path
		}
	}
	return 0, ""
}

func (i *Interpreter) printNames(out io.Writer, withType bool, only string) error {
	path := i.Compiler.CurrentModule
	program := i.Programs[path]
	if program == nil {
		return fmt.Errorf("no current script")
	}
	for _, definition := range program.Definitions {
		if only != "" && definition.Name != only {
			continue
		}
		text := definition.Name
		if withType {
			text += " :: " + formatType(definition.Type)
		}
		if _, err := fmt.Fprintln(out, text); err != nil {
			return err
		}
	}
	return nil
}

func formatType(t *semantics.Type) string {
	if t == nil {
		return "?"
	}
	switch t.Kind {
	case semantics.TypeVariable:
		return fmt.Sprintf("t%d", t.ID)
	case semantics.TypeNamed:
		return t.Name
	case semantics.TypeArrow:
		return "(" + formatType(t.From) + " -> " + formatType(t.To) + ")"
	case semantics.TypeList:
		if len(t.Items) == 1 {
			return "[" + formatType(t.Items[0]) + "]"
		}
	case semantics.TypeTuple:
		parts := make([]string, len(t.Items))
		for index := range t.Items {
			parts[index] = formatType(t.Items[index])
		}
		return "(" + strings.Join(parts, ",") + ")"
	}
	return "?"
}

func (i *Interpreter) setOption(arguments []string) error {
	if len(arguments) != 1 {
		return fmt.Errorf("usage: /set count|nocount|gc|nogc|list|nolist")
	}
	switch arguments[0] {
	case "count":
		i.Config.Count = true
	case "nocount":
		i.Config.Count = false
	case "gc":
		i.Config.GC = true
	case "nogc":
		i.Config.GC = false
	case "list":
		i.Config.List = true
	case "nolist":
		i.Config.List = false
	default:
		return fmt.Errorf("unknown setting %s", filepath.Base(arguments[0]))
	}
	return nil
}
