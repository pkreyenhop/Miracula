package evaluation

import "github.com/pkreyenhop/miracula/internal/protocol"

type Frame struct {
	Cell  protocol.CellRef
	Right bool
}
type Spine struct{ frames []Frame }

func (s *Spine) Push(f Frame) { s.frames = append(s.frames, f) }
func (s *Spine) Pop() (Frame, bool) {
	if len(s.frames) == 0 {
		return Frame{}, false
	}
	i := len(s.frames) - 1
	f := s.frames[i]
	s.frames = s.frames[:i]
	return f, true
}
func (s *Spine) Depth() int { return len(s.frames) }
