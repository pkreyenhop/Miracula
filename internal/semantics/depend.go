package semantics

import "fmt"

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
		for _, d := range graph[n] {
			if e := visit(d); e != nil {
				return e
			}
		}
		state[n] = 2
		out = append(out, n)
		return nil
	}
	for n := range graph {
		if e := visit(n); e != nil {
			return nil, e
		}
	}
	return out, nil
}
