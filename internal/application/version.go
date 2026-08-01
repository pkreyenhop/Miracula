package application

import (
	"fmt"
	"github.com/pkreyenhop/miracula/internal/buildcfg"
)

const Release = buildcfg.Version

func VersionString() string { return fmt.Sprintf("%d.%03d", Release/1000, Release%1000) }
