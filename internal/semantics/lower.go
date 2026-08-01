package semantics

import (
	"fmt"
	"github.com/pkreyenhop/miracula/internal/graphstore"
	"github.com/pkreyenhop/miracula/internal/protocol"
	"github.com/pkreyenhop/miracula/internal/syntaxfront"
	"strconv"
)

// Lower converts every executable definition to an interpreter-owned graph.
// A failed definition restores the heap to its entry checkpoint.
func Lower(script syntaxfront.Script, heap *graphstore.Heap) ([]int, error) {
	checkpoint := heap.Checkpoint()
	roots := make([]int, 0, len(script.Items))
	for _, definition := range script.Items {
		if definition.Variant != "definition" {
			continue
		}
		word, err := lowerExpr(definition.RHS, heap)
		if err != nil {
			heap.Restore(checkpoint)
			return nil, err
		}
		ref, ok := protocol.CellRefOf(word)
		if !ok {
			ref, err = heap.Make(protocol.NodeAtom, word, protocol.Nil)
			if err != nil {
				heap.Restore(checkpoint)
				return nil, err
			}
		}
		roots = append(roots, int(ref))
	}
	return roots, nil
}

func lowerExpr(expression syntaxfront.Expr, heap *graphstore.Heap) (protocol.Word, error) {
	switch expression.Variant {
	case "int":
		value, err := strconv.ParseInt(expression.Text, 0, 64)
		if err != nil {
			return 0, err
		}
		ref, err := heap.Make(protocol.NodeInteger, protocol.Word(value), 0)
		return protocol.Word(ref), err
	case "name", "constructor", "string", "char", "float", "token", "raw":
		if code, ok := PrimitiveCombinator(expression.Text); ok {
			return protocol.CombinatorWord(protocol.Comb(code)), nil
		}
		ref, err := heap.Make(protocol.NodeIdentifier, protocol.Word(hashName(expression.Text)), 0)
		return protocol.Word(ref), err
	case "application":
		function, err := lowerExpr(*expression.Func, heap)
		if err != nil {
			return 0, err
		}
		argument, err := lowerExpr(*expression.Arg, heap)
		if err != nil {
			return 0, err
		}
		ref, err := heap.Make(protocol.NodeApplication, function, argument)
		return protocol.Word(ref), err
	case "infix":
		left, err := lowerExpr(*expression.Head, heap)
		if err != nil {
			return 0, err
		}
		right, err := lowerExpr(*expression.Tail, heap)
		if err != nil {
			return 0, err
		}
		operator, err := lowerExpr(syntaxfront.Expr{Variant: "name", Text: expression.Text}, heap)
		if err != nil {
			return 0, err
		}
		first, err := heap.Make(protocol.NodeApplication, operator, left)
		if err != nil {
			return 0, err
		}
		second, err := heap.Make(protocol.NodeApplication, protocol.Word(first), right)
		return protocol.Word(second), err
	case "list", "tuple":
		tail := protocol.Nil
		for index := len(expression.Items) - 1; index >= 0; index-- {
			head, err := lowerExpr(expression.Items[index], heap)
			if err != nil {
				return 0, err
			}
			ref, err := heap.Cons(head, tail)
			if err != nil {
				return 0, err
			}
			tail = protocol.Word(ref)
		}
		return tail, nil
	default:
		return 0, fmt.Errorf("cannot lower %s", expression.Variant)
	}
}

func hashName(name string) uint64 {
	var hash uint64 = 1469598103934665603
	for i := 0; i < len(name); i++ {
		hash ^= uint64(name[i])
		hash *= 1099511628211
	}
	return hash & (1<<63 - 1)
}
