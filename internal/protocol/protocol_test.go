package protocol

import (
	"errors"
	"math"
	"testing"
)

func TestSemanticIDs(t *testing.T) {
	id, ok := StringIDFromStored(-7)
	if !ok || id != 7 || id.ToStored() != -7 {
		t.Fatal(id, ok)
	}
	if _, ok = StringIDFromStored(7); ok {
		t.Fatal("positive stored ID accepted")
	}
}
func TestValues(t *testing.T) {
	v := ValueComb(CombPLUS)
	k, ok := v.Kind()
	if !ok || k.Tag != KindCombinator || k.Combinator != CombPLUS {
		t.Fatal(k, ok)
	}
	if _, ok = ValueFromRaw(300).Kind(); ok {
		t.Fatal("token accepted as runtime value")
	}
}
func TestXCodec(t *testing.T) {
	b := make([]byte, 32)
	w := NewWriter(b)
	_ = w.WriteWord(-2)
	_ = w.WriteI32(-0x1020304)
	_ = w.WriteDouble(math.Copysign(0, -1))
	r := NewReader(w.Written())
	if v, _ := r.ReadWord(); v != -2 {
		t.Fatal(v)
	}
	if v, _ := r.ReadI32(); v != -0x1020304 {
		t.Fatal(v)
	}
	if v, _ := r.ReadDouble(); math.Float64bits(v) != 1<<63 {
		t.Fatal(v)
	}
	if err := r.Finish(); err != nil {
		t.Fatal(err)
	}
	if _, err := DecodeTag(190); !errors.Is(err, ErrInvalidTag) {
		t.Fatal(err)
	}
}
