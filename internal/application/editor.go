package application

import (
	"context"
	"os/exec"
)

func OpenEditor(ctx context.Context, editor, path string, line, column int) error {
	return exec.CommandContext(ctx, editor, path).Run()
}
