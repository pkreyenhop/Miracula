#!/usr/bin/env python3
import os
import subprocess
import sys
import time
import tempfile
import re

BENCHMARKS = {
    "Ackermann (3, 8)": {
        "script": """
ack 0 n = n + 1
ack m 0 = ack (m - 1) 1
ack m n = ack (m - 1) (ack m (n - 1))
""",
        "input": "ack 3 8\n"
    },
    "Fibonacci (30)": {
        "script": """
fib 0 = 0
fib 1 = 1
fib n = fib (n - 1) + fib (n - 2)
""",
        "input": "fib 30\n"
    },
    "Lazy Prime Sieve (take 500)": {
        "script": """
primes = sieve [2..]
sieve (p:xs) = p : sieve [x | x <- xs; x mod p ~= 0]
""",
        "input": "take 500 primes\n"
    }
}

def parse_stats(stderr_output):
    # Parse stats from lines like:
    # ||reductions = 125, cells claimed = 1000, no of gc's = 0, cpu = 0.01
    reductions = 0
    cells = 0
    gcs = 0
    
    for line in stderr_output.splitlines():
        if "reductions =" in line:
            m_red = re.search(r"reductions\s*=\s*(\d+)", line)
            m_cells = re.search(r"cells claimed\s*=\s*(\d+)", line)
            m_gcs = re.search(r"no of gc's\s*=\s*(\d+)", line)
            
            if m_red:
                reductions = int(m_red.group(1))
            if m_cells:
                cells = int(m_cells.group(1))
            if m_gcs:
                gcs = int(m_gcs.group(1))
                
    return reductions, cells, gcs

def run_benchmark(binary_path, name, config, iterations=3):
    print(f"Running macro-benchmark: {name} ...")
    
    # Create temp script file
    fd, temp_path = tempfile.mkstemp(suffix=".m")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(config["script"])
            
        times = []
        gcs_list = []
        reductions = 0
        cells = 0
        
        for i in range(iterations):
            # -count makes mira print "||reductions = N, cells claimed = M, ..."
            # to stderr after each evaluation; parse_stats() reads it from there.
            cmd = [binary_path, "-lib", "./miralib", "-count", temp_path]
            
            start_time = time.perf_counter()
            proc = subprocess.run(
                cmd,
                input=config["input"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15
            )
            elapsed = time.perf_counter() - start_time
            times.append(elapsed)
            
            red_i, cells_i, gcs_i = parse_stats(proc.stderr)
            reductions = max(reductions, red_i)
            cells = max(cells, cells_i)
            gcs_list.append(gcs_i)
            
        avg_time = sum(times) / len(times)
        avg_gcs = sum(gcs_list) / len(gcs_list)
        
        red_rate = (reductions / avg_time) if avg_time > 0 else 0
        
        return {
            "avg_time_ms": avg_time * 1000.0,
            "reductions": reductions,
            "cells": cells,
            "avg_gcs": avg_gcs,
            "red_rate_m": red_rate / 1_000_000.0
        }
        
    finally:
        os.remove(temp_path)

def main():
    binary_path = "./zig-out/bin/mira"
    if len(sys.argv) > 1:
        binary_path = sys.argv[1]
        
    if not os.path.exists(binary_path):
        print(f"Error: Binary {binary_path} not found.")
        sys.exit(1)
        
    print(f"=== Miracula Macro-Benchmarks ({binary_path}) ===\n")
    
    results = {}
    for name, config in BENCHMARKS.items():
        try:
            results[name] = run_benchmark(binary_path, name, config)
        except Exception as e:
            print(f"Failed to run benchmark {name}: {e}")
            
    print("\n| Benchmark Name | Avg Time (ms) | Reductions | Reclaimed GCs | Throughput (M reductions/s) |")
    print("|----------------|---------------|------------|---------------|-----------------------------|")
    for name, res in results.items():
        print(f"| {name} | {res['avg_time_ms']:.2f} | {res['reductions']} | {res['avg_gcs']:.1f} | {res['red_rate_m']:.3f} |")
    print()

if __name__ == "__main__":
    main()
