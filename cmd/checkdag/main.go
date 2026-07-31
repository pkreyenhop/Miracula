// Command checkdag enforces the package import contract used by the Go port.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"
)

const module = "github.com/pkreyenhop/miracula-go"

var allowed = map[string]map[string]bool{
	"protocol":    {},
	"platformsvc": {"protocol": true},
	"graphstore":  {"protocol": true, "platformsvc": true},
	"syntaxfront": {"protocol": true, "platformsvc": true, "graphstore": true},
	"semantics":   {"protocol": true, "platformsvc": true, "graphstore": true, "syntaxfront": true},
	"evaluation":  {"protocol": true, "platformsvc": true, "graphstore": true},
	"application": {"protocol": true, "platformsvc": true, "graphstore": true, "syntaxfront": true, "semantics": true, "evaluation": true},
	"commandapp":  {"protocol": true, "platformsvc": true, "application": true},
	"devtools":    {"protocol": true, "platformsvc": true},
}

type listedPackage struct {
	ImportPath string
	Imports    []string
}

func main() {
	command := exec.Command("go", "list", "-json", "./internal/...")
	output, err := command.Output()
	if err != nil {
		fmt.Fprintf(os.Stderr, "checkdag: go list: %v\n", err)
		os.Exit(1)
	}
	decoder := json.NewDecoder(strings.NewReader(string(output)))
	var violations []string
	seen := map[string]bool{}
	for decoder.More() {
		var pkg listedPackage
		if err := decoder.Decode(&pkg); err != nil {
			fmt.Fprintf(os.Stderr, "checkdag: decode go list output: %v\n", err)
			os.Exit(1)
		}
		name := strings.TrimPrefix(pkg.ImportPath, module+"/internal/")
		if _, ok := allowed[name]; !ok || strings.Contains(name, "/") {
			violations = append(violations, "unknown internal package "+pkg.ImportPath)
			continue
		}
		seen[name] = true
		for _, imported := range pkg.Imports {
			dependency := strings.TrimPrefix(imported, module+"/internal/")
			if dependency == imported {
				continue
			}
			dependency = strings.SplitN(dependency, "/", 2)[0]
			if !allowed[name][dependency] {
				violations = append(violations, fmt.Sprintf("%s may not import %s", name, dependency))
			}
		}
	}
	for name := range allowed {
		if !seen[name] {
			violations = append(violations, "missing internal package "+name)
		}
	}
	sort.Strings(violations)
	if len(violations) != 0 {
		for _, violation := range violations {
			fmt.Fprintln(os.Stderr, "checkdag:", violation)
		}
		os.Exit(1)
	}
	fmt.Printf("Go package DAG verified: %d packages\n", len(seen))
}
