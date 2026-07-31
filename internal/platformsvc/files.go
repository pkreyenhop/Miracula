package platformsvc

import (
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/pkreyenhop/miracula-go/internal/protocol"
)

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
