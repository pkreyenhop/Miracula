|| Advent of Code 2025 - Day 3: Lobby

|| Helper functions
max_list (x:xs) = if xs == [] then x else (if x > m then x else m)
                  where
                  m = max_list xs

index_of val xs = find 0 xs
                  where
                  find idx [] = -1
                  find idx (y:ys) = if y == val then idx else find (idx+1) ys

|| Part 1
largest_joltage xs = max_left * 10 + max_right
                     where
                     init_xs = take (length xs - 1) xs
                     max_left = max_list init_xs
                     first_idx = index_of max_left init_xs
                     max_right = max_list (drop (first_idx + 1) xs)

solvePart1 linesList = sum (map largest_joltage linesList)

|| Part 2
greedy 0 xs = []
greedy n xs = max_val : greedy (n-1) (drop (max_idx + 1) xs)
              where
              window = take (length xs - n + 1) xs
              max_val = max_list window
              max_idx = index_of max_val window

digits_to_val xs = foldl (\acc. \d. acc * 10 + d) 0 xs

largest_12_joltage xs = digits_to_val (greedy 12 xs)

solvePart2 linesList = sum (map largest_12_joltage linesList)

char_to_digit c = numval [c]

main = "Advent of Code 2025 - Day 3 Results:\n" ++
       "  Part 1 (Sum of largest joltages): " ++ show p1Result ++ "\n" ++
       "  Part 2 (Sum of largest 12-digit joltages): " ++ show p2Result ++ "\n"
       where
       rawInput = read "examples/aoc25/data/day3.txt"
       linesList = map (map char_to_digit) (lines rawInput)
       p1Result = solvePart1 linesList
       p2Result = solvePart2 linesList

