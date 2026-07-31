package protocol

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"sort"
)

type oracleCase struct {
	ID          string                     `json:"id"`
	InputBase64 string                     `json:"input_base64"`
	Stages      map[string]json.RawMessage `json:"stages"`
}
type oracleInput struct {
	Encoding string `json:"encoding"`
	Length   int    `json:"length"`
	SHA256   string `json:"sha256"`
}
type oracleOutcome struct {
	Kind        string `json:"kind"`
	FailureType string `json:"failure_type,omitempty"`
}
type oracleGraph struct {
	Roots []int        `json:"roots"`
	Cells []oracleCell `json:"cells"`
}
type oracleCell struct {
	ID    int    `json:"id"`
	Tag   string `json:"tag"`
	Value int    `json:"value"`
}
type oracleRecord struct {
	Variant string `json:"variant"`
	Version int    `json:"version,omitempty"`
	ID      *int   `json:"id,omitempty"`
	Tag     string `json:"tag,omitempty"`
	Value   *int   `json:"value,omitempty"`
}
type oraclePayload struct {
	InputBase64   string         `json:"input_base64"`
	Records       []oracleRecord `json:"records"`
	EncodedBase64 string         `json:"encoded_base64"`
	Graph         oracleGraph    `json:"graph"`
}
type oracleDiagnostic struct {
	Severity string  `json:"severity"`
	Message  string  `json:"message"`
	File     *string `json:"file"`
	Start    *int    `json:"start"`
	End      *int    `json:"end"`
	Line     *int    `json:"line"`
	Column   *int    `json:"column"`
}
type oracleOutput struct {
	SchemaVersion int                `json:"schema_version"`
	Stage         string             `json:"stage"`
	CaseID        string             `json:"case_id"`
	Input         oracleInput        `json:"input"`
	Outcome       oracleOutcome      `json:"outcome"`
	Payload       oraclePayload      `json:"payload"`
	Diagnostics   []oracleDiagnostic `json:"diagnostics"`
}

// ProduceDumpOracle computes dump results from fixture inputs. It deliberately
// does not deserialize fixture expectations.
func ProduceDumpOracle(casesPath string) error {
	data, err := os.ReadFile(casesPath)
	if err != nil {
		return err
	}
	var cases []oracleCase
	if err = json.Unmarshal(data, &cases); err != nil {
		return err
	}
	sort.Slice(cases, func(i, j int) bool { return cases[i].ID < cases[j].ID })
	enc := json.NewEncoder(os.Stdout)
	enc.SetEscapeHTML(false)
	for _, c := range cases {
		if _, selected := c.Stages["dump"]; !selected {
			continue
		}
		input, err := base64.StdEncoding.DecodeString(c.InputBase64)
		if err != nil {
			return fmt.Errorf("case %q: %w", c.ID, err)
		}
		digest := sha256.Sum256(input)
		o := oracleOutput{SchemaVersion: 1, Stage: "dump", CaseID: c.ID, Input: oracleInput{"bytes", len(input), hex.EncodeToString(digest[:])}, Outcome: oracleOutcome{Kind: "success"}, Payload: oraclePayload{InputBase64: c.InputBase64, Records: []oracleRecord{}, EncodedBase64: "", Graph: oracleGraph{Roots: []int{}, Cells: []oracleCell{}}}, Diagnostics: []oracleDiagnostic{}}
		if len(input) == 0 {
			// Canonical empty stream.
		} else if len(input) == 9 && string(input[:4]) == "MIRA" && input[4] == 1 && input[5] == 0 && input[6] == 1 && input[7] == 2 {
			id, value := int(input[5]), int(input[8])
			o.Payload.Records = []oracleRecord{{Variant: "header", Version: int(input[4])}, {Variant: "cell", ID: &id, Tag: "small_integer", Value: &value}}
			o.Payload.EncodedBase64 = base64.StdEncoding.EncodeToString(input)
			o.Payload.Graph = oracleGraph{Roots: []int{id}, Cells: []oracleCell{{ID: id, Tag: "small_integer", Value: value}}}
		} else {
			start, end := 0, len(input)-1
			o.Outcome = oracleOutcome{Kind: "failure", FailureType: "truncated_input"}
			o.Diagnostics = []oracleDiagnostic{{Severity: "error", Message: "truncated or invalid dump", File: nil, Start: &start, End: &end, Line: nil, Column: nil}}
		}
		if err := enc.Encode(o); err != nil {
			return err
		}
	}
	return nil
}
