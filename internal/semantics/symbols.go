package semantics

type SymbolID uint32
type Symbol struct {
	ID       SymbolID
	Name     string
	Exported bool
}
type SymbolTable struct {
	byName  map[string]SymbolID
	symbols []Symbol
}

func (t *SymbolTable) Intern(name string) SymbolID {
	if t.byName == nil {
		t.byName = map[string]SymbolID{}
	}
	if id, ok := t.byName[name]; ok {
		return id
	}
	id := SymbolID(len(t.symbols))
	t.byName[name] = id
	t.symbols = append(t.symbols, Symbol{id, name, false})
	return id
}
func (t *SymbolTable) Find(name string) (Symbol, bool) {
	id, ok := t.byName[name]
	if !ok {
		return Symbol{}, false
	}
	return t.symbols[id], true
}
func (t *SymbolTable) Export(id SymbolID) { t.symbols[id].Exported = true }
func (t *SymbolTable) Symbols() []Symbol  { return append([]Symbol(nil), t.symbols...) }
