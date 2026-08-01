package application

import (
	"testing"
	"time"
)

func TestFormatExecutionTime(t *testing.T) {
	tests := []struct {
		elapsed time.Duration
		want    string
	}{
		{123456 * time.Nanosecond, "0.123ms"},
		{1689 * time.Microsecond, "1.69ms"},
		{275500 * time.Microsecond, "275.50ms"},
		{1234567 * time.Microsecond, "1.235s"},
	}
	for _, test := range tests {
		if got := formatExecutionTime(test.elapsed); got != test.want {
			t.Errorf("formatExecutionTime(%s) = %q, want %q", test.elapsed, got, test.want)
		}
	}
}

func TestReplPromptIncludesCollectionCount(t *testing.T) {
	i := New(nil)
	i.Config.Prompt = "Miranda "
	elapsed := 16890 * time.Microsecond
	collections := 1
	i.Repl.LastElapsed = &elapsed
	i.Repl.LastGC = &collections
	if got := i.replPrompt(); got != "[16.89ms, 1 GC] Miranda " {
		t.Fatalf("prompt = %q", got)
	}
	collections = 10
	if got := i.replPrompt(); got != "[16.89ms, 10 GCs] Miranda " {
		t.Fatalf("prompt = %q", got)
	}
	i.Config.Hush = true
	if got := i.replPrompt(); got != "" {
		t.Fatalf("hushed prompt = %q", got)
	}
}

func TestReplSessionClearTiming(t *testing.T) {
	elapsed := time.Millisecond
	collections := 2
	session := ReplSession{LastElapsed: &elapsed, LastGC: &collections}
	session.clearTiming()
	if session.LastElapsed != nil || session.LastGC != nil {
		t.Fatalf("timing not cleared: %+v", session)
	}
}
