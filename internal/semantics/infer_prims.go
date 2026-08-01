package semantics

func PrimitiveType(name string) (*Type, bool) {
	signatures := map[string]string{
		"+": "num->num->num", "-": "num->num->num", "*": "num->num->num", "/": "num->num->num",
		"div": "num->num->num", "mod": "num->num->num", "^": "num->num->num",
		"=": "*->*->bool", "~=": "*->*->bool", "<": "*->*->bool", "<=": "*->*->bool", ">": "*->*->bool", ">=": "*->*->bool",
		"&": "bool->bool->bool", "\\/": "bool->bool->bool", "~": "bool->bool",
		":": "*->[*]->[*]", "++": "[*]->[*]->[*]", "--": "[*]->[*]->[*]",
		"#": "[*]->num", "!": "[*]->num->*", ".": "(**->***)->(*->**)->*->***",
		"reverse": "[*]->[*]", "take": "num->[*]->[*]", "map": "(*->**)->[*]->[**]",
		"filter": "(*->bool)->[*]->[*]", "foldl": "(*->**->*)->*->[**]->*", "foldr": "(*->**->**)->**->[*]->**",
		"sum": "[num]->num", "product": "[num]->num", "show": "*->[char]", "readvals": "[char]->[*]",
		"code": "char->num", "decode": "num->char",
		"True": "bool", "False": "bool", "undef": "*",
	}
	signature, ok := signatures[name]
	if !ok {
		return nil, false
	}
	value, err := ParseType(signature)
	return value, err == nil
}
