package application

import (
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"strings"
)

func (i *Interpreter) resolveSessionPath(raw string) (string, error) {
	path := strings.TrimSpace(raw)
	if path == "%" {
		if i.Compiler.CurrentModule == "" {
			return "", fmt.Errorf("no current script")
		}
		return i.Compiler.CurrentModule, nil
	}
	if strings.HasPrefix(path, "<") && strings.HasSuffix(path, ">") {
		return filepath.Join(i.Config.LibraryPath, strings.TrimSuffix(strings.TrimPrefix(path, "<"), ">")), nil
	}
	if path == "~" || strings.HasPrefix(path, "~/") {
		home, ok := i.Services.Environment("HOME")
		if !ok || home == "" {
			var err error
			home, err = os.UserHomeDir()
			if err != nil {
				return "", err
			}
		}
		return filepath.Join(home, strings.TrimPrefix(path, "~/")), nil
	}
	if strings.HasPrefix(path, "~") {
		separator := strings.IndexRune(path, filepath.Separator)
		name, remainder := strings.TrimPrefix(path, "~"), ""
		if separator >= 0 {
			name, remainder = path[1:separator], path[separator+1:]
		}
		account, err := user.Lookup(name)
		if err != nil {
			return "", fmt.Errorf("unknown user %s", name)
		}
		return filepath.Join(account.HomeDir, remainder), nil
	}
	return path, nil
}
