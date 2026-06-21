#!/usr/bin/env python3
import os
import re

FILES_TO_PROCESS = [
    "src/compiler/dump.zig",
    "src/compiler/module_loader.zig",
    "src/driver/commands.zig",
    "src/driver/repl.zig",
    "src/driver/startup.zig",
    "src/io/files.zig",
    "src/parser/lex.zig",
    "src/runtime/reduce.zig",
    "src/runtime/reducer/lex.zig",
    "src/runtime/reducer/ready.zig",
]

FUNCTIONS = [
    "strcmp", "strcpy", "strlen", "strcat", "strncmp", "strncpy", "strncat",
    "strchr", "strrchr", "strstr", "rindex"
]

def process_file(filepath):
    with open(filepath, "r") as f:
        content = f.read()

    # Determine depth for word import
    parts = filepath.split("/")
    depth = len(parts) - 2
    if depth == 0:
        import_path = "word.zig"
    elif depth == 1:
        import_path = "../runtime/word.zig"
    else:
        import_path = "../" * (depth - 1) + "word.zig"

    # Add word import if not present
    if 'const word = @import(' not in content:
        # Insert after the first import line
        match = re.search(r'const\s+\w+\s*=\s*@import\("[^"]+"\);', content)
        if match:
            pos = match.end()
            content = content[:pos] + f'\nconst word = @import("{import_path}");' + content[pos:]
        else:
            content = f'const word = @import("{import_path}");\n' + content

    # Replace clib.strcmp etc. with word.strcmp
    for func in FUNCTIONS:
        pattern = r'\b(clib|c)\.' + func + r'\b'
        content = re.sub(pattern, "word." + func, content)

    with open(filepath, "w") as f:
        f.write(content)

    print(f"Processed: {filepath}")

def main():
    for fp in FILES_TO_PROCESS:
        if os.path.exists(fp):
            process_file(fp)
        else:
            print(f"Warning: File not found {fp}")

if __name__ == "__main__":
    main()
