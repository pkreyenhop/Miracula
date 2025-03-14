/* MIRANDA INTEGER PACKAGE */
/* package for unbounded precision integers */

/**************************************************************************
 * Copyright (C) Research Software Limited 1985-90.  All rights reserved. *
 * The Miranda system is distributed as free software under the terms in  *
 * the file "COPYING" which is included in the distribution.              *
 *------------------------------------------------------------------------*/

#include "data.h"
#include "big.h"
#include <errno.h>

static double logIBASE,log10IBASE;
int big_one;

bigsetup()
{ logIBASE=log((double)IBASE);
  log10IBASE=log10((double)IBASE);
  big_one=make(INT,1,0);
}

isnat(x)
int x;
{ return(tag[x]==INT&&poz(x));
}

sto_int(i)  /* store C long long as mira big int */
long long i;
{ int s,x;
  if(i<0)s=SIGNBIT,i= -i; else s=0;
  x=make(INT,s|i&MAXDIGIT,0);
  if(i>>=DIGITWIDTH)
    { int *p = &rest(x);
      *p=make(INT,i&MAXDIGIT,0),p= &rest(*p);
      while(i>>=DIGITWIDTH)
           *p=make(INT,i&MAXDIGIT,0),p= &rest(*p); }
  return(x);
} /* change arg from int to long long, DT Oct 2019 */

#define maxval (1ll<<60)

long long get_int(x) /* mira big int to C long long */
int x;
{ long long n=digit0(x);
  int sign=neg(x);
  if(!(x=rest(x)))return(sign?-n:n);
{ int w=DIGITWIDTH;
  while(x&&w<60)n+=(long long)digit(x)<<w,w+=DIGITWIDTH,x=rest(x);
  if(x)n=maxval; /* overflow, return large value */
  return(sign?-n:n);
}} /* was int, change to long long, DT Oct 2019 */

bignegate(x)
int x;
{ if(bigzero(x))return(x);
  return(make(INT,hd[x]&SIGNBIT?hd[x]&MAXDIGIT:SIGNBIT|hd[x],tl[x]));
}

bigplus(x,y)
int x,y;
{ if(poz(x))
    if(poz(y))return(big_plus(x,y,0));
    else return(big_sub(x,y));
  else
    if(poz(y))return(big_sub(y,x));
    else return(big_plus(x,y,SIGNBIT)); /* both negative */
}

big_plus(x,y,signbit) /* ignore input signs, treat x,y as positive */
int x,y,signbit;
{ int d=digit0(x)+digit0(y);
  int carry = ((d&IBASE)!=0);
  int r = make(INT,signbit|d&MAXDIGIT,0); /* result */
  int *z = &rest(r); /* pointer to rest of result */
  x = rest(x); y = rest(y);
  while(x&&y) /* this loop has been unwrapped once, see above */
       { d = carry+digit(x)+digit(y);
	 carry = ((d&IBASE)!=0);
         *z = make(INT,d&MAXDIGIT,0);
	 x = rest(x); y = rest(y); z = &rest(*z); }
  if(y)x=y; /* by convention x is the longer one */
  while(x)
       { d = carry+digit(x);
	 carry = ((d&IBASE)!=0);
         *z = make(INT,d&MAXDIGIT,0);
	 x = rest(x); z = &rest(*z); }
  if(carry)*z=make(INT,1,0);
  return(r);
}

bigsub(x,y)
int x,y;
{ if(poz(x))
    if(poz(y))return(big_sub(x,y));
    else return(big_plus(x,y,0)); /* poz x, negative y */
  else
    if(poz(y))return(big_plus(x,y,SIGNBIT)); /* negative x, poz y */
    else return(big_sub(y,x)); /* both negative */
}

