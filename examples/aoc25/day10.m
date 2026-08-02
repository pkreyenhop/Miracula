|| Advent of Code 2025 - Day 10: Lights Out Switch Solver (Pure Miracula)
||
|| Each line holds a [target] light pattern, then (i,j,...) switches that
|| toggle the listed positions. Find the fewest switch presses producing
|| the target from all-off, summed over every line. Search by iterative
|| deepening on the press count: try every k-subset of the switches for
|| k = 0, 1, 2, ... and stop at the first k that matches.

split_by10 c [] = [[]]
split_by10 c (x:xs) = if x == c then [] : split_by10 c xs else (x : hd rest) : tl rest
                     where
                     rest = split_by10 c xs

not_empty10 l = l ~= ""

elem10 x [] = False
elem10 x (y:ys) = if x == y then True else elem10 x ys

flip10 c = if c == '#' then '.' else '#'

toggle10 idxs state = go 0 state
  where
  go i [] = []
  go i (c:cs) = (if elem10 i idxs then flip10 c else c) : go (i+1) cs

|| all k-element subsets, as a lazy list
choose10 0 xs = [[]]
choose10 k [] = []
choose10 k (x:xs) = [ x : rest | rest <- choose10 (k-1) xs ] ++ choose10 k xs

|| drop the surrounding brackets/parens of a token
strip_ends10 s = take (length s - 2) (drop 1 s)

parse_line10 l = (target, switches)
  where
  toks = filter not_empty10 (split_by10 ' ' l)
  target = strip_ends10 (hd toks)
  switches = [ map numval (split_by10 ',' (strip_ends10 t)) | t <- tl toks; hd t == '(' ]

fst10 (a, b) = a
snd10 (a, b) = b

solve_line10 l = search 0
  where
  parsed = parse_line10 l
  target = fst10 parsed
  switches = snd10 parsed
  n_sw = length switches
  blank = map (\c. '.') target
  apply_all [] state = state
  apply_all (sw:sws) state = apply_all sws (toggle10 sw state)
  any_match [] = False
  any_match (combo:rest) = if apply_all combo blank == target then True else any_match rest
  search k = if k > n_sw then 0
             else (if any_match (choose10 k switches) then k else search (k+1))

solvePart1 input = sum (map solve_line10 (filter not_empty10 (lines input)))

main = "Advent of Code 2025 - Day 10 Results:\n" ++
       "  Part 1 (Shortest combination count): " ++ show p1Result ++ "\n"
       where
       input = read "examples/aoc25/data/day10.txt"
       p1Result = solvePart1 input

