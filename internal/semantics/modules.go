package semantics

import (
	"errors"
	"strings"
)

var ErrMissingInclude = errors.New("missing include")

type Alias struct {
	New, Old string
	Suppress bool
}
type Module struct {
	Includes []string
	Aliases  []Alias
	Exports  []string
	Symbols  SymbolTable
}

func ParseModule(source string) Module {
	m := Module{}
	for _, line := range strings.Split(source, "\n") {
		f := strings.Fields(line)
		if len(f) == 0 {
			continue
		}
		if f[0] == "%include" && len(f) > 1 {
			m.Includes = append(m.Includes, strings.Trim(f[1], `"`))
			for _, a := range f[2:] {
				if strings.HasPrefix(a, "-") {
					m.Aliases = append(m.Aliases, Alias{Old: a[1:], Suppress: true})
				} else if p := strings.SplitN(a, "/", 2); len(p) == 2 {
					m.Aliases = append(m.Aliases, Alias{New: p[0], Old: p[1]})
				}
			}
		}
		if f[0] == "%export" {
			for _, name := range f[1:] {
				if name != "+" {
					m.Exports = append(m.Exports, name)
				}
			}
		}
	}
	return m
}