big_sub(x,y) /* ignore input signs, treat x,y as positive */
int x,y;
{ int d = digit0(x)-digit0(y);
  int borrow = (d&IBASE)!=0;
  int r=make(INT,d&MAXDIGIT,0);  /* result */
  int *z = &rest(r);
  int *p=NULL; /* pointer to trailing zeros, if any */
  x = rest(x); y = rest(y);
  while(x&&y) /* this loop has been unwrapped once, see above */
       { d = digit(x)-digit(y)-borrow;
	 borrow = (d&IBASE)!=0;
	 d = d&MAXDIGIT;
         *z = make(INT,d,0);
	 if(d)p=NULL; else if(!p)p=z;
	 x = rest(x); y = rest(y); z = &rest(*z); }
  while(y) /* at most one of these two loops will be invoked */
       { d = -digit(y)-borrow;
	 borrow = ((d&IBASE)!=0);
	 d = d&MAXDIGIT;
         *z = make(INT,d,0);
	 if(d)p=NULL; else if(!p)p=z;
	 y = rest(y); z = &rest(*z); }
  while(x) /* alternative loop */
       { d = digit(x)-borrow;
	 borrow = ((d&IBASE)!=0);
	 d = d&MAXDIGIT;
         *z = make(INT,d,0);
	 if(d)p=NULL; else if(!p)p=z;
	 x = rest(x); z = &rest(*z); }
  if(borrow) /* result is negative  - take complement and add 1 */
    { p=NULL;
      d = (digit(r)^MAXDIGIT) + 1;
      borrow = ((d&IBASE)!=0);  /* borrow now means `carry' (sorry) */
      digit(r) = SIGNBIT|d;  /* set sign bit of result */
      z = &rest(r);
      while(*z)
	   { d = (digit(*z)^MAXDIGIT)+borrow;
             borrow = ((d&IBASE)!=0);
             digit(*z) = d = d&MAXDIGIT;
	     if(d)p=NULL; else if(!p)p=z;
	     z = &rest(*z); }
    }
  if(p)*p=0; /* remove redundant (ie trailing) zeros */
  return(r);
}

bigcmp(x,y)  /* returns +ve,0,-ve as x greater than, equal, less than y */
int x,y;
{ int d,r,s=neg(x);
  if(neg(y)!=s)return(s?-1:1);
  r=digit0(x)-digit0(y);
  for(;;)
     { x=rest(x); y=rest(y);
       if(!x)if(y)return(s?1:-1);
             else return(s?-r:r);
       if(!y)return(s?-1:1);
       d=digit(x)-digit(y);
       if(d)r=d; }
}

#ifdef FASTMULT
naivemultiply(x,y)
int x,y;
#else
bigtimes(x,y) /* naive multiply - quadratic */
int x,y;
{ if(len(x)<len(y))
    { int hold=x; x=y; y=hold; }  /* important optimisation */
#endif
{ int r=make(INT,0,0);
  int d = digit0(y);
  int s=neg(y);
  int n=0;
  if(bigzero(x))return(r);  /* short cut */
  for(;;)
     { if(d)r = bigplus(r,shift(n,stimes(x,d)));
       n++;
       y = rest(y);
       if(!y)
         return(s!=neg(x)?bignegate(r):r);
       d=digit(y); }
}
#ifndef FASTMULT
}
#endif


#ifdef FASTMULT
/* see Bird and Wadler, page 155-6 */

/* experiments 30/7/88, compared with naive multiply on
	a) product[1..200]
	b) 2^10000
	c) 999^999
	d) product(rep 1000 66)
	e) dfac 500
   turns out to be v. important to make y the smaller operand in  naive
   multiply  -  when this done, fastmultiply circa 1.5* faster on a) c)
   and d) 1.5* slower on b) and (mysteriously) disastrously  slower  on
   e)  running  out  of  heap  (at  100K cells) - not installed pending
   further investigation
*/

fastmultiply(x,y) /* temporary version, assumes x,y >=0 */
int x,y;
{ int lx=len(x),ly=len(y);
  return(lx>=ly?fm(x,lx,y,ly):fm(y,ly,x,lx));
}

