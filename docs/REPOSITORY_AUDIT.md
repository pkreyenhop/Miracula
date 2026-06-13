# Repository Audit

This document inventories and classifies all top-level files and directories in the Miranda compiler repository.

## Inventory Table

| Path | Classification | Reason |
| ---- | -------------- | ------ |
| `.clang-format` | `Active` | Configuration file for C/Zig code style formatting. |
| `.date` | `Obsolete` | Metadata file containing build date; replaced by `build.zig`. |
| `.epoch` | `Obsolete` | Metadata file containing build epoch; replaced by `build.zig`. |
| `.gitignore` | `Active` | Configuration specifying ignored files for Git version control. |
| `.nextxversion` | `Obsolete` | Metadata file containing version tracking; replaced by `build.zig`. |
| `.version` | `Obsolete` | Metadata file containing version tracking; replaced by `build.zig`. |
| `.xversion` | `Obsolete` | Metadata file containing version tracking; replaced by `build.zig`. |
| `ARCHITECTURE.md` | `Active` | Architectural overview; moved to `docs/ARCHITECTURE.md`. |
| `CHANGES.md` | `Active` | Changelog and release notes history; moved to `docs/CHANGES.md`. |
| `COPYING` | `Active` | Miranda license details; renamed to `LICENSE`. |
| `ChangeLog` | `Legacy` | Historical project changelog. |
| `DECOMPOSITION.md` | `Active` | Historical modularization notes; moved to `docs/DECOMPOSITION.md`. |
| `Makefile` | `Obsolete` | Historical C build configuration; replaced by `build.zig`. |
| `README` | `Obsolete` | Legacy plain text README; replaced by `README.md`. |
| `README.md` | `Active` | Modern markdown project README. |
| `REDUCER_ARCHITECTURE.md` | `Active` | Reducer subsystem architecture overview; moved to `docs/REDUCER_ARCHITECTURE.md`. |
| `ZIG_MIGRATION.md` | `Active` | Migration progress and plans; moved to `docs/ZIG_MIGRATION.md`. |
| `allexterns` | `Legacy` | Retained; contains C function and variable extern declarations required by compiler `@cImport` modules. |
| `big.h` | `Legacy` | C header file imported by Zig and legacy C parser code. |
| `build.zig` | `Active` | Standard Zig build configuration script. |
| `cleanup.md` | `Obsolete` | Temporary migration clean up notes. |
| `combs.h` | `Legacy` | C header file imported by Zig and legacy C parser code. |
| `data.h` | `Legacy` | C header file imported by Zig and legacy C parser code. |
| `ex` | `Legacy` | Compatibility symlink to `miralib/ex` examples directory. |
| `fdate.zig` | `Active` | Date utility program compiled and used during build. |
| `gencdecs` | `Obsolete` | Shell script for generating `combs.h` and `cmbnms.c`. |
| `issues/` | `Legacy` | Historical issue tracker logs. |
| `just.1` | `Active` | Man page for the `just` text formatter. |
| `just.zig` | `Active` | Source code for the `just` text formatting utility. |
| `lex.h` | `Legacy` | C header file imported by Zig and legacy C parser code. |
| `linkmenudriver` | `Obsolete` | Old shell script wrapper to set up legacy script symlinks. |
| `makehtml.sh` | `Obsolete` | Old shell script for generating HTML manuals from troff. |
| `menudriver.zig` | `Active` | Source code for the `menudriver` UI launcher utility. |
| `mira.1` | `Active` | Standard man page for the `mira` interpreter. |
| `mira.man.ms` | `Legacy` | Source troff document for UNIX man page. |
| `miralib/` | `Active` | Miranda standard library scripts and system preludes. |
| `platform.h` | `Legacy` | C header file imported by Zig and legacy C parser code. |
| `quotehostinfo` | `Obsolete` | Shell script to format host compile info; replaced by `build.zig`. |
| `reduce_internal.h` | `Legacy` | C header file imported by Zig and legacy C parser code. |
| `revdate` | `Obsolete` | Shell script to compute revision date; replaced by `build.zig`. |
| `runtime.h` | `Legacy` | C header file imported by Zig and legacy C parser code. |
| `script.m` | `Legacy` | Simple example Miranda script. |
| `signals.h` | `Legacy` | C header file imported by Zig and legacy C parser code. |
| `src/` | `Active` | Root source directory containing the compiler runtime. |
| `tests/` | `Active` | Integration tests and verified golden test suites. |
| `tidy.txt` | `Obsolete` | Obsolete project task checklist. |
| `toks.m` | `Obsolete` | Legacy Miranda source script. |
| `utf8.h` | `Legacy` | C header file imported by Zig and legacy C parser code. |
| `version.h` | `Legacy` | C header file imported by Zig and legacy C parser code. |
| `warnings.md` | `Obsolete` | Obsolete compiler warning logs. |
| `docs/` | `Active` | Documentation directory containing project reports. |
