package devtools

import (
	"os"
	"strings"
)

func ShellQuote(value string) string          { return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'" }
func IsOwnerExecutable(mode os.FileMode) bool { return mode&0100 != 0 }

type MenuDriver struct {
	Viewer, MenuViewer string
	ReturnToMenu       bool
	History            []string
}

func DefaultMenuDriver() MenuDriver {
	return MenuDriver{Viewer: "less", MenuViewer: "cat", ReturnToMenu: true}
}
