package graphstore

import "github.com/pkreyenhop/miracula-go/internal/protocol"

type rootEntry func(func(protocol.Word))
type Registry struct{ entries []rootEntry }
type Guard struct {
	registry *Registry
	depth    int
	active   bool
}

func (r *Registry) Root(value *protocol.Word) Guard {
	r.entries = append(r.entries, func(mark func(protocol.Word)) { mark(*value) })
	return Guard{r, len(r.entries), true}
}
func (r *Registry) RootSlice(values []protocol.Word) Guard {
	r.entries = append(r.entries, func(mark func(protocol.Word)) {
		for _, v := range values {
			mark(v)
		}
	})
	return Guard{r, len(r.entries), true}
}
func (r *Registry) MarkAll(mark func(protocol.Word)) {
	for _, entry := range r.entries {
		entry(mark)
	}
}
func (g *Guard) Close() {
	if !g.active {
		return
	}
	if len(g.registry.entries) != g.depth {
		panic("graphstore: roots released out of order")
	}
	g.registry.entries = g.registry.entries[:g.depth-1]
	g.active = false
}
func (r *Registry) Reset() {
	if len(r.entries) != 0 {
		panic("graphstore: active roots during reset")
	}
	r.entries = nil
}
