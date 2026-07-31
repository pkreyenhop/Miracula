package application

import "sync/atomic"

type RuntimeState struct {
	Interrupted atomic.Bool
	Reductions  uint64
}
