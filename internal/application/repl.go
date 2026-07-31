package application

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"strings"
)

func (i *Interpreter) REPL(ctx context.Context, in io.Reader, out io.Writer) error {
	s := bufio.NewScanner(in)
	for {
		if _, e := fmt.Fprint(out, "Miranda "); e != nil {
			return e
		}
		if !s.Scan() {
			return s.Err()
		}
		line := strings.TrimSpace(s.Text())
		if line == "/q" || line == "/quit" {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		if line != "" {
			if _, e := fmt.Fprintln(out, line); e != nil {
				return e
			}
		}
	}
}
