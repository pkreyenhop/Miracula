package application

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	goruntime "runtime"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/pkreyenhop/miracula/internal/platformsvc"
	"github.com/pkreyenhop/miracula/internal/protocol"
	"github.com/pkreyenhop/miracula/internal/semantics"
	"github.com/pkreyenhop/miracula/internal/syntaxfront"
)

var ErrEvaluationReported = errors.New("evaluation error already reported")

// Evaluate compiles and evaluates one Miranda expression. Temporary graph
// cells are always reclaimed, including after parse, type, or runtime errors.
func (i *Interpreter) Evaluate(ctx context.Context, expression string) (string, error) {
	languageValue, err := i.evaluateValue(ctx, expression)
	if err != nil {
		return "", err
	}
	return renderLanguage(ctx, languageValue)
}

func (i *Interpreter) evaluateValue(ctx context.Context, expression string) (languageValue, error) {
	parsed := syntaxfront.Run([]byte("__repl = " + expression + "\n"))
	if len(parsed.Diagnostics) != 0 {
		d := parsed.Diagnostics[0]
		return languageValue{}, fmt.Errorf("%d:%d: %s", d.Span.Line, d.Span.Column, d.Message)
	}
	if len(parsed.Script.Items) != 1 {
		return languageValue{}, fmt.Errorf("expression did not produce a value")
	}
	typeEnvironment := make(map[string]*semantics.Type, len(i.StandardTypes)+16)
	for name, value := range i.StandardTypes {
		typeEnvironment[name] = value
	}
	if program := i.Programs[i.Compiler.CurrentModule]; program != nil {
		for _, definition := range program.Definitions {
			typeEnvironment[definition.Name] = definition.Type
		}
		for name, value := range program.Specifications {
			typeEnvironment[name] = value
		}
	}
	if _, typeErr := semantics.CheckWithTypes(parsed.Script, typeEnvironment); typeErr != nil {
		return languageValue{}, typeErr
	}
	value, languageErr := i.runtime().evaluate(ctx, parsed.Script.Items[0].RHS)
	if languageErr != nil {
		return languageValue{}, languageErr
	}
	return value, nil
}

func (i *Interpreter) evaluateTo(ctx context.Context, expression string, out io.Writer) (bool, error) {
	value, err := i.evaluateValue(ctx, expression)
	if err != nil {
		return false, err
	}
	if value.kind == valueList {
		if first, ok, firstErr := value.list.at(ctx, 0); firstErr != nil {
			return true, firstErr
		} else if ok && isSystemMessage(first) {
			errOut := i.Error
			if errOut == nil {
				errOut = out
			}
			return true, i.executeSystemMessages(ctx, value, out, errOut)
		}
		if err = streamLanguageList(ctx, out, value); err != nil {
			return true, err
		}
		_, err = fmt.Fprintln(out)
		return true, err
	}
	text, err := renderLanguage(ctx, value)
	if err != nil {
		return false, err
	}
	_, err = fmt.Fprintln(out, text)
	return false, err
}

func isSystemMessage(value languageValue) bool {
	value, err := forceLanguageValue(value, nil)
	if err != nil || value.kind != valueConstructor {
		return false
	}
	switch value.name {
	case "Stdout", "Stderr", "Tofile", "Closefile", "Appendfile", "System", "Exit", "Stdoutb", "Tofileb", "Appendfileb":
		return true
	}
	return false
}

