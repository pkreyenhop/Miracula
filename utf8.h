#ifndef MIRANDA_UTF8_H
#define MIRANDA_UTF8_H

typedef unsigned long unicode;
/* must be big enough to store codes up to UMAX */

#define UMAX 0x10ffff /* last unicode value */
#define BMPMAX 0xffff

#include <stdio.h>
unicode fromUTF8(FILE * /*fil*/);
void outUTF8(unicode /*u*/, FILE * /*fil*/);

#endif
