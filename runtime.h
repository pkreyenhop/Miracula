/* Core scalar runtime types shared by the Miranda C implementation. */

#ifndef MIRANDA_RUNTIME_H
#define MIRANDA_RUNTIME_H

typedef long word;
/* word must be an integer type wide enough to also store (char*) or (FILE*).
   Defining it as "long" works on the most common platforms both 32 and
   64 bit.  Be aware that word==long is reflected in printf etc formats
   e.g. %ld, in many places in the code.  If you define word to be other
   than long these will need to be changed, the gcc/clang option -Wformat
   will locate format/arg type mismatches. DT Jan 2020 */

#endif