func (i *Interpreter) executeSystemMessages(ctx context.Context, messages languageValue, stdout, stderr io.Writer) error {
	files := map[string]*os.File{}
	appendNext := map[string]bool{}
	defer func() {
		for _, file := range files {
			_ = file.Close()
		}
	}()
	for index := 0; ; index++ {
		message, ok, err := messages.list.at(ctx, index)
		if err != nil || !ok {
			return err
		}
		message, err = forceLanguageValue(message, nil)
		if err != nil {
			return err
		}
		if message.kind != valueConstructor {
			return errors.New("system message expected")
		}
		items := make([]languageValue, len(message.items))
		for itemIndex, item := range message.items {
			items[itemIndex], err = forceLanguageValue(item, nil)
			if err != nil {
				return err
			}
		}
		stringAt := func(position int) (string, error) {
			if position >= len(items) || items[position].kind != valueString {
				return "", errors.New("string message argument expected")
			}
			if len(items[position].text) > 1024 && message.name != "Stdout" && message.name != "Stderr" && message.name != "Stdoutb" {
				return "", errors.New("pathname or command exceeds 1024 characters")
			}
			return items[position].text, nil
		}
		switch message.name {
		case "Stdout", "Stdoutb":
			text, err := stringAt(0)
			if err != nil {
				return err
			}
			if message.name == "Stdout" && !utf8.ValidString(text) {
				return errors.New("illegal UTF-8 output")
			}
			_, err = io.WriteString(stdout, text)
			if err != nil {
				return err
			}
		case "Stderr":
			text, err := stringAt(0)
			if err != nil {
				return err
			}
			if !utf8.ValidString(text) {
				return errors.New("illegal UTF-8 output")
			}
			_, err = io.WriteString(stderr, text)
			if err != nil {
				return err
			}
		case "Appendfile", "Appendfileb":
			path, err := stringAt(0)
			if err != nil {
				return err
			}
			appendNext[path] = true
		case "Closefile":
			path, err := stringAt(0)
			if err != nil {
				return err
			}
			if file := files[path]; file != nil {
				if err := file.Close(); err != nil {
					return err
				}
				delete(files, path)
			}
		case "Tofile", "Tofileb":
			path, err := stringAt(0)
			if err != nil {
				return err
			}
			text, err := stringAt(1)
			if err != nil {
				return err
			}
			if message.name == "Tofile" && !utf8.ValidString(text) {
				return errors.New("illegal UTF-8 output")
			}
			file := files[path]
			if file == nil {
				flags := os.O_CREATE | os.O_WRONLY | os.O_TRUNC
				if appendNext[path] {
					flags = os.O_CREATE | os.O_WRONLY | os.O_APPEND
				}
				file, err = os.OpenFile(path, flags, 0o644)
				if err != nil {
					return err
				}
				files[path] = file
				delete(appendNext, path)
			}
			if _, err = file.WriteString(text); err != nil {
				return err
			}
		case "System":
			command, err := stringAt(0)
			if err != nil {
				return err
			}
			output, errorOutput, _, err := platformsvc.CaptureShell(ctx, command)
			if err != nil {
				return err
			}
			if _, err = io.WriteString(stdout, output); err != nil {
				return err
			}
			if _, err = io.WriteString(stderr, errorOutput); err != nil {
				return err
			}
		case "Exit":
			number, err := numberValue(items[0])
			if err != nil || !number.IsInt64() || number.Sign() < 0 || number.Int64() > 127 {
				return errors.New("Exit status must be an integer from 0 to 127")
			}
			i.Repl.ExitRequested, i.Repl.ExitStatus = true, int(number.Int64())
			return nil
		default:
			return fmt.Errorf("unknown system message %s", message.name)
		}
	}
}

