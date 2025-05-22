#install paths relative to /
#for linux, MacOS X, Cygwin:
BIN=usr/bin
LIB=usr/lib#beware no spaces after LIB
MAN=usr/share/man/man1
#for Solaris:
#BIN=usr/local/bin
#LIB=usr/local/lib#beware no spaces after LIB
#MAN=usr/local/man/man1
CC = clang
CFLAGS = -g -Wall #-O #-DCYGWIN #-DUWIN #-DIBMRISC #-Dsparc7 #-Dsparc8
#be wary of using anything higher than -O as the garbage collector may fall over
#if using gcc rather than clang try without -O first
EX = #.exe        #needed for CYGWIN, UWIN
YACC = byacc #Berkeley yacc, gnu yacc not compatible

all: FORCE
	@$(MAKE) mira miralib/menudriver exfiles

# -Dsparc7 needed for Solaris 2.7
# -Dsparc8 needed for Solaris 2.8 or later
mira: big.o cmbnms.o data.o lex.o reduce.o steer.o trans.o types.o \
      utf8.o y.tab.o version.o Makefile
	$(CC) $(CFLAGS) -o mira version.o cmbnms.o y.tab.o data.o lex.o \
	    big.o reduce.o steer.o trans.o types.o utf8.o -lm

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

big.o cmbns.o data.o lex.o reduce.o steer.o trans.o types.o y.tab.o: \
                     data.h combs.h utf8.h y.tab.h Makefile
data.o: .xversion
big.o data.o lex.o reduce.o steer.o trans.o types.o: big.h
big.o data.o lex.o reduce.o steer.o rules.y types.o: lex.h
utf8.o: utf8.h Makefile
cmbnms.o: cmbnms.c Makefile
# gendecs creates both files so avoid a parallel make running gendecs
# twice in parallel and appending two copies of the lines to the output files.
combs.h: cmbnms.c gencdecs
cmbnms.c: gencdecs
	./gencdecs
miralib/menudriver: menudriver.c Makefile
	$(CC) $(CFLAGS) menudriver.c -o miralib/menudriver
	chmod 755 miralib/menudriver$(EX)
#alternative: use shell script
#	ln -s miralib/menudriver.sh miralib/menudriver
tellcc:
	@echo $(CC) $(CFLAGS)
clean: cleanup
cleanup:
#to be done on moving to a new host
	-rm -rf *.o fdate miralib/menudriver mira$(EX)
	./unprotect
	-rm -f miralib/preludx miralib/stdenv.x miralib/ex/*.x #miralib/ex/*/*.x
	-rm -f manual.html
install:
	make -s all
	strip mira$(EX)
	cp mira$(EX) /$(BIN)
	cp mira.1 /$(MAN)
	rm -rf /$(LIB)/miralib
	./protect
	strip miralib/menudriver$(EX)
	cp -pPR miralib /$(LIB)/miralib
	./unprotect
	find /$(LIB)/miralib -exec chown `./ugroot` {} \;
release:
	make -s all
	-rm -rf usr
	mkdir -p $(BIN) $(LIB) $(MAN)
	cp mira$(EX) $(BIN)
	cp mira.1 $(MAN)
	./protect
	cp -pPR miralib $(LIB)/miralib
	./unprotect
	find usr -exec chown `./ugroot` {} \;
	tar czf `rname`.tgz ./usr
	-rm -rf usr
SOURCES = .xversion big.c big.h gencdecs data.h data.c lex.h lex.c reduce.c rules.y \
          steer.c trans.c types.c utf8.h utf8.c version.c fdate.c
sources: $(SOURCES); @echo $(SOURCES)
exfiles: mira
	@-./mira -make -lib miralib ex/*.m
html: mira.1.html manual.html
mira.1.html: mira.1 Makefile
	man2html mira.1 | sed '/Return to Main/d' > mira.1.html
manual.html: manual.md mira.1.html
	sh makehtml.sh manual.md

dist:
	version=$$(cat .version | sed 's/./&\./'); \
	rm -rf miranda-$$version; mkdir miranda-$$version; \
	tar cpf - $$(git ls-files) | (cd miranda-$$version; tar xpf -); \
	tar cfz miranda-$$version.tar.gz miranda-$$version; \
	rm -f miranda-$$version.zip; \
	zip -rq miranda-$$version.zip miranda-$$version; \
	md5sum miranda-$$version.tar.gz miranda-$$version.zip; \
	sha256sum miranda-$$version.tar.gz miranda-$$version.zip; \
	rm -rf miranda-$$version
