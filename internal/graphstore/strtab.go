package graphstore

import "github.com/pkreyenhop/miracula-go/internal/protocol"

type StringTable struct {
	values []string
	ids    map[string]protocol.StringID
}

func (t *StringTable) init() {
	if t.ids == nil {
		t.values = []string{""}
		t.ids = map[string]protocol.StringID{"": 0}
	}
}
func (t *StringTable) Intern(value string) protocol.Word {
	if value == "" {
		return 0
	}
	t.init()
	if id, ok := t.ids[value]; ok {
		return protocol.Word(id.ToStored())
	}
	id := protocol.StringID(len(t.values))
	t.values = append(t.values, value)
	t.ids[value] = id
	return protocol.Word(id.ToStored())
}
func (t *StringTable) Resolve(handle protocol.Word) string {
	if handle >= 0 {
		return ""
	}
	t.init()
	id, ok := protocol.StringIDFromStored(int64(handle))
	if !ok || int(id) >= len(t.values) {
		return ""
	}
	return t.values[id]
}
func (t *StringTable) Privatize(handle protocol.Word) protocol.Word {
	s := t.Resolve(handle)
	if s == "" {
		return handle
	}
	b := []byte(s)
	b[0] |= 0x80
	return t.Intern(string(b))
}
func (t *StringTable) Reset() { t.values = nil; t.ids = nil }
