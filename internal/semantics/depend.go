package semantics

import (
	"fmt"
	"sort"
)

func TopologicalOrder(graph map[string][]string) ([]string, error) {
	state := map[string]uint8{}
	var out []string
	var visit func(string) error
	visit = func(n string) error {
		if state[n] == 1 {
			return fmt.Errorf("dependency cycle")
		}
		if state[n] == 2 {
			return nil
		}
		state[n] = 1
		dependencies := append([]string(nil), graph[n]...)
		sort.Strings(dependencies)
		for _, d := range dependencies {
			if e := visit(d); e != nil {
				return e
			}
		}
		state[n] = 2
		out = append(out, n)
		return nil
	}
	names := make([]string, 0, len(graph))
	for n := range graph {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, n := range names {
		if e := visit(n); e != nil {
			return nil, e
		}
	}
	return out, nil
}
