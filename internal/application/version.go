package application

import "fmt"

const Release = 2067

func VersionString() string { return fmt.Sprintf("%d.%03d", Release/1000, Release%1000) }