fm(x,lx,y,ly)
int x,lx,y,ly;
{ int x1,y1,z0,z1,z2,delta;
  if(ly==1)return(digit(y)==0?make(INT,0,0):stimes(x,digit(y)));
  if(ly<=3)return(naivemultiply(x,y));
  x1=drop(x,lx/2); x=take(x,lx/2);
  y1=drop(y,ly/2); y=take(y,ly/2);
  z2=fm(x1,lx-lx/2,y1,ly-ly/2);
  z0=fm(x,len(x),y,len(y));
  delta=(lx=lx/2)-(ly=ly/2);
  z1=bigsub(fastmultiply(bigplus(shift(delta,x1),x),bigplus(y1,y)),
	     bigplus(shift(delta,z2),z0));
  return(bigplus(shift(lx+ly,z2),bigplus(shift(ly,z1),z0)));
}

take(x,n)
int x,n;
{ int d=digit(x);
  int r=make(INT,d,0);
  int *z = &rest(r);
  int *p=d?z:NULL;
  while(--n)
       { x=rest(x);
	 *z=make(INT,digit(x),0);
         if(d)p=NULL; else if(!p)p=z;
	 z = &rest(*z); }
  if(p)*p=0; /* remove redundant (ie trailing) zeros */
  return(r);
}

drop(x,n)
int x,n;
{ while(n--)x=rest(x);
  return(x);
}
#endif

shift(n,x) /* multiply big x by n'th power of IBASE */
int x,n;
{ 
#ifdef FASTMULT
  if(bigzero(x))return(x);
#endif
  while(n--)x=make(INT,0,x);
  return(x);
} /* NB - we assume x non-zero, else unnormalised result */

stimes(x,n)  /* multiply big x (>=0) by digit n (>0) */
int x,n;
{ unsigned d= n*digit0(x);  /* ignore sign of x */
  int carry=d>>DIGITWIDTH;
  int r = make(INT,d&MAXDIGIT,0);
  int *y = &rest(r);
  while(x=rest(x))
       d=n*digit(x)+carry,
       *y=make(INT,d&MAXDIGIT,0),
       y = &rest(*y),
       carry=d>>DIGITWIDTH;
  if(carry)*y=make(INT,carry,0);
  return(r);
}

int b_rem;  /* contains remainder from last call to longdiv or shortdiv */

bigdiv(x,y)  /* may assume y~=0 */
int x,y;
{ int s1,s2,q; 
  /* make x,y positive and remember signs */
  if(s1=neg(y))y=make(INT,digit0(y),rest(y));
  if(neg(x))
    x=make(INT,digit0(x),rest(x)),s2=!s1; 
  else s2=s1;
  /* effect: s1 set iff y negative, s2 set iff signs mixed */
  if(rest(y))q=longdiv(x,y);
  else q=shortdiv(x,digit(y));
  if(s2){ if(!bigzero(b_rem))
	    { x=q;
	      while((digit(x)+=1)==IBASE) /* add 1 to q in situ */
                   { digit(x)=0;
		     if(!rest(x)){ rest(x)=make(INT,1,0); break; }
		     else x=rest(x);
		   }
	    }
          if(!bigzero(q))digit(q)=SIGNBIT|digit(q);
	}
  return(q);
}

bigmod(x,y)  /* may assume y~=0 */
int x,y;
{ int s1,s2;
  /* make x,y positive and remember signs */
  if(s1=neg(y))y=make(INT,digit0(y),rest(y));
  if(neg(x))
    x=make(INT,digit0(x),rest(x)),s2=!s1; 
  else s2=s1;
  /* effect: s1 set iff y negative, s2 set iff signs mixed */
  if(rest(y))longdiv(x,y);
  else shortdiv(x,digit(y));
  if(s2){ if(!bigzero(b_rem))
	    b_rem = bigsub(y,b_rem);
	}
  return(s1?bignegate(b_rem):b_rem);
}

