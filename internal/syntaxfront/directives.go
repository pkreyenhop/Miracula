package syntaxfront

import "strings"

type Alias struct {
	New, Old string
	Suppress bool
}
type Directive struct {
	Variant, Path, Bindings, Text string
	FromMiralib                   bool
	Aliases                       []Alias
}

func ParseDirective(line string) (Directive, bool) {
	line = strings.TrimSpace(line)
	fields := strings.Fields(line)
	if len(fields) == 0 || !strings.HasPrefix(fields[0], "%") {
		return Directive{}, false
	}
	variant := strings.TrimPrefix(fields[0], "%")
	directive := Directive{Variant: variant, Text: strings.TrimSpace(strings.TrimPrefix(line, fields[0]))}
	switch variant {
	case "include", "insert":
		if len(fields) < 2 {
			return Directive{}, false
		}
		path := fields[1]
		directive.FromMiralib = strings.HasPrefix(path, "<") && strings.HasSuffix(path, ">")
		directive.Path = strings.Trim(path, `"<>`)
		if variant == "include" {
			for _, field := range fields[2:] {
				if strings.HasPrefix(field, "{") {
					directive.Bindings = directive.Text
					break
				}
				if strings.HasPrefix(field, "-") {
					directive.Aliases = append(directive.Aliases, Alias{Old: field[1:], Suppress: true})
					continue
				}
				if pair := strings.SplitN(field, "/", 2); len(pair) == 2 {
					directive.Aliases = append(directive.Aliases, Alias{New: pair[0], Old: pair[1]})
				}
			}
		}
	case "export", "free", "list", "nolist", "bnf", "lex":
	default:
		directive.Variant = "unknown"
	}
	return directive, true
}
