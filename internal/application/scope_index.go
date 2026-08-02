package application

import (
	"path/filepath"
	"sort"
	"strings"

	"github.com/pkreyenhop/miracula/internal/semantics"
	"github.com/pkreyenhop/miracula/internal/syntaxfront"
)

type scopeEntry struct {
	Name, Original, Path string
	Line                 int
	Type                 *semantics.Type
	Local, Standard      bool
}

func (i *Interpreter) scopeIndex() []scopeEntry {
	entries := map[string]scopeEntry{}
	current := i.Compiler.CurrentModule
	if program := i.Programs[current]; program != nil {
		for _, definition := range program.Definitions {
			entries[definition.Name] = scopeEntry{Name: definition.Name, Original: definition.Name, Path: current, Line: definition.Expression.Span.Line, Type: definition.Type, Local: true}
		}
	}
	runtime := i.runtime()
	for name := range runtime.globals {
		if _, local := entries[name]; local || strings.HasPrefix(name, "__") || name == "$$" {
			continue
		}
		provenance, exported := runtime.provenance[name]
		valueType, typed := i.StandardTypes[name]
		if !exported && !typed {
			continue
		}
		entry := scopeEntry{Name: name, Original: name, Type: valueType, Standard: typed}
		if exported {
			entry.Original, entry.Path = provenance.Original, provenance.Path
			entry.Line, _ = sourceDefinitionLine(i.Scripts.Scripts[entry.Path].Source, entry.Original)
			if entry.Type == nil {
				entry.Type, _ = semantics.ParseType(sourceDefinitionType(i.Scripts.Scripts[entry.Path].Source, entry.Original))
			}
		} else {
			entry.Path, entry.Line = i.standardDefinition(name)
		}
		entries[name] = entry
	}
	for name, valueType := range i.StandardTypes {
		if _, exists := entries[name]; exists {
			continue
		}
		path, line := i.standardDefinition(name)
		entries[name] = scopeEntry{Name: name, Original: name, Path: path, Line: line, Type: valueType, Standard: true}
	}
	for path, script := range i.Scripts.Scripts {
		base := filepath.Base(path)
		if base != "prelude" && base != "stdenv.m" {
			continue
		}
		for _, name := range sourceDefinitionNames(script.Source) {
			if _, exists := entries[name]; exists {
				continue
			}
			line, _ := sourceDefinitionLine(script.Source, name)
			valueType, _ := semantics.ParseType(sourceDefinitionType(script.Source, name))
			entries[name] = scopeEntry{Name: name, Original: name, Path: path, Line: line, Type: valueType, Standard: true}
		}
	}
	result := make([]scopeEntry, 0, len(entries))
	for _, entry := range entries {
		result = append(result, entry)
	}
	sort.Slice(result, func(a, b int) bool { return result[a].Name < result[b].Name })
	return result
}

func sourceDefinitionNames(source []byte) []string {
	seen := map[string]bool{}
	for _, raw := range strings.Split(string(source), "\n") {
		line := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(raw), ">"))
		separator := strings.Index(line, "=")
		if separator < 0 || strings.Contains(line[:separator], "::") {
			continue
		}
		parsed := syntaxfront.Run([]byte(strings.TrimSpace(line[:separator]) + " = 0\n"))
		if len(parsed.Script.Items) != 1 {
			continue
		}
		name, _, ok := runtimePatterns(parsed.Script.Items[0].LHS)
		if ok {
			seen[name] = true
		}
	}
	names := make([]string, 0, len(seen))
	for name := range seen {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

func (i *Interpreter) standardDefinition(name string) (string, int) {
	paths := make([]string, 0, len(i.Scripts.Scripts))
	for path := range i.Scripts.Scripts {
		base := filepath.Base(path)
		if base == "prelude" || base == "stdenv.m" {
			paths = append(paths, path)
		}
	}
	sort.Strings(paths)
	for _, path := range paths {
		if line, ok := sourceDefinitionLine(i.Scripts.Scripts[path].Source, name); ok {
			return path, line
		}
	}
	// Internally implemented standard functions intentionally have no Miranda
	// equation. Their authoritative documentation and type declaration live in
	// stdenv.m, so queries should locate that declaration instead of reporting a
	// synthetic <built-in> location.
	for _, path := range paths {
		if line, ok := sourceDeclarationLine(i.Scripts.Scripts[path].Source, name); ok {
			return path, line
		}
	}
	return "<built-in>", 0
}

func (i *Interpreter) scopeEntry(name string) (scopeEntry, bool) {
	for _, entry := range i.scopeIndex() {
		if entry.Name == name {
			return entry, true
		}
	}
	if valueType, ok := semantics.PrimitiveType(name); ok {
		return scopeEntry{Name: name, Original: name, Path: "<built-in>", Type: valueType, Standard: true}, true
	}
	return scopeEntry{}, false
}

func (entry scopeEntry) definition() semantics.TypedDefinition {
	return semantics.TypedDefinition{Name: entry.Name, Type: entry.Type, Expression: syntaxfront.Expr{Span: syntaxfront.Span{Line: entry.Line}}}
}
