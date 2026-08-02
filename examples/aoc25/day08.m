|| Advent of Code 2025 - Day 8: Euclidean Circuit Clustering (Pure Miracula)
||
|| Sort all pairwise distances, process the 1000 shortest pairs through
|| union-find (a pair whose endpoints are already connected still consumes
|| one of the 1000 slots), then multiply the three largest circuit sizes.

fst3 (a, b, c) = a
snd3 (a, b, c) = b
thd3 (a, b, c) = c

distSq8 (x1, y1, z1) (x2, y2, z2) = dx*dx + dy*dy + dz*dz
  where
  dx = x1 - x2
  dy = y1 - y2
  dz = z1 - z2

group3 [] = []
group3 (x:y:z:rest) = (x, y, z) : group3 rest

find_root parent x =
  if p == x then (x, parent)
  else (root, h_insert root_parent x root)
  where
  p = h_lookup_def parent x x
  res = find_root parent p
  root = fst res
  root_parent = snd res

|| process every edge in the list (the caller passes exactly the 1000
|| shortest, so a no-op union still consumes its slot)
unite [] parent = parent
unite (e:es) parent =
  if ru == rv then unite es parent_v
  else unite es (h_insert parent_v ru rv)
  where
  u = fst3 e
  v = snd3 e
  res_u = find_root parent u
  ru = fst res_u
  parent_u = snd res_u
  res_v = find_root parent_u v
  rv = fst res_v
  parent_v = snd res_v

group_count [] = []
group_count (x:xs) = count_more 1 x xs
  where
  count_more k val [] = [k]
  count_more k val (y:ys) = if y == val then count_more (k+1) val ys
                            else k : count_more 1 y ys

solvePart1 input = s1 * s2 * s3
  where
  pts = group3 (parse_ints input)
  n = length pts
  ipts = zip ([0 .. n - 1], pts)
  edges = [ (i, j, distSq8 p q) | (i, p) <- ipts; (j, q) <- ipts; i < j ]
  shortest = take 1000 (sort_edges edges)

  final_parent = unite shortest empty_map

  find_all_roots [] p = ([], p)
  find_all_roots (x:xs) p = (r : rest_roots, final_p)
    where
    res_x = find_root p x
    r = fst res_x
    p_x = snd res_x
    res_xs = find_all_roots xs p_x
    rest_roots = fst res_xs
    final_p = snd res_xs

  roots_res = find_all_roots [0 .. n - 1] final_parent
  roots = fst roots_res
  sorted_roots = sort_ints roots
  sizes = group_count sorted_roots
  sorted_sizes = reverse (sort_ints sizes)

  s1 = hd sorted_sizes
  s2 = hd (tl sorted_sizes)
  s3 = hd (tl (tl sorted_sizes))

main = "Advent of Code 2025 - Day 8 Results:\n" ++
       "  Part 1 (Circuit size product): " ++ show p1Result ++ "\n"
       where
       input = read "examples/aoc25/data/day8.txt"
       p1Result = solvePart1 input

