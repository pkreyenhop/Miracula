package application

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
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
	if err = i.pageManual(contents, out); err != nil {
		return err
	}
	for {
		selection, readErr := i.activeEditor.ReadChoice("next selection: ")
		if readErr != nil {
			return readErr
		}
		selection = strings.TrimSpace(selection)
		if selection == "" || selection == "q" || selection == "quit" || selection == "\x1b" {
			return nil
		}
		if strings.HasPrefix(selection, "/") {
			query := strings.TrimSpace(strings.TrimPrefix(selection, "/"))
			if query == "" {
				fmt.Fprintln(out, "search text required after /")
				continue
			}
			results, searchErr := searchManual(root, query)
			if searchErr != nil {
				return searchErr
			}
			if len(results) == 0 {
				fmt.Fprintf(out, "Pattern not found: %s\n", query)
			} else if err = i.pageManual(results, out); err != nil {
				return err
			}
			if err = i.pageManual(contents, out); err != nil {
				return err
			}
			continue
		}
		if selection == "m" || selection == "menu" {
			if err = i.pageManual(contents, out); err != nil {
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
		if err = i.pageManual(data, out); err != nil {
			return err
		}
		if err = i.pageManual(contents, out); err != nil {
			return err
		}
	}
}

func searchManual(root, query string) ([]byte, error) {
	query = strings.ToLower(query)
	var paths []string
	err := filepath.WalkDir(root, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if !entry.IsDir() && entry.Name() != "contents" {
			paths = append(paths, path)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	slices.Sort(paths)
	var results bytes.Buffer
	for _, path := range paths {
		data, readErr := os.ReadFile(path)
		if readErr != nil {
			return nil, readErr
		}
		chapter, relativeErr := filepath.Rel(root, path)
		if relativeErr != nil {
			return nil, relativeErr
		}
		for index, line := range strings.Split(string(data), "\n") {
			if strings.Contains(strings.ToLower(line), query) {
				fmt.Fprintf(&results, "%s:%d: %s\n", chapter, index+1, line)
			}
		}
	}
	return results.Bytes(), nil
}

const manualPageLines = 23

func (i *Interpreter) pageManual(data []byte, out io.Writer) error {
	lines := bytes.SplitAfter(data, []byte("\n"))
	if len(lines) != 0 && len(lines[len(lines)-1]) == 0 {
		lines = lines[:len(lines)-1]
	}
	position := 0
	pageStart := 0
	lastSearch := ""
	for position < len(lines) {
		pageStart = position
		end := min(position+manualPageLines, len(lines))
		for ; position < end; position++ {
			if _, err := out.Write(lines[position]); err != nil {
				return err
			}
		}
		if position == len(lines) {
			return nil
		}
		key, err := i.activeEditor.ReadKey("--More-- (Space: page, Enter: line, /: search, b: back, q: quit)")
		if err != nil {
			return err
		}
		if _, err = io.WriteString(out, "\r\x1b[K"); err != nil {
			return err
		}
		switch key {
		case 'q', 'Q', 27:
			return nil
		case 'b', 'B':
			position = max(0, pageStart-manualPageLines)
		case '\r', '\n':
			position = pageStart + 1
		case '/':
			query, readErr := i.activeEditor.ReadLine("/")
			if readErr != nil {
				return readErr
			}
			lastSearch = strings.TrimSpace(query)
			if found := manualSearch(lines, position, lastSearch); found >= 0 {
				position = found
			} else {
				fmt.Fprintf(out, "Pattern not found: %s\n", lastSearch)
				position = pageStart
			}
		case 'n', 'N':
			if found := manualSearch(lines, position, lastSearch); found >= 0 {
				position = found
			} else {
				position = pageStart
			}
		default: // Space and any unrecognised key advance one page.
		}
	}
	return nil
}

func manualSearch(lines [][]byte, start int, query string) int {
	if query == "" {
		return -1
	}
	query = strings.ToLower(query)
	for index := start; index < len(lines); index++ {
		if strings.Contains(strings.ToLower(string(lines[index])), query) {
			return index
		}
	}
	return -1
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