/* NB - above have entier based handling of signed cases  (as  Miranda)  in
   which  remainder  has  sign  of  divisor.   To  get  this:-  if signs of
   divi(sor/dend) mixed negate quotient  and  if  remainder  non-zero  take
   complement and add one to magnitude of quotient */

/* for alternative, truncate based handling of signed cases (usual in  C):-
   magnitudes  invariant  under  change  of  sign,  remainder  has  sign of
   dividend, quotient negative if signs of divi(sor/dend) mixed */

shortdiv(x,n) /* divide big x by single digit n returning big quotient
		 and setting external b_rem as side effect */
              /* may assume - x>=0,n>0 */
int x,n;
{ int d=digit(x),s_rem,q=0;
  while(x=rest(x))  /* reverse rest(x) into q */
       q=make(INT,d,q),d=digit(x);  /* leaving most sig. digit in d */
  { int tmp;
    x=q; s_rem=d%n; d=d/n;
    if(d||!q)q=make(INT,d,0); /* put back first digit (if not leading 0) */
    else q=0;
    while(x) /* in situ division of q by n AND destructive reversal */
         d=s_rem*IBASE+digit(x),digit(x)=d/n,s_rem=d%n,
	 tmp=x,x=rest(x),rest(tmp)=q,q=tmp;
  }
  b_rem=make(INT,s_rem,0);
  return(q);
}

longdiv(x,y)  /* divide big x by big y returning quotient, leaving
		 remainder in extern variable b_rem */
              /* may assume - x>=0,y>0 */
int x,y;
{ int n,q,ly,y1,scale;
  if(bigcmp(x,y)<0){ b_rem=x; return(make(INT,0,0)); }
  y1=msd(y);
  if((scale=IBASE/(y1+1))>1) /* rescale if necessary */
    x=stimes(x,scale),y=stimes(y,scale),y1=msd(y);
  n=q=0;ly=len(y);
  while(bigcmp(x,y=make(INT,0,y))>=0)n++;
  y=rest(y);  /* want largest y not exceeding x */
  ly += n;
  for(;;)
     { int d,lx=len(x);
       if(lx<ly)d=0; else
       if(lx==ly)
         if(bigcmp(x,y)>=0)x=bigsub(x,y),d=1;
	 else d=0;
       else{ d=ms2d(x)/y1;
	     if(d>MAXDIGIT)d=MAXDIGIT;
	     if((d -= 2)>0)x=bigsub(x,stimes(y,d));
	     else d=0;
             if(bigcmp(x,y)>=0)
	       { x=bigsub(x,y),d++;
                 if(bigcmp(x,y)>=0)
		   x=bigsub(x,y),d++; }
	   }
       q = make(INT,d,q);
       if(n-- ==0)
	 { b_rem = scale==1?x:shortdiv(x,scale); return(q); }
       ly-- ; y = rest(y); }
} /* see Bird & Wadler p82 for explanation */

len(x) /* no of digits in big x */
int x;
{ int n=1;
  while(x=rest(x))n++;
  return(n);
}

msd(x) /* most significant digit of big x */
int x;
{ while(rest(x))x=rest(x);
  return(digit(x)); /* sign? */
}

ms2d(x) /* most significant 2 digits of big x (len>=2) */
int x;
{ int d=digit(x);
  x=rest(x);
  while(rest(x))d=digit(x),x=rest(x);
  return(digit(x)*IBASE+d);
}

