# Maintenance of Miranda

The Miranda source code is now maintained on `codeberg.org/DATurner/miranda`

This is particularly relevant because the last binary release
on miranda.org.uk was of mira 2.042 in Sep 2008 and since then
Professor Turner only released it in source code form, of which
his latest is 2.066 from Jan 2020.

To build it from source, you need `make`, a C compiler and `byacc`
(it does not work at all with the supposedly compatible GNU `bison`).

It is also particularly sensitive to the version of the compiler
you use (it impacts the garbage collector) and is known to work
on both 32-bit and 64-bit systems with:

* GCC 6
* clang 14

and not to work reliably with

* GCC 12

A release will be made on Codeberg when further portability
and testing is complete, currently scheduled for 1st May 2025.

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
by saying `./mira`

There is a mailing list `miranda@groups.io` whose web site is
`http://groups.io/g/miranda` and you can also subscribe to it
by sending an email to `miranda+subscribe@groups.io`

His earlier language, KRC, is now at `codeberg.org/DATurner/KRC`

    Martin Guy <martinwguy@gmail.com>, April 2025.
