/* signals.h: Declarations for signals.c */

#include <signal.h>

typedef void (*sighandler)(int);

extern sighandler signals(int signum, sighandler handler);
