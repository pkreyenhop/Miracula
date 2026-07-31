package syntaxfront

import "testing"

func TestSourceLiterateAndPositions(t *testing.T) {
	s := NewSource([]byte("prose\n> x = 1\n"), true)
	if string(s.Bytes) != "     \n  x = 1\n" {
		t.Fatalf("%q", s.Bytes)
	}
	p := s.Position(8)
	if p.Line != 2 || p.Column != 3 {
		t.Fatal(p)
	}
}
func TestLexerFamilies(t *testing.T) {
	tokens := Lex(NewSource([]byte(`x = 1 + 2.0 : ['a', "x"]; y = x div 2`), false))
	want := []string{"name", "eq", "const_int", "plus", "const_float", "cons", "lbracket", "const_char", "comma", "const_str", "rbracket", "semicolon", "name", "eq", "name", "kw_div", "const_int", "eof"}
	if len(tokens) != len(want) {
		t.Fatalf("got %d tokens", len(tokens))
	}
	for i, k := range want {
		if tokens[i].Kind != k {
			t.Fatalf("token %d = %s, want %s", i, tokens[i].Kind, k)
		}
	}
}
