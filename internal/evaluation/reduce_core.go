package evaluation

import (
	"errors"
	"github.com/pkreyenhop/miracula-go/internal/graphstore"
	"github.com/pkreyenhop/miracula-go/internal/protocol"
)

var ErrDivisionByZero = errors.New("division by zero")

type Evaluator struct {
	Heap  *graphstore.Heap
	Trace Trace
}

func (e *Evaluator) Apply(function protocol.Value, args ...protocol.Value) (protocol.Value, error) {
	kind, ok := function.Kind()
	if !ok || kind.Tag != protocol.KindCombinator {
		return protocol.Value{}, errors.New("not a combinator")
	}
	switch kind.Combinator {
	case protocol.CombI:
		if len(args) < 1 {
			return protocol.Value{}, errors.New("missing argument")
		}
		return args[0], nil
	case protocol.CombK:
		if len(args) < 2 {
			return protocol.Value{}, errors.New("missing argument")
		}
		return args[0], nil
	case protocol.CombPLUS:
		return integerBinary(args, func(a, b int64) (int64, error) { return a + b, nil })
	case protocol.CombMINUS:
		return integerBinary(args, func(a, b int64) (int64, error) { return a - b, nil })
	case protocol.CombTIMES:
		return integerBinary(args, func(a, b int64) (int64, error) { return a * b, nil })
	case protocol.CombINTDIV:
		return integerBinary(args, func(a, b int64) (int64, error) {
			if b == 0 {
				return 0, ErrDivisionByZero
			}
			return floorDiv(a, b), nil
		})
	case protocol.CombMOD:
		return integerBinary(args, func(a, b int64) (int64, error) {
			if b == 0 {
				return 0, ErrDivisionByZero
			}
			return a - floorDiv(a, b)*b, nil
		})
	}
	return protocol.Value{}, errors.New("unimplemented combinator")
}
func integerBinary(args []protocol.Value, op func(int64, int64) (int64, error)) (protocol.Value, error) {
	if len(args) < 2 {
		return protocol.Value{}, errors.New("missing argument")
	}
	a, b := int64(args[0].ToRaw()), int64(args[1].ToRaw())
	v, e := op(a, b)
	if e != nil {
		return protocol.Value{}, e
	}
	if v >= 0 && v < 256 {
		return protocol.ValueImm(uint8(v)), nil
	}
	return protocol.ValueFromRaw(protocol.Word(v)), nil
}
