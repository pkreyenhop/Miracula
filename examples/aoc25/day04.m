|| Advent of Code 2025 - Day 4: Rolls Shelf Simulation

|| Helper functions
repeat_val c 0 = []
repeat_val c n = c : repeat_val c (n-1)

left R = '.' : take (length R - 1) R
right R = drop 1 R ++ [ '.' ]

zip8 [] [] [] [] [] [] [] [] = []
zip8 (a:as) (b:bs) (c:cs) (d:ds) (e:es) (f:fs) (g:gs) (h:hs) = (cnt a + cnt b + cnt c + cnt d + cnt e + cnt f + cnt g + cnt h) : zip8 as bs cs ds es fs gs hs
  where
  cnt '@' = 1
  cnt _   = 0
zip8 as bs cs ds es fs gs hs = []

pickable_row prev curr next = zip_cells curr counts
  where
  L1 = left prev
  L2 = prev
  L3 = right prev
  L4 = left curr
  L5 = right curr
  L6 = left next
  L7 = next
  L8 = right next
  counts = zip8 L1 L2 L3 L4 L5 L6 L7 L8
  
  zip_cells [] [] = []
  zip_cells (c:cs) (cnt:cnts) = (c, (c == '@') & (cnt < 4)) : zip_cells cs cnts
  zip_cells cs cnts = []

pickable_grid G = zip_rows (empty : G) G (drop 1 G ++ [empty])
  where
  width = length (hd G)
  empty = repeat_val '.' width
  
  zip_rows [] cs ns = []
  zip_rows ps [] ns = []
  zip_rows ps cs [] = []
  zip_rows (p:ps) (c:cs) (n:ns) = pickable_row p c n : zip_rows ps cs ns
  zip_rows ps cs ns = []

count_true [] = 0
count_true ((c, pick):xs) = (if pick then 1 else 0) + count_true xs

solvePart1 G = sum (map count_true (pickable_grid G))

update_row [] = []
update_row ((c, pick):xs) = (if pick then '.' else c) : update_row xs

solvePart2 G = if round_removed == 0 then 0 else round_removed + solvePart2 next_G
               where
               pg = pickable_grid G
               round_removed = sum (map count_true pg)
               next_G = map update_row pg

main = "Advent of Code 2025 - Day 4 Results:\n" ++
       "  Part 1 (Pickable rolls): " ++ show p1Result ++ "\n" ++
       "  Part 2 (Total removed rolls): " ++ show p2Result ++ "\n"
       where
       rawInput = read "examples/aoc25/data/day4.txt"
       G = lines rawInput
       p1Result = solvePart1 G
       p2Result = solvePart2 G

