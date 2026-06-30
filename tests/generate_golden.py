#!/usr/bin/env python3
import os
import subprocess
import sys

TEST_CASES = [
    {
        "name": "arith_add",
        "input": "1 + 2\n"
    },
    {
        "name": "arith_sub",
        "input": "10 - 3\n"
    },
    {
        "name": "arith_mul",
        "input": "7 * 8\n"
    },
    {
        "name": "arith_div",
        "input": "100 div 3\n"
    },
    {
        "name": "arith_rem",
        "input": "100 mod 3\n"
    },
    {
        "name": "arith_neg",
        "input": "-15\n"
    },
    {
        "name": "arith_assoc",
        "input": "1 + 2 * 3 - 4\n"
    },
    {
        "name": "arith_prec",
        "input": "(1 + 2) * 3\n"
    },
    {
        "name": "bignum_add",
        "input": "123456789012345678901234567890 + 987654321098765432109876543210\n"
    },
    {
        "name": "bignum_mul",
        "input": "12345678901234567890 * 98765432109876543210\n"
    },
    {
        "name": "bignum_pow",
        "input": "3^100\n"
    },
    {
        "name": "double_add",
        "input": "1.25 + 3.75\n"
    },
    {
        "name": "double_mul",
        "input": "2.5 * 4.2\n"
    },
    {
        "name": "double_div",
        "input": "7.5 / 2.5\n"
    },
    {
        "name": "double_trig",
        "input": "sin 0.0\n"
    },
    {
        "name": "list_literals",
        "input": "[1, 2, 3]\n"
    },
    {
        "name": "list_range_finite",
        "input": "[1..10]\n"
    },
    {
        "name": "list_range_step",
        "input": "[1, 3..15]\n"
    },
    {
        "name": "list_take",
        "input": "take 5 [1..]\n"
    },
    {
        "name": "list_map",
        "input": "map (2*) [1..5]\n"
    },
    {
        "name": "list_filter",
        "input": "filter (>3) [1..10]\n"
    },
    {
        "name": "list_foldl",
        "input": "foldl (+) 0 [1..10]\n"
    },
    {
        "name": "list_foldr",
        "input": "foldr (++) [] [\"a\", \"b\", \"c\"]\n"
    },
    {
        "name": "list_zip",
        "input": "zip2 [1,2,3] [4,5,6]\n"
    },
    {
        "name": "list_concat",
        "input": "[1,2] ++ [3,4]\n"
    },
    {
        "name": "string_lit",
        "input": "\"hello world\"\n"
    },
    {
        "name": "string_concat",
        "input": "\"abc\" ++ \"def\"\n"
    },
    {
        "name": "string_length",
        "input": "# \"hello\"\n"
    },
    {
        "name": "string_reverse",
        "input": "reverse \"hello\"\n"
    },
    {
        "name": "tuple_lit",
        "input": "(1, \"hello\", True)\n"
    },
    {
        "name": "tuple_pattern",
        "script": "sumpair (x, y) = x + y\n",
        "input": "sumpair (10, 20)\n"
    },
    {
        "name": "list_pattern",
        "script": "firstel (x:xs) = x\n",
        "input": "firstel [4, 5, 6]\n"
    },
    {
        "name": "custom_fib",
        "script": "fib 0 = 0\nfib 1 = 1\nfib n = fib (n-1) + fib (n-2)\n",
        "input": "fib 10\n"
    },
    {
        "name": "custom_ack",
        "script": "ack 0 n = n + 1\nack m 0 = ack (m - 1) 1\nack m n = ack (m - 1) (ack m (n - 1))\n",
        "input": "ack 3 3\n"
    },
    {
        "name": "custom_lazy",
        "script": "ones = 1 : ones\n",
        "input": "take 5 ones\n"
    },
    {
        "name": "type_class_labels",
        "script": (
            "|| Pins the type-declaration \"kind\" behaviour that depends on the tClass field:\n"
            "||  - the class label shown by ?name (finger) for each kind, and\n"
            "||  - derived-show of an algebraic value (regressed if tClass numbering drifts).\n"
            "colour ::= Red | Green | Blue\n"
            "type day == num\n"
            "abstype widget with same :: widget -> widget\n"
            "type widget == num\n"
            "same x = x\n"
        ),
        "input": "?colour\n?day\n?widget\nGreen\n[Red,Green,Blue]\n"
    },
    {
        "name": "show_int",
        "input": "show 123\n"
    },
    {
        "name": "show_double",
        "input": "show 12.34\n"
    },
    {
        "name": "show_string",
        "input": "show \"abc\"\n"
    },
    {
        "name": "show_list",
        "input": "show [1, 2, 3]\n"
    },
    {
        "name": "lex_err",
        "input": "1 + \"x\"\n"
    },
    {
        "name": "syntax_err",
        "input": "1 +\n"
    },
    {
        "name": "slash_command_help",
        "input": "/h\n"
    },
    {
        "name": "slash_command_count",
        "input": "1+2\n/count\n"
    },
    {
        "name": "lazy_io_readvals",
        "input": "take 3 readvals\n",
        "stdin_feed": "10\n20\n30\n"
    }
]

def clean_output(text):
    lines = []
    for line in text.splitlines():
        if line.startswith("||reductions =") or line.startswith("[TRACE]") or line.startswith("[ALLOC]") or line.startswith("[DIAG"):
            continue
        lines.append(line)
    return "\n".join(lines).strip()

def main():
    binary_path = "./zig-out/bin/mira"
    if not os.path.exists(binary_path):
        print(f"Error: Binary {binary_path} not found. Build first.")
        sys.exit(1)

    golden_dir = "./tests/golden"
    os.makedirs(golden_dir, exist_ok=True)

    for tc in TEST_CASES:
        name = tc["name"]
        print(f"Generating golden files for: {name}")

        script_path = ""
        if "script" in tc:
            script_path = os.path.join(golden_dir, f"{name}.m")
            with open(script_path, "w") as f:
                f.write(tc["script"])

        in_path = os.path.join(golden_dir, f"{name}.in")
        stdin_feed = tc.get("stdin_feed", "")
        full_input = tc["input"] + "\n/q\n"
        if stdin_feed:
            full_input = stdin_feed + full_input
            
        with open(in_path, "w") as f:
            f.write(full_input)

        cmd = [binary_path, "-lib", "./miralib", "-hush"]
        if script_path:
            cmd.append(script_path)

        proc = subprocess.run(
            cmd,
            input=full_input,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5
        )

        expected_stdout = clean_output(proc.stdout)
        expected_stderr = clean_output(proc.stderr)

        stdout_path = os.path.join(golden_dir, f"{name}.expected")
        with open(stdout_path, "w") as f:
            f.write(expected_stdout + "\n")

        if expected_stderr:
            stderr_path = os.path.join(golden_dir, f"{name}.expected_err")
            with open(stderr_path, "w") as f:
                f.write(expected_stderr + "\n")

    print("Successfully generated all golden files.")

if __name__ == "__main__":
    main()
