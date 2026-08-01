package application

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"path/filepath"
	"sort"
	"strings"

	"github.com/pkreyenhop/miracula-go/internal/protocol"
	"github.com/pkreyenhop/miracula-go/internal/semantics"
	"github.com/pkreyenhop/miracula-go/internal/syntaxfront"
)

// Evaluate compiles and evaluates one Miranda expression. Temporary graph
// cells are always reclaimed, including after parse, type, or runtime errors.
func (i *Interpreter) Evaluate(ctx context.Context, expression string) (string, error) {
	checkpoint := i.Heap.Checkpoint()
	defer i.Heap.Restore(checkpoint)
	parsed := syntaxfront.Run([]byte("__repl = " + expression + "\n"))
	if len(parsed.Diagnostics) != 0 {
		d := parsed.Diagnostics[0]
		return "", fmt.Errorf("%d:%d: %s", d.Span.Line, d.Span.Column, d.Message)
	}
	program, err := semantics.Compile(parsed.Script, i.Heap)
	if err != nil {
		return "", err
	}
	if len(program.Definitions) != 1 {
		return "", fmt.Errorf("expression did not produce a value")
	}
	value := protocol.ValueFromRaw(protocol.Word(program.Definitions[0].Root))
	value, err = i.Evaluator.Reduce(ctx, value)
	if err != nil {
		return "", err
	}
	return i.Evaluator.Render(ctx, value, 100000)
}

func (i *Interpreter) REPL(ctx context.Context, in io.Reader, out io.Writer) error {
	scanner := bufio.NewScanner(in)
	interactive := i.Services.Terminal(0).Interactive
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
			return scanner.Err()
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
				return nil
			}
			continue
		}
		result, err := i.Evaluate(ctx, line)
		if err != nil {
			if _, writeErr := fmt.Fprintln(out, err); writeErr != nil {
				return writeErr
			}
			continue
		}
		if _, err = fmt.Fprintln(out, result); err != nil {
			return err
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
		_, err := fmt.Fprintln(out, "/help /files /load file /reload /names /type name /set option /version /quit")
		return false, err
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
