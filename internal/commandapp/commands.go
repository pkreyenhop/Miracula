package commandapp

import "strings"

type ParsedCommand struct {
	Name      string
	Arguments []string
}

func Parse(line string) (ParsedCommand, bool) {
	line = strings.TrimSpace(line)
	if !strings.HasPrefix(line, "/") {
		return ParsedCommand{}, false
	}
	fields := strings.Fields(line[1:])
	if len(fields) == 0 {
		return ParsedCommand{}, false
	}
	return ParsedCommand{fields[0], fields[1:]}, true
}
func IsQuit(c ParsedCommand) bool { return c.Name == "q" || c.Name == "quit" }
