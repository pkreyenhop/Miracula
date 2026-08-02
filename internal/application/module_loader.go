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
	i.invalidateREPLCache()
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
		set := make(DiagnosticSet, 0, len(diagnostics))
		for index, diagnostic := range diagnostics {
			set = append(set, sourceDiagnostic("source", absolute, source, diagnostic, index))
		}
		return nil, stableDiagnostics(set)
	}
	if i.Config.List && i.Output != nil {
		listing := true
		for _, line := range strings.Split(string(source.Bytes), "\n") {
			trimmed := strings.TrimSpace(line)
			if trimmed == "%nolist" {
				listing = false
				continue
			}
			if trimmed == "%list" {
				listing = true
				continue
			}
			if listing {
				fmt.Fprintln(i.Output, line)
			}
		}
	}
	for _, line := range strings.Split(string(source.Bytes), "\n") {
		if directive, ok := syntaxfront.ParseDirective(strings.TrimSpace(line)); ok && directive.Variant == "unknown" {
			if i.Output != nil {
				fmt.Fprintf(i.Output, "syntax error: unknown directive %q\n", strings.Fields(strings.TrimSpace(line))[0])
			}
			i.startupFailed = true
			i.Compiler.CurrentModule = absolute
			metadata, hasMetadata := i.Services.Metadata(absolute)
			i.Scripts.Put(Script{Path: absolute, Source: append([]byte(nil), source.Bytes...), Metadata: metadata, HasMetadata: hasMetadata, Origins: append([]syntaxfront.Origin(nil), source.Origins...)})
			return &semantics.Program{}, nil
		}
	}
	dump, dumpErr := ReadCompiledDump(dumpPath, source.Bytes)
	i.Compiler.UsedCompiledArtifact = dumpErr == nil && dump.Program != nil
	parsed := syntaxfront.PipelineResult{Script: dump.Script}
	if !i.Compiler.UsedCompiledArtifact {
		parsed = syntaxfront.Run(source.Bytes)
	}
	if len(parsed.Diagnostics) != 0 {
		set := make(DiagnosticSet, 0, len(parsed.Diagnostics))
		for index, diagnostic := range parsed.Diagnostics {
			set = append(set, sourceDiagnostic("syntax", absolute, source, diagnostic, index))
		}
		return nil, stableDiagnostics(set)
	}
	if !i.Compiler.UsedCompiledArtifact {
		if typeErrors := semantics.CheckAllWithTypes(parsed.Script, i.StandardTypes); len(typeErrors) != 0 {
			metadata, hasMetadata := i.Services.Metadata(absolute)
			i.Scripts.Put(Script{Path: absolute, Source: append([]byte(nil), source.Bytes...), Metadata: metadata, HasMetadata: hasMetadata, Origins: append([]syntaxfront.Origin(nil), source.Origins...)})
			i.Compiler.CurrentModule = absolute
			diagnostics := typeDiagnostics(absolute, source, typeErrors, 0)
			// Name validation is deliberately independent from type inference so
			// undefined names do not mask useful type errors. Loading must aggregate
			// both passes just as editor save/reload does.
			if validationErr := i.ValidateCurrent(); validationErr != nil {
				var nameDiagnostics DiagnosticSet
				if errors.As(validationErr, &nameDiagnostics) {
					diagnostics = append(diagnostics, nameDiagnostics...)
				}
			}
			// Miranda keeps independently valid definitions available after a
			// failed interactive compilation. Install a source-preserving filtered
			// program while retaining the original script for editing and errors.
			i.installValidDefinitions(absolute, source.Bytes, parsed.Script, diagnostics)
			return nil, stableDiagnostics(diagnostics)
		}
	}
	checkpoint := i.Heap.Checkpoint()
	if err := i.runtime().installIncludes(filepath.Dir(absolute), source.Bytes); err != nil {
		i.Heap.Restore(checkpoint)
		return nil, DiagnosticSet{{Severity: "error", Phase: "module", File: absolute, Span: syntaxfront.Span{Line: 1, Column: 1}, Message: err.Error()}}
	}
	var installErr error
	if i.Compiler.UsedCompiledArtifact && dump.RuntimeUnit != nil {
		i.runtime().installRuntimeUnit(dump.RuntimeUnit)
	} else {
		installErr = i.runtime().installSource(source.Bytes)
	}
	if installErr != nil {
		i.Heap.Restore(checkpoint)
		return nil, fmt.Errorf("install source %s: %w", absolute, installErr)
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
	i.Scripts.Put(Script{Path: absolute, Source: append([]byte(nil), source.Bytes...), Metadata: metadata, HasMetadata: hasMetadata, Origins: append([]syntaxfront.Origin(nil), source.Origins...)})
	if err := i.trackProgramSources(absolute); err != nil {
		return nil, err
	}
	i.Compiler.CurrentModule = absolute
	if !i.Compiler.UsedCompiledArtifact {
		dependencies, dependencyErr := dependencyHashes(absolute, i.Config.LibraryPath)
		if dependencyErr != nil {
			return nil, dependencyErr
		}
		runtimeUnit, _ := lowerRuntimeUnit(parsed.Script, source.Bytes)
		artifact := CompiledDump{Source: source.Bytes, Dependencies: dependencies, Script: parsed.Script, Program: program, Exports: exportedTypeProfile(parsed.Script, program), RuntimeUnit: runtimeUnit}
		if writeErr := WriteCompiledArtifact(dumpPath, artifact); writeErr != nil {
			return nil, writeErr
		}
	}
	return program, nil
}

