package platformsvc

import (
	"context"
	"errors"
	"time"
)

type FileIdentity struct{ Device, Inode uint64 }
type FileMetadata struct {
	Identity           FileIdentity
	ModifiedSeconds    int64
	ModifiedNanos      int64
	Size               int64
	Mode, Owner, Group uint32
}
type StreamMode uint8

const (
	StreamInherit StreamMode = iota
	StreamPipe
	StreamDiscard
)

type ProcessRequest struct {
	Context               context.Context
	Executable            string
	Arguments             []string
	WorkingDirectory      string
	InheritEnvironment    bool
	Stdin, Stdout, Stderr StreamMode
}
type ProcessOutcome struct {
	ExitCode *uint8
	Signal   *uint8
}

func Exited(code uint8) ProcessOutcome     { return ProcessOutcome{ExitCode: &code} }
func Signaled(signal uint8) ProcessOutcome { return ProcessOutcome{Signal: &signal} }

var (
	ErrSpawnFailed        = errors.New("spawn failed")
	ErrWaitFailed         = errors.New("wait failed")
	ErrTimedOut           = errors.New("timed out")
	ErrProcessInterrupted = errors.New("process interrupted")
)

const ShellFallbackPath = "/bin/sh"
const ShellCommandArgument = "-c"

type Signal uint8

const (
	SignalInterrupt Signal = iota
	SignalTerminate
)

type SignalAction uint8

const (
	SignalNotify SignalAction = iota
	SignalIgnore
	SignalDefault
)

type TerminalInfo struct {
	Interactive bool
	Columns     *uint16
	Rows        *uint16
}

type TerminalState struct {
	termios [72]byte
}

type Services interface {
	Metadata(string) (FileMetadata, bool)
	Run(ProcessRequest) (ProcessOutcome, error)
	Terminal(uint32) TerminalInfo
	Monotonic() time.Duration
	Environment(string) (string, bool)
	FindExecutable(string) (string, bool)
}
