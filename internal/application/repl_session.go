package application

import "time"

type ReplSession struct {
	Prompt        string
	LastCommand   string
	ExitRequested bool
	LastElapsed   *time.Duration
	LastGC        *int
}

func (s *ReplSession) clearTiming() {
	s.LastElapsed = nil
	s.LastGC = nil
}