func (i *Interpreter) installValidDefinitions(path string, source []byte, script syntaxfront.Script, diagnostics DiagnosticSet) {
	badDefinitions := map[string]bool{}
	badLines := map[int]bool{}
	for _, diagnostic := range diagnostics {
		if diagnostic.Definition != "" {
			badDefinitions[diagnostic.Definition] = true
		}
		if diagnostic.Span.Line > 0 {
			badLines[diagnostic.Span.Line] = true
		}
	}
	filtered := append([]byte(nil), source...)
	for _, item := range script.Items {
		if item.Variant != "definition" {
			continue
		}
		name, _, named := runtimePatterns(item.LHS)
		bad := badLines[item.Span.Line] || named && badDefinitions[name]
		if !bad {
			continue
		}
		start, end := max(0, item.Span.Start), min(len(filtered), item.Span.End)
		for index := start; index < end; index++ {
			if filtered[index] != '\n' {
				filtered[index] = ' '
			}
		}
	}
	parsed := syntaxfront.Run(filtered)
	if len(parsed.Diagnostics) != 0 || len(semantics.CheckAllWithTypes(parsed.Script, i.StandardTypes)) != 0 {
		return
	}
	checkpoint := i.Heap.Checkpoint()
	if err := i.runtime().installIncludes(filepath.Dir(path), filtered); err != nil {
		i.Heap.Restore(checkpoint)
		return
	}
	if err := i.runtime().installSource(filtered); err != nil {
		i.Heap.Restore(checkpoint)
		return
	}
	program, err := semantics.Compile(parsed.Script, i.Heap)
	if err != nil {
		i.Heap.Restore(checkpoint)
		return
	}
	if i.Programs == nil {
		i.Programs = map[string]*semantics.Program{}
	}
	i.Programs[path] = program
}

func (i *Interpreter) trackProgramSources(root string) error {
	paths, err := RelevantSources(root, i.Config.LibraryPath)
	if err != nil {
		return err
	}
	for _, path := range paths {
		if path == root {
			continue
		}
		source, readErr := os.ReadFile(path)
		if readErr != nil {
			return readErr
		}
		metadata, hasMetadata := i.Services.Metadata(path)
		i.Scripts.Put(Script{Path: path, Source: source, Metadata: metadata, HasMetadata: hasMetadata})
	}
	return nil
}
