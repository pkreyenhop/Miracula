package evaluation

import (
	"context"
	"errors"
	"github.com/pkreyenhop/miracula-go/internal/graphstore"
	"github.com/pkreyenhop/miracula-go/internal/protocol"
)

var ErrNotReducible = errors.New("not reducible")

// Reduce evaluates an application graph to weak-head normal form. Traversal is
// iterative and checks cancellation while walking arbitrarily deep spines.
func (e *Evaluator) Reduce(ctx context.Context, value protocol.Value) (protocol.Value, error) {
	if e.Heap == nil {
		return protocol.Value{}, errors.New("nil evaluation heap")
	}
	current := value.ToRaw()
	for reductions := 0; ; reductions++ {
		if reductions&255 == 0 {
			select {
			case <-ctx.Done():
				return protocol.Value{}, protocol.ErrInterrupted
			default:
			}
		}
		focus := current
		arguments := make([]protocol.Word, 0, 8)
		for steps := 0; ; steps++ {
			if steps&255 == 0 {
				select {
				case <-ctx.Done():
					return protocol.Value{}, protocol.ErrInterrupted
				default:
				}
			}
			ref, ok := protocol.CellRefOf(focus)
			if !ok {
				break
			}
			cell, ok := e.Heap.Cell(ref)
			if !ok || cell.Tag != protocol.NodeApplication {
				break
			}
			arguments = append(arguments, cell.Tail)
			focus = cell.Head
		}
		for left, right := 0, len(arguments)-1; left < right; left, right = left+1, right-1 {
			arguments[left], arguments[right] = arguments[right], arguments[left]
		}
		kind, ok := protocol.ValueFromRaw(focus).Kind()
		if !ok || kind.Tag != protocol.KindCombinator {
			return protocol.ValueFromRaw(current), nil
		}
		result, consumed, err := e.reduceCombinator(ctx, kind.Combinator, arguments)
		if err != nil {
			return protocol.Value{}, err
		}
		if consumed == 0 {
			return protocol.ValueFromRaw(current), nil
		}
		for _, argument := range arguments[consumed:] {
			ref, makeErr := e.Heap.Make(protocol.NodeApplication, result, argument)
			if makeErr != nil {
				return protocol.Value{}, makeErr
			}
			result = protocol.Word(ref)
		}
		e.Trace.Add(protocol.CombNames[kind.Combinator], "rewrite")
		current = result
	}
}

