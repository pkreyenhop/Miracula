package devtools

import (
	"os"
	"testing"
)

func TestJustify(t *testing.T) {
	if got := Justify("alpha beta gamma delta\n", 16, 3); got != "alpha beta gamma\ndelta\n" {
		t.Fatalf("%q", got)
	}
}
func TestMenuHelpers(t *testing.T) {
	if ShellQuote("a'b") != "'a'\\''b'" {
		t.Fatal(ShellQuote("a'b"))
	}
	if !IsOwnerExecutable(os.FileMode(0700)) || IsOwnerExecutable(os.FileMode(0600)) {
		t.Fatal("mode")
	}
}
func TestEpoch(t *testing.T) {
	if EpochDate(0) != "1 January 1970" {
		t.Fatal(EpochDate(0))
	}
}
