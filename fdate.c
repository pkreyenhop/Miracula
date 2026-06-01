/* reads a filename from stdin and prints its time-last-modified,
   in format [d]d <Month-name> yyyy */
/* Used by the Makefile to decide whether the recorded source revision date
   needs to be refreshed before rebuilding the interpreter. */

#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <time.h>

static struct stat buf;
static struct tm *t;

static char *month[] = {"January", "February", "March",     "April",   "May",      "June",
                        "July",    "August",   "September", "October", "November", "December"};
int main(void) {
  char f[200];
  if (scanf("%s", f) == 1 && stat(f, &buf) == 0)
    t = localtime(&buf.st_mtime),
    printf("%d %s %4d\n", (*t).tm_mday, month[(*t).tm_mon], (*t).tm_year + 1900);
  else
    fprintf(stderr, "fdate: bad file \"%s\"\n", f);
  return 0;
}
