package application

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
)

func (i *Interpreter) runManual(out io.Writer) error {
	if i.activeEditor == nil {
		return fmt.Errorf("manual command requires an interactive session")
	}
	root := filepath.Join(i.Config.LibraryPath, "manual")
	stack := []string{root}
	lastSelection := map[string]int{}
	for {
		current := stack[len(stack)-1]
		contents, err := os.ReadFile(filepath.Join(current, "contents"))
		if err != nil {
			return err
		}
		if err = i.pageManual(contents, out); err != nil {
			return err
		}
		selection, readErr := i.activeEditor.ReadChoice("next selection: ")
		if readErr != nil {
			return readErr
		}
		selection = strings.TrimSpace(selection)
		if selection == "" {
			if len(stack) == 1 {
				return nil
			}
			stack = stack[:len(stack)-1]
			continue
		}
		if selection == "q" || selection == "quit" || selection == "\x1b" {
			return nil
		}
		if selection == "???" {
			fmt.Fprintln(out, "VIEWER=internal Go pager")
			fmt.Fprintln(out, "MENUVIEWER=internal Go pager")
			fmt.Fprintln(out, "RETURNTOMENU=YES")
			continue
		}
		if strings.HasPrefix(selection, "!") {
			command := strings.TrimSpace(strings.TrimPrefix(selection, "!"))
			if command == "" {
				fmt.Fprintln(out, "shell command required after !")
				continue
			}
			if err = i.runShell(context.Background(), i.expandCurrentScript(command)); err != nil {
				fmt.Fprintln(out, err)
			}
			continue
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
			continue
		}
		if selection == "m" || selection == "menu" {
			continue
		}
		if selection == "." || selection == "+" || selection == "-" {
			last := lastSelection[current]
			if last == 0 {
				fmt.Fprintln(out, "no previous manual selection")
				continue
			}
			if selection == "+" {
				last++
			}
			if selection == "-" {
				last--
			}
			if last < 1 {
				fmt.Fprintln(out, "manual section not found")
				continue
			}
			selection = fmt.Sprint(last)
		}
		page, ok := manualPagePath(current, selection)
		if !ok {
			fmt.Fprintln(out, "invalid manual selection")
			continue
		}
		if info, statErr := os.Stat(page); statErr == nil && info.IsDir() {
			if _, contentsErr := os.Stat(filepath.Join(page, "contents")); contentsErr != nil {
				fmt.Fprintln(out, "manual section not found")
				continue
			}
			if number, numberErr := strconv.Atoi(selection); numberErr == nil {
				lastSelection[current] = number
			}
			stack = append(stack, page)
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
		if number, numberErr := strconv.Atoi(selection); numberErr == nil {
			lastSelection[current] = number
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

func (i *Interpreter) manualPageHeight() int {
	if i.Services != nil {
		if rows := i.Services.Terminal(1).Rows; rows != nil && *rows > 2 {
			return int(*rows) - 1
		}
	}
	return manualPageLines
}

func (i *Interpreter) pageManual(data []byte, out io.Writer) error {
	lines := bytes.SplitAfter(data, []byte("\n"))
	if len(lines) != 0 && len(lines[len(lines)-1]) == 0 {
		lines = lines[:len(lines)-1]
	}
	position := 0
	pageStart := 0
	lastSearch := ""
	searchForward := true
	pageLines := i.manualPageHeight()
	for position < len(lines) {
		pageStart = position
		end := min(position+pageLines, len(lines))
		for ; position < end; position++ {
			if _, err := out.Write(lines[position]); err != nil {
				return err
			}
		}
		if position == len(lines) {
			return nil
		}
		key, err := i.activeEditor.ReadKey("--More-- (Space: page, Enter: line, /?: search, b: back, h: help, q: quit)")
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
			position = max(0, pageStart-pageLines)
		case '\r', '\n':
			position = pageStart + 1
		case '/':
			query, readErr := i.activeEditor.ReadLine("/")
			if readErr != nil {
				return readErr
			}
			lastSearch = strings.TrimSpace(query)
			searchForward = true
			if found := manualSearch(lines, position, lastSearch); found >= 0 {
				position = found
			} else {
				fmt.Fprintf(out, "Pattern not found: %s\n", lastSearch)
				position = pageStart
			}
		case '?':
			query, readErr := i.activeEditor.ReadLine("?")
			if readErr != nil {
				return readErr
			}
			lastSearch, searchForward = strings.TrimSpace(query), false
			if found := manualSearchBackward(lines, pageStart-1, lastSearch); found >= 0 {
				position = found
			} else {
				fmt.Fprintf(out, "Pattern not found: %s\n", lastSearch)
				position = pageStart
			}
		case 'n', 'N':
			found := -1
			if searchForward {
				found = manualSearch(lines, position, lastSearch)
			} else {
				found = manualSearchBackward(lines, pageStart-1, lastSearch)
			}
			if found >= 0 {
				position = found
			} else {
				position = pageStart
			}
		case 'h', 'H':
			fmt.Fprintln(out, "Space next page; Enter next line; b previous page; /text forward search; ?text backward search; n repeat search; q quit")
			position = pageStart
		default: // Space and any unrecognised key advance one page.
		}
	}
	return nil
}

func manualSearchBackward(lines [][]byte, start int, query string) int {
	if query == "" {
		return -1
	}
	query = strings.ToLower(query)
	for index := min(start, len(lines)-1); index >= 0; index-- {
		if strings.Contains(strings.ToLower(string(lines[index])), query) {
			return index
		}
	}
	return -1
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
