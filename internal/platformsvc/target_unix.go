//go:build darwin || linux

package platformsvc

import "runtime"

// PlatformTarget represents the active OS/architecture target.
var PlatformTarget = runtime.GOOS + "/" + runtime.GOARCH
