package semantics

import "testing"

func TestParseAndFormatMirandaTypes(t *testing.T) {
	for _, text := range []string{
		"num->num->num",
		"(*->**)->[*]->[**]",
		"(num,bool,[char])",
		"tree *->tree *",
		"()",
	} {
		value, err := ParseType(text)
		if err != nil {
			t.Fatalf("ParseType(%q): %v", text, err)
		}
		if got := FormatType(value); got != text {
			t.Fatalf("ParseType(%q) formatted as %q", text, got)
		}
	}
}
