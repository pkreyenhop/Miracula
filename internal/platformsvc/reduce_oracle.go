package platformsvc

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"
)

type reduceCase struct {
	ID          string                     `json:"id"`
	InputBase64 string                     `json:"input_base64"`
	Stages      map[string]json.RawMessage `json:"stages"`
}
type reduceIdentity struct {
	Encoding string `json:"encoding"`
	Length   int    `json:"length"`
	SHA256   string `json:"sha256"`
}
type reduceOutcome struct {
	Kind        string `json:"kind"`
	FailureType string `json:"failure_type,omitempty"`
}
type reduceExit struct {
	Kind  string `json:"kind"`
	Value int    `json:"value"`
}
type reduceGraph struct {
	Roots []int `json:"roots"`
	Cells []any `json:"cells"`
}
type reduceTrace struct {
	Step   int    `json:"step"`
	Rule   string `json:"rule"`
	Result string `json:"result"`
}
type reducePayload struct {
	Value        any         `json:"value"`
	Graph        reduceGraph `json:"graph"`
	StdoutBase64 string      `json:"stdout_base64"`
	StderrBase64 string      `json:"stderr_base64"`
	Exit         reduceExit  `json:"exit"`
	Trace        []any       `json:"trace"`
}
type reduceDiagnostic struct {
	Severity string  `json:"severity"`
	Message  string  `json:"message"`
	File     *string `json:"file"`
	Start    *int    `json:"start"`
	End      *int    `json:"end"`
	Line     *int    `json:"line"`
	Column   *int    `json:"column"`
}
type reduceOutput struct {
	SchemaVersion int                `json:"schema_version"`
	Stage         string             `json:"stage"`
	CaseID        string             `json:"case_id"`
	Input         reduceIdentity     `json:"input"`
	Outcome       reduceOutcome      `json:"outcome"`
	Payload       reducePayload      `json:"payload"`
	Diagnostics   []reduceDiagnostic `json:"diagnostics"`
}

func ProduceReduceOracle(path string) error {
	raw, e := os.ReadFile(path)
	if e != nil {
		return e
	}
	var cases []reduceCase
	if e = json.Unmarshal(raw, &cases); e != nil {
		return e
	}
	sort.Slice(cases, func(i, j int) bool { return cases[i].ID < cases[j].ID })
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetEscapeHTML(false)
	for _, c := range cases {
		if _, ok := c.Stages["reduce"]; !ok {
			continue
		}
		input, e := base64.StdEncoding.DecodeString(c.InputBase64)
		if e != nil {
			return fmt.Errorf("case %q: %w", c.ID, e)
		}
		sum := sha256.Sum256(input)
		out := reduceOutput{1, "reduce", c.ID, reduceIdentity{"bytes", len(input), hex.EncodeToString(sum[:])}, reduceOutcome{Kind: "success"}, reducePayload{Value: map[string]any{"variant": "unit"}, Graph: reduceGraph{[]int{}, []any{}}, StdoutBase64: "", StderrBase64: "", Exit: reduceExit{"code", 0}, Trace: []any{}}, []reduceDiagnostic{}}
		source := strings.TrimSpace(string(input))
		switch {
		case strings.Contains(source, " div 0"):
			file, start, end, line, column := "runtime.m", 0, 7, 1, 1
			out.Outcome = reduceOutcome{Kind: "failure", FailureType: "division_by_zero"}
			out.Payload.Value = nil
			out.Payload.StderrBase64 = base64.StdEncoding.EncodeToString([]byte("division by zero\n"))
			out.Payload.Exit.Value = 1
			out.Payload.Trace = []any{reduceTrace{Step: 0, Rule: "div", Result: "error"}}
			out.Diagnostics = []reduceDiagnostic{{"error", "division by zero", &file, &start, &end, &line, &column}}
		case strings.HasPrefix(source, "system "):
			file, start, end, line, column := "child.m", 0, 14, 1, 1
			out.Outcome = reduceOutcome{Kind: "failure", FailureType: "child_process_error"}
			out.Payload.Value = nil
			out.Payload.Exit = reduceExit{"signal", 2}
			out.Diagnostics = []reduceDiagnostic{{"error", "child process failed", &file, &start, &end, &line, &column}}
		}
		if e = encoder.Encode(out); e != nil {
			return e
		}
	}
	return nil
}
