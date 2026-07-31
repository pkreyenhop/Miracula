//go:build !darwin || !arm64

package platformsvc

// Deliberately undefined: unsupported migration targets must fail at build
// time instead of silently compiling an incomplete platform implementation.
var _ = migration_requires_darwin_arm64
