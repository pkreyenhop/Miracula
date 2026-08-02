// Command package builds and packages the production Miranda executable using
// only the Go toolchain and Go standard library.
package main

import (
	"archive/tar"
	"compress/gzip"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

const module = "github.com/pkreyenhop/miracula/internal/buildcfg."

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(arguments []string) error {
	if len(arguments) == 0 {
		return errors.New("usage: go run ./internal/cmd/package <build|install|uninstall|archive|clean>")
	}
	root, err := repositoryRoot()
	if err != nil {
		return err
	}
	switch arguments[0] {
	case "build":
		flags := flag.NewFlagSet("build", flag.ContinueOnError)
		output := flags.String("output", filepath.Join(root, "build", "mira"), "output executable")
		if err = flags.Parse(arguments[1:]); err != nil {
			return err
		}
		return build(root, absolute(root, *output))
	case "install", "uninstall":
		flags := flag.NewFlagSet(arguments[0], flag.ContinueOnError)
		prefix := flags.String("prefix", "/usr/local", "absolute installation prefix")
		destdir := flags.String("destdir", "/", "staging root")
		if err = flags.Parse(arguments[1:]); err != nil {
			return err
		}
		if !filepath.IsAbs(*prefix) {
			return errors.New("--prefix must be absolute")
		}
		target := filepath.Join(*destdir, strings.TrimPrefix(filepath.Clean(*prefix), string(filepath.Separator)))
		if arguments[0] == "install" {
			return install(root, target)
		}
		return uninstall(target)
	case "archive":
		flags := flag.NewFlagSet("archive", flag.ContinueOnError)
		output := flags.String("output", filepath.Join(root, "build", "miracula-darwin-arm64.tar.gz"), "output archive")
		if err = flags.Parse(arguments[1:]); err != nil {
			return err
		}
		return archive(root, absolute(root, *output))
	case "clean":
		return clean(root)
	default:
		return fmt.Errorf("unknown package command %q", arguments[0])
	}
}

func repositoryRoot() (string, error) {
	command := exec.Command("git", "rev-parse", "--show-toplevel")
	output, err := command.Output()
	if err != nil {
		return "", errors.New("package must run inside the repository")
	}
	return strings.TrimSpace(string(output)), nil
}

func absolute(root, path string) string {
	if filepath.IsAbs(path) {
		return path
	}
	return filepath.Join(root, path)
}

func git(root string, arguments ...string) string {
	command := exec.Command("git", arguments...)
	command.Dir = root
	output, err := command.Output()
	if err != nil {
		return "unknown"
	}
	return strings.TrimSpace(string(output))
}

func epoch(root string) int64 {
	text := os.Getenv("SOURCE_DATE_EPOCH")
	if text == "" {
		text = git(root, "show", "-s", "--format=%ct", "HEAD")
	}
	value, _ := strconv.ParseInt(text, 10, 64)
	return value
}

func build(root, output string) error {
	if err := os.MkdirAll(filepath.Dir(output), 0o755); err != nil {
		return err
	}
	temporary, err := os.MkdirTemp(filepath.Dir(output), ".miracula-build-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(temporary)
	executable := filepath.Join(temporary, "mira")
	date := time.Unix(epoch(root), 0).UTC().Format("2006-01-02")
	ldflags := strings.Join([]string{"-s", "-w", "-X=" + module + "Commit=" + git(root, "rev-parse", "HEAD"), "-X=" + module + "VersionDate=" + date, "-X=" + module + "Host=go-production-build"}, " ")
	command := exec.Command("go", "build", "-trimpath", "-buildvcs=false", "-ldflags", ldflags, "-o", executable, "./cmd/mira")
	command.Dir, command.Stdout, command.Stderr = root, os.Stdout, os.Stderr
	if err = command.Run(); err != nil {
		return err
	}
	return os.Rename(executable, output)
}

func install(root, target string) error {
	if err := build(root, filepath.Join(target, "bin", "mira")); err != nil {
		return err
	}
	if err := copyTree(filepath.Join(root, "lib", "miralib"), filepath.Join(target, "lib", "miralib")); err != nil {
		return err
	}
	docs := filepath.Join(target, "share", "doc", "miracula")
	if err := os.MkdirAll(docs, 0o755); err != nil {
		return err
	}
	if err := copyFile(filepath.Join(root, "README.md"), filepath.Join(docs, "README.md")); err != nil {
		return err
	}
	return copyFile(filepath.Join(root, "lib", "miralib", "COPYING"), filepath.Join(docs, "COPYING"))
}

func uninstall(target string) error {
	if err := os.Remove(filepath.Join(target, "bin", "mira")); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	for _, path := range []string{filepath.Join(target, "lib", "miralib"), filepath.Join(target, "share", "doc", "miracula")} {
		if err := os.RemoveAll(path); err != nil {
			return err
		}
	}
	return nil
}

func ignored(path string, entry fs.DirEntry) bool {
	name := entry.Name()
	return name == "__pycache__" || name == ".DS_Store" || name == "preludx" || strings.HasSuffix(name, ".x")
}

func copyTree(source, target string) error {
	return filepath.WalkDir(source, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if ignored(path, entry) {
			if entry.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		relative, _ := filepath.Rel(source, path)
		destination := filepath.Join(target, relative)
		if entry.IsDir() {
			return os.MkdirAll(destination, 0o755)
		}
		return copyFile(path, destination)
	})
}

func copyFile(source, target string) error {
	input, err := os.Open(source)
	if err != nil {
		return err
	}
	defer input.Close()
	if err = os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		return err
	}
	info, err := input.Stat()
	if err != nil {
		return err
	}
	output, err := os.OpenFile(target, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, info.Mode().Perm())
	if err != nil {
		return err
	}
	_, copyErr := io.Copy(output, input)
	closeErr := output.Close()
	if copyErr != nil {
		return copyErr
	}
	return closeErr
}

func archive(root, output string) error {
	temporary, err := os.MkdirTemp("", "miracula-package-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(temporary)
	staging := filepath.Join(temporary, "stage")
	if err = install(root, staging); err != nil {
		return err
	}
	if err = os.MkdirAll(filepath.Dir(output), 0o755); err != nil {
		return err
	}
	raw, err := os.Create(output)
	if err != nil {
		return err
	}
	defer raw.Close()
	compressed, err := gzip.NewWriterLevel(raw, gzip.BestCompression)
	if err != nil {
		return err
	}
	compressed.Name, compressed.ModTime = "", time.Unix(epoch(root), 0).UTC()
	tarball := tar.NewWriter(compressed)
	var paths []string
	if err = filepath.WalkDir(staging, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr == nil && path != staging {
			paths = append(paths, path)
		}
		return walkErr
	}); err != nil {
		return err
	}
	sort.Strings(paths)
	for _, path := range paths {
		info, statErr := os.Lstat(path)
		if statErr != nil {
			return statErr
		}
		header, headerErr := tar.FileInfoHeader(info, "")
		if headerErr != nil {
			return headerErr
		}
		relative, _ := filepath.Rel(staging, path)
		header.Name = filepath.ToSlash(filepath.Join("miracula", relative))
		header.Uid, header.Gid, header.Uname, header.Gname = 0, 0, "root", "root"
		header.ModTime, header.AccessTime, header.ChangeTime = time.Unix(epoch(root), 0).UTC(), time.Time{}, time.Time{}
		if err = tarball.WriteHeader(header); err != nil {
			return err
		}
		if info.Mode().IsRegular() {
			file, openErr := os.Open(path)
			if openErr != nil {
				return openErr
			}
			_, copyErr := io.Copy(tarball, file)
			file.Close()
			if copyErr != nil {
				return copyErr
			}
		}
	}
	if err = tarball.Close(); err != nil {
		return err
	}
	return compressed.Close()
}

func clean(root string) error {
	if err := os.RemoveAll(filepath.Join(root, "build")); err != nil {
		return err
	}
	return filepath.WalkDir(root, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() && (entry.Name() == ".git" || entry.Name() == "build") {
			return filepath.SkipDir
		}
		if !entry.IsDir() && (entry.Name() == "preludx" || strings.HasSuffix(entry.Name(), ".x")) {
			return os.Remove(path)
		}
		return nil
	})
}
