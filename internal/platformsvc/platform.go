//go:build darwin && arm64

package platformsvc

import (
	"bytes"
	"context"
	"errors"
	"os"
	"os/exec"
	"syscall"
	"time"
	"unsafe"
)

func CaptureShell(ctx context.Context, command string) (string, string, int, error) {
	cmd := exec.CommandContext(ctx, ShellFallbackPath, ShellCommandArgument, command)
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	err := cmd.Run()
	if err == nil {
		return stdout.String(), stderr.String(), 0, nil
	}
	var exit *exec.ExitError
	if errors.As(err, &exit) {
		return stdout.String(), stderr.String(), exit.ExitCode(), nil
	}
	return "", "", 0, ErrSpawnFailed
}

func GetFileInfo(path string) (FileMetadata, bool) {
	i, e := os.Stat(path)
	if e != nil {
		return FileMetadata{}, false
	}
	s, ok := i.Sys().(*syscall.Stat_t)
	if !ok {
		return FileMetadata{}, false
	}
	return FileMetadata{Identity: FileIdentity{Device: uint64(s.Dev), Inode: uint64(s.Ino)}, ModifiedSeconds: i.ModTime().Unix(), Mode: uint32(i.Mode().Perm()), Owner: s.Uid, Group: s.Gid}, true
}
func Geteuid() uint32    { return uint32(os.Geteuid()) }
func Getegid() uint32    { return uint32(os.Getegid()) }
func MonotonicNs() int64 { return time.Since(processStart).Nanoseconds() }

var processStart = time.Now()

func IsTerminal(fd uintptr) bool {
	var term [72]byte
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd, syscall.TIOCGETA, uintptr(unsafe.Pointer(&term[0])))
	return errno == 0
}
func TerminalWidth(fd uintptr) (uint16, bool) {
	var size struct{ Row, Col, XPixel, YPixel uint16 }
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd, syscall.TIOCGWINSZ, uintptr(unsafe.Pointer(&size)))
	if errno != 0 || size.Col == 0 {
		return 0, false
	}
	return size.Col, true
}

func MakeRaw(fd uintptr) (TerminalState, error) {
	var state TerminalState
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd, syscall.TIOCGETA, uintptr(unsafe.Pointer(&state.termios[0])))
	if errno != 0 {
		return TerminalState{}, errno
	}
	raw := state.termios
	// Darwin termios stores input, output, control, and local flags in the
	// first four uint64-compatible slots. Disable canonical input and echo while
	// retaining signal generation so Ctrl-C still reaches the interpreter.
	flags := (*[4]uint64)(unsafe.Pointer(&raw[0]))
	flags[3] &^= uint64(syscall.ICANON | syscall.ECHO)
	raw[32+syscall.VMIN] = 1
	raw[32+syscall.VTIME] = 0
	_, _, errno = syscall.Syscall(syscall.SYS_IOCTL, fd, syscall.TIOCSETA, uintptr(unsafe.Pointer(&raw[0])))
	if errno != 0 {
		return TerminalState{}, errno
	}
	return state, nil
}

func RestoreTerminal(fd uintptr, state TerminalState) error {
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd, syscall.TIOCSETA, uintptr(unsafe.Pointer(&state.termios[0])))
	if errno != 0 {
		return errno
	}
	return nil
}
func RunShell(ctx context.Context, shell, command string) (ProcessOutcome, error) {
	if shell == "" {
		shell = ShellFallbackPath
	}
	cmd := exec.CommandContext(ctx, shell, ShellCommandArgument, command)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	e := cmd.Run()
	if e == nil {
		return Exited(0), nil
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
	code := status.ExitStatus()
	if code < 0 {
		return ProcessOutcome{}, ErrWaitFailed
	}
	if code > 255 {
		code = 255
	}
	return Exited(uint8(code)), nil
}
