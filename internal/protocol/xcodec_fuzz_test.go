package protocol

import (
	"math"
	"testing"
)

func FuzzXCodecScalars(f *testing.F) {
	f.Add(int64(0), uint32(0), uint16(0), uint64(0))
	f.Add(int64(-1), ^uint32(0), ^uint16(0), math.Float64bits(math.Inf(1)))
	f.Fuzz(func(t *testing.T, word int64, integer uint32, short uint16, floatBits uint64) {
		buffer := make([]byte, 22)
		writer := NewWriter(buffer)
		if err := writer.WriteWord(word); err != nil {
			t.Fatal(err)
		}
		if err := writer.WriteI32(int32(integer)); err != nil {
			t.Fatal(err)
		}
		if err := writer.WriteU16(short); err != nil {
			t.Fatal(err)
		}
		if err := writer.WriteDouble(math.Float64frombits(floatBits)); err != nil {
			t.Fatal(err)
		}
		reader := NewReader(writer.Written())
		gotWord, err := reader.ReadWord()
		if err != nil || gotWord != word {
			t.Fatalf("word %d %v", gotWord, err)
		}
		gotInteger, err := reader.ReadI32()
		if err != nil || gotInteger != int32(integer) {
			t.Fatalf("integer %d %v", gotInteger, err)
		}
		gotShort, err := reader.ReadU16()
		if err != nil || gotShort != short {
			t.Fatalf("short %d %v", gotShort, err)
		}
		gotFloat, err := reader.ReadDouble()
		if err != nil || math.Float64bits(gotFloat) != floatBits {
			t.Fatalf("float %x %v", math.Float64bits(gotFloat), err)
		}
		if err := reader.Finish(); err != nil {
			t.Fatal(err)
		}
	})
}

func FuzzXCodecRejectsShortScalars(f *testing.F) {
	f.Add([]byte{})
	f.Add([]byte{1, 2, 3, 4, 5, 6, 7})
	f.Fuzz(func(t *testing.T, data []byte) {
		if len(data) >= XWordBytes {
			t.Skip()
		}
		if _, err := NewReader(data).ReadWord(); err == nil {
			t.Fatal("short word accepted")
		}
	})
}
