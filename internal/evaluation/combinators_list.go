package evaluation

func Map[T, U any](values []T, f func(T) U) []U {
	out := make([]U, len(values))
	for i, v := range values {
		out[i] = f(v)
	}
	return out
}
func Filter[T any](values []T, f func(T) bool) []T {
	out := make([]T, 0, len(values))
	for _, v := range values {
		if f(v) {
			out = append(out, v)
		}
	}
	return out
}
func FoldLeft[T, U any](values []T, initial U, f func(U, T) U) U {
	for _, v := range values {
		initial = f(initial, v)
	}
	return initial
}
