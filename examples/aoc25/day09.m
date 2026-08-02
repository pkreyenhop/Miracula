|| Advent of Code 2025 - Day 9: Max Coordinate Area (Pure Miracula)
||
|| Each input line is an "x,y" point. Over all ordered pairs (p, q) with
|| q strictly right of and above p, find the largest rectangle area
|| (qx - px) * (qy - py).

split_by9 c [] = [[]]
split_by9 c (x:xs) = if x == c then [] : split_by9 c xs else (x : hd rest) : tl rest
                    where
                    rest = split_by9 c xs

not_empty9 l = l ~= ""

parse_pt9 l = (numval (hd parts), numval (hd (tl parts)))
             where
             parts = split_by9 ',' l

solvePart1 input = max_acc 0 areas
  where
  pts = map parse_pt9 (filter not_empty9 (lines input))
  areas = [ (xj - xi) * (yj - yi) | (xi, yi) <- pts; (xj, yj) <- pts; xj > xi; yj > yi ]
  max_acc best [] = best
  max_acc best (a:as) = if a > best then max_acc a as else max_acc best as

main = "Advent of Code 2025 - Day 9 Results:\n" ++
       "  Part 1 (Maximum area): " ++ show p1Result ++ "\n"
       where
       input = read "examples/aoc25/data/day9.txt"
       p1Result = solvePart1 input

