// Package buildcfg exposes immutable identity injected into production builds.
package buildcfg

const Version = 2067
const XVersion = 83

// These variables may be set with -ldflags -X for release builds.
var (
	VersionDate = "unknown-date"
	Host        = "compiled by go build\nunknown-host"
	Commit      = "unknown"
)
