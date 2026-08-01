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

// StronglyConnectedOrder returns recursive binding groups with dependencies
// before their users. Names inside a group are lexical for reproducibility.
func StronglyConnectedOrder(graph map[string][]string) [][]string {
	index := 0
	indices, low := map[string]int{}, map[string]int{}
	onStack := map[string]bool{}
	var stack []string
	var components [][]string
	var connect func(string)
	connect = func(name string) {
		index++
		indices[name], low[name] = index, index
		stack = append(stack, name)
		onStack[name] = true
		deps := append([]string(nil), graph[name]...)
		sort.Strings(deps)
		for _, dependency := range deps {
			if indices[dependency] == 0 {
				connect(dependency)
				low[name] = min(low[name], low[dependency])
			} else if onStack[dependency] {
				low[name] = min(low[name], indices[dependency])
			}
		}
		if low[name] != indices[name] {
			return
		}
		var component []string
		for {
			last := stack[len(stack)-1]
			stack = stack[:len(stack)-1]
			onStack[last] = false
			component = append(component, last)
			if last == name {
				break
			}
		}
		sort.Strings(component)
		components = append(components, component)
	}
	names := make([]string, 0, len(graph))
	for name := range graph {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		if indices[name] == 0 {
			connect(name)
		}
	}
	return components
}
