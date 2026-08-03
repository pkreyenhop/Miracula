//go:build !(darwin || linux)

package platformsvc

// Deliberately undefined: unsupported targets must fail at build
// time instead of silently compiling an incomplete platform implementation.
var _ = requires_darwin_or_linux
