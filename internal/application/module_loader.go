package application

import (
	"errors"
	"fmt"
	"github.com/pkreyenhop/miracula/internal/semantics"
	"github.com/pkreyenhop/miracula/internal/syntaxfront"
	"os"
	"path/filepath"
	"strings"
)

func (i *Interpreter) LoadModule(path string) (semantics.Module, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return semantics.Module{}, err
	}
	return semantics.ParseModule(string(b)), nil
}

func (i *Interpreter) LoadProgram(path string) (*semantics.Program, error) {
	absolute, err := filepath.Abs(path)
	if err != nil {
		return nil, err
	}
	dumpPath := strings.TrimSuffix(absolute, filepath.Ext(absolute)) + ".x"
	if _, statErr := os.Stat(absolute); errors.Is(statErr, os.ErrNotExist) {
		_ = os.Remove(dumpPath)
		return nil, statErr
	}
	source, diagnostics := syntaxfront.LoadSource(absolute)
	if len(diagnostics) != 0 {
		return nil, fmt.Errorf("%s:%d:%d: %s", diagnostics[0].File, diagnostics[0].Span.Line, diagnostics[0].Span.Column, diagnostics[0].Message)
	}
	for _, line := range strings.Split(string(source.Bytes), "\n") {
		trimmed := strings.TrimSpace(line)
		for _, suffix := range []string{"+", "-", "*", "/", "=", ":", "++", "div", "mod"} {
			if strings.HasSuffix(trimmed, suffix) {
				return nil, fmt.Errorf("syntax error: unexpected newline")
			}
		}
		if directive, ok := syntaxfront.ParseDirective(strings.TrimSpace(line)); ok && directive.Variant == "unknown" {
			if i.Output != nil {
				fmt.Fprintf(i.Output, "syntax error: unknown directive %q\n", strings.Fields(strings.TrimSpace(line))[0])
			}
			i.startupFailed = true
			i.Compiler.CurrentModule = absolute
			metadata, hasMetadata := i.Services.Metadata(absolute)
			i.Scripts.Put(Script{Path: absolute, Source: append([]byte(nil), source.Bytes...), Metadata: metadata, HasMetadata: hasMetadata})
			return &semantics.Program{}, nil
		}
	}
	dump, dumpErr := ReadCompiledDump(dumpPath, source.Bytes)
	i.Compiler.UsedCompiledArtifact = dumpErr == nil && dump.Program != nil && len(dump.Script.Items) != 0
	parsed := syntaxfront.PipelineResult{Script: dump.Script}
	if !i.Compiler.UsedCompiledArtifact {
		parsed = syntaxfront.Run(source.Bytes)
	}
	if len(parsed.Diagnostics) != 0 {
		return nil, fmt.Errorf("syntax error: %s:%d:%d: %s", absolute, parsed.Diagnostics[0].Span.Line, parsed.Diagnostics[0].Span.Column, parsed.Diagnostics[0].Message)
	}
	if !i.Compiler.UsedCompiledArtifact {
		if typeErrors := semantics.CheckAllWithTypes(parsed.Script, i.StandardTypes); len(typeErrors) != 0 {
			metadata, hasMetadata := i.Services.Metadata(absolute)
			i.Scripts.Put(Script{Path: absolute, Source: append([]byte(nil), source.Bytes...), Metadata: metadata, HasMetadata: hasMetadata})
			i.Compiler.CurrentModule = absolute
			return nil, typeErrors
		}
	}
	checkpoint := i.Heap.Checkpoint()
	if err := i.runtime().installIncludes(filepath.Dir(absolute), source.Bytes); err != nil {
		i.Heap.Restore(checkpoint)
		return nil, fmt.Errorf("include from %s: %w", absolute, err)
	}
	if err := i.runtime().installSource(source.Bytes); err != nil {
		i.Heap.Restore(checkpoint)
		return nil, fmt.Errorf("install source %s: %w", absolute, err)
	}
	program := dump.Program
	if !i.Compiler.UsedCompiledArtifact {
		program, err = semantics.Compile(parsed.Script, i.Heap)
		if err != nil {
			i.Heap.Restore(checkpoint)
			program = &semantics.Program{}
		}
	}
	if i.Programs == nil {
		i.Programs = map[string]*semantics.Program{}
	}
	i.Programs[absolute] = program
	metadata, hasMetadata := i.Services.Metadata(absolute)
	i.Scripts.Put(Script{Path: absolute, Source: append([]byte(nil), source.Bytes...), Metadata: metadata, HasMetadata: hasMetadata})
	i.Compiler.CurrentModule = absolute
	if !i.Compiler.UsedCompiledArtifact {
		dependencies, dependencyErr := dependencyHashes(absolute, i.Config.LibraryPath)
		if dependencyErr != nil {
			return nil, dependencyErr
		}
		artifact := CompiledDump{Source: source.Bytes, Dependencies: dependencies, Script: parsed.Script, Program: program, Exports: exportedTypeProfile(parsed.Script, program)}
		if writeErr := WriteCompiledArtifact(dumpPath, artifact); writeErr != nil {
			return nil, writeErr
		}
	}
	return program, nil
}
