package semantics

func Irrefutable(pattern string) bool { return pattern == "_" || pattern != "" }
