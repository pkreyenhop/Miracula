/* DEFINITIONS FOR MIRANDA INTEGER PACKAGE (variable length) */

/**************************************************************************
 * Copyright (C) Research Software Limited 1985-90.  All rights reserved. *
 * The Miranda system is distributed as free software under the terms in  *
 * the file "COPYING" which is included in the distribution.              *
 *------------------------------------------------------------------------*/

#define SIGNBIT 020000000000
   /* most significant bit of 32 bit word */
#define IBASE 0100000
   /* 2^15 (ie 8^5) so digit is a positive short */
#define MAXDIGIT 077777
#define DIGITWIDTH 15
#define digit0(x) (hd[x]&MAXDIGIT)
#define digit(x) hd[x]
#define rest(x) tl[x]
#define poz(x) (!(hd[x]&SIGNBIT))
#define neg(x) (hd[x]&SIGNBIT)
#define bigzero(x) (!digit(x)&&!rest(x))
#define getsmallint(x) (hd[x]&SIGNBIT?-digit0(x):digit(x))
#define stosmallint(x) make(INT,(x)<0?SIGNBIT|(-(x)):(x),0)
long long get_int();
int sto_int(long long);
double bigtodbl();
long double bigtoldbl(); /* not currently used */
double biglog();
double biglog10();
#define force_dbl(x) (tag[x]==INT?bigtodbl(x):get_dbl(x))
#define PTEN 10000
   /* largest power of ten < IBASE (used by bigscan) */
#define PSIXTEEN 4096
   /* largest power of sixteen <= IBASE (used by bigtostr) */
#define PEIGHT 0100000
   /* (=32768) largest power of eight <= IBASE (used by bigtostr) */
#define TENW 4
   /* number of factors of 10 in PTEN */
#define OCTW 5
   /* number of factors of 8 in IBASE */

/* END OF DEFINITIONS FOR INTEGER PACKAGE */