bigpow(x,y)  /* assumes y poz */
int x,y;
{ int d,r=make(INT,1,0);
  while(rest(y))  /* this loop has been unwrapped once, see below */
       { int i=DIGITWIDTH;
	 d=digit(y);
	 while(i--)
	      { if(d&1)r=bigtimes(r,x); 
		x = bigtimes(x,x);
		d >>= 1; }
	 y=rest(y);
       }
  d=digit(y);
  if(d&1)r=bigtimes(r,x); 
  while(d>>=1)
       { x = bigtimes(x,x);
         if(d&1)r=bigtimes(r,x); }
  return(r);
}

double bigtodbl(x)
int x;
{ int s=neg(x);
  double b=1.0, r=(double)digit0(x);
  x = rest(x);
  while(x)b=b*IBASE,r=r+b*digit(x),x=rest(x);
  if(s)return(-r);
  return(r);
} /* small end first */
/* note: can return oo, -oo
   but is used without surrounding sto_/set)dbl() only in compare() */

/* not currently used
long double bigtoldbl(x)
int x;
{ int s=neg(x);
  long double b=1.0L, r=digit0(x);
  x = rest(x);
  while(x)b=b*IBASE,r=r+b*digit(x),x=rest(x);
/*printf("bigtoldbl returns %Le\n",s?-r:r); /* DEBUG
  if(s)return(-r);
  return(r);
} /* not compatible with std=c90, lib fns eg sqrtl broken */

dbltobig(x)  /* entier */
double x;
{ int s= (x<0);
  int r=make(INT,0,0);
  int *p = &r;
  double y= floor(x);
/*if(fabs(y-x+1.0)<1e-9)y += 1.0; /* trick due to Peter Bartke, see note */
  for(y=fabs(y);;)
     { double n = fmod(y,(double)IBASE);
       digit(*p) = (int)n;
       y = (y-n)/(double)IBASE; 
       if(y>0.0)rest(*p)=make(INT,0,0),p=&rest(*p);
       else break;
     }
  if(s)digit(r)=SIGNBIT|digit(r);
  return(r);
}
/* produces junk in low order digits if x exceeds range in which integer
   can be held without error as a double -- NO, see next comment */
/* hugs, ghci, mira produce same integer for floor/entier hugenum, has 2^971
   as factor so the low order bits are NOT JUNK -- 9.1.12 */

/* note on suppressed fix:
   choice of 1e9 arbitrary, chosen to prevent eg entier(100*0.29) = 28
   but has undesirable effects, causing eg entier 1.9999999999 = 2
   underlying problem is that computable floor on true Reals is _|_ at
   the exact integers.  There are inherent deficiences in 64 bit fp,
   no point in trying to mask this */

double biglog(x)  /* logarithm of big x */
int x;
{ int n=0;
  double r=digit(x);
  if(neg(x)||bigzero(x))errno=EDOM,math_error("log");
  while(x=rest(x))n++,r=digit(x)+r/IBASE;
  return(log(r)+n*logIBASE);
}

double biglog10(x)  /* logarithm of big x */
int x;
{ int n=0;
  double r=digit(x);
  if(neg(x)||bigzero(x))errno=EDOM,math_error("log10");
  while(x=rest(x))n++,r=digit(x)+r/IBASE;
  return(log10(r)+n*log10IBASE);
}

bigscan(p)  /* read a big number (in decimal) */
            /* NB does NOT check for malformed number, assumes already done */
char *p;    /* p is a pointer to a null terminated string of digits */
{ int s=0,r=make(INT,0,0);
  if(*p=='-')s=1,p++; /* optional leading `-' (for NUMVAL) */
  while(*p)
       { int d= *p-'0',f=10;
	 p++;
	 while(*p&&f<PTEN)d=10*d+*p-'0',f=10*f,p++;
	 /* rest of loop does r=f*r+d; (in situ) */
	 d= f*digit(r)+d;
       { int carry=d>>DIGITWIDTH;
	 int *x = &rest(r);
	 digit(r)=d&MAXDIGIT;
	 while(*x)
	      d=f*digit(*x)+carry,
	      digit(*x)=d&MAXDIGIT,
	      carry=d>>DIGITWIDTH,
	      x = &rest(*x);
	 if(carry)*x=make(INT,carry,0);
       }}
/*if(*p=='e')
    { int s=bigscan(p+1);
      r = bigtimes(r,bigpow(make(INT,10,0),s); } */
  if(s&&!bigzero(r))digit(r)=digit(r)|SIGNBIT;
  return(r);
}
/* code to handle (unsigned) exponent commented out */

