package application

type Config struct {
	LibraryPath, Editor, Prompt string
	HeapCells, DictionaryCells  int
	UTF8, Strict, StrictIf      bool
	Count, List, GC, Object     bool
	NoStdEnv, Hush, Recheck     bool
}

func DefaultConfig() Config {
	return Config{
		LibraryPath: "./miralib", Editor: "vi +!", Prompt: "Miranda ",
		HeapCells: 1250000, DictionaryCells: 100000, UTF8: true, StrictIf: true,
	}
}
