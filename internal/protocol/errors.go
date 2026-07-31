package protocol

import (
	"errors"
	"fmt"
)

var (
	ErrSyntax                = errors.New("syntax error")
	ErrTypeCheckAbort        = errors.New("type check aborted")
	ErrHeapExhausted         = errors.New("heap exhausted")
	ErrLoad                  = errors.New("load error")
	ErrEvaluationInterrupted = errors.New("evaluation interrupted")
)

// FatalError is returned to the command boundary, which owns printing and exit.
type FatalError struct{ Message string }

func (e FatalError) Error() string { return e.Message }
func NewFatal(format string, args ...any) error {
	return FatalError{Message: fmt.Sprintf(format, args...)}
}
