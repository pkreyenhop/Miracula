%export sum3

%free { elem :: type
        zero :: elem
        add :: elem->elem->elem
      }

sum3 :: elem->elem->elem->elem
sum3 x y z = add x (add y (add z zero))
