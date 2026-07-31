//go:build darwin && arm64

package platformsvc

import (
	"errors"
	"os"
	"os/signal"
	"syscall"
)

var ErrRegistrationFailed = errors.New("signal registration failed")

type Registration struct {
	native          os.Signal
	previousIgnored bool
}

func Register(s Signal, action SignalAction, notify func()) (Registration, error) {
	native := signalNumber(s)
	r := Registration{native: native, previousIgnored: signal.Ignored(native)}
	switch action {
	case SignalIgnore:
		signal.Ignore(native)
	case SignalDefault:
		signal.Reset(native)
	case SignalNotify:
		if notify == nil {
			return Registration{}, ErrRegistrationFailed
		}
		ch := make(chan os.Signal, 1)
		signal.Notify(ch, native)
		go func() {
			for range ch {
				notify()
			}
		}()
	}
	return r, nil
}
func (r Registration) Restore() {
	signal.Reset(r.native)
	if r.previousIgnored {
		signal.Ignore(r.native)
	}
}
func signalNumber(s Signal) os.Signal {
	if s == SignalTerminate {
		return syscall.SIGTERM
	}
	return syscall.SIGINT
}
