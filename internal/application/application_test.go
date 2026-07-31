package application

import (
	"bytes"
	"context"
	"github.com/pkreyenhop/miracula-go/internal/platformsvc"
	"strings"
	"testing"
)

func TestInterpreterIsolation(t *testing.T) {
	a, b := New(platformsvc.NativeServices{}), New(platformsvc.NativeServices{})
	a.Strings.Intern("a")
	if b.Strings.Resolve(-1) != "" {
		t.Fatal("state leaked")
	}
}
func TestREPLQuit(t *testing.T) {
	i := New(platformsvc.NativeServices{})
	var out bytes.Buffer
	if e := i.REPL(context.Background(), strings.NewReader("/q\n"), &out); e != nil {
		t.Fatal(e)
	}
}
