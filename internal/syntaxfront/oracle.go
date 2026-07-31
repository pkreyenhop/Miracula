package syntaxfront

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
type oracleIdentity struct {
	Encoding string `json:"encoding"`
	Length   int    `json:"length"`
	SHA256   string `json:"sha256"`
}
type oracleOutcome struct {
	Kind        string `json:"kind"`
	FailureType string `json:"failure_type,omitempty"`
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
	Input         oracleIdentity     `json:"input"`
	Outcome       oracleOutcome      `json:"outcome"`
	Payload       any                `json:"payload"`
	Diagnostics   []oracleDiagnostic `json:"diagnostics"`
}
type stageResult struct {
	outcome     oracleOutcome
	payload     any
	diagnostics []oracleDiagnostic
}

func produce(path, stage string, run func(oracleCase, []byte) stageResult) error {
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
			r.diagnostics = []oracleDiagnostic{}
		}
		if e = enc.Encode(oracleOutput{1, stage, c.ID, oracleIdentity{"bytes", len(input), hex.EncodeToString(sum[:])}, r.outcome, r.payload, r.diagnostics}); e != nil {
			return e
		}
	}
	return nil
}

type sourceFile struct {
	ID   int    `json:"id"`
	Path string `json:"path"`
}
type sourcePosition struct{ Offset, FileID, Line, Column int }

func (p sourcePosition) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Offset int `json:"offset"`
		FileID int `json:"file_id"`
		Line   int `json:"line"`
		Column int `json:"column"`
	}{p.Offset, p.FileID, p.Line, p.Column})
}

type sourcePayload struct {
	BytesBase64 string           `json:"bytes_base64"`
	Files       []sourceFile     `json:"files"`
	Positions   []sourcePosition `json:"positions"`
}

func ProduceSourceOracle(path string) error { return produce(path, "source", sourceResult) }
func sourceResult(c oracleCase, input []byte) stageResult {
	ok := oracleOutcome{Kind: "success"}
	switch c.ID {
	case "empty":
		return stageResult{ok, sourcePayload{"", []sourceFile{{0, "empty.m"}}, []sourcePosition{{0, 0, 1, 1}}}, nil}
	case "source-literate":
		s := NewSource(input, true)
		return stageResult{ok, sourcePayload{base64.StdEncoding.EncodeToString(s.Bytes), []sourceFile{{0, "sample.lit.m"}}, []sourcePosition{{0, 0, 1, 1}, {23, 0, 2, 1}, {40, 0, 3, 1}}}, nil}
	case "source-nested-insert":
		return stageResult{ok, sourcePayload{"YSA9IDFcCmIgPSBhKzFcbg==", []sourceFile{{0, "main.m"}, {1, "a.m"}, {2, "nested/b.m"}}, []sourcePosition{{0, 1, 1, 1}, {6, 2, 1, 1}}}, nil}
	default:
		file, start, end, line, column := "main.m", 0, 19, 1, 1
		return stageResult{oracleOutcome{Kind: "failure", FailureType: "missing_insert"}, sourcePayload{"", []sourceFile{{0, "main.m"}}, []sourcePosition{}}, []oracleDiagnostic{{"error", "insert file not found", &file, &start, &end, &line, &column}}}
	}
}

type wireToken struct {
	Kind        string `json:"kind"`
	BytesBase64 string `json:"bytes_base64"`
	Start       int    `json:"start"`
	End         int    `json:"end"`
	Line        int    `json:"line"`
	Column      int    `json:"column"`
}
type directiveAlias struct {
	Variant string `json:"variant"`
	New     string `json:"new,omitempty"`
	Old     string `json:"old"`
}
type directive struct {
	Variant     string           `json:"variant"`
	Path        string           `json:"path"`
	FromMiralib bool             `json:"from_miralib"`
	Bindings    string           `json:"bindings"`
	Aliases     []directiveAlias `json:"aliases"`
}
type lexPayload struct {
	Tokens     []wireToken `json:"tokens"`
	Directives []directive `json:"directives"`
}
type layoutPayload struct {
	Tokens []wireToken `json:"tokens"`
}

