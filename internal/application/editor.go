package application

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/pkreyenhop/miracula/internal/platformsvc"
)

type LineEditor interface {
	ReadLine(prompt string) (string, error)
	ReadKey(prompt string) (byte, error)
	ReadChoice(prompt string) (string, error)
	SetCompleter(func(string) []string)
	LoadHistory(path string) error
	SaveHistory() error
	Suspend() error
	Resume() error
	Close() error
}

type terminalLineEditor struct {
	input       *bufio.Reader
	output      io.Writer
	file        *os.File
	state       platformsvc.TerminalState
	raw         bool
	terminal    bool
	history     []string
	historyPath string
	complete    func(string) []string
}

func (e *terminalLineEditor) SetCompleter(complete func(string) []string) {
	e.complete = complete
}

func (e *terminalLineEditor) LoadHistory(path string) error {
	e.historyPath = path
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	for _, line := range strings.Split(strings.TrimSuffix(string(data), "\n"), "\n") {
		if line != "" {
			e.history = append(e.history, line)
		}
	}
	return nil
}

func (e *terminalLineEditor) SaveHistory() error {
	if e.historyPath == "" {
		return nil
	}
	data := []byte(strings.Join(e.history, "\n"))
	if len(data) != 0 {
		data = append(data, '\n')
	}
	return platformsvc.AtomicReplace(e.historyPath, data, 0o600)
}

func NewLineEditor(input io.Reader, output io.Writer) (LineEditor, error) {
	editor := &terminalLineEditor{input: bufio.NewReader(input), output: output}
	if file, ok := input.(*os.File); ok && platformsvc.IsTerminal(file.Fd()) {
		state, err := platformsvc.MakeRaw(file.Fd())
		if err != nil {
			return nil, err
		}
		editor.file, editor.state, editor.raw = file, state, true
		editor.terminal = true
	}
	return editor, nil
}

func (e *terminalLineEditor) Suspend() error {
	if !e.raw {
		return nil
	}
	if err := platformsvc.RestoreTerminal(e.file.Fd(), e.state); err != nil {
		return err
	}
	e.raw = false
	return nil
}

func (e *terminalLineEditor) Resume() error {
	if !e.terminal || e.raw {
		return nil
	}
	state, err := platformsvc.MakeRaw(e.file.Fd())
	if err != nil {
		return err
	}
	e.state, e.raw = state, true
	return nil
}

func (e *terminalLineEditor) Close() error {
	if !e.raw {
		return nil
	}
	e.raw = false
	return platformsvc.RestoreTerminal(e.file.Fd(), e.state)
}

