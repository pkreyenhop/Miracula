package application

import "strings"

type Config struct {
	LibraryPath, Editor, Prompt string
	RCPath                      string
	HeapCells, DictionaryCells  int
	UTF8, Strict, StrictIf      bool
	Count, List, GC, Object     bool
	NoStdEnv, Hush, Recheck     bool
	BadEditor                   bool
}

func EditorCannotOpenAtLine(editor string) bool {
	return !strings.Contains(editor, "+!") && !strings.Contains(editor, "%d") && !strings.Contains(editor, "%l")
}

func DefaultConfig() Config {
	return Config{
		LibraryPath: "./lib/miralib", Editor: "vi +!", Prompt: "Miranda ",
		HeapCells: 1250000, DictionaryCells: 100000, UTF8: true, StrictIf: true,
	}
}
