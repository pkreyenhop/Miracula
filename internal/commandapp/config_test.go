package commandapp

import (
	"github.com/pkreyenhop/miracula-go/internal/platformsvc"
	"os"
	"path/filepath"
	"testing"
	"time"
)

type configServices map[string]string

func (s configServices) Environment(name string) (string, bool) {
	value, ok := s[name]
	return value, ok
}
func (configServices) Metadata(string) (platformsvc.FileMetadata, bool) {
	return platformsvc.FileMetadata{}, false
}
func (configServices) Run(platformsvc.ProcessRequest) (platformsvc.ProcessOutcome, error) {
	return platformsvc.Exited(0), nil
}
func (configServices) Terminal(uint32) platformsvc.TerminalInfo {
	return platformsvc.TerminalInfo{}
}
func (configServices) Monotonic() time.Duration             { return 0 }
func (configServices) FindExecutable(string) (string, bool) { return "", false }

var _ platformsvc.Services = configServices{}

func TestResolveDefaultsPrecedence(t *testing.T) {
	home := t.TempDir()
	if err := os.WriteFile(filepath.Join(home, ".mirarc"), []byte("lhdve 2000 3000 2067 rc editor\n"), 0600); err != nil {
		t.Fatal(err)
	}
	services := configServices{
		"HOME": home, "MIRALIB": "/environment/library", "EDITOR": "environment editor",
		"MIRAPROMPT": "go> ", "RECHECKMIRA": "1", "NOSTRICTIF": "1",
	}
	config := resolveDefaults(services)
	if config.LibraryPath != "/environment/library" || config.Editor != "rc editor" || config.Prompt != "go> " {
		t.Fatalf("unexpected text config: %+v", config)
	}
	if config.HeapCells != 2000 || config.DictionaryCells != 3000 || !config.List || !config.Recheck || config.StrictIf {
		t.Fatalf("unexpected option config: %+v", config)
	}
}

func TestFlagsOverrideResolvedDefaults(t *testing.T) {
	defaults := resolveDefaults(configServices{"MIRALIB": "/environment/library"})
	options, err := ParseOptions([]string{"-lib", "/flag/library", "-editor", "flag editor"}, defaults)
	if err != nil {
		t.Fatal(err)
	}
	if options.Config.LibraryPath != "/flag/library" || options.Config.Editor != "flag editor" {
		t.Fatalf("flags did not win: %+v", options.Config)
	}
}
