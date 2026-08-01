package application

import (
	"context"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/pkreyenhop/miracula/internal/semantics"
	"github.com/pkreyenhop/miracula/internal/syntaxfront"
)

type commandExpression struct {
	Expression string
	TypeQuery  bool
	Background bool
	Append     bool
	Paths      []string
}

func parseCommandExpression(line string) (commandExpression, error) {
	result := commandExpression{Expression: strings.TrimSpace(line)}
	if index, appendMode := commandOperator(result.Expression); index >= 0 {
		operatorLength := 2
		if appendMode {
			operatorLength = 3
		}
		paths, err := commandWords(result.Expression[index+operatorLength:])
		if err != nil || len(paths) < 1 || len(paths) > 2 {
			return result, fmt.Errorf("redirection requires one or two output paths")
		}
		result.Expression = strings.TrimSpace(result.Expression[:index])
		result.Background, result.Append, result.Paths = true, appendMode, paths
		if result.Expression == "" {
			return result, fmt.Errorf("redirection requires an expression")
		}
		return result, nil
	}
	if index := trailingTypeQuery(result.Expression); index >= 0 {
		result.Expression = strings.TrimSpace(result.Expression[:index])
		result.TypeQuery = true
		if result.Expression == "" {
			return result, fmt.Errorf("type query requires an expression")
		}
	}
	return result, nil
}

func commandOperator(text string) (int, bool) {
	quote := rune(0)
	escaped := false
	for index, char := range text {
		if escaped {
			escaped = false
			continue
		}
		if char == '\\' {
			escaped = true
			continue
		}
		if quote != 0 {
			if char == quote {
				quote = 0
			}
			continue
		}
		if char == '\'' || char == '"' {
			quote = char
			continue
		}
		if strings.HasPrefix(text[index:], "&>>") {
			return index, true
		}
		if strings.HasPrefix(text[index:], "&>") {
			return index, false
		}
	}
	return -1, false
}

func trailingTypeQuery(text string) int {
	trimmed := strings.TrimSpace(text)
	if !strings.HasSuffix(trimmed, "::") {
		return -1
	}
	return len(trimmed) - 2
}

func commandWords(text string) ([]string, error) {
	var words []string
	var current strings.Builder
	quote := rune(0)
	escaped := false
	flush := func() {
		if current.Len() != 0 {
			words = append(words, current.String())
			current.Reset()
		}
	}
	for _, char := range text {
		if escaped {
			current.WriteRune(char)
			escaped = false
			continue
		}
		if char == '\\' {
			escaped = true
			continue
		}
		if quote != 0 {
			if char == quote {
				quote = 0
			} else {
				current.WriteRune(char)
			}
			continue
		}
		if char == '\'' || char == '"' {
			quote = char
			continue
		}
		if char == ' ' || char == '\t' {
			flush()
			continue
		}
		current.WriteRune(char)
	}
	if escaped || quote != 0 {
		return nil, fmt.Errorf("unterminated quoted output path")
	}
	flush()
	return words, nil
}

func (i *Interpreter) expressionType(expression string) (string, error) {
	parsed := syntaxfront.Run([]byte("__repl = " + expression + "\n"))
	if len(parsed.Diagnostics) != 0 {
		return "", fmt.Errorf("%s", parsed.Diagnostics[0].Message)
	}
	environment := i.expressionTypeEnvironment()
	program, err := semantics.CheckWithTypes(parsed.Script, environment)
	if err != nil {
		return "", err
	}
	if len(program.Definitions) != 1 {
		return "", fmt.Errorf("expression did not produce a type")
	}
	return semantics.FormatType(program.Definitions[0].Type), nil
}

func (i *Interpreter) expressionTypeEnvironment() map[string]*semantics.Type {
	environment := make(map[string]*semantics.Type, len(i.StandardTypes)+16)
	for name, value := range i.StandardTypes {
		environment[name] = value
	}
	if program := i.Programs[i.Compiler.CurrentModule]; program != nil {
		for _, definition := range program.Definitions {
			environment[definition.Name] = definition.Type
		}
		for name, value := range program.Specifications {
			environment[name] = value
		}
	}
	if i.Repl.LastExpressionType != nil {
		environment["$$"] = i.Repl.LastExpressionType
	}
	return environment
}

func (i *Interpreter) expandCurrentScript(text string) string {
	var result strings.Builder
	escaped := false
	for _, char := range text {
		if escaped {
			if char != '%' {
				result.WriteRune('\\')
			}
			result.WriteRune(char)
			escaped = false
			continue
		}
		if char == '\\' {
			escaped = true
			continue
		}
		if char == '%' {
			result.WriteString(i.Compiler.CurrentModule)
		} else {
			result.WriteRune(char)
		}
	}
	if escaped {
		result.WriteRune('\\')
	}
	return result.String()
}

func (i *Interpreter) shellCommand(line string) string {
	command := strings.TrimSpace(strings.TrimPrefix(line, "!"))
	if line == "!!" {
		return i.Repl.LastShellCommand
	}
	command = i.expandCurrentScript(command)
	if command != "" {
		i.Repl.LastShellCommand = command
	}
	return command
}

func (i *Interpreter) startBackgroundEvaluation(parent context.Context, command commandExpression) error {
	flags := os.O_CREATE | os.O_WRONLY
	if command.Append {
		flags |= os.O_APPEND
	} else {
		flags |= os.O_TRUNC
	}
	stdout, err := os.OpenFile(command.Paths[0], flags, 0o666)
	if err != nil {
		return err
	}
	stderr := io.Writer(stdout)
	var stderrFile *os.File
	if len(command.Paths) == 2 {
		stderrFile, err = os.OpenFile(command.Paths[1], flags, 0o666)
		if err != nil {
			stdout.Close()
			return err
		}
		stderr = stderrFile
	}
	ctx, cancel := context.WithCancel(context.WithValue(parent, closedInputContextKey{}, true))
	go func() {
		defer cancel()
		defer stdout.Close()
		if stderrFile != nil {
			defer stderrFile.Close()
		}
		if _, evaluationErr := i.evaluateToWriters(ctx, command.Expression, stdout, stderr); evaluationErr != nil {
			fmt.Fprintln(stderr, legacyEvaluationError(evaluationErr))
		}
	}()
	return nil
}