func (i *Interpreter) REPL(ctx context.Context, in io.Reader, out io.Writer) error {
	interactive := i.Services.Terminal(0).Interactive
	var scanner *bufio.Scanner
	var editor LineEditor
	if interactive {
		var err error
		editor, err = NewLineEditor(in, out)
		if err != nil {
			i.recordError(i.Compiler.CurrentModule, err)
			return err
		}
		if home, ok := i.Services.Environment("HOME"); ok {
			if err = editor.LoadHistory(filepath.Join(home, ".miranda_history")); err != nil {
				return err
			}
		}
		editor.SetCompleter(i.completeIdentifier)
		i.activeEditor = editor
		defer func() {
			_ = editor.SaveHistory()
			_ = editor.Close()
			i.activeEditor = nil
		}()
	} else {
		scanner = bufio.NewScanner(in)
	}
	hadError := i.startupFailed
	for {
		if interactive && i.Config.Recheck {
			if err := i.recheckSource(); err != nil {
				fmt.Fprintln(out, err)
			}
		}
		var rawLine string
		if interactive {
			prompt := i.replPrompt()
			line, err := editor.ReadLine(prompt)
			if err != nil && !errors.Is(err, io.EOF) {
				return err
			}
			if errors.Is(err, io.EOF) {
				if !i.Config.Hush {
					fmt.Fprintln(out, "miranda logout")
				}
				if hadError {
					return ErrEvaluationReported
				}
				return nil
			}
			rawLine = line
		} else if scanner.Scan() {
			rawLine = scanner.Text()
		} else {
			if err := scanner.Err(); err != nil {
				return err
			}
			if hadError {
				return ErrEvaluationReported
			}
			return nil
		}
		line := strings.TrimSpace(rawLine)
		if line == "" {
			i.Repl.clearTiming()
			continue
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		if strings.HasPrefix(line, "/") {
			i.Repl.clearTiming()
			quit, err := i.runCommand(line, out)
			if err != nil {
				if _, writeErr := fmt.Fprintln(out, err); writeErr != nil {
					return writeErr
				}
			}
			if quit {
				if interactive && !i.Config.Hush {
					fmt.Fprintln(out, "miranda logout")
				}
				if hadError {
					return ErrEvaluationReported
				}
				return nil
			}
			continue
		}
		if interactive && strings.HasPrefix(line, "?") {
			i.Repl.clearTiming()
			if err := i.handleQuery(line, out); err != nil {
				if _, writeErr := fmt.Fprintln(out, err); writeErr != nil {
					return writeErr
				}
			}
			continue
		}
		if interactive && strings.HasPrefix(line, "!") {
			i.Repl.clearTiming()
			command := strings.TrimSpace(strings.TrimPrefix(line, "!"))
			if command == "" {
				if _, err := fmt.Fprintln(out, `No previous shell command to substitute for "!"`); err != nil {
					return err
				}
				continue
			}
			if err := i.runShell(ctx, command); err != nil {
				if _, writeErr := fmt.Fprintln(out, err); writeErr != nil {
					return writeErr
				}
			}
			continue
		}
		if interactive && strings.HasPrefix(line, "|") {
			i.Repl.clearTiming()
			if err := handleBarLine(line, out); err != nil {
				return err
			}
			continue
		}
		started := i.Services.Monotonic()
		var beforeGC goruntime.MemStats
		goruntime.ReadMemStats(&beforeGC)
		evaluationContext, cancel := context.WithCancel(ctx)
		registration, registrationErr := platformsvc.Register(platformsvc.SignalInterrupt, platformsvc.SignalNotify, cancel)
		streamed, err := i.evaluateTo(evaluationContext, line, out)
		elapsed := i.Services.Monotonic() - started
		var afterGC goruntime.MemStats
		goruntime.ReadMemStats(&afterGC)
		collections := int(afterGC.NumGC - beforeGC.NumGC)
		i.Repl.LastElapsed = &elapsed
		i.Repl.LastGC = &collections
		cancel()
		if registrationErr == nil {
			registration.Restore()
		}
		if errors.Is(err, context.Canceled) || errors.Is(err, protocol.ErrInterrupted) {
			destination := i.Error
			if destination == nil {
				destination = out
			}
			if streamed {
				fmt.Fprintln(out)
			}
			fmt.Fprintln(destination, "<<...interrupt>>")
			hadError = i.startupFailed
			continue
		}
		if err != nil {
			diagnostic := legacyEvaluationError(err)
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

func handleBarLine(line string, out io.Writer) error {
	if strings.HasPrefix(line, "||") {
		return nil
	}
	_, err := fmt.Fprintln(out, "\aunknown command - type /h for help")
	return err
}

func (i *Interpreter) runShell(ctx context.Context, command string) error {
	shell := platformsvc.ShellFallbackPath
	if configured, ok := i.Services.Environment("SHELL"); ok && configured != "" {
		shell = configured
	}
	if i.activeEditor != nil {
		if err := i.activeEditor.Suspend(); err != nil {
			return err
		}
		defer i.activeEditor.Resume()
	}
	registration, registrationErr := platformsvc.Register(platformsvc.SignalInterrupt, platformsvc.SignalIgnore, nil)
	if registrationErr == nil {
		defer registration.Restore()
	}
	_, err := i.Services.Run(platformsvc.ProcessRequest{Context: ctx, Executable: shell, Arguments: []string{platformsvc.ShellCommandArgument, command}, InheritEnvironment: true, Stdin: platformsvc.StreamInherit, Stdout: platformsvc.StreamInherit, Stderr: platformsvc.StreamInherit})
	if err == nil && i.Config.Recheck {
		err = i.recheckSource()
	}
	return err
}

func (i *Interpreter) recheckSource() error {
	path := i.Compiler.CurrentModule
	if path == "" {
		return nil
	}
	script, ok := i.Scripts.Scripts[path]
	if !ok || !script.HasMetadata {
		return nil
	}
	metadata, exists := i.Services.Metadata(path)
	if !exists || metadata == script.Metadata {
		return nil
	}
	_, err := i.LoadProgram(path)
	i.recordLoadResult(path, err)
	return err
}

func (i *Interpreter) handleQuery(line string, out io.Writer) error {
	if strings.HasPrefix(line, "??") {
		name := strings.TrimSpace(strings.TrimPrefix(line, "??"))
		if name == "" {
			_, err := fmt.Fprintln(out, "\aidentifier needed after `??'")
			return err
		}
		definition, path, ok := i.findDefinition(name)
		if !ok {
			return i.diagnose(out, name)
		}
		if i.Config.BadEditor {
			return i.editorWarning(out)
		}
		if i.Repl.Errors == nil {
			i.Repl.Errors = map[string]ErrorLocation{}
		}
		previous, hadPrevious := i.Repl.Errors[path]
		i.Repl.Errors[path] = ErrorLocation{Path: path, Line: definition.Expression.Span.Line, Column: 0}
		err := i.editCommand([]string{path}, out)
		if hadPrevious {
			i.Repl.Errors[path] = previous
		} else {
			delete(i.Repl.Errors, path)
		}
		return err
	}
	names := strings.Fields(strings.TrimSpace(strings.TrimPrefix(line, "?")))
	if len(names) == 0 {
		return i.allNames(out)
	}
	for _, name := range names {
		if err := i.fingerName(out, name); err != nil {
			return err
		}
	}
	return nil
}

func (i *Interpreter) findDefinition(name string) (semantics.TypedDefinition, string, bool) {
	path := i.Compiler.CurrentModule
	program := i.Programs[path]
	if program != nil {
		for _, definition := range program.Definitions {
			if definition.Name == name {
				return definition, path, true
			}
		}
	}
	if provenance, exists := i.runtime().provenance[name]; exists {
		source, err := os.ReadFile(provenance.Path)
		if err == nil {
			if line, ok := sourceDefinitionLine(source, provenance.Original); ok {
				return semantics.TypedDefinition{Name: name, Expression: syntaxfront.Expr{Span: syntaxfront.Span{Line: line}}}, provenance.Path, true
			}
		}
	}
	paths := make([]string, 0, len(i.Scripts.Scripts))
	for candidate := range i.Scripts.Scripts {
		if candidate != path {
			paths = append(paths, candidate)
		}
	}
	sort.Strings(paths)
	for _, candidate := range paths {
		if line, ok := sourceDefinitionLine(i.Scripts.Scripts[candidate].Source, name); ok {
			return semantics.TypedDefinition{Name: name, Expression: syntaxfront.Expr{Span: syntaxfront.Span{Line: line}}}, candidate, true
		}
	}
	return semantics.TypedDefinition{}, "", false
}

func (i *Interpreter) fingerName(out io.Writer, name string) error {
	definition, path, ok := i.findDefinition(name)
	if !ok {
		return i.diagnose(out, name)
	}
	typeText := formatType(definition.Type)
	if definition.Type == nil {
		typeText = sourceDefinitionType(i.Scripts.Scripts[path].Source, name)
		if typeText == "" {
			typeText = "*"
		}
	}
	aliasText := ""
	if provenance, ok := i.runtime().provenance[name]; ok && provenance.Original != name {
		aliasText = fmt.Sprintf(" (alias of %s)", provenance.Original)
	}
	_, err := fmt.Fprintf(out, "%s :: %s%s ||defined in %q line %d\n", name, typeText, aliasText, path, definition.Expression.Span.Line)
	return err
}

func sourceDefinitionLine(source []byte, name string) (int, bool) {
	for index, raw := range strings.Split(string(source), "\n") {
		line := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(raw), ">"))
		separator := strings.Index(line, "=")
		if separator < 0 || strings.Contains(line[:separator], "::") {
			continue
		}
		parsed := syntaxfront.Run([]byte(strings.TrimSpace(line[:separator]) + " = 0\n"))
		if len(parsed.Script.Items) != 1 {
			continue
		}
		definitionName, _, ok := runtimePatterns(parsed.Script.Items[0].LHS)
		if ok && definitionName == name {
			return index + 1, true
		}
	}
	return 0, false
}

func sourceDefinitionType(source []byte, name string) string {
	prefix := name + " ::"
	for _, raw := range strings.Split(string(source), "\n") {
		line := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(raw), ">"))
		if strings.HasPrefix(line, prefix) {
			return strings.TrimSpace(strings.TrimPrefix(line, prefix))
		}
	}
	return ""
}

