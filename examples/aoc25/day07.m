|| Advent of Code 2025 - Day 7: Puzzle Path Splits (Pure Miracula)

fst (a, b) = a
snd (a, b) = b

split_by5 c [] = [[]]
split_by5 c (x:xs) = if x == c then [] : split_by5 c xs else (x : hd rest) : tl rest
                    where
                    rest = split_by5 c xs

not_empty5 l = l ~= ""

union7 [] ys = ys
union7 (x:xs) [] = x:xs
union7 (x:xs) (y:ys) = if x < y then x : union7 xs (y:ys)
                       else (if x == y then x : union7 xs ys
                             else y : union7 (x:xs) ys)

step_row7 active row = scan 0 active [] 0 row
  where
  scan idx [] next_acc splits rest = (next_acc, splits)
  scan idx (c:cs) next_acc splits [] = scan idx cs next_acc splits []
  scan idx (c:cs) next_acc splits (x:xs) =
    if idx < c then scan (idx+1) (c:cs) next_acc splits xs
    else (if x == '^' then scan (idx+1) cs (union7 next_acc [c-1, c+1]) (splits+1) xs
          else scan (idx+1) cs (union7 next_acc [c]) splits xs)

simulate7 active splits [] = splits
simulate7 active splits (row:rows) = simulate7 next_active (splits + row_splits) rows
  where
  step = step_row7 active row
  next_active = fst step
  row_splits = snd step

find_S7 idx [] = -1
find_S7 idx (x:xs) = if x == 'S' then idx else find_S7 (idx+1) xs

solvePart1 input = simulate7 [s_col] 0 (tl grid)
  where
  grid = filter not_empty5 (split_by5 '\n' input)
  s_col = find_S7 0 (hd grid)

main = "Advent of Code 2025 - Day 7 Results:\n" ++
       "  Part 1 (Total splits): " ++ show p1Result ++ "\n"
       where
       input = read "examples/aoc25/data/day7.txt"
       p1Result = solvePart1 input

