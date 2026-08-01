package application

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

func (i *Interpreter) runManual(out io.Writer) error {
	if i.activeEditor == nil {
		return fmt.Errorf("manual command requires an interactive session")
	}
	root := filepath.Join(i.Config.LibraryPath, "manual")
	contents, err := os.ReadFile(filepath.Join(root, "contents"))
	if err != nil {
		return err
	}
	if _, err = out.Write(contents); err != nil {
		return err
	}
	for {
		selection, readErr := i.activeEditor.ReadLine("next selection: ")
		if readErr != nil {
			return readErr
		}
		selection = strings.TrimSpace(selection)
		if selection == "" || selection == "q" || selection == "quit" {
			return nil
		}
		if selection == "m" || selection == "menu" {
			if _, err = out.Write(contents); err != nil {
				return err
			}
			continue
		}
		page, ok := manualPagePath(root, selection)
		if !ok {
			fmt.Fprintln(out, "invalid manual selection")
			continue
		}
		data, openErr := os.ReadFile(page)
		if openErr != nil {
			fmt.Fprintln(out, "manual section not found")
			continue
		}
		if _, err = out.Write(data); err != nil {
			return err
		}
	}
}

func manualPagePath(root, selection string) (string, bool) {
	for _, character := range selection {
		if character != '/' && (character < '0' || character > '9') {
			return "", false
		}
	}
	if selection == "" || strings.HasPrefix(selection, "/") || strings.Contains(selection, "//") {
		return "", false
	}
	path := filepath.Clean(filepath.Join(root, selection))
	if path == root || !strings.HasPrefix(path, root+string(filepath.Separator)) {
		return "", false
	}
	return path, true
}
