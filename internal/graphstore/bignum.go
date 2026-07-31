package graphstore

import "math/big"

type Bignum struct{ value big.Int }

func NewBignum(v int64) *Bignum { n := new(Bignum); n.value.SetInt64(v); return n }
func ParseBignum(text string, base int) (*Bignum, bool) {
	n := new(Bignum)
	_, ok := n.value.SetString(text, base)
	return n, ok
}
func (n *Bignum) String() string        { return n.value.String() }
func (n *Bignum) Int64() (int64, bool)  { return n.value.Int64(), n.value.IsInt64() }
func (n *Bignum) Sign() int             { return n.value.Sign() }
func (n *Bignum) Neg() *Bignum          { r := new(Bignum); r.value.Neg(&n.value); return r }
func (n *Bignum) Add(m *Bignum) *Bignum { r := new(Bignum); r.value.Add(&n.value, &m.value); return r }
func (n *Bignum) Sub(m *Bignum) *Bignum { r := new(Bignum); r.value.Sub(&n.value, &m.value); return r }
func (n *Bignum) Mul(m *Bignum) *Bignum { r := new(Bignum); r.value.Mul(&n.value, &m.value); return r }
func (n *Bignum) Quo(m *Bignum) (*Bignum, bool) {
	q, _, ok := n.DivMod(m)
	return q, ok
}
func (n *Bignum) DivMod(m *Bignum) (*Bignum, *Bignum, bool) {
	if m.Sign() == 0 {
		return nil, nil, false
	}
	q, r := new(Bignum), new(Bignum)
	q.value.QuoRem(&n.value, &m.value, &r.value)
	if r.Sign() != 0 && r.Sign() != m.Sign() {
		q.value.Sub(&q.value, big.NewInt(1))
		r.value.Add(&r.value, &m.value)
	}
	return q, r, true
}
func (n *Bignum) Mod(m *Bignum) (*Bignum, bool) {
	_, r, ok := n.DivMod(m)
	return r, ok
}
func (n *Bignum) Pow(exp uint64) *Bignum {
	r := new(Bignum)
	r.value.Exp(&n.value, new(big.Int).SetUint64(exp), nil)
	return r
}
func (n *Bignum) Cmp(m *Bignum) int { return n.value.Cmp(&m.value) }
