# Maintenance of Miranda

The Miranda source code is now maintained on `codeberg.org/DATurner/miranda`

This is particularly relevant because the last binary release
on miranda.org.uk was of mira 2.042 in Sep 2008 and since then
Professor Turner only released it in source code form, of which
his latest is 2.066 from Jan 2020, but those releases do not compile
out of the box.

To build it from source, you need `make` and a C compiler.
If you need to modify `rules.y` you'll also need `byacc`;
it does not work at all with the supposedly compatible GNU `bison`.

It is known to work on
aarch, amd, arm, chrp, evbarm, loongarch, mips, powerpc, riscv and x86,
on 32-bit and 64-bit, big-endian and little-endian systems running
AIX, AlmaLinux, AlpineLinux, Archlinux, CentOS, Debian, FreeBSD, Haiku,
MacOS X, NetBSD, OpenBSD, OpenSUSE and Rocky with all versions of
GCC from 2.95 to 14 and clang 11 to 16 with no optimization enabled and
some versions of gcc and clang up to `-O3`. The 64-bit version has been
tested with up to 2TB of RAM for the heap, over 100,000,000,000 cells.

You can see whether optimization will work for you in the table "Compilers"
in https://codeberg.org/DATurner/miranda/issues/25 

It compiles but does not work on Solaris with a sun4u processor
and a Windows port has not yet been attempted.

A release will be made on Codeberg when further portability
and testing are complete, currently scheduled for 1st May 2025.

In the meantime, you can

```
git clone https://codeberg.org/DATurner/miranda
cd miranda
make
make install
```

which puts it in `/usr/bin/mira` and `/usr/lib/miralib`.
To install it elsewhere or use a different compiler than GCC,
edit `Makefile` before building.

You can also test it in the source directory before installing it
by running it as `./mira`

There is a mailing list `miranda@groups.io` whose web site is
`http://groups.io/g/miranda` and you can also subscribe to it
by sending an email to `miranda+subscribe@groups.io`

His earlier language, KRC, is maintained at `codeberg.org/DATurner/KRC`

    Martin Guy <martinwguy@gmail.com>, April 2025.
