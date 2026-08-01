package main

import (
	"context"
	"errors"
	"fmt"
	"github.com/pkreyenhop/miracula-go/internal/application"
	"github.com/pkreyenhop/miracula-go/internal/commandapp"
	"github.com/pkreyenhop/miracula-go/internal/platformsvc"
	"os"
)

func main() {
	ctx := context.Background()
	command := commandapp.Command{
		Stdin: os.Stdin, Stdout: os.Stdout, Stderr: os.Stderr,
		Services: platformsvc.NativeServices{},
	}
	err := command.Run(ctx, os.Args[1:])
	if err != nil && !errors.Is(err, application.ErrEvaluationReported) {
		fmt.Fprintln(os.Stderr, err)
	}
	os.Exit(commandapp.ExitCode(err))
}
