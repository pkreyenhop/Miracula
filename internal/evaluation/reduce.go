package evaluation

import (
	"context"
	"github.com/pkreyenhop/miracula-go/internal/protocol"
)

func (e *Evaluator) Reduce(ctx context.Context, value protocol.Value) (protocol.Value, error) {
	select {
	case <-ctx.Done():
		return protocol.Value{}, protocol.ErrInterrupted
	default:
		return value, nil
	}
}
