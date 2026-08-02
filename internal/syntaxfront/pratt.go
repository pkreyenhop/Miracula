package syntaxfront

type BindingPower struct{ Left, Right int }

func InfixBinding(kind string) (BindingPower, bool) {
	switch kind {
	case "pipe_forward":
		// Pipelines bind more weakly than every existing Miranda operator and
		// associate left, so x |> f |> g means g (f x).
		return BindingPower{10, 11}, true
	case "or":
		return BindingPower{20, 19}, true
	case "and", "ampersand":
		return BindingPower{30, 29}, true
	case "eq", "not_equal", "less", "greater", "less_equal", "greater_equal":
		return BindingPower{40, 41}, true
	case "cons", "append", "difference":
		return BindingPower{50, 49}, true
	case "plus", "minus":
		return BindingPower{60, 61}, true
	case "star", "slash", "kw_div", "kw_mod":
		return BindingPower{70, 71}, true
	case "power":
		return BindingPower{79, 78}, true
	case "dot":
		return BindingPower{80, 81}, true
	case "subscript":
		return BindingPower{90, 91}, true
	case "custom_infix":
		return BindingPower{99, 98}, true
	}
	return BindingPower{}, false
}
