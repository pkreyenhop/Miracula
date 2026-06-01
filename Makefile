#install paths
#for linux, MacOS X, Cygwin:
BIN=/usr/local/bin
#LIB=/usr/local/lib
MAN=/usr/local/share/man/man1
#for Solaris:
#MAN=/usr/local/man/man1
CFLAGS = -std=c23 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Wpedantic
# Historical portability flags: #-O #-DCYGWIN #-DUWIN #-DIBMRISC #-Dsparc7 #-Dsparc8
#be wary of using anything higher than -O as the garbage collector may fall over
#if using gcc rather than clang try without -O first
EX = #.exe        #needed for CYGWIN, UWIN
YACC = byacc #Berkeley yacc, gnu yacc not compatible
CC = clang
CXX = clang++
CXXFLAGS = -std=c++26 -D_POSIX_C_SOURCE=200809L -Wno-deprecated \
	-Wno-deprecated-register -Wno-writable-strings \
	-Wno-c++98-compat -Wno-c++98-compat-pedantic
CXX_COMPILEFLAGS = -x c++ $(CXXFLAGS)
WARNING_AUDIT_CFLAGS = $(CFLAGS)
LINK = $(CC)
LDFLAGS =
LDLIBS = -lm
CRITERION_CFLAGS = $(shell pkg-config --cflags criterion)
CRITERION_LIBS = $(shell pkg-config --libs criterion)
ZIG_CC = zig cc
ZIG_CXX = zig c++
ZIG_CACHE_ENV = ZIG_GLOBAL_CACHE_DIR=$(CURDIR)/.zig-cache/global \
	ZIG_LOCAL_CACHE_DIR=$(CURDIR)/.zig-cache/local
ZIG_CFLAGS = $(CFLAGS) -Wno-deprecated-octal-literals
ZIG_CXXFLAGS = -x c++ $(CXXFLAGS)
ZIG_CXX_LDFLAGS = -nostdlib++
MIRA_OBJS = version.o cmbnms.o y.tab.o data.o lex.o big.o reduce.o signals.o \
	steer.o trans.o types.o utf8.o
CORE_OBJS = big.o cmbnms.o data.o lex.o reduce.o signals.o steer.o trans.o \
	types.o utf8.o y.tab.o
RUNTIME_HEADERS = data.h platform.h runtime.h combs.h utf8.h version.h y.tab.h
HEADER_CHECK_INCLUDES = '\#include "runtime.h"' '\#include "platform.h"' \
	'\#include "signals.h"' '\#include "utf8.h"' '\#include "lex.h"' \
	'\#include "big.h"' '\#include "data.h"' '\#include "version.h"'
.PHONY: all test check check-headers check-c cxx check-cxx zig-cc zig-cxx \
        check-zig tools check-tools clean clean-build-products cleanup install \
        sources exfiles pdf dist tellcc warning-audit FORCE

all: FORCE
	@$(MAKE) mira miralib/menudriver exfiles

test: mira tests/mira_tests
	./tests/mira_tests -j1

check: check-headers check-c check-tools

warning-audit:
	@$(MAKE) check-c
	@$(MAKE) clean-build-products
	@$(MAKE) CFLAGS="$(WARNING_AUDIT_CFLAGS)" mira tools

check-headers:
	printf '%s\n' $(HEADER_CHECK_INCLUDES) 'int main(void) { return 0; }' | \
	    $(CC) $(CFLAGS) -fsyntax-only -x c -

check-c:
	@$(MAKE) cleanup
	@$(MAKE) test

cxx:
	@$(MAKE) cleanup
	@$(MAKE) CC="$(CXX)" CFLAGS="$(CXX_COMPILEFLAGS)" LINK="$(CXX)" \
	    LDFLAGS="$(CXXFLAGS)" mira miralib/menudriver

check-cxx: cxx

zig-cc:
	@$(MAKE) clean-build-products
	@mkdir -p .zig-cache/global .zig-cache/local
	@$(ZIG_CACHE_ENV) $(MAKE) CC="$(ZIG_CC)" CFLAGS="$(ZIG_CFLAGS)" \
	    LINK="$(ZIG_CC)" mira miralib/menudriver

zig-cxx:
	@$(MAKE) clean-build-products
	@mkdir -p .zig-cache/global .zig-cache/local
	@$(ZIG_CACHE_ENV) $(MAKE) CC="$(ZIG_CXX)" CFLAGS="$(ZIG_CXXFLAGS)" \
	    LINK="$(ZIG_CXX)" LDFLAGS="$(ZIG_CXX_LDFLAGS)" \
	    mira miralib/menudriver

check-zig: zig-cc zig-cxx

tools: fdate just miralib/menudriver

check-tools:
	@$(MAKE) tools

