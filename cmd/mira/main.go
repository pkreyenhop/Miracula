package main

import (
	"context"
	"fmt"
	"github.com/pkreyenhop/miracula-go/internal/commandapp"
	"github.com/pkreyenhop/miracula-go/internal/platformsvc"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	command := commandapp.Command{
		Stdin: os.Stdin, Stdout: os.Stdout, Stderr: os.Stderr,
		Services: platformsvc.NativeServices{},
	}
	err := command.Run(ctx, os.Args[1:])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
	}
	os.Exit(commandapp.ExitCode(err))
}
