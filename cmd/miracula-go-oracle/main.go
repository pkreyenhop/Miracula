// Command miracula-go-oracle exposes completed Go pipeline stages to the
// language-neutral oracle verifier. Until a stage is translated, requesting
// it fails with exit status 3; it must never replay expected fixture output.
package main

import (
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"

	"github.com/pkreyenhop/miracula-go/internal/protocol"
)

type producer func(casesPath string) error

// Producers are added only by the translation unit that implements a stage.
var producers = map[string]producer{
	"dump": protocol.ProduceDumpOracle,
}

func main() {
	stage := flag.String("stage", "", "pipeline stage to produce")
	cases := flag.String("cases", "", "oracle cases JSON file")
	list := flag.Bool("list-stages", false, "list implemented stages")
	flag.Parse()
	if *list {
		stages := make([]string, 0, len(producers))
		for name := range producers {
			stages = append(stages, name)
		}
		sort.Strings(stages)
		fmt.Println(strings.Join(stages, "\n"))
		return
	}
	if *stage == "" || *cases == "" {
		fmt.Fprintln(os.Stderr, "miracula-go-oracle: --stage and --cases are required")
		os.Exit(2)
	}
	produce, available := producers[*stage]
	if !available {
		fmt.Fprintf(os.Stderr, "miracula-go-oracle: stage %q is not implemented\n", *stage)
		os.Exit(3)
	}
	if err := produce(*cases); err != nil {
		fmt.Fprintf(os.Stderr, "miracula-go-oracle: stage %q: %v\n", *stage, err)
		os.Exit(1)
	}
}
