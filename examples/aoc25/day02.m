|| Advent of Code 2025 - Day 2: Gift Shop (Pure Miracula)

seq x y = ifzero x then y else y

split_by5 c [] = [[]]
split_by5 c (x:xs) = if x == c then [] : split_by5 c xs else (x : hd rest) : tl rest
                    where
                    rest = split_by5 c xs

repeat_chunk2 0 chunk = []
repeat_chunk2 k chunk = chunk ++ repeat_chunk2 (k-1) chunk

checkPart2_1 n = (length s mod 2 == 0) & (take half s == drop half s)
               where
               s = show n
               half = length s / 2

checkPart2_2 n = any_repeat 1
               where
               s = show n
               L = length s
               any_repeat d = if d > L / 2 then False
                              else (if (L mod d == 0) & (repeat_chunk2 (L/d) (take d s) == s) then True
                                    else any_repeat (d+1))

solveDay2_range part start end = loop 0 start
  where
  check = if part == 1 then checkPart2_1 else checkPart2_2
  loop acc curr = if curr > end then acc
                  else (if check curr then seq next_acc (loop next_acc (curr + 1))
                        else loop acc (curr + 1))
                  where
                  next_acc = acc + curr

solvePart1 input = sum (map (\r. solve_r r 1) (split_by5 ',' input))
  where
  solve_r r part = solveDay2_range part (numval startStr) (numval endStr)
                   where
                   parts = split_by5 '-' r
                   startStr = hd parts
                   endStr = hd (tl parts)

solvePart2 input = sum (map (\r. solve_r r 2) (split_by5 ',' input))
  where
  solve_r r part = solveDay2_range part (numval startStr) (numval endStr)
                   where
                   parts = split_by5 '-' r
                   startStr = hd parts
                   endStr = hd (tl parts)

main = "Advent of Code 2025 - Day 2 Results:\n" ++
       "  Part 1 (Sum of invalid IDs): " ++ show p1Result ++ "\n" ++
       "  Part 2 (Sum of invalid IDs): " ++ show p2Result ++ "\n"
       where
       input = read "examples/aoc25/data/day2.txt"
       p1Result = solvePart1 input
       p2Result = solvePart2 input

