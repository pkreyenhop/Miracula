package semantics

func PrimitiveType(name string) (*Type, bool) {
	signatures := map[string]string{
		"+": "num->num->num", "-": "num->num->num", "*": "num->num->num", "/": "num->num->num",
		"div": "num->num->num", "mod": "num->num->num", "^": "num->num->num",
		"=": "*->*->bool", "~=": "*->*->bool", "<": "*->*->bool", "<=": "*->*->bool", ">": "*->*->bool", ">=": "*->*->bool",
		"&": "bool->bool->bool", "\\/": "bool->bool->bool", "~": "bool->bool",
		":": "*->[*]->[*]", "++": "[*]->[*]->[*]", "--": "[*]->[*]->[*]",
		"#": "[*]->num", "!": "[*]->num->*", ".": "(**->***)->(*->**)->*->***",
		"|>":      "*->(*->**)->**",
		"reverse": "[*]->[*]", "take": "num->[*]->[*]", "map": "(*->**)->[*]->[**]",
		"filter": "(*->bool)->[*]->[*]", "foldl": "(*->**->*)->*->[**]->*", "foldr": "(*->**->**)->**->[*]->**",
		"sum": "[num]->num", "product": "[num]->num", "show": "*->[char]", "readvals": "[char]->[*]",
		"code": "char->num", "decode": "num->char",
		"True": "bool", "False": "bool", "undef": "*",
		"$-": "[char]", "$:-": "[char]", "$+": "[*]", "$*": "[[char]]",
		"Stdout": "[char]->sys_message", "Stderr": "[char]->sys_message", "Tofile": "[char]->[char]->sys_message", "Closefile": "[char]->sys_message", "Appendfile": "[char]->sys_message", "System": "[char]->sys_message", "Exit": "num->sys_message", "Stdoutb": "[char]->sys_message", "Tofileb": "[char]->[char]->sys_message", "Appendfileb": "[char]->sys_message",
		"read": "[char]->[char]", "readb": "[char]->[char]", "filemode": "[char]->[char]", "filestat": "[char]->((num,num),num)", "getenv": "[char]->[char]", "system": "[char]->([char],[char],num)",
	}
	signature, ok := signatures[name]
	if !ok {
		return nil, false
	}
	value, err := ParseType(signature)
	return value, err == nil
}
