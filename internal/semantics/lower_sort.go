package semantics

import "sort"

func SortNames(names []string) []string {
	out := append([]string(nil), names...)
	sort.Strings(out)
	return out
}