func (i *Interpreter) allNames(out io.Writer) error {
	program := i.Programs[i.Compiler.CurrentModule]
	if program == nil {
		return fmt.Errorf("no current script")
	}
	names := make([]string, 0, len(program.Definitions))
	for _, definition := range program.Definitions {
		names = append(names, definition.Name)
	}
	sort.Strings(names)
	for _, name := range names {
		if _, err := fmt.Fprintln(out, name); err != nil {
			return err
		}
	}
	return nil
}

func (i *Interpreter) diagnose(out io.Writer, name string) error {
	valid := name != "" && name[0] >= 'A' && name[0] <= 'Z' || name != "" && name[0] >= 'a' && name[0] <= 'z'
	if valid {
		for _, character := range name[1:] {
			if !isIdentifierRune(character) {
				valid = false
				break
			}
		}
	}
	if !valid {
		_, err := fmt.Fprintf(out, "%q -- not an identifier\n", name)
		return err
	}
	sections := map[string]int{"abstype": 21, "div": 8, "if": 15, "mod": 8, "otherwise": 15, "readvals": 31, "show": 23, "type": 22, "where": 15, "with": 21}
	if section, ok := sections[name]; ok {
		_, err := fmt.Fprintf(out, "%s -- keyword (see manual, section %d)\n", name, section)
		return err
	}
	_, err := fmt.Fprintf(out, "identifier %q not in scope\n", name)
	return err
}

