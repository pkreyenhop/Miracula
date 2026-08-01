package commandapp

import (
	"bufio"
	"github.com/pkreyenhop/miracula/internal/application"
	"github.com/pkreyenhop/miracula/internal/platformsvc"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

func environmentConfig(services platformsvc.Services, config application.Config) application.Config {
	if value, ok := services.Environment("MIRALIB"); ok && value != "" {
		config.LibraryPath = value
	}
	if value, ok := services.Environment("EDITOR"); ok && value != "" {
		config.Editor = value
	}
	if value, ok := services.Environment("MIRAPROMPT"); ok {
		config.Prompt = value
	}
	if _, ok := services.Environment("RECHECKMIRA"); ok {
		config.Recheck = true
	}
	if _, ok := services.Environment("NOSTRICTIF"); ok {
		config.StrictIf = false
	}
	return config
}

func environmentOneShots(services platformsvc.Services, config application.Config) application.Config {
	if value, ok := services.Environment("MIRAPROMPT"); ok {
		config.Prompt = value
	}
	if _, ok := services.Environment("RECHECKMIRA"); ok {
		config.Recheck = true
	}
	if _, ok := services.Environment("NOSTRICTIF"); ok {
		config.StrictIf = false
	}
	return config
}

func readRC(path string, config application.Config) (application.Config, bool) {
	file, err := os.Open(path)
	if err != nil {
		return config, false
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	if !scanner.Scan() {
		return config, false
	}
	fields := strings.Fields(scanner.Text())
	if len(fields) < 5 || (!strings.HasPrefix(fields[0], "hdve") && !strings.HasPrefix(fields[0], "lhdve")) {
		return config, false
	}
	heap, heapErr := strconv.Atoi(fields[1])
	dictionary, dictionaryErr := strconv.Atoi(fields[2])
	if heapErr != nil || dictionaryErr != nil || heap < 100 || heap > 50000000 || dictionary < 100 || dictionary > 50000000 {
		return config, false
	}
	config.HeapCells, config.DictionaryCells = heap, dictionary
	config.Editor = strings.Join(fields[4:], " ")
	config.List = strings.HasPrefix(fields[0], "l") || strings.Contains(fields[0], "l")
	config.Recheck = strings.Contains(fields[0], "r")
	return config, true
}

func resolveDefaults(services platformsvc.Services) application.Config {
	config := application.DefaultConfig()
	if executable, err := os.Executable(); err == nil {
		installedLibrary := filepath.Clean(filepath.Join(filepath.Dir(executable), "..", "lib", "miralib"))
		if info, statErr := os.Stat(installedLibrary); statErr == nil && info.IsDir() {
			config.LibraryPath = installedLibrary
		}
	}
	config = environmentConfig(services, config)
	if home, ok := services.Environment("HOME"); ok {
		if loaded, found := readRC(filepath.Join(home, ".mirarc"), config); found {
			return environmentOneShots(services, loaded)
		}
	}
	if loaded, found := readRC(filepath.Join(config.LibraryPath, ".mirarc"), config); found {
		return environmentOneShots(services, loaded)
	}
	return environmentOneShots(services, config)
}
