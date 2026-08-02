|| Advent of Code 2025 - Day 1: Secret Entrance

mod100 n = (n mod 100 + 100) mod 100

parse_instruction text = if text!0 = 'L' then 0-numval (drop 1 text) else numval (drop 1 text)

count_zeroes [] = 0
count_zeroes (0:xs) = 1 + count_zeroes xs
count_zeroes (x:xs) = count_zeroes xs

landing_positions p [] = []
landing_positions p (rotation:rotations) = mod100 (p+rotation) : landing_positions (mod100 (p+rotation)) rotations

click_positions p [] = []
click_positions p (rotation:rotations) = rotation_path p rotation ++ click_positions (mod100 (p+rotation)) rotations

rotation_path p rotation = [mod100 (p-step)|step<-[1..0-rotation]], if rotation < 0
                         = [mod100 (p+step)|step<-[1..rotation]], otherwise

solve_part1 rotations = count_zeroes (landing_positions 50 rotations)
solve_part2 rotations = count_zeroes (click_positions 50 rotations)

rotations = map parse_instruction (lines (read "examples/aoc25/data/day1.txt"))
main = "Advent of Code 2025 - Day 1 Results:\n  Part 1: " ++ show (solve_part1 rotations) ++ "\n  Part 2: " ++ show (solve_part2 rotations) ++ "\n"
