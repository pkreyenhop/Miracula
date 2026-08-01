package application

import "github.com/pkreyenhop/miracula/internal/platformsvc"

type Script struct {
	Path        string
	Source      []byte
	Metadata    platformsvc.FileMetadata
	HasMetadata bool
}
type ScriptStore struct{ Scripts map[string]Script }

func (s *ScriptStore) Put(script Script) {
	if s.Scripts == nil {
		s.Scripts = map[string]Script{}
	}
	s.Scripts[script.Path] = script
}