func (e *terminalLineEditor) ReadLine(prompt string) (string, error) {
	if _, err := io.WriteString(e.output, prompt); err != nil {
		return "", err
	}
	var line []rune
	cursor := 0
	historyIndex := len(e.history)
	var draft []rune
	redraw := func() error {
		if _, err := fmt.Fprintf(e.output, "\r\x1b[2K%s%s", prompt, string(line)); err != nil {
			return err
		}
		if back := len(line) - cursor; back > 0 {
			_, err := fmt.Fprintf(e.output, "\x1b[%dD", back)
			return err
		}
		return nil
	}
	for {
		b, err := e.input.ReadByte()
		if err != nil {
			if errors.Is(err, io.EOF) && len(line) != 0 {
				return string(line), nil
			}
			return "", err
		}
		switch b {
		case '\r', '\n':
			if e.raw {
				_, _ = io.WriteString(e.output, "\r\n")
			}
			result := string(line)
			if result != "" {
				e.history = append(e.history, result)
			}
			return result, nil
		case 1: // Ctrl-A
			cursor = 0
		case 5: // Ctrl-E
			cursor = len(line)
		case 11: // Ctrl-K
			line = line[:cursor]
		case 20: // Ctrl-T
			if len(line) > 1 && cursor > 0 {
				left := cursor - 1
				if cursor == len(line) {
					left--
				}
				line[left], line[left+1] = line[left+1], line[left]
				if cursor < len(line) {
					cursor++
				}
			}
		case 4: // Ctrl-D
			if len(line) == 0 {
				return "", io.EOF
			}
			if cursor < len(line) {
				line = append(line[:cursor], line[cursor+1:]...)
			}
		case 8, 127:
			if cursor > 0 {
				line = append(line[:cursor-1], line[cursor:]...)
				cursor--
			}
		case '\t':
			prefix, ok := identifierPrefix(line, cursor)
			if ok && e.complete != nil {
				matches := e.complete(prefix)
				if len(matches) == 1 {
					suffix := []rune(strings.TrimPrefix(matches[0], prefix))
					line = append(line, make([]rune, len(suffix))...)
					copy(line[cursor+len(suffix):], line[cursor:len(line)-len(suffix)])
					copy(line[cursor:], suffix)
					cursor += len(suffix)
				} else if len(matches) > 1 {
					_, _ = fmt.Fprintf(e.output, "\r\n%s\r\n", strings.Join(matches, "  "))
				}
			}
		case 27:
			a, _ := e.input.ReadByte()
			if a == 'b' {
				for cursor > 0 && line[cursor-1] == ' ' {
					cursor--
				}
				for cursor > 0 && isIdentifierRune(line[cursor-1]) {
					cursor--
				}
			} else if a == 'f' {
				for cursor < len(line) && isIdentifierRune(line[cursor]) {
					cursor++
				}
				for cursor < len(line) && line[cursor] == ' ' {
					cursor++
				}
			} else if a == '[' {
				b2, _ := e.input.ReadByte()
				switch b2 {
				case 'A':
					if historyIndex == len(e.history) {
						draft = append(draft[:0], line...)
					}
					if historyIndex > 0 {
						historyIndex--
						line = []rune(e.history[historyIndex])
						cursor = len(line)
					}
				case 'B':
					if historyIndex < len(e.history) {
						historyIndex++
						if historyIndex == len(e.history) {
							line = append(line[:0], draft...)
						} else {
							line = []rune(e.history[historyIndex])
						}
						cursor = len(line)
					}
				case 'D':
					if cursor > 0 {
						cursor--
					}
				case 'C':
					if cursor < len(line) {
						cursor++
					}
				case 'H':
					cursor = 0
				case 'F':
					cursor = len(line)
				case '3':
					_, _ = e.input.ReadByte()
					if cursor < len(line) {
						line = append(line[:cursor], line[cursor+1:]...)
					}
				}
			}
		default:
			var r rune
			if b < utf8.RuneSelf {
				r = rune(b)
			} else {
				_ = e.input.UnreadByte()
				r, _, err = e.input.ReadRune()
				if err != nil {
					return "", err
				}
			}
			line = append(line, 0)
			copy(line[cursor+1:], line[cursor:])
			line[cursor] = r
			cursor++
		}
		if err := redraw(); err != nil {
			return "", err
		}
	}
}

func (e *terminalLineEditor) ReadKey(prompt string) (byte, error) {
	if _, err := io.WriteString(e.output, prompt); err != nil {
		return 0, err
	}
	return e.input.ReadByte()
}

// ReadChoice is a line read which also recognizes a standalone Escape. It is
// used by modal menus without changing Escape handling in the normal REPL.
func (e *terminalLineEditor) ReadChoice(prompt string) (string, error) {
	if _, err := io.WriteString(e.output, prompt); err != nil {
		return "", err
	}
	key, err := e.input.ReadByte()
	if err != nil {
		return "", err
	}
	if key == 27 {
		if e.raw {
			_, _ = io.WriteString(e.output, "\r\n")
		}
		return "\x1b", nil
	}
	if err = e.input.UnreadByte(); err != nil {
		return "", err
	}
	return e.ReadLine("")
}

