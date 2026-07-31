package application

type Script struct {
	Path   string
	Source []byte
}
type ScriptStore struct{ Scripts map[string]Script }

func (s *ScriptStore) Put(script Script) {
	if s.Scripts == nil {
		s.Scripts = map[string]Script{}
	}
	s.Scripts[script.Path] = script
}
