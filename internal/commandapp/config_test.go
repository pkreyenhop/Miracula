package commandapp

import (
	"github.com/pkreyenhop/miracula/internal/application"
	"github.com/pkreyenhop/miracula/internal/platformsvc"
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
	if config.RCPath != filepath.Join(home, ".mirarc") {
		t.Fatalf("rc path = %q", config.RCPath)
	}
}

func TestReadRCWrittenInCurrentLegacyFormat(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".mirarc")
	if err := os.WriteFile(path, []byte("hdvelr 3000000 200000 2067 vi +!\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	config, ok := readRC(path, application.DefaultConfig())
	if !ok || config.HeapCells != 3000000 || config.DictionaryCells != 200000 || config.Editor != "vi +!" || !config.List || !config.Recheck {
		t.Fatalf("loaded=%v config=%+v", ok, config)
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

func TestEnvironmentLocaleAndOneShotPrecedence(t *testing.T) {
	tests := []struct {
		locale string
		utf8   bool
	}{{"en_NZ.UTF-8", true}, {"C", false}, {"de_DE.ISO-8859-1", false}}
	for _, test := range tests {
		config := resolveDefaults(configServices{"LANG": test.locale, "MIRAPROMPT": "m> ", "RECHECKMIRA": "1", "NOSTRICTIF": "1"})
		if config.UTF8 != test.utf8 || config.Prompt != "m> " || !config.Recheck || config.StrictIf {
			t.Errorf("locale %q config = %+v", test.locale, config)
		}
	}
	config := resolveDefaults(configServices{"LC_ALL": "C", "LANG": "en_US.UTF-8"})
	if config.UTF8 {
		t.Fatal("LC_ALL did not override LANG")
	}
}
