/* Shared system includes and portability shims for the Miranda runtime. */

#ifndef MIRANDA_PLATFORM_H
#define MIRANDA_PLATFORM_H

#include "runtime.h"

#include <unistd.h> /* execl */
#include <stdlib.h> /* malloc, calloc, realloc, getenv */
#include <limits.h> /* MAX_DBL */
#include <stdio.h>
#include "signals.h"
#include <math.h>
#include <ctype.h>
#include <string.h>

#define index(s, c) strchr(s, c)
#define rindex(s, c) strrchr(s, c)

#if IBMRISC | sparc7
union wait {
  word w_status;
};
#else
#include <sys/wait.h>
#endif

#endif
