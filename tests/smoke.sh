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

printf 'smoke tests passed\n'
