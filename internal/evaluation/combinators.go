package evaluation

import "github.com/pkreyenhop/miracula/internal/protocol"

func Identity(v protocol.Value) protocol.Value    { return v }
func Constant(a, b protocol.Value) protocol.Value { return a }
