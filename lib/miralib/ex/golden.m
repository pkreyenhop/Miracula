%include "bignum"

|| Output an infinite number of decimal places of the golden ratio

golden = bn_half (bn_add bn_1 (bn_sqrt (bn "5")))
