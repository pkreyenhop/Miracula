package application

import "time"

type ReplSession struct {
	Prompt        string
	LastCommand   string
	ExitRequested bool
	LastElapsed   *time.Duration
	LastGC        *int
	Errors        map[string]ErrorLocation
}

type ErrorLocation struct {
	Path         string
	Line, Column int
}

func (s *ReplSession) clearTiming() {
	s.LastElapsed = nil
	s.LastGC = nil
}
