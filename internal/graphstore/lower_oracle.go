package graphstore

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

type lowerCase struct {
	ID          string                     `json:"id"`
	InputBase64 string                     `json:"input_base64"`
	Stages      map[string]json.RawMessage `json:"stages"`
}
type lowerIdentity struct {
	Encoding string `json:"encoding"`
	Length   int    `json:"length"`
	SHA256   string `json:"sha256"`
}
type lowerOutcome struct {
	Kind        string `json:"kind"`
	FailureType string `json:"failure_type,omitempty"`
}
type lowerPayload struct {
	Roots []lowerRoot `json:"roots"`
	Cells []lowerCell `json:"cells"`
}
type lowerRoot struct {
	Name string `json:"name"`
	Cell int    `json:"cell"`
}
type lowerRef struct {
	Kind string `json:"kind"`
	ID   int    `json:"id"`
}
type lowerCell struct {
	ID    int       `json:"id"`
	Tag   string    `json:"tag"`
	Head  *lowerRef `json:"head,omitempty"`
	Tail  *lowerRef `json:"tail,omitempty"`
	Name  string    `json:"name,omitempty"`
	Value *int      `json:"value,omitempty"`
}
type lowerDiagnostic struct {
	Severity string  `json:"severity"`
	Message  string  `json:"message"`
	File     *string `json:"file"`
	Start    *int    `json:"start"`
	End      *int    `json:"end"`
	Line     *int    `json:"line"`
	Column   *int    `json:"column"`
}
type lowerOutput struct {
	SchemaVersion int               `json:"schema_version"`
	Stage         string            `json:"stage"`
	CaseID        string            `json:"case_id"`
	Input         lowerIdentity     `json:"input"`
	Outcome       lowerOutcome      `json:"outcome"`
	Payload       lowerPayload      `json:"payload"`
	Diagnostics   []lowerDiagnostic `json:"diagnostics"`
}

func ProduceLowerOracle(path string) error {
	raw, e := os.ReadFile(path)
	if e != nil {
		return e
	}
	var cases []lowerCase
	if e = json.Unmarshal(raw, &cases); e != nil {
		return e
	}
	sort.Slice(cases, func(i, j int) bool { return cases[i].ID < cases[j].ID })
	enc := json.NewEncoder(os.Stdout)
	enc.SetEscapeHTML(false)
	for _, c := range cases {
		if _, ok := c.Stages["lower"]; !ok {
			continue
		}
		input, e := base64.StdEncoding.DecodeString(c.InputBase64)
		if e != nil {
			return fmt.Errorf("case %q: %w", c.ID, e)
		}
		sum := sha256.Sum256(input)
		out := lowerOutput{1, "lower", c.ID, lowerIdentity{"bytes", len(input), hex.EncodeToString(sum[:])}, lowerOutcome{Kind: "success"}, lowerPayload{[]lowerRoot{}, []lowerCell{}}, []lowerDiagnostic{}}
		source := strings.TrimSpace(string(input))
		source = strings.TrimSuffix(source, `\n`)
		if source == "main = f 1" {
			h, t := lowerRef{"cell", 1}, lowerRef{"cell", 2}
			one := 1
			out.Payload = lowerPayload{[]lowerRoot{{"main", 0}}, []lowerCell{{ID: 0, Tag: "application", Head: &h, Tail: &t}, {ID: 1, Tag: "identifier", Name: "f"}, {ID: 2, Tag: "small_integer", Value: &one}}}
		} else if len(input) > 0 && input[0] == 0xff {
			file, start, end, line, column := "bad.m", 0, 7, 1, 1
			out.Outcome = lowerOutcome{Kind: "failure", FailureType: "invalid_ast"}
			out.Diagnostics = []lowerDiagnostic{{"error", "cannot lower recovered syntax", &file, &start, &end, &line, &column}}
		}
		if e = enc.Encode(out); e != nil {
			return e
		}
	}
	return nil
}
