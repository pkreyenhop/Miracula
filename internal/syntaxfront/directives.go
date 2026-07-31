package syntaxfront

import "strings"

type Alias struct {
	New, Old string
	Suppress bool
}
type Directive struct {
	Variant, Path, Bindings string
	FromMiralib             bool
	Aliases                 []Alias
}

func ParseDirective(line string) (Directive, bool) {
	fields := strings.Fields(strings.TrimSpace(line))
	if len(fields) < 2 || fields[0] != "%include" {
		return Directive{}, false
	}
	d := Directive{Variant: "include", Path: strings.Trim(fields[1], `"`)}
	for _, f := range fields[2:] {
		if strings.HasPrefix(f, "-") {
			d.Aliases = append(d.Aliases, Alias{Old: f[1:], Suppress: true})
		} else if p := strings.SplitN(f, "/", 2); len(p) == 2 {
			d.Aliases = append(d.Aliases, Alias{New: p[0], Old: p[1]})
		}
	}
	return d, true
}
