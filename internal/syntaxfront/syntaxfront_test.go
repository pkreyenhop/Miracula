package syntaxfront

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

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

func TestDirectivesHaveExplicitOwners(t *testing.T) {
	for _, test := range []struct{ text, variant string }{
		{`%include <ex/set> new/old -hidden`, "include"}, {`%insert "body.m"`, "insert"},
		{`%export + -private`, "export"}, {`%free { f::num }`, "free"},
		{`%list`, "list"}, {`%nolist`, "nolist"}, {`%bnf`, "bnf"}, {`%lex`, "lex"},
		{`%mystery`, "unknown"},
	} {
		directive, ok := ParseDirective(test.text)
		if !ok || directive.Variant != test.variant {
			t.Errorf("%q => %+v, %v", test.text, directive, ok)
		}
	}
}

func TestLoadSourceExpandsNestedInsert(t *testing.T) {
	directory := t.TempDir()
	if err := os.Mkdir(filepath.Join(directory, "nested"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "main.m"), []byte("%insert \"a.m\"\nc = b+1\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "a.m"), []byte("%insert \"nested/b.m\"\na = b\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "nested/b.m"), []byte("b = 1\n"), 0600); err != nil {
		t.Fatal(err)
	}
	source, diagnostics := LoadSource(filepath.Join(directory, "main.m"))
	if len(diagnostics) != 0 {
		t.Fatal(diagnostics)
	}
	if string(source.Bytes) != "b = 1\na = b\nc = b+1\n" {
		t.Fatalf("%q", source.Bytes)
	}
}

func TestInsertIndentSourceMapAndLiterateRules(t *testing.T) {
	directory := t.TempDir()
	fragment := filepath.Join(directory, "fragment")
	root := filepath.Join(directory, "root.m")
	if err := os.WriteFile(fragment, []byte("x = 1\ny = 2\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(root, []byte("f = value\n  where\n  %insert \"fragment\"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	source, diagnostics := LoadSource(root)
	if len(diagnostics) != 0 {
		t.Fatal(diagnostics)
	}
	if string(source.Bytes) != "f = value\n  where\n  x = 1\n  y = 2\n" {
		t.Fatalf("inserted source = %q", source.Bytes)
	}
	if len(source.Origins) < 4 || source.Origins[2].File != fragment || source.Origins[2].Line != 1 {
		t.Fatalf("origins = %+v", source.Origins)
	}

	literate := filepath.Join(directory, "example.lit.m")
	if err := os.WriteFile(literate, []byte("Narrative\n> x = 1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, diagnostics := LoadSource(literate); len(diagnostics) == 0 || !strings.Contains(diagnostics[0].Message, "blank line") {
		t.Fatalf("literate diagnostics = %+v", diagnostics)
	}
	if err := os.WriteFile(literate, []byte("Narrative\n\n> x = 1 _\b< 2\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	normalized, diagnostics := LoadSource(literate)
	if len(diagnostics) != 0 || !strings.Contains(string(normalized.Bytes), "x = 1 <= 2") {
		t.Fatalf("normalized=%q diagnostics=%+v", normalized.Bytes, diagnostics)
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

func TestLiteralLexicalConformance(t *testing.T) {
	tokens := Lex(NewSource([]byte("foo2' = 0x1.8p+2; bar'3 = 0o77; s = \"a\\\nb\"; c = '\\X0020ac'"), false))
	want := []string{"name", "eq", "const_float", "semicolon", "name", "eq", "const_int", "semicolon", "name", "eq", "const_str", "semicolon", "name", "eq", "const_char", "eof"}
	if len(tokens) != len(want) {
		t.Fatalf("token count = %d, want %d: %#v", len(tokens), len(want), tokens)
	}
	for index, kind := range want {
		if tokens[index].Kind != kind {
			t.Fatalf("token %d = %s, want %s", index, tokens[index].Kind, kind)
		}
	}
}

func TestParenthesizedNegativeIsNotAnOperatorSection(t *testing.T) {
	parsed := Run([]byte("value = (-12345678901234567890) + 12345678901234567880\n"))
	if len(parsed.Diagnostics) > 0 || len(parsed.Script.Items) != 1 {
		t.Fatal(parsed.Diagnostics)
	}
	left := parsed.Script.Items[0].RHS.Head
	if left == nil || left.Variant != "neg" {
		t.Fatalf("left = %#v", left)
	}
}

func BenchmarkParseSource(b *testing.B) {
	source := []byte("qsort [] = []\nqsort (a:x) = qsort [b | b <- x; b <= a] ++ [a] ++ qsort [b | b <- x; b > a]\n")
	b.ReportAllocs()
	for n := 0; n < b.N; n++ {
		result := Run(source)
		if len(result.Diagnostics) != 0 {
			b.Fatal(result.Diagnostics)
		}
	}
}