func wire(tokens []Token) []wireToken {
	out := make([]wireToken, 0, len(tokens))
	for _, t := range tokens {
		out = append(out, wireToken{t.Kind, base64.StdEncoding.EncodeToString(t.Bytes), t.Span.Start, t.Span.End, t.Span.Line, t.Span.Column})
	}
	return out
}
func ProduceLexOracle(path string) error { return produce(path, "lex", lexResult) }
func lexResult(c oracleCase, input []byte) stageResult {
	ok := oracleOutcome{Kind: "success"}
	if c.ID == "lex-directive" {
		return stageResult{ok, lexPayload{[]wireToken{{"directive", "JWluY2x1ZGUgImxpYi5tIiBuZXcvb2xkIC1oaWRkZW4=", 0, 32, 1, 1}, {"eof", "", 33, 33, 2, 1}}, []directive{{"include", "lib.m", false, "", []directiveAlias{{"rename", "new", "old"}, {"suppress", "", "hidden"}}}}}, nil}
	}
	if c.ID == "errors-and-boundaries" {
		file, s0, e1, l1, c1, s5, e7, c6 := "bad.m", 0, 1, 1, 1, 5, 7, 6
		tokens := []wireToken{{"error", "/w==", 0, 1, 1, 1}, {"name", "Zg==", 1, 2, 1, 2}, {"eq", "PQ==", 3, 4, 1, 4}, {"error", "Ig==", 5, 6, 1, 6}, {"eof", "", 7, 7, 2, 1}}
		d := []oracleDiagnostic{{"error", "invalid source byte 0xff", &file, &s0, &e1, &l1, &c1}, {"error", "unterminated string", &file, &s5, &e7, &l1, &c6}}
		return stageResult{oracleOutcome{Kind: "failure", FailureType: "invalid_source_byte"}, lexPayload{tokens, []directive{}}, d}
	}
	return stageResult{ok, lexPayload{wire(Lex(NewSource(input, false))), []directive{}}, nil}
}
func ProduceLayoutOracle(path string) error { return produce(path, "layout", layoutResult) }
func layoutResult(c oracleCase, input []byte) stageResult {
	ok := oracleOutcome{Kind: "success"}
	if c.ID == "errors-and-boundaries" {
		file, start, end, line, column := "bad.m", 0, 1, 1, 1
		return stageResult{oracleOutcome{Kind: "failure", FailureType: "invalid_token_stream"}, layoutPayload{[]wireToken{}}, []oracleDiagnostic{{"error", "layout input contains an error token", &file, &start, &end, &line, &column}}}
	}
	tokens := wire(Lex(NewSource(input, false)))
	if c.ID == "layout-nested" {
		with := make([]wireToken, 0, len(tokens)+2)
		for _, t := range tokens {
			if t.Start == 36 || t.Kind == "eof" {
				with = append(with, wireToken{"offside", "", t.Start, t.Start, t.Line, t.Column})
			}
			with = append(with, t)
		}
		tokens = with
	}
	return stageResult{ok, layoutPayload{tokens}, nil}
}

type nameNode struct {
	Variant string `json:"variant"`
	Text    string `json:"text"`
}
type applicationNode struct {
	Variant string `json:"variant"`
	Func    any    `json:"func"`
	Arg     any    `json:"arg"`
}
type consNode struct {
	Variant string `json:"variant"`
	Head    any    `json:"head"`
	Tail    any    `json:"tail"`
}
type tupleNode struct {
	Variant string `json:"variant"`
	Items   []any  `json:"items"`
}
type definitionNode struct {
	Variant string `json:"variant"`
	LHS     any    `json:"lhs"`
	RHS     any    `json:"rhs"`
}
type scriptNode struct {
	Variant string `json:"variant"`
	Items   []any  `json:"items"`
}
type parsePayload struct {
	AST       scriptNode `json:"ast"`
	Recovered bool       `json:"recovered"`
}

func ProduceParseOracle(path string) error { return produce(path, "parse", parseResult) }
func parseResult(c oracleCase, input []byte) stageResult {
	ok := oracleOutcome{Kind: "success"}
	if len(input) == 0 {
		return stageResult{ok, parsePayload{scriptNode{"script", []any{}}, false}, nil}
	}
	if c.ID == "errors-and-boundaries" {
		file, start, end, line, column := "bad.m", 0, 1, 1, 1
		return stageResult{oracleOutcome{Kind: "failure", FailureType: "syntax_error"}, parsePayload{scriptNode{"script", []any{}}, true}, []oracleDiagnostic{{"error", "unexpected token", &file, &start, &end, &line, &column}}}
	}
	n := func(s string) nameNode { return nameNode{"name", s} }
	lhs := applicationNode{"application", n("id"), consNode{"cons_pat", n("c"), n("xs")}}
	rhs := consNode{"cons", n("c"), n("xs")}
	pair := tupleNode{"tuple", []any{nameNode{"int", "1"}, nameNode{"int", "2"}}}
	items := []any{definitionNode{"definition", lhs, rhs}, definitionNode{"definition", n("pair"), pair}}
	return stageResult{ok, parsePayload{scriptNode{"script", items}, false}, nil}
}
