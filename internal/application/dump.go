package application

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"github.com/pkreyenhop/miracula-go/internal/graphstore"
	"io"
	"os"
	"path/filepath"
)

func DumpGraph(w io.Writer, g graphstore.DumpGraph) error { return graphstore.EncodeGraph(w, g) }

type CompiledDump struct {
	Version      int    `json:"version"`
	SourceSHA256 string `json:"source_sha256"`
	Source       []byte `json:"source"`
}

var ErrStaleDump = errors.New("stale compiled dump")

func WriteCompiledDump(path string, source []byte) error {
	digest := sha256.Sum256(source)
	dump := CompiledDump{Version: Release, SourceSHA256: hex.EncodeToString(digest[:]), Source: append([]byte(nil), source...)}
	temporary, err := os.CreateTemp(filepath.Dir(path), ".mira-dump-*")
	if err != nil {
		return err
	}
	name := temporary.Name()
	defer os.Remove(name)
	encoder := json.NewEncoder(temporary)
	if err = encoder.Encode(dump); err != nil {
		temporary.Close()
		return err
	}
	if err = temporary.Sync(); err != nil {
		temporary.Close()
		return err
	}
	if err = temporary.Close(); err != nil {
		return err
	}
	if err = os.Chmod(name, 0o644); err != nil {
		return err
	}
	return os.Rename(name, path)
}
func ReadCompiledDump(path string, source []byte) (CompiledDump, error) {
	file, err := os.Open(path)
	if err != nil {
		return CompiledDump{}, err
	}
	defer file.Close()
	var dump CompiledDump
	if err = json.NewDecoder(file).Decode(&dump); err != nil {
		return CompiledDump{}, err
	}
	digest := sha256.Sum256(source)
	if dump.Version != Release || dump.SourceSHA256 != hex.EncodeToString(digest[:]) {
		return CompiledDump{}, ErrStaleDump
	}
	return dump, nil
}
