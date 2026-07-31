package graphstore

func ScanDecimal(value string) (*Bignum, bool) { return ParseBignum(value, 10) }
func ScanHex(value string) (*Bignum, bool)     { return ParseBignum(value, 16) }
func ScanOctal(value string) (*Bignum, bool)   { return ParseBignum(value, 8) }
func (n *Bignum) Hex() string                  { return n.value.Text(16) }
func (n *Bignum) Octal() string                { return n.value.Text(8) }
