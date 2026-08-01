package graphstore

import "github.com/pkreyenhop/miracula/internal/protocol"

type StringTable struct {
	values []string
	ids    map[string]protocol.StringID
	limit  int
	used   int
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
	if t.limit > 0 && t.used+len(value) > t.limit {
		return 0
	}
	t.values = append(t.values, value)
	t.ids[value] = id
	t.used += len(value)
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
func (t *StringTable) Reset() { t.values = nil; t.ids = nil; t.used = 0 }
func (t *StringTable) SetLimit(limit int) bool {
	if limit < t.used {
		return false
	}
	t.limit = limit
	return true
}
func (t *StringTable) Limit() int { return t.limit }
func (t *StringTable) Used() int  { return t.used }
