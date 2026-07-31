package semantics

type TypeError struct {
	Message, File            string
	Start, End, Line, Column int
}

func (e TypeError) Error() string { return e.Message }
