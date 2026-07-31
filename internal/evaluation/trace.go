package evaluation

type TraceStep struct {
	Step   int    `json:"step"`
	Rule   string `json:"rule"`
	Result string `json:"result"`
}
type Trace struct{ Steps []TraceStep }

func (t *Trace) Add(rule, result string) {
	t.Steps = append(t.Steps, TraceStep{len(t.Steps), rule, result})
}
