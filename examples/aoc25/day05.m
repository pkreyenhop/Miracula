|| Advent of Code 2025 - Day 5: Interval Range Merging

|| Helper functions
split_by c [] = [[]]
split_by c (x:xs) = if x == c then [] : split_by c xs else (x : hd rest) : tl rest
                    where
                    rest = split_by c xs

elem x [] = False
elem x (y:ys) = if x == y then True else elem x ys

is_in_range val (start, end) = (val >= start) & (val <= end)

any_range val [] = False
any_range val (r:rs) = if is_in_range val r then True else any_range val rs

|| Quicksort for ranges by start value
get_start (s, e) = s

qsort [] = []
qsort (x:xs) = qsort [y | y <- xs; get_start y < get_start x] ++ [x] ++ qsort [y | y <- xs; get_start y >= get_start x]

|| Interval merging
max a b = if a > b then a else b

merge [] = []
merge (x:xs) = if xs == [] then [x] else (if s2 <= e1 + 1 then merge ((s1, max e1 (snd (hd xs))) : tl xs) else x : merge xs)
               where
               s1 = fst x
               e1 = snd x
               s2 = fst (hd xs)

|| Part 1
solvePart1 ranges ids = length [x | x <- ids; any_range x ranges]

|| Part 2
range_len (start, end) = end - start + 1
solvePart2 ranges = sum (map range_len (merge (qsort ranges)))

parse_range rangeStr = (numval startStr, numval endStr)
                       where
                       parts = split_by '-' rangeStr
                       startStr = hd parts
                       endStr = hd (tl parts)

not_empty l = l ~= ""

not True = False
not False = True

main = "Advent of Code 2025 - Day 5 Results:\n" ++
       "  Part 1 (IDs in range): " ++ show p1Result ++ "\n" ++
       "  Part 2 (Total points covered): " ++ show p2Result ++ "\n"
       where
       rawInput = read "examples/aoc25/data/day5.txt"
       || split by newline
       allLines = filter not_empty (split_by '\n' rawInput)
       
       rangesLines = [l | l <- allLines; elem '-' l]
       idsLines = [l | l <- allLines; not (elem '-' l)]
       
       ranges = map parse_range rangesLines
       ids = map numval idsLines
       
       p1Result = solvePart1 ranges ids
       p2Result = solvePart2 ranges

