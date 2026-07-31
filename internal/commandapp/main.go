package commandapp

import (
	"context"
	"github.com/pkreyenhop/miracula-go/internal/application"
	"github.com/pkreyenhop/miracula-go/internal/platformsvc"
	"io"
)

type Command struct {
	Stdin          io.Reader
	Stdout, Stderr io.Writer
	Services       platformsvc.Services
}

func (c Command) Run(ctx context.Context, args []string) error {
	i := application.New(c.Services)
	i.Input, i.Output, i.Error = c.Stdin, c.Stdout, c.Stderr
	if e := i.Boot(); e != nil {
		return e
	}
	return i.REPL(ctx, c.Stdin, c.Stdout)
}