func identifierPrefix(line []rune, cursor int) (string, bool) {
	start := cursor
	for start > 0 && isIdentifierRune(line[start-1]) {
		start--
	}
	if start == cursor {
		return "", false
	}
	for _, r := range line[start:cursor] {
		if r > unicode.MaxASCII {
			return "", false
		}
	}
	return string(line[start:cursor]), true
}

func isIdentifierRune(r rune) bool {
	return r <= unicode.MaxASCII && (r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '_' || r == '\'')
}

func editorCommandTemplate(template, path string, line, column int) string {
	quotedPath := `"` + strings.NewReplacer(`\`, `\\`, `"`, `\"`).Replace(path) + `"`
	var command strings.Builder
	hasFile := false
	for index := 0; index < len(template); index++ {
		character := template[index]
		if character == '\\' && index+1 < len(template) && strings.ContainsRune("!%&", rune(template[index+1])) {
			index++
			command.WriteByte(template[index])
			continue
		}
		switch character {
		case '!':
			command.WriteString(strconv.Itoa(line))
		case '&':
			command.WriteString(strconv.Itoa(column))
		case '%':
			command.WriteString(quotedPath)
			hasFile = true
		default:
			command.WriteByte(character)
		}
	}
	if !hasFile {
		if command.Len() != 0 && !strings.HasSuffix(command.String(), " ") {
			command.WriteByte(' ')
		}
		command.WriteString(quotedPath)
	}
	return command.String()
}

func (i *Interpreter) editCommand(arguments []string, out io.Writer) error {
	if len(arguments) > 1 {
		return fmt.Errorf("usage: /edit [file]")
	}
	path := i.Compiler.CurrentModule
	if len(arguments) == 1 {
		path = arguments[0]
		if filepath.Ext(path) == "" {
			path += ".m"
		}
	}
	if path == "" {
		return fmt.Errorf("no current script")
	}
	absolute, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	if _, err = os.Stat(absolute); errors.Is(err, os.ErrNotExist) {
		header := ""
		if home, ok := i.Services.Environment("HOME"); ok {
			candidate := filepath.Join(home, ".mirahdr")
			if _, statErr := os.Stat(candidate); statErr == nil {
				header = candidate
			}
		}
		if header == "" {
			candidate := filepath.Join(i.Config.LibraryPath, ".mirahdr")
			if _, statErr := os.Stat(candidate); statErr == nil {
				header = candidate
			}
		}
		if header != "" && absolute != i.Compiler.CurrentModule {
			if i.activeEditor == nil {
				return fmt.Errorf("cannot confirm creation outside an interactive session")
			}
			answer, readErr := i.activeEditor.ReadLine(fmt.Sprintf("open new script %q? [ny]", absolute))
			if readErr != nil || len(answer) == 0 || answer[0] != 'y' && answer[0] != 'Y' {
				return readErr
			}
		}
		if header != "" {
			if err = platformsvc.CopyFile(header, absolute); err != nil {
				return err
			}
		}
	} else if err != nil {
		return err
	}
	before, beforeOK := i.Services.Metadata(absolute)
	line, column := 1, 1
	if location, ok := i.Repl.Errors[absolute]; ok {
		if i.Config.BadEditor {
			if err = i.editorWarning(out); err != nil {
				return err
			}
		} else {
			line, column = location.Line, location.Column
		}
	}
	command := editorCommandTemplate(i.Config.Editor, absolute, line, column)
	if i.activeEditor != nil {
		if err = i.activeEditor.Suspend(); err != nil {
			return err
		}
		defer i.activeEditor.Resume()
	}
	_, err = i.Services.Run(platformsvc.ProcessRequest{Context: context.Background(), Executable: platformsvc.ShellFallbackPath, Arguments: []string{platformsvc.ShellCommandArgument, command}, InheritEnvironment: true, Stdin: platformsvc.StreamInherit, Stdout: platformsvc.StreamInherit, Stderr: platformsvc.StreamInherit})
	if err != nil {
		return err
	}
	after, afterOK := i.Services.Metadata(absolute)
	if afterOK && (!beforeOK || after != before) {
		err = i.reloadEditedProgram(absolute, out)
	}
	return err
}

func (i *Interpreter) reloadEditedProgram(path string, out io.Writer) error {
	display := path
	if workingDirectory, err := os.Getwd(); err == nil {
		if relative, relativeErr := filepath.Rel(workingDirectory, path); relativeErr == nil {
			display = relative
		}
	}
	fmt.Fprintf(out, "compiling %s\nchecking types in %s\n", display, display)
	_, loadErr := i.LoadProgram(path)
	i.recordLoadResult(path, loadErr)
	if loadErr != nil {
		return loadErr
	}
	firstErrorLine := 0
	if typeErr := i.ValidateCurrentTypes(); typeErr != nil {
		var sourceTypeErrors SourceTypeErrors
		if !errors.As(typeErr, &sourceTypeErrors) || len(sourceTypeErrors) == 0 {
			return typeErr
		}
		if i.Repl.Errors == nil {
			i.Repl.Errors = map[string]ErrorLocation{}
		}
		firstErrorLine = sourceTypeErrors[0].Line
		absolute, _ := filepath.Abs(sourceTypeErrors[0].Path)
		i.Repl.Errors[absolute] = ErrorLocation{Path: absolute, Line: firstErrorLine, Column: 1}
		for _, sourceTypeErr := range sourceTypeErrors {
			if _, err := fmt.Fprintf(out, "type error in definition of %s\n(line %3d of %q) %s\n", sourceTypeErr.Definition, sourceTypeErr.Line, display, sourceTypeErr.Error()); err != nil {
				return err
			}
		}
	}
	validationErr := i.ValidateCurrent()
	var sourceErrors SourceValidationErrors
	if errors.As(validationErr, &sourceErrors) && len(sourceErrors) != 0 {
		if i.Repl.Errors == nil {
			i.Repl.Errors = map[string]ErrorLocation{}
		}
		first := sourceErrors[0]
		if firstErrorLine == 0 || first.Line < firstErrorLine {
			absolute, _ := filepath.Abs(first.Path)
			i.Repl.Errors[absolute] = ErrorLocation{Path: absolute, Line: first.Line, Column: 1}
		}
		for _, sourceErr := range sourceErrors {
			if _, err := fmt.Fprintf(out, "(line %3d of %q) undefined name %q\n", sourceErr.Line, display, sourceErr.Name); err != nil {
				return err
			}
		}
		return nil
	}
	return validationErr
}

func (i *Interpreter) editorCommand(arguments []string, out io.Writer) error {
	if len(arguments) == 0 {
		_, err := fmt.Fprintln(out, i.Config.Editor)
		return err
	}
	name := strings.Join(arguments, " ")
	if name[0] == '"' || name[0] == '\'' {
		return fmt.Errorf("please type name of editor without quotation marks")
	}
	if i.activeEditor == nil {
		return fmt.Errorf("cannot confirm editor change outside an interactive session")
	}
	answer, err := i.activeEditor.ReadLine(fmt.Sprintf("change editor to: %q? [ny]", name))
	if err != nil {
		return err
	}
	if len(answer) == 0 || answer[0] != 'y' && answer[0] != 'Y' {
		_, err = fmt.Fprintln(out, "editor not changed")
		return err
	}
	i.Config.Editor = name
	i.Config.BadEditor = EditorCannotOpenAtLine(name)
	if err = i.WriteRC(); err != nil {
		return err
	}
	_, err = fmt.Fprintln(out, "editor = "+name)
	return err
}

func (i *Interpreter) editorWarning(out io.Writer) error {
	_, err := fmt.Fprintf(out, "The currently installed editor command, %q, does not\ninclude a facility for opening a file at a specified line number.  As a\nresult the `??' command and certain other features of the Miranda system\nare disabled.  See manual section 31/5 on changing the editor for more\ninformation.\n", i.Config.Editor)
	return err
}
