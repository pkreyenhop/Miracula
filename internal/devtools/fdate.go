package devtools

import (
	"fmt"
	"os"
	"time"
)

func FileDate(path string) (string, error) {
	info, e := os.Stat(path)
	if e != nil {
		return "", e
	}
	t := info.ModTime().Local()
	return fmt.Sprintf("%d %s %4d", t.Day(), t.Month(), t.Year()), nil
}
func EpochDate(seconds int64) string {
	t := time.Unix(seconds, 0).UTC()
	return fmt.Sprintf("%d %s %4d", t.Day(), t.Month(), t.Year())
}