func (e *Evaluator) reduceCombinator(ctx context.Context, combinator protocol.Comb, arguments []protocol.Word) (protocol.Word, int, error) {
	require := func(count int) error {
		if len(arguments) < count {
			return ErrNotReducible
		}
		return nil
	}
	switch combinator {
	case protocol.CombI:
		if err := require(1); err != nil {
			return 0, 0, nil
		}
		return arguments[0], 1, nil
	case protocol.CombK:
		if err := require(2); err != nil {
			return 0, 0, nil
		}
		return arguments[0], 2, nil
	case protocol.CombKI:
		if err := require(2); err != nil {
			return 0, 0, nil
		}
		return arguments[1], 2, nil
	case protocol.CombB:
		if err := require(3); err != nil {
			return 0, 0, nil
		}
		gx, err := e.application(arguments[1], arguments[2])
		if err != nil {
			return 0, 0, err
		}
		result, err := e.application(arguments[0], gx)
		return result, 3, err
	case protocol.CombC:
		if err := require(3); err != nil {
			return 0, 0, nil
		}
		fx, err := e.application(arguments[0], arguments[2])
		if err != nil {
			return 0, 0, err
		}
		result, err := e.application(fx, arguments[1])
		return result, 3, err
	case protocol.CombCB:
		if err := require(3); err != nil {
			return 0, 0, nil
		}
		fx, err := e.application(arguments[0], arguments[2])
		if err != nil {
			return 0, 0, err
		}
		result, err := e.application(arguments[1], fx)
		return result, 3, err
	case protocol.CombS:
		if err := require(3); err != nil {
			return 0, 0, nil
		}
		fx, err := e.application(arguments[0], arguments[2])
		if err != nil {
			return 0, 0, err
		}
		gx, err := e.application(arguments[1], arguments[2])
		if err != nil {
			return 0, 0, err
		}
		result, err := e.application(fx, gx)
		return result, 3, err
	case protocol.CombP:
		if err := require(2); err != nil {
			return 0, 0, nil
		}
		ref, err := e.Heap.Cons(arguments[0], arguments[1])
		return protocol.Word(ref), 2, err
	case protocol.CombCOND:
		if err := require(3); err != nil {
			return 0, 0, nil
		}
		truth, err := e.truth(ctx, arguments[0])
		if err != nil {
			return 0, 0, err
		}
		if truth {
			return arguments[1], 3, nil
		}
		return arguments[2], 3, nil
	case protocol.CombNOT:
		if err := require(1); err != nil {
			return 0, 0, nil
		}
		truth, err := e.truth(ctx, arguments[0])
		if err != nil {
			return 0, 0, err
		}
		return booleanWord(!truth), 1, nil
	case protocol.CombAND, protocol.CombOR:
		if err := require(2); err != nil {
			return 0, 0, nil
		}
		left, err := e.truth(ctx, arguments[0])
		if err != nil {
			return 0, 0, err
		}
		if combinator == protocol.CombAND && !left {
			return booleanWord(false), 2, nil
		}
		if combinator == protocol.CombOR && left {
			return booleanWord(true), 2, nil
		}
		right, err := e.truth(ctx, arguments[1])
		if err != nil {
			return 0, 0, err
		}
		if combinator == protocol.CombAND {
			return booleanWord(left && right), 2, nil
		}
		return booleanWord(left || right), 2, nil
	case protocol.CombNEG:
		if err := require(1); err != nil {
			return 0, 0, nil
		}
		number, err := e.integer(ctx, arguments[0])
		if err != nil {
			return 0, 0, err
		}
		return e.boxInteger(-number, 1)
	case protocol.CombEQ, protocol.CombNEQ, protocol.CombGR, protocol.CombGRE:
		if err := require(2); err != nil {
			return 0, 0, nil
		}
		left, err := e.integer(ctx, arguments[0])
		if err != nil {
			return 0, 0, err
		}
		right, err := e.integer(ctx, arguments[1])
		if err != nil {
			return 0, 0, err
		}
		truth := false
		switch combinator {
		case protocol.CombEQ:
			truth = left == right
		case protocol.CombNEQ:
			truth = left != right
		case protocol.CombGR:
			truth = left > right
		case protocol.CombGRE:
			truth = left >= right
		}
		return booleanWord(truth), 2, nil
	case protocol.CombHD, protocol.CombTL:
		if err := require(1); err != nil {
			return 0, 0, nil
		}
		list, err := e.Reduce(ctx, protocol.ValueFromRaw(arguments[0]))
		if err != nil {
			return 0, 0, err
		}
		ref, ok := protocol.CellRefOf(list.ToRaw())
		if !ok {
			return 0, 0, errors.New("list expected")
		}
		cell, ok := e.Heap.Cell(ref)
		if !ok || cell.Tag != protocol.NodeCons {
			return 0, 0, errors.New("non-empty list expected")
		}
		if combinator == protocol.CombHD {
			return cell.Head, 1, nil
		}
		return cell.Tail, 1, nil
	case protocol.CombLENGTH:
		if err := require(1); err != nil {
			return 0, 0, nil
		}
		length, cursor := int64(0), arguments[0]
		for cursor != protocol.Nil {
			select {
			case <-ctx.Done():
				return 0, 0, protocol.ErrInterrupted
			default:
			}
			value, err := e.Reduce(ctx, protocol.ValueFromRaw(cursor))
			if err != nil {
				return 0, 0, err
			}
			ref, ok := protocol.CellRefOf(value.ToRaw())
			if !ok {
				return 0, 0, errors.New("list expected")
			}
			cell, ok := e.Heap.Cell(ref)
			if !ok || cell.Tag != protocol.NodeCons {
				return 0, 0, errors.New("list expected")
			}
			length++
			cursor = cell.Tail
		}
		ref, err := e.Heap.Make(protocol.NodeInteger, protocol.Word(length), 0)
		return protocol.Word(ref), 1, err
	case protocol.CombDROP:
		if err := require(2); err != nil {
			return 0, 0, nil
		}
		count, err := e.integer(ctx, arguments[0])
		if err != nil {
			return 0, 0, err
		}
		cursor := arguments[1]
		for count > 0 {
			cell, nextErr := e.listCell(ctx, cursor)
			if nextErr != nil {
				return 0, 0, nextErr
			}
			cursor = cell.Tail
			count--
		}
		return cursor, 2, nil
	case protocol.CombSUBSCRIPT:
		if err := require(2); err != nil {
			return 0, 0, nil
		}
		index, err := e.integer(ctx, arguments[1])
		if err != nil {
			return 0, 0, err
		}
		if index < 0 {
			return 0, 0, errors.New("subscript out of range")
		}
		cursor := arguments[0]
		for index > 0 {
			cell, nextErr := e.listCell(ctx, cursor)
			if nextErr != nil {
				return 0, 0, nextErr
			}
			cursor = cell.Tail
			index--
		}
		cell, err := e.listCell(ctx, cursor)
		if err != nil {
			return 0, 0, err
		}
		return cell.Head, 2, nil
	case protocol.CombTAKE:
		if err := require(2); err != nil {
			return 0, 0, nil
		}
		count, err := e.integer(ctx, arguments[0])
		if err != nil {
			return 0, 0, err
		}
		if count <= 0 {
			return protocol.Nil, 2, nil
		}
		cursor := arguments[1]
		heads := make([]protocol.Word, 0, count)
		for count > 0 && cursor != protocol.Nil {
			cell, nextErr := e.listCell(ctx, cursor)
			if nextErr != nil {
				return 0, 0, nextErr
			}
			heads = append(heads, cell.Head)
			cursor = cell.Tail
			count--
		}
		result := protocol.Nil
		for index := len(heads) - 1; index >= 0; index-- {
			ref, makeErr := e.Heap.Cons(heads[index], result)
			if makeErr != nil {
				return 0, 0, makeErr
			}
			result = protocol.Word(ref)
		}
		return result, 2, nil
	case protocol.CombMAP:
		if err := require(2); err != nil {
			return 0, 0, nil
		}
		return e.mapList(ctx, arguments[0], arguments[1], 2)
	case protocol.CombAPPEND:
		if err := require(2); err != nil {
			return 0, 0, nil
		}
		heads, err := e.listHeads(ctx, arguments[0])
		if err != nil {
			return 0, 0, err
		}
		result := arguments[1]
		for index := len(heads) - 1; index >= 0; index-- {
			ref, makeErr := e.Heap.Cons(heads[index], result)
			if makeErr != nil {
				return 0, 0, makeErr
			}
			result = protocol.Word(ref)
		}
		return result, 2, nil
	case protocol.CombPLUS, protocol.CombMINUS, protocol.CombTIMES, protocol.CombINTDIV, protocol.CombMOD:
		if err := require(2); err != nil {
			return 0, 0, nil
		}
		left, err := e.integer(ctx, arguments[0])
		if err != nil {
			return 0, 0, err
		}
		right, err := e.integer(ctx, arguments[1])
		if err != nil {
			return 0, 0, err
		}
		var result int64
		switch combinator {
		case protocol.CombPLUS:
			result = left + right
		case protocol.CombMINUS:
			result = left - right
		case protocol.CombTIMES:
			result = left * right
		case protocol.CombINTDIV:
			if right == 0 {
				return 0, 0, ErrDivisionByZero
			}
			result = floorDiv(left, right)
		case protocol.CombMOD:
			if right == 0 {
				return 0, 0, ErrDivisionByZero
			}
			result = left - floorDiv(left, right)*right
		}
		ref, err := e.Heap.Make(protocol.NodeInteger, protocol.Word(result), 0)
		return protocol.Word(ref), 2, err
	default:
		return 0, 0, nil
	}
}

