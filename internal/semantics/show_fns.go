package semantics

type ShowFns struct{ ShowInt, ShowChar, ShowList string }

func DefaultShowFns() ShowFns { return ShowFns{"shownum", "showchar", "showlist"} }
