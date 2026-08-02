|| Advent of Code 2025 - Day 6: Matrix Operations & Rotations

|| Helper functions
split_by c [] = [[]]
split_by c (x:xs) = if x == c then [] : split_by c xs else (x : hd rest) : tl rest
                    where
                    rest = split_by c xs

elem x [] = False
elem x (y:ys) = if x == y then True else elem x ys

not True = False
not False = True

not_empty l = l ~= ""

|| Part 1

apply_op op nums = if op == "+" then sum nums else product nums

solve_sub problem = apply_op op nums
                    where
                    op = last problem
                    nums = map numval (init problem)
                    
                    last (x:xs) = if xs == [] then x else last xs
                    init (x:xs) = if xs == [] then [] else x : init xs

zip5 [] [] [] [] [] = []
zip5 (a:as) (b:bs) (c:cs) (d:ds) (e:es) = [a, b, c, d, e] : zip5 as bs cs ds es
zip5 as bs cs ds es = []

solvePart1 tokens = sum (map solve_sub subproblems)
  where
  ops = [t | t <- tokens; (t == "+") \/ (t == "*")]
  opCount = length ops
  
  row1 = take opCount tokens
  row2 = take opCount (drop opCount tokens)
  row3 = take opCount (drop (2*opCount) tokens)
  row4 = take opCount (drop (3*opCount) tokens)
  row5 = take opCount (drop (4*opCount) tokens)
  
  subproblems = zip5 row1 row2 row3 row4 row5

|| Part 2
repeat_val c 0 = []
repeat_val c n = c : repeat_val c (n-1)

max_val [] = 0
max_val (x:xs) = if x > m then x else m
                 where
                 m = max_val xs

len_show x = length (show x)

not_zero_char c = c ~= '0'

rotate_numbers arr = reverse (map numval (map (filter not_zero_char) (transpose digits_matrix)))
                     where
                     digits_matrix = [padded x | x <- arr]
                     max_digits = max_val (map len_show arr)
                     padded x = repeat_val '0' (max_digits - length s) ++ s
                                where
                                s = show x

find_dividers idx [] = []
find_dividers idx (c1 : cs) = if cs == [] then [] else (if (c1 == ' ') & ((c2 == '+') \/ (c2 == '*')) then idx : find_dividers (idx+1) cs else find_dividers (idx+1) cs)
                              where
                              c2 = hd cs

format_row row dividers maxLen = scan 0 row dividers
  where
  scan idx [] divs = if idx >= maxLen then [] else (if is_div then 'x' else '0') : scan (idx+1) [] next_divs
                     where
                     is_div = (divs ~= []) & (idx == hd divs)
                     next_divs = if is_div then tl divs else divs
  scan idx (c:cs) divs = if idx >= maxLen then [] else (if is_div then 'x' else (if c == ' ' then '0' else c)) : scan (idx+1) cs next_divs
                         where
                         is_div = (divs ~= []) & (idx == hd divs)
                         next_divs = if is_div then tl divs else divs

solve_part2_cols [] [] = 0
solve_part2_cols (op:ops) (col:cols) = (if op == '+' then sum col else product col) + solve_part2_cols ops cols

solvePart2 allLines = solve_part2_cols operations rotated_cols
  where
  numLines = take (length allLines - 1) allLines
  opLine = last allLines
  
  last (x:xs) = if xs == [] then x else last xs
  
  dividers = find_dividers 0 opLine
  maxLen = length opLine
  
  formatted = [ format_row r dividers maxLen | r <- numLines ]
  
  parsed_grid = map (map numval) (map (\r. split_by 'x' r) formatted)
  
  rotated_cols = map rotate_numbers (transpose parsed_grid)
  
  operations = [ c | c <- opLine; (c == '+') \/ (c == '*') ]

replace_nl '\n' = ' '
replace_nl c = c

not_newline c = c ~= '\n'

main = "Advent of Code 2025 - Day 6 Results:\n" ++
       "  Part 1 (Sum of operations): " ++ show p1Result ++ "\n" ++
       "  Part 2 (Rotated grid sum): " ++ show p2Result ++ "\n"
       where
       rawInput = read "examples/aoc25/data/day6.txt"
       || split tokens for Part 1
       tokens = filter not_empty (split_by ' ' (map replace_nl rawInput))
       p1Result = solvePart1 tokens
       
       || lines for Part 2
       allLines = filter not_empty (split_by '\n' rawInput)
       p2Result = solvePart2 allLines

