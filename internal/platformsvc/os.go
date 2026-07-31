//go:build darwin && arm64

package platformsvc

import (
	"os"
	"os/exec"
	"syscall"

	"github.com/pkreyenhop/miracula-go/internal/protocol"
)

type OsWord = protocol.Word
type OsUnicode = protocol.Unicode
type WaitStatusType = syscall.WaitStatus

func Open(path string, flag int, perm os.FileMode) (*os.File, error) {
	return os.OpenFile(path, flag, perm)
}
func Getcwd() (string, error)                   { return os.Getwd() }
func Chdir(path string) error                   { return os.Chdir(path) }
func Getenv(name string) (string, bool)         { return os.LookupEnv(name) }
func FindExecutable(name string) (string, bool) { p, e := exec.LookPath(name); return p, e == nil }
func Unlink(path string) error                  { return os.Remove(path) }
func Exit(code int)                             { os.Exit(code) }
