package graphstore

import (
	"errors"
	"github.com/pkreyenhop/miracula-go/internal/protocol"
)

type StreamID uint32

func StreamIDFromWord(w protocol.Word) (StreamID, bool) {
	if w <= 0 || w > 1<<32-1 {
		return 0, false
	}
	return StreamID(w), true
}
func (id StreamID) Word() protocol.Word { return protocol.Word(id) }

var (
	ErrResourceMissing   = errors.New("resource missing")
	ErrResourceClosed    = errors.New("resource closed")
	ErrResourceWrongKind = errors.New("wrong resource kind")
)

type resourceEntry struct {
	stream     *Stream
	closed     bool
	generation uint64
}
type ResourceCheckpoint struct{ generation uint64 }
type ResourceTable struct {
	entries    map[StreamID]*resourceEntry
	next       StreamID
	generation uint64
}

func (t *ResourceTable) RegisterStream(s *Stream) StreamID {
	if t.entries == nil {
		t.entries = make(map[StreamID]*resourceEntry)
		if t.next == 0 {
			t.next = 1
		}
	}
	id := t.next
	t.next++
	t.generation++
	t.entries[id] = &resourceEntry{stream: s, generation: t.generation}
	return id
}
func (t *ResourceTable) ResolveStream(id StreamID) (*Stream, error) {
	e, ok := t.entries[id]
	if !ok {
		return nil, ErrResourceMissing
	}
	if e.closed {
		return nil, ErrResourceClosed
	}
	if e.stream == nil {
		return nil, ErrResourceWrongKind
	}
	return e.stream, nil
}
func (t *ResourceTable) CloseStream(id StreamID) error {
	e, ok := t.entries[id]
	if !ok {
		return ErrResourceMissing
	}
	if e.closed {
		return ErrResourceClosed
	}
	e.closed = true
	return e.stream.Close()
}
func (t *ResourceTable) Checkpoint() ResourceCheckpoint { return ResourceCheckpoint{t.generation} }
func (t *ResourceTable) Restore(c ResourceCheckpoint) {
	for id, e := range t.entries {
		if e.generation > c.generation {
			if !e.closed && e.stream != nil {
				_ = e.stream.Close()
			}
			delete(t.entries, id)
		}
	}
	t.generation = c.generation
}
func (t *ResourceTable) Reset() {
	for _, e := range t.entries {
		if !e.closed && e.stream != nil {
			_ = e.stream.Close()
		}
	}
	t.entries = nil
	t.generation++
}
