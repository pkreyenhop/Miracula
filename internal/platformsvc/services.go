//go:build darwin || linux

package platformsvc

import (
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"syscall"
	"time"
)

type NativeServices struct{}

func (NativeServices) Metadata(path string) (FileMetadata, bool) { return GetFileInfo(path) }
func (NativeServices) Terminal(fd uint32) TerminalInfo {
	interactive := IsTerminal(uintptr(fd))
	rows, columns, ok := TerminalSize(uintptr(fd))
	if !ok {
		return TerminalInfo{Interactive: interactive}
	}
	return TerminalInfo{Interactive: interactive, Columns: &columns, Rows: &rows}
}
func (NativeServices) Monotonic() time.Duration               { return time.Duration(MonotonicNs()) }
func (NativeServices) Environment(name string) (string, bool) { return os.LookupEnv(name) }
func (NativeServices) FindExecutable(name string) (string, bool) {
	path, e := exec.LookPath(name)
	return path, e == nil
}
func (NativeServices) Run(request ProcessRequest) (ProcessOutcome, error) {
	ctx := request.Context
	if ctx == nil {
		ctx = context.Background()
	}
	cmd := exec.CommandContext(ctx, request.Executable, request.Arguments...)
	cmd.Dir = request.WorkingDirectory
	if request.InheritEnvironment {
		cmd.Env = os.Environ()
	}
	cmd.Stdin = streamReader(request.Stdin, os.Stdin)
	cmd.Stdout = streamWriter(request.Stdout, os.Stdout)
	cmd.Stderr = streamWriter(request.Stderr, os.Stderr)
	e := cmd.Run()
	if e == nil {
		return Exited(0), nil
	}
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return ProcessOutcome{}, ErrTimedOut
	}
	if errors.Is(ctx.Err(), context.Canceled) {
		return ProcessOutcome{}, ErrProcessInterrupted
	}
	var ee *exec.ExitError
	if !errors.As(e, &ee) {
		return ProcessOutcome{}, ErrSpawnFailed
	}
	status, ok := ee.Sys().(syscall.WaitStatus)
	if !ok {
		return ProcessOutcome{}, ErrWaitFailed
	}
	if status.Signaled() {
		return Signaled(uint8(status.Signal())), nil
	}
	return Exited(uint8(status.ExitStatus())), nil
}
func streamReader(mode StreamMode, in *os.File) io.Reader {
	switch mode {
	case StreamDiscard:
		return nil
	default:
		return in
	}
}
func streamWriter(mode StreamMode, out *os.File) io.Writer {
	switch mode {
	case StreamDiscard:
		return io.Discard
	default:
		return out
	}
}

var _ Services = NativeServices{}