bigxscan(p,q)  /* read unsigned hex number in '\0'-terminated string p to q */
               /* assumes redundant leading zeros removed */
char *p, *q;
{ int r; /* will hold result */
  int *x = &r;
  if(*p=='0'&&!p[1])return make(INT,0,0);
  while(q>p)
       { unsigned long long hold;
         q = q-p<15 ? p : q-15; /* read upto 15 hex digits from small end */
         sscanf(q,"%llx",&hold);
         *q = '\0';
         int count=4; /* 15 hex digits => 4 bignum digits */
         while(count-- && !(hold==0 && q==p))
              *x = make(INT,hold&MAXDIGIT,0),
              hold >>= DIGITWIDTH,
              x = &rest(*x);
       }
  return r;
}

bigoscan(p,q)  /* read unsigned octal number in '\0'-terminated string p to q */
               /* assumes redundant leading zeros removed */
char *p, *q;
{ int r; /* will hold result */
  int *x = &r;
  while(q>p)
       { unsigned int hold;
         q = q-p<5 ? p : q-5; /* read (upto) 5 octal digits from small end */
         sscanf(q,"%o",&hold);
         *q = '\0';
         *x = make(INT,hold,0),
         x = &rest(*x);
       }
  return r;
}

digitval(c)
char c;
{ return isdigit(c)?c-'0':
         isupper(c)?10+c-'A':
         10+c-'a'; }

strtobig(z,base) /* numeral (as Miranda string) to big number */
                 /* does NOT check for malformed numeral, assumes
	            done and that z fully evaluated */
int z;
{ int s=0,r=make(INT,0,0),PBASE=PTEN;
  if(base==16)PBASE=PSIXTEEN; else
  if(base==8)PBASE=PEIGHT;
  if(z!=NIL&&hd[z]=='-')s=1,z=tl[z]; /* optional leading `-' (for NUMVAL) */
  if(base!=10)z=tl[tl[z]]; /* remove "0x" or "0o" */
  while(z!=NIL)
       { int d=digitval(hd[z]),f=base;
         z=tl[z];
         while(z!=NIL&&f<PBASE)d=base*d+digitval(hd[z]),f=base*f,z=tl[z];
         /* rest of loop does r=f*r+d; (in situ) */
         d= f*digit(r)+d;
       { int carry=d>>DIGITWIDTH;
         int *x = &rest(r);
         digit(r)=d&MAXDIGIT;
         while(*x)
              d=f*digit(*x)+carry,
              digit(*x)=d&MAXDIGIT,
              carry=d>>DIGITWIDTH,
              x = &rest(*x);
         if(carry)*x=make(INT,carry,0);
       }}
  if(s&&!bigzero(r))digit(r)=digit(r)|SIGNBIT;
  return(r);
}

extern char *dicp;

