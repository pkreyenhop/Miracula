package evaluation

import (
	"context"
	"fmt"
	"github.com/pkreyenhop/miracula-go/internal/protocol"
	"strconv"
	"strings"
)

// Render reduces and formats the graph forms owned by the runtime. The node
// budget prevents malformed or cyclic values from producing unbounded output.
func (e *Evaluator) Render(ctx context.Context, value protocol.Value, budget int) (string, error) {
	if budget <= 0 {
		budget = 100000
	}
	seen := map[protocol.CellRef]bool{}
	var render func(protocol.Word, int) (string, error)
	render = func(word protocol.Word, remaining int) (string, error) {
		if remaining <= 0 {
			return "", errorsNew("output limit exceeded")
		}
		reduced, err := e.Reduce(ctx, protocol.ValueFromRaw(word))
		if err != nil {
			return "", err
		}
		word = reduced.ToRaw()
		if word == protocol.Nil {
			return "[]", nil
		}
		kind, ok := protocol.ValueFromRaw(word).Kind()
		if ok && kind.Tag == protocol.KindImmediate {
			return strconv.QuoteRune(rune(kind.Immediate)), nil
		}
		ref, ok := protocol.CellRefOf(word)
		if !ok {
			return fmt.Sprintf("%d", word), nil
		}
		if seen[ref] {
			return "...", nil
		}
		seen[ref] = true
		defer delete(seen, ref)
		cell, ok := e.Heap.Cell(ref)
		if !ok {
			return "", errorsNew("invalid graph cell")
		}
		switch cell.Tag {
		case protocol.NodeInteger:
			return fmt.Sprintf("%d", cell.Head), nil
		case protocol.NodeCons:
			var items []string
			cursor := word
			for cursor != protocol.Nil {
				if remaining-len(items) <= 0 {
					return "", errorsNew("output limit exceeded")
				}
				current, ok := protocol.CellRefOf(cursor)
				if !ok {
					tail, err := render(cursor, remaining-len(items))
					if err != nil {
						return "", err
					}
					return "[" + strings.Join(items, ",") + "|" + tail + "]", nil
				}
				cons, ok := e.Heap.Cell(current)
				if !ok || cons.Tag != protocol.NodeCons {
					tail, err := render(cursor, remaining-len(items))
					if err != nil {
						return "", err
					}
					return "[" + strings.Join(items, ",") + "|" + tail + "]", nil
				}
				item, err := render(cons.Head, remaining-len(items)-1)
				if err != nil {
					return "", err
				}
				items = append(items, item)
				cursor = cons.Tail
			}
			return "[" + strings.Join(items, ",") + "]", nil
		default:
			return fmt.Sprintf("<%s>", protocolTag(cell.Tag)), nil
		}
	}
	return render(value.ToRaw(), budget)
}

type renderError string

func (e renderError) Error() string           { return string(e) }
func errorsNew(value string) error            { return renderError(value) }
func protocolTag(tag protocol.NodeTag) string { return fmt.Sprintf("node:%d", tag) }
