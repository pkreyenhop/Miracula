package commandapp

import (
	"context"
	"fmt"
	"github.com/pkreyenhop/miracula-go/internal/application"
	"github.com/pkreyenhop/miracula-go/internal/buildcfg"
	"github.com/pkreyenhop/miracula-go/internal/platformsvc"
	"io"
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
	if err = i.Boot(); err != nil {
		return err
	}
	return i.REPL(ctx, c.Stdin, c.Stdout)
}

func ExitCode(err error) int {
	if err == nil {
		return 0
	}
	return 1
}
