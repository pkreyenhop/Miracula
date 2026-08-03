//go:build darwin

package platformsvc

import (
	"syscall"
	"unsafe"
)

func IsTerminal(fd uintptr) bool {
	var term syscall.Termios
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd, syscall.TIOCGETA, uintptr(unsafe.Pointer(&term)))
	return errno == 0
}

func MakeRaw(fd uintptr) (TerminalState, error) {
	var state TerminalState
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd, syscall.TIOCGETA, uintptr(unsafe.Pointer(&state.termios)))
	if errno != 0 {
		return TerminalState{}, errno
	}
	raw := state.termios
	raw.Lflag &^= uint64(syscall.ICANON | syscall.ECHO)
	raw.Cc[syscall.VMIN] = 1
	raw.Cc[syscall.VTIME] = 0
	_, _, errno = syscall.Syscall(syscall.SYS_IOCTL, fd, syscall.TIOCSETA, uintptr(unsafe.Pointer(&raw)))
	if errno != 0 {
		return TerminalState{}, errno
	}
	return state, nil
}

func RestoreTerminal(fd uintptr, state TerminalState) error {
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd, syscall.TIOCSETA, uintptr(unsafe.Pointer(&state.termios)))
	if errno != 0 {
		return errno
	}
	return nil
}
