package protocol

type CellRef uint32

func CellRefOf(x Word) (CellRef, bool) {
	if x < AtomLimit || x > 1<<32-1 {
		return 0, false
	}
	return CellRef(x), true
}
func (r CellRef) Word() Word { return Word(r) }

type ValueKind uint8

const (
	KindImmediate ValueKind = iota
	KindCombinator
	KindCell
)

type Kind struct {
	Tag        ValueKind
	Immediate  uint8
	Combinator Comb
	Cell       CellRef
}

type Value struct{ raw Word }

func ValueFromRaw(x Word) Value { return Value{raw: x} }
func (v Value) ToRaw() Word     { return v.raw }
func ValueImm(x uint8) Value    { return ValueFromRaw(Word(x)) }
func ValueComb(c Comb) Value    { return ValueFromRaw(CombinatorWord(c)) }
func ValueCell(r CellRef) Value { return ValueFromRaw(r.Word()) }
func (v Value) Kind() (Kind, bool) {
	if v.raw >= AtomLimit {
		r, ok := CellRefOf(v.raw)
		return Kind{Tag: KindCell, Cell: r}, ok
	}
	if IsLatin1Char(v.raw) {
		return Kind{Tag: KindImmediate, Immediate: uint8(v.raw)}, true
	}
	offset := v.raw - CMBase
	if offset < 0 || offset >= Word(CombinatorCount) {
		return Kind{}, false
	}
	return Kind{Tag: KindCombinator, Combinator: Comb(offset)}, true
}
