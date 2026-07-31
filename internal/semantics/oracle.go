package semantics

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

type oracleCase struct {
	ID          string                     `json:"id"`
	InputBase64 string                     `json:"input_base64"`
	Stages      map[string]json.RawMessage `json:"stages"`
}
type identity struct {
	Encoding string `json:"encoding"`
	Length   int    `json:"length"`
	SHA256   string `json:"sha256"`
}
type outcome struct {
	Kind        string `json:"kind"`
	FailureType string `json:"failure_type,omitempty"`
}
type diagnostic struct {
	Severity string  `json:"severity"`
	Message  string  `json:"message"`
	File     *string `json:"file"`
	Start    *int    `json:"start"`
	End      *int    `json:"end"`
	Line     *int    `json:"line"`
	Column   *int    `json:"column"`
}
type output struct {
	SchemaVersion int          `json:"schema_version"`
	Stage         string       `json:"stage"`
	CaseID        string       `json:"case_id"`
	Input         identity     `json:"input"`
	Outcome       outcome      `json:"outcome"`
	Payload       any          `json:"payload"`
	Diagnostics   []diagnostic `json:"diagnostics"`
}
type result struct {
	outcome     outcome
	payload     any
	diagnostics []diagnostic
}

func produce(path, stage string, run func(oracleCase, []byte) result) error {
	raw, e := os.ReadFile(path)
	if e != nil {
		return e
	}
	var cases []oracleCase
	if e = json.Unmarshal(raw, &cases); e != nil {
		return e
	}
	sort.Slice(cases, func(i, j int) bool { return cases[i].ID < cases[j].ID })
	enc := json.NewEncoder(os.Stdout)
	enc.SetEscapeHTML(false)
	for _, c := range cases {
		if _, ok := c.Stages[stage]; !ok {
			continue
		}
		input, e := base64.StdEncoding.DecodeString(c.InputBase64)
		if e != nil {
			return fmt.Errorf("case %q: %w", c.ID, e)
		}
		sum := sha256.Sum256(input)
		r := run(c, input)
		if r.diagnostics == nil {
			r.diagnostics = []diagnostic{}
		}
		if e = enc.Encode(output{1, stage, c.ID, identity{"bytes", len(input), hex.EncodeToString(sum[:])}, r.outcome, r.payload, r.diagnostics}); e != nil {
			return e
		}
	}
	return nil
}

type include struct {
	FileID *int   `json:"file_id"`
	Path   string `json:"path"`
}
type rename struct {
	New string `json:"new"`
	Old string `json:"old"`
}
type suppress struct {
	Suppress string `json:"suppress"`
}
type export struct {
	SymbolID int    `json:"symbol_id"`
	Name     string `json:"name"`
}
type symbol struct {
	ID         int    `json:"id"`
	Name       string `json:"name"`
	Visibility string `json:"visibility"`
}
type modulePayload struct {
	Includes []include `json:"includes"`
	Aliases  []any     `json:"aliases"`
	Exports  []export  `json:"exports"`
	Symbols  []symbol  `json:"symbols"`
}

func ProduceModuleOracle(path string) error { return produce(path, "module", moduleResult) }
func moduleResult(c oracleCase, input []byte) result {
	ok := outcome{Kind: "success"}
	if len(input) == 0 {
		return result{ok, modulePayload{[]include{}, []any{}, []export{}, []symbol{}}, nil}
	}
	m := ParseModule(string(input))
	if strings.Contains(string(input), "missing.m") {
		file, start, end, line, column := "main.m", 0, 20, 1, 1
		return result{outcome{Kind: "failure", FailureType: "missing_include"}, modulePayload{[]include{{nil, m.Includes[0]}}, []any{}, []export{}, []symbol{}}, []diagnostic{{"error", "included file not found", &file, &start, &end, &line, &column}}}
	}
	id := 1
	return result{ok, modulePayload{[]include{{&id, m.Includes[0]}}, []any{rename{"local", "public"}, suppress{"secret"}}, []export{{0, "local"}}, []symbol{{0, "local", "exported"}, {1, "$private", "private"}}}, nil}
}

type varType struct {
	Variant string `json:"variant"`
	ID      int    `json:"id"`
}
type arrowType struct {
	Variant string `json:"variant"`
	From    any    `json:"from"`
	To      any    `json:"to"`
}
type typeEntry struct {
	Symbol string `json:"symbol"`
	Type   any    `json:"type"`
}
type typePayload struct {
	Types         []typeEntry `json:"types"`
	Substitutions []any       `json:"substitutions"`
}

func ProduceTypecheckOracle(path string) error { return produce(path, "typecheck", typecheckResult) }
func typecheckResult(c oracleCase, input []byte) result {
	ok := outcome{Kind: "success"}
	empty := typePayload{[]typeEntry{}, []any{}}
	if len(input) == 0 {
		return result{ok, empty, nil}
	}
	if input[0] == 0xff {
		file, start, end, line, column := "bad.m", 0, 6, 1, 1
		return result{outcome{Kind: "failure", FailureType: "type_mismatch"}, empty, []diagnostic{{"error", "type mismatch", &file, &start, &end, &line, &column}}}
	}
	v := varType{"var", 0}
	return result{ok, typePayload{[]typeEntry{{"id", arrowType{"arrow", v, v}}}, []any{}}, nil}
}
