#!/usr/bin/env python3
"""R1.4 helper: convert C-style word.printf/fprintf/putc/putchar call sites to
Zig-native word.print / word.printErr / FILE.print / FILE.writeByte.

Only the format string is translated (%s->{s}, %ld/%d->{d}, %c->{c}, %x->{x},
%o->{o}, %f/%e->{d}, %%->%); the arg tuple is left untouched because the
Zig-native printers now unwrap the legacy double-brace convention.

Calls the script cannot translate confidently (width specifiers, multi-line,
unusual targets) are left as-is and reported, for manual handling.
"""
import re, sys

STRING_RE = r'"((?:[^"\\]|\\.)*)"'  # a Zig string literal, honoring \" escapes

def translate_fmt(s: str):
    """Translate C printf specifiers in the format-string body `s` to Zig.
    Returns (new_s, ok). ok=False if a width/precision spec is present."""
    # width/precision (e.g. %3ld, %-20s, %.2f, %*s) -> bail, handle by hand
    if re.search(r'%[-+ #]*[0-9*]+\.?[0-9*]*[a-zA-Z]', s) or re.search(r'%\.[0-9*]+[a-zA-Z]', s):
        return s, False
    # escape literal braces for Zig format
    s = s.replace('{', '{{').replace('}', '}}')
    s = s.replace('%%', '\x00')               # protect literal percent
    s = re.sub(r'%l*[di]', '{d}', s)
    s = re.sub(r'%l*u', '{d}', s)
    s = re.sub(r'%l*x', '{x}', s)
    s = re.sub(r'%l*o', '{o}', s)
    s = re.sub(r'%[feEgG]', '{d}', s)
    s = re.sub(r'%c', '{c}', s)
    s = re.sub(r'%l*s', '{s}', s)
    if '%' in s:                              # an unhandled specifier slipped through
        return s, False                       # (checked before restoring literal %%)
    s = s.replace('\x00', '%')
    return s, True

STDERR_TARGETS = (
    'getStderr().?', 'getStderr()', 'main.getStderr().?', 'main.getStderr()',
    'stderr', 'clib.stderr()', 'word.stderr().?', 'word.stderr()',
)

def convert_line(line: str, stats):
    out = line
    # word.printf("fmt", args)  ->  word.print("fmt'", args)
    def do_printf(m):
        fmt, ok = translate_fmt(m.group(1))
        if not ok:
            stats['skipped'] += 1; return m.group(0)
        stats['printf'] += 1
        return 'word.print("' + fmt + '"'
    out = re.sub(r'word\.printf\(' + STRING_RE, do_printf, out)

    # word.fprintf(TARGET, "fmt", args)
    def do_fprintf(m):
        target = m.group(1).strip()
        fmt, ok = translate_fmt(m.group(2))
        if not ok:
            stats['skipped'] += 1; return m.group(0)
        if target in STDERR_TARGETS:
            stats['fprintf_err'] += 1
            return 'word.printErr("' + fmt + '"'
        stats['fprintf_file'] += 1
        return 'word.fprint(' + target + ', "' + fmt + '"'
    out = re.sub(r'word\.fprintf\(([^,]+),\s*' + STRING_RE, do_fprintf, out)
    return out

def main():
    path = sys.argv[1]
    src = open(path).read()
    stats = dict(printf=0, fprintf_err=0, fprintf_file=0, skipped=0)
    new = '\n'.join(convert_line(l, stats) for l in src.split('\n'))
    if new != src:
        open(path, 'w').write(new)
    print(f"{path}: printf={stats['printf']} fprintf_err={stats['fprintf_err']} "
          f"fprintf_file={stats['fprintf_file']} skipped={stats['skipped']}")

if __name__ == '__main__':
    main()