func (i *Interpreter) replPrompt() string {
	if i.Config.Hush {
		return ""
	}
	prompt := i.Config.Prompt
	if prompt == "" {
		prompt = "Miranda "
	}
	if i.Repl.LastElapsed == nil {
		return prompt
	}
	annotation := formatExecutionTime(*i.Repl.LastElapsed)
	if i.Repl.LastGC != nil && *i.Repl.LastGC > 0 {
		label := "GCs"
		if *i.Repl.LastGC == 1 {
			label = "GC"
		}
		annotation += fmt.Sprintf(", %d %s", *i.Repl.LastGC, label)
	}
	return "[" + annotation + "] " + prompt
}

func formatExecutionTime(elapsed time.Duration) string {
	if elapsed < time.Millisecond {
		return fmt.Sprintf("%.3fms", float64(elapsed)/float64(time.Millisecond))
	}
	if elapsed < time.Second {
		return fmt.Sprintf("%.2fms", float64(elapsed)/float64(time.Millisecond))
	}
	return fmt.Sprintf("%.3fs", elapsed.Seconds())
}

func (i *Interpreter) completeIdentifier(prefix string) []string {
	if prefix == "" {
		return nil
	}
	seen := map[string]bool{}
	for name := range i.StandardTypes {
		if strings.HasPrefix(name, prefix) {
			seen[name] = true
		}
	}
	for name := range i.runtime().globals {
		if strings.HasPrefix(name, prefix) {
			seen[name] = true
		}
	}
	if program := i.Programs[i.Compiler.CurrentModule]; program != nil {
		for _, definition := range program.Definitions {
			if strings.HasPrefix(definition.Name, prefix) {
				seen[definition.Name] = true
			}
		}
	}
	matches := make([]string, 0, len(seen))
	for name := range seen {
		matches = append(matches, name)
	}
	sort.Strings(matches)
	if len(matches) > 128 {
		matches = matches[:128]
	}
	return matches
}