func (e *Evaluator) application(function, argument protocol.Word) (protocol.Word, error) {
	ref, err := e.Heap.Make(protocol.NodeApplication, function, argument)
	return protocol.Word(ref), err
}

func (e *Evaluator) boxInteger(value int64, consumed int) (protocol.Word, int, error) {
	ref, err := e.Heap.Make(protocol.NodeInteger, protocol.Word(value), 0)
	return protocol.Word(ref), consumed, err
}
func booleanWord(value bool) protocol.Word {
	if value {
		return protocol.CombinatorWord(protocol.CombTrue)
	}
	return protocol.CombinatorWord(protocol.CombFalse)
}
func (e *Evaluator) truth(ctx context.Context, value protocol.Word) (bool, error) {
	reduced, err := e.Reduce(ctx, protocol.ValueFromRaw(value))
	if err != nil {
		return false, err
	}
	switch reduced.ToRaw() {
	case protocol.CombinatorWord(protocol.CombTrue):
		return true, nil
	case protocol.CombinatorWord(protocol.CombFalse):
		return false, nil
	default:
		return false, errors.New("truthvalue expected")
	}
}
func (e *Evaluator) listCell(ctx context.Context, value protocol.Word) (graphstore.Cell, error) {
	reduced, err := e.Reduce(ctx, protocol.ValueFromRaw(value))
	if err != nil {
		return graphstore.Cell{}, err
	}
	if reduced.ToRaw() == protocol.Nil {
		return graphstore.Cell{}, errors.New("non-empty list expected")
	}
	ref, ok := protocol.CellRefOf(reduced.ToRaw())
	if !ok {
		return graphstore.Cell{}, errors.New("list expected")
	}
	cell, ok := e.Heap.Cell(ref)
	if !ok || cell.Tag != protocol.NodeCons {
		return graphstore.Cell{}, errors.New("list expected")
	}
	return cell, nil
}
func (e *Evaluator) listHeads(ctx context.Context, value protocol.Word) ([]protocol.Word, error) {
	var heads []protocol.Word
	cursor := value
	for cursor != protocol.Nil {
		select {
		case <-ctx.Done():
			return nil, protocol.ErrInterrupted
		default:
		}
		cell, err := e.listCell(ctx, cursor)
		if err != nil {
			return nil, err
		}
		heads = append(heads, cell.Head)
		cursor = cell.Tail
	}
	return heads, nil
}
func (e *Evaluator) mapList(ctx context.Context, function, list protocol.Word, consumed int) (protocol.Word, int, error) {
	heads, err := e.listHeads(ctx, list)
	if err != nil {
		return 0, 0, err
	}
	result := protocol.Nil
	for index := len(heads) - 1; index >= 0; index-- {
		mapped, makeErr := e.application(function, heads[index])
		if makeErr != nil {
			return 0, 0, makeErr
		}
		ref, makeErr := e.Heap.Cons(mapped, result)
		if makeErr != nil {
			return 0, 0, makeErr
		}
		result = protocol.Word(ref)
	}
	return result, consumed, nil
}

func (e *Evaluator) integer(ctx context.Context, value protocol.Word) (int64, error) {
	reduced, err := e.Reduce(ctx, protocol.ValueFromRaw(value))
	if err != nil {
		return 0, err
	}
	ref, ok := protocol.CellRefOf(reduced.ToRaw())
	if !ok {
		return int64(reduced.ToRaw()), nil
	}
	cell, ok := e.Heap.Cell(ref)
	if !ok || cell.Tag != protocol.NodeInteger {
		return 0, errors.New("number expected")
	}
	return int64(cell.Head), nil
}

func floorDiv(left, right int64) int64 {
	quotient, remainder := left/right, left%right
	if remainder != 0 && (remainder < 0) != (right < 0) {
		quotient--
	}
	return quotient
}
