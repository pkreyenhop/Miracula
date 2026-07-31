package syntaxfront

type BindingPower struct{ Left, Right int }

func InfixBinding(kind string) (BindingPower, bool) {
	switch kind {
	case "cons":
		return BindingPower{20, 20}, true
	case "plus":
		return BindingPower{50, 51}, true
	}
	return BindingPower{}, false
}
