#! /bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMPDIR=${TMPDIR:-/tmp}
TEST_HOME=$(mktemp -d "$TMPDIR/mira-test.XXXXXX")
TEST_WORK=$(mktemp -d "$TMPDIR/mira-work.XXXXXX")

cleanup()
{
	rm -rf "$TEST_HOME"
	rm -rf "$TEST_WORK"
}
trap cleanup EXIT HUP INT TERM

run_mira()
{
	name=$1
	script=$2
	input=$3
	expected=$4

	if [ -n "$script" ]; then
		output=$(printf "%s" "$input" |
			HOME="$TEST_HOME" "$ROOT/mira" -lib "$ROOT/miralib" -hush "$script")
	else
		output=$(printf "%s" "$input" |
			HOME="$TEST_HOME" "$ROOT/mira" -lib "$ROOT/miralib" -hush)
	fi

	if [ "$output" != "$expected" ]; then
		printf 'FAIL: %s\n' "$name" >&2
		printf 'expected:\n%s\n' "$expected" >&2
		printf 'got:\n%s\n' "$output" >&2
		exit 1
	fi
}

repeat_char()
{
	awk -v count="$1" -v char="$2" 'BEGIN {
		for (i = 0; i < count; i++) {
			printf "%s", char
		}
	}'
}

run_mira_expect_stderr()
{
	name=$1
	script=$2
	input=$3
	expected_output=$4
	expected_stderr=$5
	shift 5
	stderr_file=$TEST_WORK/$name.stderr

	set +e
	output=$(printf "%s" "$input" |
		HOME="$TEST_HOME" "$ROOT/mira" "$@" -lib "$ROOT/miralib" -hush "$script" 2>"$stderr_file")
	status=$?
	set -e

	if [ "$status" -ne 0 ]; then
		printf 'FAIL: %s exited with status %s\n' "$name" "$status" >&2
		printf 'stderr:\n' >&2
		sed -n '1,40p' "$stderr_file" >&2
		exit 1
	fi

	if [ "$output" != "$expected_output" ]; then
		printf 'FAIL: %s\n' "$name" >&2
		printf 'expected:\n%s\n' "$expected_output" >&2
		printf 'got:\n%s\n' "$output" >&2
		exit 1
	fi

	if ! grep -F "$expected_stderr" "$stderr_file" >/dev/null; then
		printf 'FAIL: %s\n' "$name" >&2
		printf 'expected stderr to contain:\n%s\n' "$expected_stderr" >&2
		printf 'got stderr:\n' >&2
		sed -n '1,40p' "$stderr_file" >&2
		exit 1
	fi
}

write_compile_stress_script()
{
	path=$1
	items=$2

	awk -v items="$items" 'BEGIN {
		print "stress_list"
		print "=["
		for (i = 0; i < items; i++) {
			printf "  \"compile-time-stress-%04d\",\n", i
		}
		print "  \"compile-time-stress-end\"]"
		print "stress_len = # stress_list"
	}' >"$path"
}

run_compile_time_guard()
{
	name=$1
	script=$2
	limit=${MIRA_COMPILE_TIMEOUT:-15}
	stdout_file=$TEST_WORK/$name.stdout
	stderr_file=$TEST_WORK/$name.stderr

	if ! command -v timeout >/dev/null 2>&1; then
		printf 'SKIP: %s, timeout command unavailable\n' "$name"
		return
	fi

	if ! HOME="$TEST_HOME" timeout "$limit" "$ROOT/mira" -lib "$ROOT/miralib" -hush -make "$script" \
		>"$stdout_file" 2>"$stderr_file"; then
		printf 'FAIL: %s exceeded %ss or failed to compile\n' "$name" "$limit" >&2
		printf 'stdout:\n' >&2
		sed -n '1,40p' "$stdout_file" >&2
		printf 'stderr:\n' >&2
		sed -n '1,40p' "$stderr_file" >&2
		exit 1
	fi
}

run_standard_lib_load_guard()
{
	name=$1
	limit=${MIRA_STDLIB_TIMEOUT:-10}
	stdlib_home=$TEST_WORK/$name.home
	stdout_file=$TEST_WORK/$name.stdout
	stderr_file=$TEST_WORK/$name.stderr
	expected='3628800
[3,2,1]
abcdef'

	if ! command -v timeout >/dev/null 2>&1; then
		printf 'SKIP: %s, timeout command unavailable\n' "$name"
		return
	fi

	mkdir "$stdlib_home"
	if ! printf 'product [1..10]\nreverse [1,2,3]\n"abc" ++ "def"\n/q\n' |
		HOME="$stdlib_home" timeout "$limit" "$ROOT/mira" -lib "$ROOT/miralib" -hush \
			>"$stdout_file" 2>"$stderr_file"; then
		printf 'FAIL: %s exceeded %ss or failed while loading standard lib\n' "$name" "$limit" >&2
		printf 'stdout:\n' >&2
		sed -n '1,40p' "$stdout_file" >&2
		printf 'stderr:\n' >&2
		sed -n '1,40p' "$stderr_file" >&2
		exit 1
	fi

	output=$(cat "$stdout_file")
	if [ "$output" != "$expected" ]; then
		printf 'FAIL: %s\n' "$name" >&2
		printf 'expected:\n%s\n' "$expected" >&2
		printf 'got:\n%s\n' "$output" >&2
		exit 1
	fi
}

run_mira "standard arithmetic and lists" "" "1+2
product [1..10]
map (2*) [1..5]
/q
" "3
3628800
[2,4,6,8,10]"

run_mira "big integers" "" "12345678901234567890 + 10
2^80
/q
" "12345678901234567900
1208925819614629174706176"

run_mira "lazy lists and strings" "" "take 5 [1..]
reverse [1,2,3]
zip2 [1,2,3] [4,5,6]
\"abc\" ++ \"def\"
/q
" "[1,2,3,4,5]
[3,2,1]
[(1,4),(2,5),(3,6)]
abcdef"

run_mira "example script fib" "$ROOT/miralib/ex/fib" "fib 10
/q
" "55"

cat > "$TEST_WORK/user-defs.m" <<'EOF'
square x = x*x
twice f x = f (f x)
pairup x y = (x,y)
EOF

run_mira "user script definitions" "$TEST_WORK/user-defs.m" "square 12
twice square 2
pairup \"a\" [1,2]
/q
" "144
16
(\"a\",[1,2])"

run_mira "type error reporting" "" "1 + \"x\"
/q
" "type error in expression
cannot unify [char] with num"

run_mira "syntax error reporting" "" "1 +
/q
" "syntax error - unexpected newline"

long_string=$(repeat_char 4096 a)
long_integer=$(repeat_char 512 9)
long_integer_plus_one=1$(repeat_char 512 0)

run_mira "very long literals" "" "# \"$long_string\"
$long_integer + 1
/q
" "4096
$long_integer_plus_one"

compile_stress=$TEST_WORK/compile-stress.m
write_compile_stress_script "$compile_stress" 1500
run_compile_time_guard "compile time stress guard" "$compile_stress"
run_standard_lib_load_guard "standard lib load speed guard"

compile_gc_stress=$TEST_WORK/compile-gc-stress.m
write_compile_stress_script "$compile_gc_stress" 600
run_mira_expect_stderr "compile-gc-stress" "$compile_gc_stress" "stress_len
/q
" "601" "<<gc after" -heap 25000 -gc

run_mira_expect_stderr "runtime-gc-stress" "" "sum [1..4000]
/q
" "8002000" "<<gc after" -heap 12000 -gc

printf 'smoke tests passed\n'