# -Dsparc7 needed for Solaris 2.7
# -Dsparc8 needed for Solaris 2.8 or later
mira: $(CORE_OBJS) version.o Makefile
	$(LINK) $(LDFLAGS) -o mira $(MIRA_OBJS) $(LDLIBS)

.c.o:
	$(CC) $(CFLAGS) -c -o $@ $<

# It must always run this rule before building mira (or not)
FORCE: fdate
	@# Quietly check whether the host or last modification date have changed
	@{ echo host: `uname -m` `uname -s` `uname -r` \
	   gcc -v 2>&1 | tail -1 ; } > .newhost
	@rm -f sources
	@ls -t `$(MAKE) -s sources` | ./fdate > .newvdate
	@if cmp -s .host .newhost; \
	 then rm .newhost; \
	 else mv .newhost .host; \
	 fi
	@if cmp -s .vdate .newvdate; \
	 then rm .newvdate; \
	 else mv .newvdate .vdate; \
	 fi

version.o: version.c .host .vdate miralib/.version
	$(CC) $(CFLAGS) -DVERS=`cat miralib/.version` \
		        -DHOST="`./quotehostinfo`" \
			-DVDATE="\"`cat .vdate`\"" \
			-c version.c

y.tab.c y.tab.h: rules.y
	$(YACC) -d rules.y

$(CORE_OBJS): $(RUNTIME_HEADERS) Makefile
data.o: .xversion
big.o data.o lex.o reduce.o steer.o trans.o types.o: big.h
big.o data.o lex.o reduce.o steer.o rules.y types.o: lex.h
utf8.o: utf8.h Makefile
cmbnms.o: cmbnms.c Makefile
fdate: fdate.c Makefile
	$(CC) $(CFLAGS) fdate.c -o fdate
just: just.c Makefile
	$(CC) $(CFLAGS) just.c -o just
# gendecs creates both files so avoid a parallel make running gendecs
# twice in parallel and appending two copies of the lines to the output files.
combs.h: cmbnms.c gencdecs
cmbnms.c: gencdecs
	./gencdecs
miralib/menudriver: menudriver.c signals.c Makefile
	$(CC) $(CFLAGS) -c -o menudriver.o menudriver.c
	$(CC) $(CFLAGS) -c -o menudriver-signals.o signals.c
	$(LINK) $(LDFLAGS) -o miralib/menudriver menudriver.o \
	    menudriver-signals.o
	chmod 755 miralib/menudriver$(EX)
tests/mira_tests: tests/mira_tests.c Makefile
	$(CC) $(CFLAGS) $(CRITERION_CFLAGS) -o tests/mira_tests \
	    tests/mira_tests.c $(CRITERION_LIBS)
#alternative: use shell script
#	ln -s miralib/menudriver.sh miralib/menudriver
tellcc:
	@echo $(CC) $(CFLAGS)
clean: cleanup
clean-build-products:
#to be done on moving to a new host
	-rm -rf *.o fdate just miralib/menudriver mira$(EX) tests/mira_tests
	-rm -f miralib/preludx miralib/stdenv.x miralib/ex/*.x #miralib/ex/*/*.x
	-rm -f mira.1.pdf mira.man.pdf
cleanup: clean-build-products
	-rm -rf .zig-cache
install:
	make -s all
	strip mira$(EX)
	cp mira$(EX) $(BIN)/
	cp mira.1 $(MAN)/
	rm -rf $(LIB)/miralib
	strip miralib/menudriver$(EX)
	cp -rp miralib $(LIB)/
SOURCES = .xversion big.c big.h gencdecs data.h platform.h runtime.h data.c \
          lex.h lex.c reduce.c rules.y signals.c signals.h steer.c trans.c \
          types.c utf8.h utf8.c version.h version.c fdate.c
sources: $(SOURCES); @echo $(SOURCES)
exfiles: mira
	@-./mira -make -lib miralib ex/*.m
PDF=mira.1.pdf mira.man.pdf
pdf: $(PDF)
mira.1.pdf: mira.1 Makefile
	groff -man -Tpdf mira.1 > mira.1.pdf
mira.man.pdf: mira.man.ms
	tbl mira.man.ms | groff -Tpdf -ms > mira.man.pdf

dist: $(PDF)
	version=$$(cat .version | sed 's/./&\./'); \
	rm -rf miranda-$$version; mkdir miranda-$$version; \
	tar cpf - $$(git ls-files) $(PDF) | (cd miranda-$$version; tar xpf -); \
	tar cfz miranda-$$version.tar.gz miranda-$$version; \
	rm -f miranda-$$version.zip; \
	zip -rq miranda-$$version.zip miranda-$$version; \
	md5sum miranda-$$version.tar.gz miranda-$$version.zip; \
	sha256sum miranda-$$version.tar.gz miranda-$$version.zip; \
	rm -rf miranda-$$version