func (i *Interpreter) runCommand(line string, out io.Writer) (bool, error) {
	fields := strings.Fields(strings.TrimPrefix(line, "/"))
	if len(fields) == 0 {
		return false, nil
	}
	i.Repl.LastCommand = line
	switch fields[0] {
	case "a", "aux":
		return false, platformsvc.FileCopy(filepath.Join(i.Config.LibraryPath, "auxfile"), out)
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
	case "files":
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
	case "f", "file", "l", "load":
		if fields[0] == "f" || fields[0] == "file" {
			if len(fields) == 1 {
				if i.Compiler.CurrentModule == "" {
					return false, fmt.Errorf("no current script")
				}
				_, err := fmt.Fprintln(out, i.Compiler.CurrentModule)
				return false, err
			}
		}
		if len(fields) != 2 {
			return false, fmt.Errorf("usage: /load file")
		}
		_, err := i.LoadProgram(fields[1])
		i.recordLoadResult(fields[1], err)
		return false, err
	case "r", "reload":
		path := i.Compiler.CurrentModule
		if path == "" {
			return false, fmt.Errorf("no current script")
		}
		_, err := i.LoadProgram(path)
		i.recordLoadResult(path, err)
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
	case "cd":
		directory := ""
		if len(fields) == 2 {
			directory = fields[1]
		} else if len(fields) == 1 {
			directory, _ = i.Services.Environment("HOME")
		} else {
			return false, fmt.Errorf("cannot cd to %s", strings.Join(fields[1:], " "))
		}
		if err := os.Chdir(directory); err != nil {
			return false, fmt.Errorf("cannot cd to %s", directory)
		}
		if i.Config.Recheck {
			return false, i.recheckSource()
		}
		return false, nil
	case "dic":
		if len(fields) == 1 {
			_, err := fmt.Fprintf(out, "%d chars 0 in use\n", i.Config.DictionaryCells)
			return false, err
		}
		if len(fields) == 2 {
			_, err := fmt.Fprintf(out, "sorry, cannot change size of dictionary while in use\n(/q and reinvoke with flag: mira -dic %s ... )\n", fields[1])
			return false, err
		}
	case "gc":
		i.Config.GC = true
		return false, nil
	case "nogc":
		i.Config.GC = false
		return false, nil
	case "heap":
		return false, i.heapCommand(fields[1:], out)
	case "hush":
		i.Config.Hush = true
		return false, nil
	case "nohush":
		i.Config.Hush = false
		return false, nil
	case "list":
		i.Config.List = true
		return false, i.WriteRC()
	case "nolist":
		i.Config.List = false
		return false, i.WriteRC()
	case "miralib":
		_, err := fmt.Fprintln(out, i.Config.LibraryPath)
		return false, err
	case "recheck":
		i.Config.Recheck = true
		return false, i.WriteRC()
	case "norecheck":
		i.Config.Recheck = false
		return false, i.WriteRC()
	case "s", "settings":
		return false, i.printSettings(out)
	case "V":
		_, err := fmt.Fprintf(out, "Miranda release %s (Go, %s/%s)\n", VersionString(), goruntime.GOOS, goruntime.GOARCH)
		return false, err
	case "find":
		if len(fields) == 1 {
			return false, fmt.Errorf("\aextra characters at end of command")
		}
		for _, name := range fields[1:] {
			if err := i.printNames(out, true, name); err != nil {
				return false, err
			}
		}
		return false, nil
	case "m", "man":
		return false, i.runManual(out)
	case "edit", "e":
		return false, i.editCommand(fields[1:], out)
	case "editor":
		return false, i.editorCommand(fields[1:], out)
	default:
		return false, fmt.Errorf("\aunknown command - type /h for help")
	}
	return false, fmt.Errorf("\aunknown command - type /h for help")
}

