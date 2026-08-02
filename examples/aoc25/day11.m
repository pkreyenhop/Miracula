|| Advent of Code 2025 - Day 11: DAG Path Counting (Pure Miracula)
||
|| Each line "u: v w x" lists the outputs of node u. Part 1 counts the
|| distinct paths you -> out. Part 2 counts the paths svr -> out that pass
|| through both dac and fft; the memo key appends the two flags to the
|| node name. The memo map is threaded through the recursion the same way
|| aoc8.m threads its union-find parent map (-1 marks a memo miss).

split_by11 c [] = [[]]
split_by11 c (x:xs) = if x == c then [] : split_by11 c xs else (x : hd rest) : tl rest
                     where
                     rest = split_by11 c xs

not_empty11 l = l ~= ""

fst11 (a, b) = a
snd11 (a, b) = b

parse_adj11 [] adj = adj
parse_adj11 (l:ls) adj = parse_adj11 ls (h_insert adj u vs)
  where
  parts = split_by11 ':' l
  u = hd parts
  vs = filter not_empty11 (split_by11 ' ' (hd (tl parts)))

parse_input11 input = parse_adj11 (filter not_empty11 (lines input)) empty_map

solvePart1 input = fst11 (go "you" empty_map)
  where
  adj = parse_input11 input
  go u memo = if u == "out" then (1, memo)
              else (if cached ~= 0 - 1 then (cached, memo)
                    else (total, h_insert m2 u total))
              where
              cached = h_lookup_def memo u (0 - 1)
              res = go_list (h_lookup_def adj u []) memo
              total = fst11 res
              m2 = snd11 res
  go_list [] memo = (0, memo)
  go_list (v:vs) memo = (a + b, mb)
                        where
                        ra = go v memo
                        a = fst11 ra
                        ma = snd11 ra
                        rb = go_list vs ma
                        b = fst11 rb
                        mb = snd11 rb

solvePart2 input = fst11 (go "svr" False False empty_map)
  where
  adj = parse_input11 input
  go u dac fft memo = if u == "out" then ((if d2 & f2 then 1 else 0), memo)
                      else (if cached ~= 0 - 1 then (cached, memo)
                            else (total, h_insert m2 key total))
                      where
                      d2 = if u == "dac" then True else dac
                      f2 = if u == "fft" then True else fft
                      key = u ++ (if d2 then "1" else "0") ++ (if f2 then "1" else "0")
                      cached = h_lookup_def memo key (0 - 1)
                      res = go_list (h_lookup_def adj u []) d2 f2 memo
                      total = fst11 res
                      m2 = snd11 res
  go_list [] dac fft memo = (0, memo)
  go_list (v:vs) dac fft memo = (a + b, mb)
                                where
                                ra = go v dac fft memo
                                a = fst11 ra
                                ma = snd11 ra
                                rb = go_list vs dac fft ma
                                b = fst11 rb
                                mb = snd11 rb

main = "Advent of Code 2025 - Day 11 Results:\n" ++
       "  Part 1 (Paths count you -> out): " ++ show p1Result ++ "\n" ++
       "  Part 2 (Paths count svr -> out containing dac & fft): " ++ show p2Result ++ "\n"
       where
       input = read "examples/aoc25/data/day11.txt"
       p1Result = solvePart1 input
       p2Result = solvePart2 input

