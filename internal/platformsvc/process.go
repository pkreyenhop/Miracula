//go:build darwin && arm64

package platformsvc

import "syscall"

type ProcessID int
type ForkResult struct {
	Child  bool
	Parent ProcessID
}

func ForkProcess() (ForkResult, error) { return ForkResult{}, ErrSpawnFailed }
func WaitChild(id ProcessID) (ProcessOutcome, error) {
	var status syscall.WaitStatus
	pid, e := syscall.Wait4(int(id), &status, 0, nil)
	if e != nil || pid != int(id) {
		return ProcessOutcome{}, ErrWaitFailed
	}
	if status.Exited() {
		return Exited(uint8(status.ExitStatus())), nil
	}
	if status.Signaled() {
		return Signaled(uint8(status.Signal())), nil
	}
	return ProcessOutcome{}, ErrWaitFailed
}