bigtostr(x) /* number to decimal string (as Miranda list) */
int x;
{ int x1,sign,s=NIL;
#ifdef DEBUG
  extern int debug;
  if(debug&04)  /* print octally */
    { int d=digit0(x);
      sign=neg(x);
      for(;;)
	   { int i=OCTW;
	     while(i--||d)s=cons('0'+(d&07),s),d >>= 3;
             x=rest(x);
             if(x)s=cons(' ',s),d=digit(x);
	     else return(sign?cons('-',s):s); }
    }
#endif
  if(rest(x)==0)
    { extern char *dicp;
      sprintf(dicp,"%d",getsmallint(x));
      return(str_conv(dicp)); }
  sign=neg(x);
  x1=make(INT,digit0(x),0); /* reverse x into x1 */
  while(x=rest(x))x1=make(INT,digit(x),x1);
  x=x1;
  for(;;)
     { /* in situ division of (reversed order) x by PTEN */
       int d=digit(x),rem=d%PTEN;
       d=d/PTEN; x1=rest(x);
       if(d)digit(x)=d;
       else x=x1; /* remove leading zero from result */
       while(x1)
            d=rem*IBASE+digit(x1),
            digit(x1)=d/PTEN,
            rem=d%PTEN,
            x1=rest(x1);
       /* end of in situ division (also uses x1 as temporary) */
       if(x)
         { int i=TENW;
	   while(i--)s=cons('0'+rem%10,s),rem=rem/10; }
       else
	 { while(rem)s=cons('0'+rem%10,s),rem=rem/10;
           return(sign?cons('-',s):s); }
     }
}

bigtostrx(x) /* integer to hexadecimal string (as Miranda list) */
int x;
{ int r=NIL, s=neg(x);
  while(x)
       { int count=4; /* 60 bits => 20 octal digits => 4 bignum digits */
         unsigned long long factor=1;
         unsigned long long hold=0;
         while(count-- && x) /* calculate value of (upto) 4 bignum digits */
              hold=hold+factor*digit0(x),
              /* printf("::%llx\n",hold), /* DEBUG */
              factor<<=15,
              x=rest(x);
         sprintf(dicp,"%.15llx",hold); /* 15 hex digits = 60 bits */
         /* printf(":::%s\n",dicp); /* DEBUG */
         char *q=dicp+15;
         while(--q>=dicp)r = cons(*q,r);
       }
  while(digit(r)=='0'&&rest(r)!=NIL)r=rest(r); /* remove redundant leading 0's */
  r = cons('0',cons('x',r));
  if(s)r = cons('-',r);
  return(r);
}

bigtostr8(x) /* integer to octal string (as Miranda list) */
int x;
{ int r=NIL, s=neg(x);
  while(x)
       { char *q = dicp+5;
         sprintf(dicp,"%.5o",digit0(x));
         while(--q>=dicp)r = cons(*q,r);
         x = rest(x); }
  while(digit(r)=='0'&&rest(r)!=NIL)r=rest(r); /* remove redundant leading 0's */
  r = cons('0',cons('o',r));
  if(s)r = cons('-',r);
  return(r);
}

#ifdef DEBUG
wff(x) /* check for well-formation of integer */
int x;
{ int y=x;
  if(tag[x]!=INT)printf("BAD TAG %d\n",tag[x]);
  if(neg(x)&&!digit0(x)&&!rest(x))printf("NEGATIVE ZERO!\n");
  if(digit0(x)&(~MAXDIGIT))printf("OVERSIZED DIGIT!\n");
  while(x=rest(x))
       if(tag[x]!=INT)printf("BAD INTERNAL TAG %d\n",tag[x]); else
       if(digit(x)&(~MAXDIGIT))
	 printf("OVERSIZED DIGIT!\n"); else
       if(!digit(x)&&!rest(x))
	 printf("TRAILING ZERO!\n");
  return(y);
}

normalise(x)  /* remove trailing zeros */
int x;
{ if(rest(x))rest(x)=norm1(rest(x));
  return(wff(x));
}

norm1(x)
int x;
{ if(rest(x))rest(x)=norm1(rest(x));
  return(!digit(x)&&!rest(x)?0:x);
}

#endif

/* stall(s)
char *s;
{ fprintf(stderr,"big integer %s not yet implemented\n",s);
  exit(0);
}

#define destrev(x,y,z)  while(x)z=x,x=rest(x),rest(z)=y,y=z;
/* destructively reverse x into y using z as temp */

/* END OF MIRANDA INTEGER PACKAGE */

