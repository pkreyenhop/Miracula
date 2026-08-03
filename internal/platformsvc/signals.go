//go:build darwin || linux

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
	channel         chan os.Signal
	done            chan struct{}
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
		done := make(chan struct{})
		signal.Notify(ch, native)
		r.channel = ch
		r.done = done
		go func() {
			defer close(done)
			for range ch {
				notify()
			}
		}()
	}
	return r, nil
}
func (r *Registration) Restore() {
	if r.channel != nil {
		signal.Stop(r.channel)
		close(r.channel)
		<-r.done
		r.channel = nil
		r.done = nil
	}
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
