package application

type Config struct {
	LibraryPath, Editor string
	HeapCells           int
	UTF8, Strict        bool
}

func DefaultConfig() Config { return Config{LibraryPath: "./miralib", HeapCells: 1250000, UTF8: true} }
