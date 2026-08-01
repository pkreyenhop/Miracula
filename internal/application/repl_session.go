package application

import (
	"time"

	"github.com/pkreyenhop/miracula/internal/semantics"
)

type ReplSession struct {
	Prompt             string
	LastCommand        string
	LastShellCommand   string
	LastExpressionType *semantics.Type
	ExitRequested      bool
	ExitStatus         int
	LastElapsed        *time.Duration
	LastGC             *int
	Errors             map[string]ErrorLocation
	Diagnostics        DiagnosticSet
}

type ErrorLocation struct {
	Path         string
	Line, Column int
}

func (s *ReplSession) clearTiming() {
	s.LastElapsed = nil
	s.LastGC = nil
}
