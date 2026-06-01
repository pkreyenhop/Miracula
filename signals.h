/* signals.h: Declarations for signals.c */

#ifndef MIRANDA_SIGNALS_H
#define MIRANDA_SIGNALS_H

#include <signal.h>

typedef void (*sighandler)(int);

extern sighandler signals(int signum, sighandler handler);

#endif
