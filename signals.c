/*
 * signals.c - signal() with BSD semantics
 *
 * signal() is not recommended for redirecting signals to a handler
 * because the semantics vary too much between platforms.
 * signal(2) * says to use sigaction() instead but mira uses signal()
 * all over the place to redirect to handlers.
 * 
 * Rather than reimplement every use of signal() to use sigaction()
 * this makes a version of signal() that has BSD semantics, which are
 * what it expects.

signal():
  typedef void (*sighandler_t)(int);
  sighandler_t signal(int signum, sighandler_t handler);
  The BSD semantics are equivalent to calling sigaction(2) with
           sa.sa_flags = SA_RESTART;
  signal() returns the previous value of the signal handler.
  On failure, it returns SIG_ERR, and errno is set to indicate the error.

sigaction():
  int sigaction(int signum,
                const struct sigaction *_Nullable restrict act,
                struct sigaction *_Nullable restrict oldact);
  struct sigaction {
    void     (*sa_handler)(int);
    void     (*sa_sigaction)(int, siginfo_t *, void *);
    sigset_t   sa_mask;
    int        sa_flags;
    void     (*sa_restorer)(void);
  };
  Do not assign to both sa_handler and sa_sigaction.
  sigaction() returns 0 on success; on error, -1 is returned,
  and errno is set to indicate the error.
 */

#include "signals.h"

sighandler signals(int signum, sighandler handler)
{
  struct sigaction act,oldact;

  act.sa_handler=handler;
  sigemptyset(&act.sa_mask);
  act.sa_flags=SA_RESTART;
  return sigaction(signum, &act, &oldact)==0
         ? oldact.sa_handler : SIG_ERR;
}
