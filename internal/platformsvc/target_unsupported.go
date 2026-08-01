//go:build !darwin || !arm64

package platformsvc

// Deliberately undefined: unsupported targets must fail at build
// time instead of silently compiling an incomplete platform implementation.
var _ = requires_darwin_arm64
