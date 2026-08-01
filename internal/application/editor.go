package application

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"unicode/utf8"

	"github.com/pkreyenhop/miracula/internal/platformsvc"
)

type LineEditor interface {
	ReadLine(prompt string) (string, error)
	Close() error
}

type terminalLineEditor struct {
	input  *bufio.Reader
	output io.Writer
	file   *os.File
	state  platformsvc.TerminalState
	raw    bool
}

func NewLineEditor(input io.Reader, output io.Writer) (LineEditor, error) {
	editor := &terminalLineEditor{input: bufio.NewReader(input), output: output}
	if file, ok := input.(*os.File); ok && platformsvc.IsTerminal(file.Fd()) {
		state, err := platformsvc.MakeRaw(file.Fd())
		if err != nil {
			return nil, err
		}
		editor.file, editor.state, editor.raw = file, state, true
	}
	return editor, nil
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
			return string(line), nil
		case 1: // Ctrl-A
			cursor = 0
		case 5: // Ctrl-E
			cursor = len(line)
		case 11: // Ctrl-K
			line = line[:cursor]
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
		case 27:
			a, _ := e.input.ReadByte()
			b2, _ := e.input.ReadByte()
			if a == '[' {
				switch b2 {
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

func OpenEditor(ctx context.Context, editor, path string, line, column int) error {
	return exec.CommandContext(ctx, editor, path).Run()
}
