package platformsvc

import (
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/pkreyenhop/miracula-go/internal/protocol"
)

// AtomicReplace writes a complete file beside its destination and then
// renames it into place. A failed write never exposes a partial destination.
func AtomicReplace(path string, data []byte, mode os.FileMode) error {
	directory := filepath.Dir(path)
	temporary, err := os.CreateTemp(directory, ".miracula-*")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err = temporary.Chmod(mode); err == nil {
		_, err = temporary.Write(data)
	}
	if err == nil {
		err = temporary.Sync()
	}
	if closeErr := temporary.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	return os.Rename(temporaryPath, path)
}

type FilesWord = protocol.Word

func FileMtime(path string) protocol.Word {
	if i, ok := GetFileInfo(path); ok {
		return protocol.Word(i.ModifiedSeconds)
	}
	return 0
}
func IsMirandaSource(path string) bool { return strings.HasSuffix(path, ".m") }
func SameFile(a, b FileMetadata) bool  { return a.Identity == b.Identity }
func InodeID(path string) FileIdentity {
	if i, ok := GetFileInfo(path); ok {
		return i.Identity
	}
	return FileIdentity{}
}
func FileExists(path string) bool { _, ok := GetFileInfo(path); return ok }
func FileCopy(path string, w io.Writer) error {
	f, e := os.Open(path)
	if e != nil {
		return e
	}
	defer f.Close()
	_, e = io.Copy(w, f)
	return e
}
func CopyFile(from, to string) error {
	in, e := os.Open(from)
	if e != nil {
		return e
	}
	defer in.Close()
	out, e := os.OpenFile(to, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if e != nil {
		return e
	}
	_, copyErr := io.Copy(out, in)
	closeErr := out.Close()
	if copyErr != nil {
		return copyErr
	}
	return closeErr
}
func UnlinkObject(source, suffix string) error {
	if source == "" {
		return nil
	}
	return os.Remove(strings.TrimSuffix(source, filepath.Ext(source)) + suffix)
}
func MakeAbsolute(path string) (string, error) { return filepath.Abs(path) }
func TermWidth() int {
	if columns, ok := TerminalWidth(os.Stdout.Fd()); ok {
		return int(columns) - 2
	}
	return 78
}
