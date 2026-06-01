/* DEFINITIONS FOR MIRANDA INTEGER PACKAGE (variable length) */

#ifndef MIRANDA_BIG_H
#define MIRANDA_BIG_H

#include "runtime.h"

/**************************************************************************
 * Copyright (C) Research Software Limited 1985-90.  All rights reserved. *
 * The Miranda system is distributed as free software under the terms in  *
 * the file "COPYING" which is included in the distribution.              *
 *                                                                        *
 * Revised to C11 standard and made 64bit compatible, January 2020        *
 *------------------------------------------------------------------------*/

#define SIGNBIT 0x10000000
/* most significant bit of 32 bit word */
#define IBASE 0x8000
/* 2^15 (ie 8^5) so digit is a positive short */
#define MAXDIGIT 0x7fff
#define DIGITWIDTH 15
#define digit0(x) (hd(x) & MAXDIGIT)
#define digit(x) hd(x)
#define rest(x) tl(x)
#define poz(x) (!(hd(x) & SIGNBIT))
#define neg(x) (hd(x) & SIGNBIT)
#define bigzero(x) (!digit(x) && !rest(x))
#define getsmallint(x) (hd(x) & SIGNBIT ? -digit0(x) : digit(x))
#define stosmallint(x) make(INT, (x) < 0 ? SIGNBIT | (-(x)) : (x), 0)
long long get_int(word /*x*/);
word sto_int(long long /*i*/);
double bigtodbl(word /*x*/);
long double bigtoldbl(word); /* not currently used */
double biglog(word /*x*/);
double biglog10(word /*x*/);
int bigcmp(word /*x*/, word /*y*/);
word bigdiv(word /*x*/, word /*y*/);
word bigmod(word /*x*/, word /*y*/);
word bignegate(word /*x*/);
word bigoscan(char * /*p*/, char * /*q*/);
word bigplus(word /*x*/, word /*y*/);
word bigpow(word /*x*/, word /*y*/);
word bigscan(char * /*p*/);
void bigsetup(void);
word bigsub(word /*x*/, word /*y*/);
word bigtimes(word /*x*/, word /*y*/);
word bigtostr(word /*x*/);
word bigtostr8(word /*x*/);
word bigtostrx(word /*x*/);
word bigxscan(char * /*p*/, char * /*q*/);
word dbltobig(double /*x*/);
int isnat(word /*x*/);
word strtobig(word /*z*/, int /*base*/);
#define force_dbl(x) (tag[x] == INT ? bigtodbl(x) : get_dbl(x))
#define PTEN 10000
/* largest power of ten < IBASE (used by bigscan) */
#define PSIXTEEN 4096
/* largest power of sixteen <= IBASE (used by bigtostr) */
#define PEIGHT 0x8000
/* (=32768) largest power of eight <= IBASE (used by bigtostr) */
#define TENW 4
/* number of factors of 10 in PTEN */
#define OCTW 5
/* number of factors of 8 in IBASE */

/* END OF DEFINITIONS FOR INTEGER PACKAGE */

#endif
