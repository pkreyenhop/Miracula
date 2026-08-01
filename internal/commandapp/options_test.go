package commandapp

import (
	"github.com/pkreyenhop/miracula/internal/application"
	"testing"
)

func TestParseOptions(t *testing.T) {
	opts, err := ParseOptions([]string{"-lib", "/library", "-heap", "2000", "-dic", "3000", "-hush", "script"}, application.DefaultConfig())
	if err != nil {
		t.Fatal(err)
	}
	if opts.Config.LibraryPath != "/library" || opts.Config.HeapCells != 2000 || opts.Config.DictionaryCells != 3000 || !opts.Config.Hush || opts.Script != "script" {
		t.Fatalf("unexpected options: %+v", opts)
	}
}

func TestParseOptionsFailures(t *testing.T) {
	tests := []struct {
		args []string
		want string
	}{
		{[]string{"-unknown"}, `mira: unknown flag "-unknown"`},
		{[]string{"-lib"}, `mira: missing param after flag "lib"`},
		{[]string{"-heap", "99"}, `mira: bad value after flag "-heap"`},
		{[]string{"one", "two"}, "mira: too many args"},
	}
	for _, test := range tests {
		_, err := ParseOptions(test.args, application.DefaultConfig())
		if err == nil || err.Error() != test.want {
			t.Errorf("ParseOptions(%q) error = %v, want %q", test.args, err, test.want)
		}
	}
}

func TestExecPreservesScriptArguments(t *testing.T) {
	opts, err := ParseOptions([]string{"-exec", "program.m", "a", "b"}, application.DefaultConfig())
	if err != nil {
		t.Fatal(err)
	}
	if opts.Mode != ModeExec || opts.Script != "program.m" || len(opts.ScriptArgs) != 2 {
		t.Fatalf("unexpected exec options: %+v", opts)
	}
}