var diagnosticLocationPattern = regexp.MustCompile(`^(?:(.*):)?([0-9]+):([0-9]+):`)

func (i *Interpreter) recordError(path string, err error) {
	if err == nil {
		return
	}
	match := diagnosticLocationPattern.FindStringSubmatch(err.Error())
	if match == nil {
		return
	}
	line, _ := strconv.Atoi(match[2])
	column, _ := strconv.Atoi(match[3])
	if match[1] != "" {
		path = match[1]
	}
	if absolute, absoluteErr := filepath.Abs(path); absoluteErr == nil {
		path = absolute
	}
	if i.Repl.Errors == nil {
		i.Repl.Errors = map[string]ErrorLocation{}
	}
	i.Repl.Errors[path] = ErrorLocation{Path: path, Line: line, Column: column}
}

func (i *Interpreter) recordLoadResult(path string, err error) {
	absolute, absoluteErr := filepath.Abs(path)
	if absoluteErr == nil {
		path = absolute
	}
	if err != nil {
		i.recordError(path, err)
		return
	}
	delete(i.Repl.Errors, path)
}

func (i *Interpreter) heapCommand(arguments []string, out io.Writer) error {
	if len(arguments) == 0 {
		_, err := fmt.Fprintf(out, "%d cells", i.Config.HeapCells)
		if i.Config.HeapCells != DefaultConfig().HeapCells {
			_, _ = fmt.Fprintf(out, " (default=%d)", DefaultConfig().HeapCells)
		}
		_, _ = fmt.Fprintln(out)
		return err
	}
	if len(arguments) != 1 {
		return fmt.Errorf("illegal value (heap unchanged)")
	}
	value, err := strconv.Atoi(arguments[0])
	if err != nil || value < 100 || value > 50000000 {
		return fmt.Errorf("illegal value (heap unchanged)")
	}
	if value < i.Heap.LiveCount() {
		return fmt.Errorf("sorry, cannot shrink heap to %d at this time", value)
	}
	i.Config.HeapCells = value
	if _, err = fmt.Fprintf(out, "heaplimit = %d cells\n", value); err != nil {
		return err
	}
	return i.WriteRC()
}

func (i *Interpreter) printSettings(out io.Writer) error {
	list := "no"
	if i.Config.List {
		list = ""
	}
	recheck := "no"
	if i.Config.Recheck {
		recheck = ""
	}
	if _, err := fmt.Fprintf(out, "*\theap %d\n*\tdic %d\n*\teditor = %s\n*\t%slist\n*\t%srecheck\n", i.Config.HeapCells, i.Config.DictionaryCells, i.Config.Editor, list, recheck); err != nil {
		return err
	}
	if !i.Config.StrictIf {
		fmt.Fprintln(out, "\t-nostrictif (deprecated!)")
	}
	if i.Config.Count {
		fmt.Fprintln(out, "\tcount")
	}
	if i.Config.GC {
		fmt.Fprintln(out, "\tgc")
	}
	if i.Config.UTF8 {
		fmt.Fprintln(out, "\tUTF-8 i/o")
	}
	if i.Config.Hush {
		fmt.Fprintln(out, "\thush")
	}
	_, err := fmt.Fprintln(out, "\n* items remembered between sessions")
	return err
}

func legacyEvaluationError(err error) string {
	var typeErr semantics.TypeError
	if errors.As(err, &typeErr) {
		return "type error in expression\n" + typeErr.Message
	}
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
	var mismatch *languageTypeMismatch
	if errors.As(err, &mismatch) {
		return fmt.Sprintf("type error in expression\ncannot unify %s with %s", mismatch.actual, mismatch.expected)
	}
	if err.Error() == "list expected" {
		return "type error in expression\ncannot unify ? with [*]"
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
	return semantics.FormatType(t)
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
