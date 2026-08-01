package evaluation

import (
	"context"
	"github.com/pkreyenhop/miracula/internal/platformsvc"
)

func RunSystem(ctx context.Context, command string) (platformsvc.ProcessOutcome, error) {
	return platformsvc.RunShell(ctx, platformsvc.ShellFallbackPath, command)
}
