package commandapp

import "testing"

func TestParse(t *testing.T) {
	c, ok := Parse("/editor file.m")
	if !ok || c.Name != "editor" || len(c.Arguments) != 1 {
		t.Fatal(c, ok)
	}
	if !IsQuit(ParsedCommand{Name: "q"}) {
		t.Fatal("quit")
	}
}
