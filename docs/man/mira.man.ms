.nr HY 0
'\" Enclosure macro for examples
.de SP
.if t .sp .5
.if n .sp
..
.de XE
.SP
.nf
.ft CW
..
.de XX
.ft R
.SP
.fi
..
.TL
Miranda System Manual
.AU
Copyright Research Software Limited 1985-2020
.TS
center;
r l r l.
1.	How to use the manual system	20.	Algebraic types
2.	About the name \(lqMiranda\(rq	21.	Abstract types
3.	About this release	22.	Empty types
4.	The Miranda command interpreter	23.	The special function \f(CWshow\fP
5.	Brief summary of main commands	24.	Formal syntax of Miranda scripts
6.	List of remaining commands	25.	Comments on syntax
7.	Expressions	26.	Miranda lexical syntax
8.	Operators	27.	The library mechanism
9.	Operator sections	28.	The standard environment
10.	Identifiers	29.	Literate scripts
11.	Literals	30.	Some hints on Miranda style
12.	Tokenisation and layout	31.	UNIX/Miranda system interface
13.	Iterative expressions	32.	-->> CHANGES <<--
14.	Scripts, overview	33.	Copying
15.	Definitions	34.	Bug reports
16.	Pattern matching
17.	Compiler directives
18.	Basic type structure
19.	Type synonyms
.TE
Printout of online manual pages for version 2067;
manual pages last revised May 2025.
.LP
The Miranda System Manual is Copyright (c) Research Software
Limited, 1985-2019. It may be freely reproduced, with or without
changes, for use with the Miranda System but commercial publication
rights are reserved to the Copyright holder. 
.SH
1. How to use the Miranda on-line reference manual
.LP
The manual is menu driven, and is a separate subsystem that can be
invoked from the Miranda command interpreter. To access the manual from
Miranda, type
.XE
    /man
.XX
followed by return. To access the manual directly from the command
line, without entering Miranda first, type the line
.XE
    mira -man
.XX
as a shell command.
.LP
On entering the manual system a contents page is displayed listing
numbered sections. In response to the question at the bottom of the
page you should enter the number of the section you wish to see and
press return (i.e. ENTER). The contents of that section are then
displayed to you. When you are ready to leave the manual, press return,
without giving a section number, in response to the question at the
foot of the contents page \- typing q (for \(lqquit\(rq) has the same effect.
.LP
If the section is more than one page long, you should press the space
bar when you have finished reading a page, in order to see the next page
(or press return to see one more line). At the end of the section, you
may press return to go back to the contents page.
.LP
The manual is organised in short sections, each at most two or three
screenfulls long. Where a section would otherwise be too long to fit in
with this philosophy, the manual is organised recursively and will
display a subsidiary contents page, with a list of numbered subsections,
which you may read, as before, by typing the appropriate number. To
return to the main menu from a submenu, press return with no section
number, in response to the question at the bottom of the page.
.LP
The manual is intended to provide online documentation of the Miranda
programming language and the command system in which it is embedded. It
is not intended to be a tutorial on functional programming. It does not
provide information about the operating system, for which separate
documentation is available (but there is a section on the \fIUNIX/Miranda
system interface\fP).
.SH
Summary of manual behaviour
.LP
Whenever the manual system prompts the user for input \- by asking for
\(lqnext selection\(rq \- the complete repertoire of possible responses is:
.TS
l l.
q	quit the manual
<return> 	T{
exit one level of menu structure (i.e.
.RS
if at foot of section, return to menu
.br
if at submenu, return to master menu
.br
if at main menu, quit the manual)
.RE
T}
<number>	display section from current contents page
.	(dot) same again, i.e. redisplay last requested section
+	display next section in numerical order
\(mi	display previous section
!command	temporary escape to O/S, executes shell command
.TE
.SH
Summary of the behaviour of \f(CWmore\fP
.LP
Individual sections of the manual are displayed to you using the UNIX
program \f(CWmore\fP or an equivalent such as \f(CWless\fP
(you can change this by setting an environment variable \f(CWVIEWER\fP (*)).
These programs have their own UNIX manual page describing their features.
The responses you can give generally include
.TS
l l.
[SPACE]	display next screenful
[return]	display one more line
q	(quit) cease showing me this file
b	(back) scroll backwards by one screenful
/context	search for context (e.g. a word)
?context	search backwards for context
h	 help
.TE
(*) See the section on Environment Variables under \fIUNIX/Miranda system
interface\fP.
.SH
2. About the name \(lqMiranda\(rq
.LP
The word \(lqMiranda\(rq is not an acronym.
It is a proper name (like \(lqAda\(rq).
.LP
\(lq\fBMiranda\fP (f). From the Latin meaning `to be admired'. This name was
first used by Shakespeare for the heroine of \fIThe Tempest\fP, a young girl
blessed with many admirable qualities. Like other unusual Shakespearean
names it has been used quite frequently in the 20th century.\(rq
.RS
Collins Dictionary of First Names, William Collins and Son Ltd, London, 1967
.RE
.LP
\(lqO wonder! How many goodly creatures are there here! O brave new world.\)rq
.RS
\fIThe Tempest\fP by William Shakespeare (from a speech by Miranda, Act 5, Scene 1)
.RE
.LP
When used as the name of a functional programming system,
\(lqMiranda\(rq is a trademark (tm) of Research Software Ltd.
.LP
Note that only the first letter of Miranda is upper case \- it should
never be written all in capitals.
.SH
3. About this release
.LP
This is the first maintenance release from
\f(CWcodeberg.org/DATurner/miranda\fP, based on
Miranda release two of October 1989 rereleased thirty years on
as open source \- as historical record and in the hope that it may still
be useful. Originally released in 1985, Miranda was the first widely
used non-strict, purely functional language with polymorphic typing and
had a significant influence on the development of the field.
.LP
The source code has been revised to the current C standard (C11) so it
will compile for both 32 and 64 bit platforms. Various bugs have been
fixed and some features added (see the Changes section of the manual)
but the Miranda language and main features of the system interface
remain unchanged. The manual has been revised in places for clarity and
to remove out of date material.
.LP
The online manual pages are primarily intended to document the system at
the level required by someone who already knows quite a lot about
programming languages and has some previous exposure to functional
programming. There is a certain amount of tutorial material, but if you
are a beginner to functional programming you may find parts of the
manual hard to follow, and will need to seek help elsewhere.
.LP
The following paper gives a convenient summary of the main features of
Miranda: D. A. Turner \fIAn Overview of Miranda\fP, SIGPLAN Notices, December 1986.
.LP
A copy of this paper is included in the manual pages, but this and other
information about Miranda can be found on the world wide web at
miranda.org.uk
.LP
Miranda has two available text books
.LP
.IP 1.
Simon Thompson \fIMiranda: the Craft of Functional Programming\fP,
Addison-Wesley, 470 pages, 1995. ISBN 0-201-42279-4 (Paperback).
A webpage for the book by the author is at
.br
\f(CWwww.cs.kent.ac.uk/people/staff/sjt/Miranda_craft/\fP
.br
or follow the link under BOOKS at miranda.org.uk.
.IP 2.
Chris Clack, Colin Myers & Ellen Poon \fIProgramming with Miranda\fP,
Prentice Hall, 312 pages, 1995. ISBN 0-13-192592-X
.br
The rights in this book have reverted to the authors who have made it
available online \- follow the link under BOOKS at miranda.org.uk.
.LP
There were two other texts, both now out of print, but there may be
copies in a library or with second hand book sellers.
.IP
Richard Bird & Philip Wadler \fIAn Introduction to Functional Programming\fP,
Prentice Hall, 293 pages, March 1988.
.br
This used a mathematical notation, quite closely based on Miranda but
equally suitable for use with other functional languages.
.IP
Ian Holyer \fIFunctional Programming with Miranda\fP, Pitman, 215 pages, 1991.
.SH
4. The Miranda command interpreter
.LP
The Miranda system is invoked from Unix by the command
.XE
    mira [script]
.XX
where \f(CWscript\fP (optional parameter) is the pathname of a file containing
a set of Miranda definitions. If no script is specified a default
name \f(CWscript.m\fP is assumed. The named script (\f(CWscript.m\fP by default)
becomes your \fIcurrent script\fP, during the ensuing Miranda session.
You can change your \(lqcurrent script\(rq during a session,
but at any time there is a unique filename which is current.
.LP
Note that a file containing a Miranda script is expected to have a name
ending in \f(CW.m\fP and the \f(CWmira\fP command will add this extension if
missing. So \f(CWmira stuff\fP will be interpreted as \f(CWmira stuff.m\fP. It is
a convenient and widely used convention that files containing program
sources should have names indicating which language they are written in.
.LP
The set of names in scope at any time are those of the current script,
together with the names of any scripts which it `includes' (see library
directives) plus the names of the \fIstandard environment\fP, which is always
in scope. The current script may be an empty or non-existent file if
you have not yet put any definitions in it. In this case just the names
of the standard environment will be in scope.
.LP
The prompt \f(CWMiranda\fP indicates that you are talking to the Miranda
interpreter. This activity is called a Miranda \(lqsession\(rq. Each
command should be typed on a single line, following the prompt, and is
entered by hitting return. Any command not beginning with one of the
special characters \f(CW/\fP, \f(CW?\fP or \f(CW!\fP is assumed to be an expression to be
evaluated. The following commands are available during a session.
.SH 2
\f(CWexp\fP
.LP
Any Miranda expression typed on a line by itself is evaluated, and the
value is printed on the screen. If the value is of type \f(CW[char]\fP it is
printed literally, otherwise the special function \f(CWshow\fP is applied to
it to convert it to printable form. Example
.XE
    Miranda sum[1..100]
    5050 (response)
.XX
There is a special symbol \f(CW$$\fP which is always set to the last expression
evaluated. So after the above command \f(CW$$\fP will have the value 5050, and
this can be used in the next expression \- e.g. \f(CW$$/2\fP will produce the
response 2525 (and the value of \f(CW$$\fP is now 2525).
.SH 2
\f(CWexp &>\fP pathname
.LP
A background process is set up to evaluate \f(CWexp\fP, and the resulting
output (including error messages, if any) sent to the designated file.
.SH 2
\f(CWexp &>>\fP pathname
.LP
As above, except that the output is appended to the designated file,
instead of replacing its previous contents.
.SH 2
\f(CWexp ::\fP
.LP
Print the type of the expression (instead of the value). Useful for
investigating the type structure of a script.
.SH 2
\f(CW?\fP
.LP
Lists all identifiers currently in scope, grouped by file of origin,
starting with the standard environment.
.SH 2
\f(CW?identifier(s)\fP
.LP
Gives more information about any identifier defined in the current
environment (namely its type and the name of the file in which it is
defined). This command will also accept a list of identifiers,
separated by spaces.
.SH 2
\f(CW??identifier\fP
.LP
Opens the relevant source file at the definition of identifier, which
may be any currently in scope. Try for example \f(CW??map\fP
.LP
For this and several other features to work Miranda must be configured
to use an appropriate editor \- the default is vi, but you can change
this. See section 31 subheading 5 of this manual (\fIHow to change the
default editor\fP).
.SH 2
\f(CW!command\fP
.LP
Execute any UNIX shell command.
.SH 2
\f(CW!!\fP
.LP
Repeat last shell command.
.LP
Note that the character \f(CW%\fP can be used in any Miranda session command,
including a \f(CW!\fP command, as an abbreviation for the pathname of the
current script. So, for example
.XE
    !wc %
.XX
does a word count on the current script. (If for some reason you need
to include a literal \f(CW%\fP character in a command, you can escape it with a
preceding backslash.)
.LP
All the remaining commands begin with \f(CW/\fP. Each of the following
commands can be abbreviated to its first letter.
.SH 2
\f(CW/edit\fP (also \f(CW/e\fP)
.LP
Edit the current script. Calls up the currently installed editor
(default \f(CWvi\fP, to change this see remark under ?? above). On quitting the
editor, if changes have been made to any relevant source file, the
Miranda system automatically recompiles the current script and any other
scripts on which it depends and which have been updated.
.SH 2
\f(CW/edit\fP pathname (also \f(CW/e\fP pathname)
.LP
Edit arbitrary script. Note that the pathname should end in \f(CW.m\fP and
that this will be added if missing.
.LP
Note by the way that (on most UNIX-like systems) Miranda understands the
commonly used \f(CW~\fP convention in pathnames. That is \f(CW~/file\fP means \f(CWfile\fP in
your home directory, and \f(CW~jack/file\fP means \f(CWfile\fP in jack's home directory.
.SH 2
\f(CW/file\fP (also \f(CW/f\fP)
.LP
Print the name of file containing the current script.
.SH 2
\f(CW/file\fP pathname (also \f(CW/f\fP pathname)
.LP
Change to new current script. Equivalent to quitting the Miranda
system and reinvoking it with a new sourcefile. Like \f(CW/e\fP, \f(CW/f\fP adds \f(CW.m\fP
to the end of the filename if missing.
.LP
Important special case \- reselecting the current script, e.g. by saying
.XE
    /f %
.XX
forces the current script to be RECOMPILED \- this is useful if the script
has errors and you wish to see the error messages again.
.SH 2
\f(CW/help\fP (also \f(CW/h\fP)
.LP
Display summary of main available commands. There are a few less used
auxiliary commands, not covered here /aux (or /a) will summarise these.
.SH 2
\f(CW/man\fP (also \f(CW/m\fP)
.LP
Enter the online manual system.
.SH 2
\f(CW/quit\fP (also \f(CW/q\fP)
.LP
Quit the Miranda system. Typing the end of file character (Control-D)
also has this effect.
.LP
Finally note that \f(CW$-\fP and \f(CW$+\fP are allowed as notations for
the standard input in Miranda expressions. The standard input as a list of
characters is denoted by \f(CW$-\fP. As a simple example, evaluating the
expression
.XE
    reverse $-
.XX
causes everything typed at the keyboard upto the next Control-D to be
echoed backwards.
.LP
The notation \f(CW$+\fP also denotes the standard input, but as a sequence of
Miranda expressions (one per line), and returns their values as a list.
For example
.XE
    sum $+
.XX
reads a sequence of numeric expressions from the standard input, and
returns the sum of their values. See the manual section 31/3 on reading with
interpretation for further information.
.SH
.ne 20
5. Summary of main available commands
.LP
.TS
l l.
\f(CWexp\fP	Evaluate a Miranda expression
\f(CWexp &> file\fP	Send value of expression to file (background process)
\f(CWexp &>> file\fP	Append value of expression to file (background process)
\f(CWexp ::\fP	Print type of \f(CWexp\fP
\f(CW?\fP	List all identifiers in scope (grouped by source file)
\f(CW?identifier(s)\fP	Give more information about identifier(s)
\f(CW??identifier\fP	Open source file at definition of identifier
\f(CW!command\fP	Execute any UNIX shell command
\f(CW!!\fP	Repeat last shell command
\f(CW/edit /e\fP	Edit current script (default editor = vi or joe)
\f(CW/edit filename\fP	Edit filename
\f(CW/file /f\fP	Display filename of current script
\f(CW/file filename\fP	Change to new current script
\f(CW/help /h\fP	Display this command summary
\f(CW/man /m\fP	Enter online reference manual (menu driven)
\f(CW/quit /q\fP	Quit the Miranda system
\f(CW/aux /a\fP	Display list of auxiliary commands
.TE
.SH 2
Notes
.LP
Each \f(CW/\fP command can be abbreviated to its first letter \- \f(CW/e /f /h /m /q\fP
.LP
\f(CW%\fP is shorthand for the name of the current script (in commands).
Special case: note that \f(CW/f %\fP forces recompilation of current script.
.LP
\f(CW$$\fP is shorthand for the last expression evaluated (in expressions)
.SH
.ne 20
6. List of remaining commands
.LP
.TS
l l.
\f(CW/aux /a\fP	Print this list of auxiliary commands
\f(CW/cd [dirname]\fP	Change directory (defaults to home directory)
\f(CW/count (/nocount)\fP	Statistics following each evaluation (default off)
\f(CW/dic\fP	Report size of dictionary for storing names etc
\f(CW/editor\fP	Report name of text editor used by ?? and /e commands
\f(CW/editor PROG\fP	*Change resident editor to PROG (see below)
\f(CW/find id(s)\fP	Like \f(CW?ids\fP but look under original names of aliases
\f(CW/gc (/nogc)\fP	Enable garbage collection reports (default off)
\f(CW/heap\fP	Report size of heap
\f(CW/heap SIZE\fP	Set heap to SIZE cells
\f(CW/hush (/nohush)\fP	Control prompts and other feedback (default on)
\f(CW/list (/nolist)\fP	*Control listing of script when compiling (default off)
\f(CW/miralib\fP	Report absolute pathname of the directory miralib
\f(CW/(no)recheck\fP	*Control busy checking for script updates (default off)
\f(CW/settings /s\fP	Print current settings of controllable options
\f(CW/version /v\fP	Print version information
\f(CW/V\fP	More detailed version information
\f(CW||...\fP	Lines beginning in \f(CW||\fP are ignored (comment facility)
.TE
.LP
Commands marked (*) are sticky, i.e. remembered for subsequent sessions.
If you don't like the resident editor choose another \- recommended editors
include \- vi, joe, pico, nano, emacs \- for more info see the \f(CW/man\fP section 31/5.
.LP
\f(CW/recheck\fP enables a check for update of any relevant source file before
each evaluation, instead of only after /e[dit] \- appropriate if an
editor window is kept open alongside the mira session window.
.SH
7. Expressions
.LP
In Miranda an expression denotes a value. Expressions occur in two
contexts, but have the same(*) syntax in both situations. First, the
basic mode of operation of the Miranda command interpreter is that it
evaluates expressions typed at the terminal (these are called `command-level
expressions'). Second, expressions are an important
syntactic component of scripts (because scripts are collections of
definitions, and the right hand sides of definitions are composed of
expressions).
.LP
Expressions typed at the terminal are volatile \- only by being made part
of a script can an expression be saved for future use.
.LP
An expression is either simple, or a function application, or an
operator expression, or an operator.
.LP
A simple expression is one of the following:
.IP
Identifier: (see section 10.\ \fIIdentifiers\fP)
these are of two kinds based on the case of the initial letter
.RS
.IP
variable e.g. \f(CWx\fP or \f(CWmap\fP
.IP
constructor e.g. \f(CWX\fP or \f(CWTrue\fP
.RE
.IP
Literal, e.g. \f(CW136\fP or \f(CW"fruit"\fP (see section 11.\ \fILiterals\fP)
.IP
An operator section (see section 9.\ \fIOperator sections\fPy)
.IP
The keyword \f(CWshow\fP or \f(CWreadvals\fP (see sections 23.\ \f(CWshow\fP and 31/3.\ \f(CWreadvals\fP)
.IP
A list, such as \f(CW[1,5,7,9]\fP or a `dotdot' list or a list comprehension
(see section 13.\ \fIIterative expressions\fP).
.IP
A tuple, such as \f(CW(True,"green",37)\fP. Tuples differ from lists in that
they can have components of mixed type. They are always enclosed in
round parentheses. The empty tuple, which has no components, is written
\f(CW()\fP. Otherwise, a tuple must have at least two components \- there is
no concept of a one-tuple. Tuples cannot be subscripted, but their
components can be extracted by pattern matching. Since there is no
concept of a one-tuple, the use of parentheses for grouping does not
conflict with their use for tuple formation.
.IP
Any expression enclosed in parentheses is a simple expression.
.SH 2
Function application
.LP
is denoted by juxtaposition, and is left associative, so e.g.
.XE
    f a b
.XX
denotes a curried function application of two arguments. (So \f(CWf\fP is
really a function of one argument whose result is another function -
thus \f(CWf a b\fP is actually parsed as \f(CW(f a) b\fP \- the advantage of this
arrangement is that \f(CWf a\fP has a meaning in its own right, it is a
partially applied version of \f(CWf\fP.)
.SH 2
Operator expressions
.LP
For example
.XE
    5*x-17
.XX
There are a variety of infix and prefix operators, of various binding
powers (see section 8.\ \fIOperators\fP). Note that function application
is more binding than any operator.
.LP
An operator on its own can be used as the name of the corresponding
function, as shown in the following examples
.XE
    arith2_ops = [+,-,*,/,div,mod,^]
    sum = foldr (+) 0
.XX
both of which are legal definitions. Note that when an operator is
passed as a parameter it needs to be parenthesised, to force the correct
parse. An ambiguity arises in the case of `\f(CW-\fP' which has two meanings as
an operator (infix and prefix). The convention is that `\f(CW-\fP' occurring
alone always refers to the infix (i.e. dyadic) case. The name \f(CWneg\fP is
provided for the unary minus function, as part of the standard environment.
.LP
A formal syntax for expressions can be found in the manual section
called \fIFormal syntax of Miranda scripts\fP.
.LP
(*) Note: There is one exception to the rule that command level
expressions have the same syntax as expressions inside scripts \- the
notation \f(CW$$\fP, meaning the last expression evaluated, is allowed only in
command level expressions.
.SH
8. Operators and their binding powers
.LP
Here is a list of all prefix and infix operators, in order of increasing
binding power. Operators given on the same line are of the same binding
power. Prefix operators are identified as such in the comments \- all
others are infix.
.TS
l l.
\f(CW: ++ --\fP	right associative
\f(CW\e/\fP	associative
\f(CW&\fP	associative
\f(CW~\fP	prefix
\f(CW> >= = ~= <= <\fP	continued relations allowed, e.g. \f(CW0<x<=10\fP
\f(CW+ -\fP	left associative
\f(CW-\fP	prefix
\f(CW* / div mod\fP	left associative
\f(CW^\fP	right associative
\f(CW.\fP	associative
\f(CW#\fP	prefix
\f(CW!\fP	left associative
\f(CW$identifier $IDENTIFIER\fP	right associative
.TE
.SH 2
Brief explanation of each operator
.LP
.TS
l lx.
\f(CW:\fP	T{
prefix an element to a list, type \f(CW*->[*]->[*]\fP
T}
\f(CW++ --\fP	T{
list concatenation, list subtraction, both of type \f(CW[*]->[*]->[*]\fP
.br
A formal definition of list subtraction is given below.
T}
\f(CW\e/ &\fP	T{
logical `or', `and', both of type \f(CWbool->bool->bool\fP
T}
\f(CW~\fP	T{
logical negation, type \f(CWbool->bool\fP
T}
\f(CW> >= = ~= <= <\fP	T{
comparison operators, all of type \f(CW*->*->bool\fP
.br
Note that there is an ordering defined on every (non-function) type. In
the case of numbers, characters and strings the order is as you would
expect, on other types it as an arbitrary but reproducible ordering.
Equality on structured data is a test for isomorphism. (i.e. in LISP
terms it is "EQUAL" not "EQ"). It is an error to test functions for
equality or order.
T}
\f(CW+ -\fP	plus, minus, type \f(CWnum->num->num\fP
\f(CW-\fP	T{
unary minus, type \f(CWnum->num\fP
.br
Note that in Miranda unary minus binds less tightly than the multiplication and division operators. This is the usual algebraic convention, but is different from PASCAL.
T}
\f(CW* / div mod\fP	T{
times, divide, integer divide, integer remainder, all of type \f(CWnum->num->num\fP
.br
\f(CW/\fP can be applied to integers or fractional numbers, and always gives
a fractional result, so e.g. \f(CW6/2\fP is \f(CW3.0\fP.
\f(CWdiv\fP and \f(CWmod\fP can only be applied to integers and give
integer results,
e.g. \f(CW7\ div\ 2\fP is \f(CW3\fP, \f(CW7\ mod\ 2\fP is \f(CW1\fP.
.br
\f(CWdiv\fP and \f(CWmod\fP obey the following laws,
where \f(CWa\fP and \f(CWb\fP are any integers:
.XE
with b ~= 0
(i)  b * (a div b) + a mod b = a
(ii) if b>0 then 0 <= a mod b < b
     if b<0 then b < a mod b <= 0
.XX
T}
\f(CW^\fP	`to the power of', type \f(CWnum->num->num\fP
\f(CW.\fP	function composition, type \f(CW(**->***)->(*->**)->*->***\fP
\f(CW#\fP	length of list, type \f(CW[*]->num\fP
\f(CW!\fP	T{
list subscripting, type \f(CW[*]->num->*\fP
.br
Note that the first element of a non-empty list \f(CWx\fP is \f(CWx!0\fP
and the last element is \f(CWx!(#x-1)\fP
T}
T{
\f(CW$identifier
.br
$IDENTIFIER\fP
T}	T{
do-it-yourself infix, \f(CWa $f b\fP is equivalent in all contexts to \f(CWf a b\fP. Also works for constructors of two or more arguments.
T}
.TE
.SH 2
Note on list subtraction
.LP
Here is a formal definition of the \f(CW--\fP operator in Miranda. It is
defined using an auxiliary function \f(CWremove\fP which removes the first
occurrence (if any) of a given item from a list.
.XE
    x -- [] = x
    x -- (b:y) = (remove b x) -- y
    remove b [] = []
    remove b (a:x) = x,            if a=b
                   = a:remove b x, otherwise
.XX
.SH
9. Sections
.LP
An infix operator can be partially applied, by supplying it with only
one of its operands, the result being a function of one argument. Such
expressions are always parenthesised, to avoid ambiguity,
and are called `sections'.
Two different kinds of sections (called presections and
postsections) are possible since either the first or the second operand
can be supplied.
.LP
An example of a presection is
.XE
	(1/)
.XX
which denotes the reciprocal function. An example of a postsection is
.XE
	(/3)
.XX
which gives a concise notation for the `divide by three' function.
Note that both of these examples are functions of type \f(CW(num->num)\fP.
With one exception (see below) sections can be formed using any infix operator.
Further examples are \f(CW(0:)\fP which is a function for prefixing lists of
numbers with zero, and \f(CW(^2)\fP which is the square function.
.LP
Sections may be regarded as the analogue of currying for infix
operators. They are a minor syntactic convenience, and do not really
add any power to the language, since any function denoted in this way
could have been introduced by explicit definition. For the first two
examples given above we could have written, say
.XE
    reciprocal y = 1/y
    divide_by_three x = x/3
.XX
and then used the function names, although this would have been somewhat
more verbose.
.LP
To summarise the conventions for infixes, taking infix division as an
example, note that the following expressions are all equivalent.
.XE
    a / b
    (/) a b
    (a /) b
    (/ b) a
.XX
The usual rules about operator precedence (see the manual section on
operators) apply to sections. For example, we can write \f(CW(a*b+)\fP but not
\f(CW(a+b*)\fP, because \f(CW*\fP is more binding than \f(CW+\fP. The latter example should
have been written \f(CW((a+b)*)\fP. As always when writing complicated
expressions, if there is any possibility of ambiguity it is better to
put in extra parentheses.
.SH 2
Special case
.LP
It is not possible to form a postsection in infix minus, because of a
conflict of meaning with unary minus. For example:
.XE
    (-b)
.XX
is a parenthesised occurrence of negative \f(CWb\fP, not a section. As a way
round this there is a function \f(CWsubtract\fP in the standard environment
with the definition: \f(CWsubtract x y = y - x\fP. This is a normal curried
function, so we can write \f(CW(subtract b)\fP to get the function that
subtracts \f(CWb\fP from things.
.LP
Presections in infix minus, such as \f(CW(a-)\fP, cause no ambiguity.
There are no problems with infix plus because Miranda does not have a
unary plus operator.
.SH 2
Acknowledgement
.LP
The idea of sections is due to Richard Bird (of Oxford University
Programming Research Group) and David Wile (of USC Information Sciences
Institute).
.SH
10. Identifiers
.LP
An identifier consists of a letter followed by zero or more additional
characters which may be letters, digits or occurrences of \f(CW_\fP or \f(CW'\fP
(underscore and single quote). Examples:
.XE
    x  yellow  p11d  y'  GROSS_INCOME
.XX
Note that both upper and lower case letters are allowed, and they are
treated as different, so x and X are not the same identifier. There is
no restriction on the length of identifiers, and all the characters are
significant in deciding whether two identifiers are the same.
Identifiers fall into two different classes
(called in the formal syntax \f(CWidentifier\fP and \f(CWIDENTIFIER\fP)
depending on whether their initial letter
is upper or lower case.
.LP
Identifiers are used for three different purposes in Miranda:
.IP (i)
as variables, i.e. names for values (note that the names of functions are
also considered to be variables),
.IP (ii)
as typenames, such as \f(CWbool\fP and \f(CWchar\fP, and
.IP (iii)
as constructors (see section on algebraic types).
The names of constructors must begin with an upper case letter, while
variables and typenames must begin with a lower case letter.
.SH 2
Reserved words
.LP
The following are special symbols of the Miranda language:
.XE
    abstype div if mod otherwise readvals show type where with (10)
.XX
These are often shown as underlined (or bold) in published documents,
but in programs they are typed as ordinary lower case words (which means
that these words cannot be used as identifiers).
.SH 2
Predefined identifiers
.LP
The following identifiers are normally* predefined and always in scope.
They constitute the `standard environment'. They are defined in the
script \f(CWstdenv.m\fP, contained in the directory
\f(CW/usr/lib/miralib\fP.
.SH 3
(a) predefined typenames
.XE
    bool char num sys_message
.XX
.SH 3
(b) predefined constructors
.XE
    False True :: bool
    Appendfile Closefile Exit Stderr Stdout System Tofile :: sys_message
.XX
.SH 3
(c) predefined variables
.XE
    abs and arctan cjustify code concat const converse cos decode  digit
    drop dropwhile e entier error exp filemode filter foldl foldl1 foldr
    foldr1 force fst getenv hd hugenum id  index  init  integer  iterate
    last  lay  layn  letter  limit lines ljustify log log10 map map2 max
    max2 member merge min min2 mkset neg numval or  pi  postfix  product
    read  readb  rep  repeat reverse rjustify scan seq showfloat showhex
    shownum showoct showscaled sin snd sort  spaces  sqrt  subtract  sum
    system take takewhile tinynum tl transpose undef until zip zip2 zip3
    zip4 zip5 zip6 (91)
.XX
See manual section 28: \fIThe standard environment\fP
for a listing of its contents.
.LP
You can suppress automatic inclusion of \f(CW<stdenv>\fP
by calling \f(CWmira\fP with the flag \f(CW-stdenv\fP.
See the manual section 31/7: \fIOptions, setup files etc.\fP"
.SH
11. Literals
.LP
Miranda has three types of literal constant: numerals, character
constants and string constants.
.LP
Numerals are written in the following style
.XE
    12  5237563  24.6  4.5e13  0.63e-6
.XX
A numeral containing decimal point and/or scale factor (\f(CW.\fP or \f(CWe\fP) is
held internally as double precision (=64 bit) floating point, accuracy
approximately 17 significant figures. Integers are held in a different
internal representation, and have unbounded precision.
.LP
The two kinds of number, integer and floating point, are both of type
\f(CWnum\fP as far as the type-checker is concerned, and can be freely mixed
in calculations. There is automatic conversion from integer to float
when required, but not in the opposite direction. To convert from
floating point to integer, use \f(CWentier\fP (see standard environment).
.LP
Negative numbers are denoted by applying the prefix \f(CW-\fP operator to a
numeral, thus:
.XE
    -12  -4.5e13
.XX
but note that the notation \f(CW-12\fP is an expression, not a literal, so if
you wish to apply a function to it, you must write \f(CWf (-12)\fP, not \f(CWf -12\fP,
which would be read as an attempt to subtract \f(CW12\fP from \f(CWf\fP.
.LP
Integers can be written in hexadecimal (base 16) or octal (base 8)
notation starting with \f(CW0x\fP or \f(CW0o\fP, e.g. \f(CW4095\fP can also be written as \f(CW0xfff\fP
or \f(CW0o7777\fP. Floating point numbers can be expressed in hexadecimal
notation, optionally scaled by \f(CWp\fP followed by a power of 2. For
example 0x1.0p-2 means 0.25.
.LP
Character constants are written using single quotes, thus
.XE
    'a'    '0'    '\en'
.XX
The type \f(CWchar\fP includes all Unicode* characters, those outside ASCII
and Latin-1 can be expressed by numeric escape codes, see below.
.LP
Note that the functions \f(CWcode::char->num\fP, \f(CWdecode::num->char\fP convert
characters to and from their numeric codes.
.LP
String constants are written using double quotes, thus
.XE
    "hello dolly"    ""    "\en\en\en"
.XX
Escape conventions in character and string constants are as in C,
using the backslash character.
.XE
    \e'     single quote
    \e"     double quote
    \e\e     the \e character itself
    \ea     alarm
    \eb     backspace
    \ef     formfeed
    \en     newline
    \er     carriage return
    \et     tab
    \ev     vertical tab
.XX
plus these numeric escapes which specify characters by code number.
.XE
    \eddd     up to 3 decimal digits [0-9]
    \exffff   up to 4 hex digits [0-9a-f]
    \eXffffff up to 6 hex digits
.XX
For escape codes to \f(CW\e999\fP you can use either decimal or hex, for example
the DELETE character can be written as \f(CW\e127\fP or \f(CW\ex7f\fP. The \f(CW\ex\fP and \f(CW\eX\fP
forms cover the whole range of Unicode values. For example \f(CW\ex3b3\fP is
the Greek letter lower case gamma and \f(CW\ex20ac\fP is the euro sign. The \f(CW\eX\fP
form is unlikely to be needed but is provided for completeness.
.LP
Specifying a character by numeric code in a string or char constant has
the same effect as including it literally, so for example \f(CW"£"\fP and
\f(CW"\e163"\fP are exactly the same string.
.LP
Where a numeric escape code in a string is followed by a literal digit
(or hex digit for \f(CW\ex\fP \f(CW\eX\fP) the numeral can be padded with leading 0s to
force the correct parse. For example \f(CW"\e0078"\fP is the alarm character \f(CW\e7\fP
followed by a literal \f(CW'8'\fP , while \f(CW"\e78"\fP is \f(CW"N"\fP.
.LP
Literal newlines are allowed inside string quotes if escaped by a
preceding backslash, in which case the newline is ignored (as in C).
Thus the string \f(CW"hello dolly"\fP can equally be written
.XE
        "hello \
    dolly"
.XX
A literal newline is not allowed inside character quotes.
.LP
Unicode is an international standard providing numeric codes for the
symbols of practically all known human writing systems. Unicode
points 0-127 coincide with ascii and 128-255 with Latin-1.
.SH
12. Tokenisation and layout
.LP
A Miranda script or expression is regarded as being composed of \fItokens\fP,
separated by \fIlayout\fP.
.LP
A token is one of the following \- an identifier, a literal, a type
variable, or a delimiter. Identifiers and literals each have their own
manual section. A type variable is a sequence of one or more stars,
thus \f(CW*\fP, \f(CW**\fP, \f(CW***\fP etc. (see basic type structure). Delimiters are the
miscellaneous symbols, such as operators, parentheses, and keywords. A
formal definition of the syntax of tokens, including a list of all the
delimiters in given under \fIMiranda lexical syntax\fP.
.SH 2
Rules about layout
.LP
Layout consists of white space characters (spaces, tabs, newlines and
formfeeds), and comments. A comment consists of a pair of adjacent
vertical bars, together with all the text to the right of the bars on
the same line. Thus
.XE
    || this is a comment
.XX
Layout is not permitted inside tokens (except in \f(CWchar\fP and \f(CWstring\fP
constants, where it is significant) but may be inserted freely between
tokens to make scripts more readable. Layout is ignored by the compiler
except in two respects:
.LP
1) At least one space (or other layout characters) must be present
between two tokens that would otherwise form an instance of a single
larger token. For example in
.XE
    f 19 'b'
.XX
we have a function, \f(CWf\fP, applied to a number and a character, but if we
were to omit the two intervening spaces, the compiler would read this as
a single six-character identifier, because both digits and single-quotes
are legal characters in an identifier. (Where it is not required to
force the correct tokenisation, or because of the offside rule, see
below, the presence of layout between tokens is optional.)
.LP
2) Certain syntactic objects (roughly, the right hand sides of
declarations \- for an exact account see those entities followed by \f(CW(;)\fP
in the formal syntax) obey Landin's `offside rule' [Landin 1966].
This requires that every token of the object lie either directly below
or to the right of its first token. A token which breaks this rule is
said to be `offside' with respect to that object and terminates its
parse. For example in
.XE
    x = 2 < a
    y = f q
.XX
the \f(CWy\fP is offside with respect to the right hand side of the definition
of \f(CWx\fP (because it is to the left of the initial \f(CW2\fP). In such a case
the trailing semicolon may be omitted from the right hand side of the
equation for \f(CWx\fP.
.LP
It is because of the offside rule that Miranda scripts do not normally
contain explicit semicolons as terminators for definitions. The same
rule enables the compiler to determine the scopes of nested \f(CWwhere\fPs by
looking at their indentation levels. For example in
.XE
    f x = g y z
          where
          y = (x+1)*(x-1)
          z = p x (q y)
    g r = groo (r+1)
.XX
it is the offside rule which makes it clear that the definition of \f(CWg\fP
is not local to the right hand side of the definition of \f(CWf\fP, but those
of \f(CWy\fP and \f(CWz\fP are.
.LP
It is always possible to terminate a right hand side by an EXPLICIT
semicolon, instead of relying on the offside rule. For example the
above script could be written all in one line, as
.XE
    f x = g y z where y = (x+1)*(x-1); z = p x (q y);; g r = groo (r+1);
.XX
Notice that we need TWO semicolons after the definition of \f(CWz\fP \- the first
terminates the rhs of the definition of \f(CWz\fP, and the second terminates
the larger rhs of which it is a part, namely that of the definition of
\f(CWf\fP. If we put only one semicolon at this point, the definition of \f(CWg\fP
would be local to that of \f(CWf\fP.
.LP
This example should convince the reader that code using layout
information to show the block structure is much more readable, and this
is the normal practise.
.LP
[Reference: P.J. Landin "The Next 700 Programming Languages", CACM vol 9
pp157-165 (March 1966).]
.LP
Note that an additional comment convention applies in scripts whose
first character is a \f(CW>\fP. See section 29.\ \fILiterate Scripts\fP.
.SH
13. Iterative expressions
.SH 2
13/1. Dotdot notation
.LP
The following abbreviations are provided for denoting lists, of type
\f(CW[num]\fP, whose members form a finite or infinite arithmetic series.
Let \f(CWa\fP, \f(CWb\fP, \f(CWc\fP stand for arbitrary numeric expressions.
.TS
l lx.
\f(CW[a..b]\fP	T{
list of numbers from a to b inclusive, interval = 1
T}
\f(CW[a..]\fP	T{
infinite list starting at a and increasing by 1
T}
\f(CW[a,b..c]\fP	T{
arithmetic series, first member \f(CWa\fP, second member \f(CWb\fP, last member not greater than \f(CWc\fP (if \f(CWb-a\fP non-negative) or not less than \f(CWc\fP (if \f(CWb-a\fP negative).
T}
\f(CW[a,b..]\fP	T{
infinite series starting at \f(CWa\fP, interval = \f(CW(b-a)\fP
T}
.TE
So the notation \f(CW[1..10]\fP has as value the list \f(CW[1,2,3,4,5,6,7,8,9,10]\fP.
.LP
Here are some more examples
.XE
    nats = [0..]
    evens = [0,2..]
    odds_less_than_100 = [1,3..99]
    neg_odds = [-1,-3..]
    tenths = [1.0,1.1 .. 2.0]
.XX
.SH 2
13/2. List comprehensions
.XE
    [exp | qualifiers]
.XX
List of all \f(CWexp\fP such that \f(CWqualifiers\fP. If there are two or more
qualifiers they are separated by semicolons. Each qualifier is either a
generator, of which the allowed forms are
.XE
    pattern-list <-  exp		(first form)
    pattern <- exp, exp ..		(second form)
.XX
or else a filter, which is a boolean expression restricting the range of
the variables introduced by preceding generators. The variables
introduced on the left of each \f(CW<-\fP are local to the list comprehension.
.LP
Some examples:
.XE
    sqs = [ n*n | n<-[1..] ]
    factors n = [ r | r<-[1..n div 2]; n mod r = 0 ]
    knights_moves [i,j] = [ [i+a,j+b] | a,b<-[-2..2]; a^2+b^2=5 ]
.XX
Notice that a list of variables on the lhs of a \f(CW<-\fP is shorthand for
multiple generators, e.g. \f(CWi,j<-thing\fP expands to \f(CWi<-thing; j<-thing\fP.
.LP
The variables introduced by the generators come into scope from left to
right, so later generators can make use of variables introduced by
earlier ones. An example of this is shown by the following definition
of a function for generating all the permutations of a given list.
.XE
    perms [] = [[]]
    perms  x = [ a:p | a<-x; p<-perms(x--[a]) ]
.XX
The second form of generator allows the construction of lists from
arbitrary recurrence relations, thus
.XE
    x <- a, f x ..
.XX
causes \f(CWx\fP to assume in turn the values \f(CWa\fP, \f(CWf a\fP, \f(CWf(f a)\fP, etc.
.LP
An example of its use is in the following definition of the Fibonacci
series
.XE
    fibs = [ a | (a,b) <- (1,1), (b,a+b) .. ]
.XX
Another example is given by the following expression which lists the
powers of two
.XE
    [ n | n <- 1, 2*n .. ]
.XX
The order of enumeration of a list comprehension with multiple
generators is like that of nested for-loops, with the rightmost
generator as the innermost loop. For example the value of the
comprehension \f(CW[ f x y | x<-[1..4]; y<-[1..4] ]\fP is
.XE
    [ f 1 1, f 1 2, f 1 3, f 1 4, f 2 1, f 2 2, f 2 3, f 2 4,
      f 3 1, f 3 2, f 3 3, f 3 4, f 4 1, f 4 2, f 4 3, f 4 4 ]
.XX
As a consequence of this order of enumeration of multiple generators, if
any generator other than the first (leftmost) is infinite, some
combinations of values will never be reached in the enumeration. To
overcome this a second, diagonalising, form of list comprehension is
provided (see separate manual section).
.LP
Note that list comprehensions do NOT remove duplicates from the result
list. To remove duplicates from a list, apply the standard function
\f(CWmkset\fP.
.SH 2
13/3. Diagonalising list comprehensions
.XE
    [ exp // qualifiers ]
.XX
Syntax and scope rules exactly as for standard list comprehensions, the
only difference being the use of \f(CW//\fP in place of the vertical bar. The
order of enumeration of the generators is such that it is guaranteed
that every possible combination of values will be reached eventually.
The diagonalisation algorithm used is "fair" in the sense that it gives
equal priority to all of the generators.
.LP
For example the value of [f x y//x<-[1..4]; y<-[1..4]] is
.XE
    [ f 1 1, f 1 2, f 2 1, f 1 3, f 2 2, f 3 1, f 1 4, f 2 3,
      f 3 2, f 4 1, f 2 4, f 3 3, f 4 2, f 3 4, f 4 3, f 4 4 ]
.XX
The algorithm used used is "Cantorian diagonalisation" \- imagine the
possible combinations of values from the two generators laid out in a
(perhaps infinite) rectangular array, and traverse each diagonal in turn
starting from the origin. The appropriate higher-dimensional analogue
of this algorithm is used for the case of a list comprehension with
three or more generators.
.LP
As an example of an enumeration that could not be defined at all using a
standard list comprehension, because of the presence of several infinite
generators, here is a definition of the list of all pythagorean
triangles (right-angled triangles with integer sides)
.XE
    pyths = [(a,b,c)//a,b,c<-[1..];a^2+b^2=c^2]
.XX
In the case that there is only one generator, the use of \f(CW//\fP instead of \f(CW|\fP
makes no difference to the meaning of the list comprehension.
.SH
14. Scripts
.LP
In Miranda the script is the persistent entity that is saved from
session to session (i.e. it plays the role of what is called a program
in conventional languages). Associated with a Miranda session at any
given time is a single current script, identified by a UNIX pathname
ending in \f(CW.m\fP.
.LP
A script is a collection of declarations, establishing an environment in
which you wish to evaluate expressions. The order of the declarations
in a script is not significant \- for example, there is no requirement
that an identifier be defined before it is used.
.LP
An identifier may not have more than one top-level binding in a given
script.
.LP
Here are the kinds of declaration that can occur in a script:
.IP 1)
a definition (of a function, data structure etc. \-
see section 15.\ \fIDefinitions\fP for more details). Example
.XE
    fac n = product[1..n]
.XX
.IP 2)
a specification of the type of one or more identifiers, of the form
.XE
    var-list :: <type>
.XX
Example:
.XE
    fac :: num->num
.XX
See \fIBasic type structure\fP for an account of possible types. Note that
these type specifications are normally optional, since the compiler is
able to deduce them from the definitions of the corresponding
identifiers. It is however possible to introduce an identifier by means
of a type specification only, without giving it a defining equation
(such identifiers are said to be `specified but not defined' and are
useful in program development). A special case of this is the
introduction of an otherwise undefined typename \- see section 
22.\ \fIPlaceholder types\fP.
.IP 3)
the definition of a user defined type \- these are of three kinds,
synonyms, algebraic types and abstract types (see sections 20. and 21.)
on each).
.IP 4)
a library directive (\f(CW%export\fP, \f(CW%include\fP or \f(CW%free\fP) these are used
specify the interfaces between separately compiled scripts \- see
section 27.\ \fIThe library mechanism\fP.
.LP
Section 24. gives the formal syntax of Miranda scripts.
.SH 2
Note
.LP
 A directory called \f(CWex\fP (meaning `examples') containing a collection of
example scripts is supplied with the Miranda system, and will be found
under the \f(CWmiralib\fP directory (usually kept at \f(CW/usr/lib/miralib\fP \- the
Miranda session command \f(CW/miralib\fP will tell you where it is on your
system).
.LP
A convention which the Miranda system consistently understands in
Miranda session commands, library directives etc. is that a pathname
enclosed in <angle_brackets>, instead of "string_quotes" is relative to
the miralib directory. In particular note that the Miranda session
command
.XE
    /cd <ex>
.XX
will change your current directory to be \f(CW".../miralib/ex"\fP. You can
then say, e.g.
.XE
    !ls
.XX
to see what's in there. In fact there is a README file, so a good thing
to say next would be
.XE
    !vi README
.XX
.SH
15. Definitions
.LP
The purpose of a definition is to give a value to one or more variables.
There are two kinds of definition, `scalar' and `conformal'. A scalar
definition gives a value to a single variable, and consists of one or
more consecutive equations of the form
.XE
    fnform = rhs
.XX
where a \f(CWfnform\fP consists of the name being defined followed by zero or
more formal parameters. Here are three examples of scalar definitions,
of \f(CWanswer\fP, \f(CWsqdiff\fP and \f(CWequal\fP respectively
.XE
    answer = 42

    sqdiff a b = a^2 - b^2

    equals a a = True
    equals a b = False
.XX
When a scalar definition consists of more than one equation, the order
of the equations can be significant, as the last example shows. (Notice
that \f(CWequals\fP as defined here is a function of two arguments with the
same action as the built in \f(CW=\fP operator of boolean expressions.)
.LP
A conformal definition gives values to several variables simultaneously
and is an equation of the form
.XE
    pattern = rhs
.XX
An example of this kind of definition is
.XE
    (x,y,z) = ploggle
.XX
For this to make sense, the value of \f(CWploggle\fP must of course be a
3-tuple. More information about the `pattern matching' aspect of
definitions is given in the manual section of that name.
.LP
Both \f(CWfnform\fP and pattern equations share a common notion of `right hand
side'.
.SH 2
Right hand sides
.LP
The simplest form of rhs is just an expression (as in all the equations
above). It is also possible to give several alternative expressions,
distinguished by guards. A guard consists of the word \f(CWif\fP followed by
a boolean expression. An example of a right hand side with several
alternatives is given by the following definition of the greatest common
divisor function, using Euclid's algorithm
.XE
    gcd a b = gcd (a-b) b, if a>b
            = gcd a (b-a), if a<b
            = a,           if a=b
.XX
Note that the guards are written on the right, following a comma. The
layout is significant (because the offside rule is used to resolve any
ambiguities in the parse).
.LP
The last guard can be written \f(CWotherwise\fP, to indicate that this is the
case which applies if all the other guards are false. For example the
correct rule for recognising a leap year can be written:
.XE
    leap y = y div 400 = 0,    if y mod 100 = 0
           = y div 4 = 0,      otherwise
.XX
The \f(CWotherwise\fP may here be regarded as standing for
\f(CWif y mod 100 ~= 0\fP.
In the general case it abbreviates the conjunction of the negation of
all the previous guards, and may be used to avoid writing out a long
boolean expression.
.LP
Although it is better style to write guards that are mutually exclusive,
this is not something the compiler can enforce \- in the general case the
alternative selected is the first (in the order they are written) whose
guard evaluates to True.
.LP
[In older versions of Miranda the presence of the keyword \f(CWif\fP after the
guard comma was optional.]
.SH 2
Block structure
.LP
A right hand side can be qualified by a \f(CWwhere\fP clause. This is written
after the last alternative. The bindings introduced by the \f(CWwhere\fP govern
the whole rhs, including the guards. Example
.XE
    foo x = p + q, if p<q
          = p - q, if p>=q
    	    where
    	    p = x^2 + 1
    	    q = 3*x^3 - 5
.XX
Notice that the whole \f(CWwhere\fP clause must be indented, to show that it is
part of the rhs. Following a \f(CWwhere\fP can be any number of definitions,
and the syntax of such local definitions is exactly the same as that for
top level definitions (including therefore, recursively, the possibility
that they may contain nested \f(CWwhere\fPs).
.LP
It is not permitted to have locally defined types, however.
New typenames can be introduced only at top level.
.SH
16. Pattern Matching
.LP
The notion of `pattern' plays an important role in Miranda. There are
three contexts in which patterns can be used \- in function definitions,
in conformal definitions, and on the left of the \f(CW<-\fP in list
comprehensions. We first explain the general rules for pattern
formation, which are the same in all three contexts.
.LP
Patterns are built from variables and constants, using constructors.
Here are some simple examples.
.XE
    x
    3
    (x,y,3)
.XX
The first pattern is just the variable \f(CWx\fP, the second is the constant 3,
the last example is built from two variables and a constant, using the
\f(CW(,,)\fP constructor for 3-tuples. The components of a structured pattern
can themselves be arbitrary patterns, permitting nested structures of
any depth.
.LP
A pattern can also contain repeated variables, e.g. \f(CW(x,1,x)\fP. A
pattern containing repeated variables matches a value only when the
parts of the value corresponding to occurrences of the same variable are
equal.
.LP
The constructors which can be used in a pattern include those of tuple
formation \f(CW(..,..)\fP, list formation \f(CW[..,..]\fP, and the constructors of
any user defined Algebraic Type (see separate manual section). In
addition there are special facilities for matching on lists and natural
numbers, as follows.
.LP
(Lists) The \f(CW:\fP operator can be used in patterns, so for example the
following three patterns are all equivalent (and will match any 2-list).
.XE
    a:b:[]
    a:[b]
    [a,b]
.XX
Note that \f(CW:\fP is right associative (see manual section on Operators).
.LP
(Natural numbers) It is permitted to write patterns of the form \f(CWp+k\fP
where \f(CWp\fP is a pattern and \f(CWk\fP is a literal integer constant. This
construction will succeed in matching a value n, if and only if \f(CWn\fP is an
integer \f(CW>=k\fP, and in this case \f(CWp\fP is bound to \f(CW(n-k)\fP. Example, \f(CWy+1\fP
matches any positive integer, and \f(CWy\fP gets bound to the integer-minus-one.
.LP
Note that the automatic coercion from integer to floating point, which
takes place in expression evaluation, does not occur in pattern
matching. An integer pattern such as \f(CW3\fP or \f(CWn+1\fP will not match any
floating point number. It is not permitted to write patterns containing
floating point constants.
.SH 2
Case analysis
.LP
The main use of pattern matching in Miranda is in the left hand side of
function definitions. In the simplest case a pattern is used simply to
provide the right hand side of the function definition with names for
subcomponents of a data structure. For example, functions for accessing
the elements of a 2-tuple may be defined,
.XE
    fst_of_two (a,b) = a
    snd_of_two (a,b) = b
.XX
More generally a function can be defined by giving a series of
equations, in which the use of different patterns on the left expresses
case analysis on the argument(s). Some simple examples
.XE
    factorial 0 = 1
    factorial(n+1) = (n+1)*factorial n

    reverse [] = []
    reverse (a:x) = reverse x ++ [a]

    last [a] = a
    last (a:x) = last x, if x~=[]
    last [] = error "last of empty list"
.XX
Many more examples can be found in the definition of the standard
environment (see the separate manual section). Note that pattern matching
can be combined with the use of guards (see last example above).
Patterns in a case analysis do not have to be mutually exclusive
(although as a matter of programming style that is good practice) \- the
rule is that cases are tried in order from top to bottom, and the first
equation which `matches' is used.
.SH 2
Conformal definitions
.LP
Apart from the simple case where the pattern is a single variable, the
construction
.XE
    pattern = rhs
.XX
is called a `conformal definition'. If the value of the right hand hand
side matches the structure of the given pattern, the variables on the
left are bound to the corresponding components of the value. Example
.XE
    [a,b,3] = [1,2,3]
.XX
defines \f(CWa\fP and \f(CWb\fP to have the values \f(CW1\fP and \f(CW2\fP respectively. If the match
fails anywhere, all the variables on the left are `undefined'.
For example, within the scope of the definition
.XE
    (x,x) = (1,2)
.XX
the value of \f(CWx\fP is neither \f(CW1\fP nor \f(CW2\fP, but `undefined' (i.e. an error message
will result if you try to access the value of \f(CWx\fP in any way).
.LP
As a constraint to prevent "nonsense" definitions, it is a rule that the
pattern on the left hand side of a conformal definition must contain at
least one variable. So e.g. \f(CW1\ =\ 2\fP is not a syntactically valid
definition.
.SH 2
Patterns on the left of generators
.LP
In a list comprehension (see section 13/2) the bound entity on
the left hand side of an \f(CW<-\fP symbol can be any pattern. We give two
simple examples \- in both examples we assume x is a list of 2-tuples.
.LP
To denote a similar list but with the elements of each tuple swapped
over we can write
.XE
    [(b,a)|(a,b)<-x]
.XX
To extract from x all second elements of a 2-tuple whose first member is
17, we can write
.XE
    [ b |(17,b)<-x]
.XX
.SH 2
Irrefutable patterns (*)
.LP
(Technical note, for people interested in denotational semantics)
.LP
DEFINITION: an algebraic type having only one constructor and for which
that constructor is non-nullary (ie has at least one field) is called
a `product type'. The constructor of a product type is called a `product
constructor'.
.LP
Each type of n-tuple (n~=0) is also defined to be a product type.
In fact, it should be clear that any user defined product type is isomorphic
to a tuple type. Example, if we define
.XE
    wibney ::= WIB num bool
.XX
then the type wibney is isomorphic to the tuple type (num,bool).
.LP
A pattern composed only of product-constructors and identifiers, and
containing no repeated identifiers, is said to be "irrefutable". For
example \f(CWWIB p q\fP, \f(CW(x,y,z)\fP and \f(CW(a,(b,c))\fP are irrefutable patterns.
We show what this means by an example. Suppose we define \f(CWf\fP, by
.XE
    f :: (num,num,bool) -> [char]
    f (x,y,z) = "bingo"
.XX
As a result of the constraints of strong typing, \f(CWf\fP can only be applied
to objects of type \f(CW(num,num,bool)\fP and given any actual parameter of that
type, the above equation for \f(CWf\fP MUST match.
.LP
Interestingly, this works even if the actual parameter is an expression
which does not terminate, or contains an error. (For example try typing
.XE
    f undef
.XX
and you will get "bingo", not an error message.)
.LP
This is because of a decision about the denotational semantics of
algebraic types in Miranda \- namely that product types (as defined
above) correspond to the domain construction DIRECT PRODUCT (as opposed
to lifted product). This means that the bottom element of a type such
as (num,num,bool) behaves indistinguishably from (bottom,bottom,bottom).
.LP
Note that singleton types such as the empty tuple type \f(CW()\fP, or say,
.XE
    it ::= IT
.XX
are not product types under the above definition, and therefore patterns
containing sui-generis constants such as \f(CW()\fP or \f(CWIT\fP are not irrefutable.
This corresponds to a semantic decision that we do NOT wish to identify
objects such as \f(CW()\fP or \f(CWIT\fP with the bottom element of their type.
.LP
For a more detailed discussion of the semantics of Miranda see the
formal language definition (in preparation).
.LP
(*) A useful discussion of the semantics of pattern-matching, including
the issue of irrefutable patterns, can be found in (chapter 4 of) the
following: S. L. Peyton-Jones \fIThe Implementation of Functional Programming
Languages\fP, Prentice Hall International, March 1987, ISBN 0-13-453333-X.
.SH
17. Compiler directives
.LP
Certain keywords, beginning with \f(CW%\fP, modify the action of the compiler
when present in a script. These are called `compiler directives'. The
directives currently available are as follows.
.SH 2
\f(CW%list\fP \f(CW%nolist\fP
.LP
If the \f(CW/list\fP feature is enabled (switched on and off by \f(CW/list\fP,
\f(CW/nolist\fP at command level) the compiler echos the source to the user's
terminal during compilation of a Miranda script. The directives \f(CW%list\fP,
\f(CW%nolist\fP may be placed in a file to give more detailed control over this
behaviour. If the compiler is in an echoing state then encountering
\f(CW%nolist\fP causes it to cease echoing from that point onwards in the
source, until the next occurrence of \f(CW%list\fP or the end of the source
file in which the directive occurs, whichever is the sooner. These
directives may occur anywhere in a script and have no effect on the
semantics (i.e. they are just like comments, apart from having a
side-effect on the lex analyser).
.LP
If the \f(CW/list\fP feature of the compiler is not enabled these directives
are ignored. Since the default state of the compiler is now \f(CW/nolist\fP
these directives are of marginal value and retained only for historical
reasons.
.SH 2
\f(CW%insert\fP
.LP
A directive of the form
.XE
    %insert "pathname"
.XX
may occur anywhere in a Miranda script, and is textually replaced by the
contents of the file \f(CW"pathname"\fP during lexical analysis. The pathname
must be given as a literal string, enclosed in double quotes. (Most
uses of this directive are now better handled by %include, see below).
.LP
If the %insert directive is textually indented in the file in which it
occurs, the whole of the inserted text will be treated as being indented
by the same amount as the initial \f(CW%\fP of the directive.
.LP
Insert directives may be invoked recursively, to a depth limit imposed
by the operating system, typically about 16, which should be enough for
any reasonable purpose. Note that the pathnames are resolved
statically, not dynamically, so that the meaning of an \f(CW%insert\fP directive
is computed relative to the file in which it occurs, NOT relative to the
directory from which the compiler was invoked.
.LP
The use of static rather than dynamic pathname resolution is a departure
from normal UNIX conventions (both the C compiler and the Unix shell
resolve pathnames dynamically) but is much more convenient in practice.
.LP
Note that if the subject of an \f(CW%insert\fP directive is a complete Miranda
script it is always better to use \f(CW%include\fP (see manual section on the
library mechanism), since this avoids needless recompilation of the
definitions of the subsidiary script. The use of \f(CW%include\fP also imposes
a hierarchical scope discipline, and is more likely to lead to well
structured code.
.LP
A point to beware of when using \f(CW%insert\fP is that unlike \f(CW%include\fP, it does
NOT add a missing \f(CW.m\fP extension to its pathname argument automatically.
This is because the argument file may contain an arbitrary piece of text
(e.g. an expression or a signature) and need not be a complete Miranda
script, so it would be inappropriate to insist that it's pathname end in
\f(CW.m\fP
in all cases.
.SH 2
\f(CW%include\fP \f(CW%export\fP \f(CW%free\fP
.LP
These directives control the identifier bindings between separately
compiled scripts. See section 27.\ \fIThe library mechanism\fP
for details.
.SH
18. Basic type structure and notation for types
.LP
The Miranda programming language is `strongly typed' \- that is each
expression and each variable has a type that can be deduced by a static
analysis of the program text.
.SH 2
Primitive types
.SH 3
\f(CWnum\fP
.LP
Values of type \f(CWnum\fP include both integer and floating point numbers,
e.g.
.XE
    23     0   -17   1.26e11
.XX
They are stored using different internal representations, but can be
freely mixed in calculations, and are both of type \f(CWnum\fP for type
checking purposes. There is automatic conversion from integer to
floating point when required (but not in the opposite direction \- use
\f(CWentier\fP, see standard environment). Floating point numbers are held to
double precision, integers to unbounded precision.
.SH 3
\f(CWbool\fP
.LP
The values of type \f(CWbool\fP are the two truth values:
.XE
    True    False
.XX
.SH 3
\f(CWchar\fP
.LP
The values of type \f(CWchar\fP are characters in the Latin-1 character set,
e.g.
.XE
    'a'    '%'    '\et'
.XX
.SH 2
List types
.LP
\f(CW[t]\fP is the type of lists whose elements are of type \f(CWt\fP
.LP
Thus \f(CW[num]\fP is the type of lists of numbers such as \f(CW[1,2,3,4,5]\fP
.LP
\f(CW[[num]]\fP is the type of lists of lists of numbers, such as \f(CW[[1,2],[3,4]]\fP
.LP
\f(CW[char]\fP are lists of characters \- this is also the type of string
constants, so e.g. \f(CW['h','e','l','l','o']\fP and \f(CW"hello"\fP are interchangeable
objects of this type.
.SH 2
Tuple types
.LP
\f(CW(t1,...,tn)\fP is the type of a tuple with elements of type \f(CWt1\fP to \f(CWtn\fP
.LP
Example \- the value \f(CW(1,True,"red")\fP is of type \f(CW(num,bool,[char])\fP
.LP
The type of the empty tuple, \f(CW()\fP, is also written \f(CW()\fP.
.LP
Notice that tuples are distinguished from lists by being enclosed in
parentheses, instead of square brackets.
.LP
There is no concept of a 1-tuple in Miranda, so the use of parentheses
to enclose subexpressions, as in say \f(CWa*(b+c)\fP, does not conflict with
their use for tuple formation.
.SH 2
Function types
.LP
\f(CWt1->t2\fP is the type of a function with argument type \f(CWt1\fP and result
type \f(CWt2\fP.
.LP
The \f(CW->\fP is right associative, so e.g. \f(CWnum->num->num\fP is the type of a
curried function of two numeric arguments.
.LP
In addition to the built-in types described above, user defined types
may be introduced \- these are of three kinds, synonym types, algebraic
types and abstract types \- see sections 19, 20 and 21 for each.
.SH 2
Implicit typing
.LP
In Miranda the types of identifiers do NOT normally need to be declared
explicitly \- the compiler is able to infer the type of identifiers from
their defining equations. For example if you write
.XE
    plural x = x ++ "s"
.XX
the compiler will DEDUCE that \f(CWplural\fP is of type \f(CW[char]->[char]\fP. It is
however permitted to include explicit type declarations in the script if
desired, e.g. you could write (anywhere in the same script)
.XE
    plural :: [char]->[char]
.XX
and the compiler will check this for consistency with the defining
equation (the symbol \f(CW::\fP means `is of type'). More generally the type
declared may be an `instance' (see below) of the type implied by the
definition \- in this case the effect of the declaration is to restrict
the type of the identifier to be less general than it would otherwise
have been.
.LP
Note that only top-level identifiers may be the subject of type
declarations, and that the type of an identifier may be declared at most
once in a given script.
.SH 2
Polymorphism
.LP
The final feature of the type system is that it permits polymorphic
types. There is an alphabet of generic type variables, written
.XE
    *    **    ***    etc.
.XX
each of which stands for an arbitrary type. We give a simple example -
the identity function, which may be defined
.XE
    id x = x
.XX
is attributed the type \f(CW*->*\fP. This means that \f(CWid\fP has many types
\- \f(CWnum->num\fP, \f(CWchar->char\fP, \f(CW[[bool]]->[[bool]]\fP and so on
\- each of these is an instance of its most general type, \f(CW*->*\fP.
.LP
Another simple example of polymorphism is the function \f(CWmap\fP (see
standard environment) which applies a function to every element of a
list. For example \f(CWmap integer [1,1.5,2]\fP is \f(CW[True,False,True]\fP. The
type of \f(CWmap\fP is
.XE
    map :: (*->**) -> [*] -> [**]
.XX
The most polymorphic possible object is \f(CWundef\fP, the identifier which
stands for the undefined, or error value (\f(CWundef\fP is defined in the
standard environment). Since every type has an undefined value, the
correct type specification for undef is
.XE
    undef :: *
.XX
Many of the functions in the standard environment have polymorphic types -
the text of the standard environment (see section 28) is
therefore a useful source of examples.
.SH
19. Type synonym declarations
.LP
These permit the user to introduce a new name for an already existing
type, e.g.
.XE
    string == [char]
.XX
type synonyms are entirely transparent to the typechecker (it best to
think of them as being just macros). For obvious reasons, recursive type
synonyms are not permitted.
.LP
It is also possible to introduce a synonym for a type forming operator,
by introducing generic type variable as parameters of the definition,
e.g.
.XE
    invt * ** == (*->**)->(**->*)
.XX
So within a script containing the above two \f(CW==\fP definitions, the type
\f(CWinvt num string\fP will be shorthand for
.XE
    (num->[char])->([char]->num)
.XX
.SH
20. Algebraic type definitions
.LP
The simplest method of introducing a new data type into a Miranda script
is by means of an algebraic type definition. This enables the user to
introduce a new concrete data type with specified constructors.
A simple example would be
.XE
    tree ::= Nilt | Node num tree tree
.XX
The \f(CW::=\fP sign is used to introduce an algebraic data type. This
definition introduces three new identifiers
.IP
\f(CWtree\fP a typename
.IP
\f(CWNilt\fP a nullary constructor (i.e. an atom), of type \f(CWtree\fP
.IP
\f(CWNode\fP a constructor, of type \f(CWnum->tree->tree->tree\fP
.LP
Now we can define trees using constructors \f(CWNilt\fP & \f(CWNode\fP, for example
.XE
    t = Node 3 Nilt Nilt
.XX
It is not necessary to have names for selector functions because the
constructors can be used in pattern matching. For example a function
for counting the number of nodes in a tree could be written
.XE
    size Nilt = 0
    size (Node a x y) = 1 + size x + size y
.XX
Note that the names of constructors must begin with an upper case letter
(and conversely, any identifier beginning with an upper case letter is
assumed to be a constructor).
.LP
An algebraic type can have any number (>=1) of constructors and each
constructor can have any number (>=0) fields, of specified types. The
number of fields taken by a constructor is called its `arity'. A
constructor of arity zero is said to be atomic. Algebraic types are a
very general idea and include a number of special cases that in other
languages require separate constructions.
.LP
One interesting case that all of the constructors can be atomic, giving
us what is called in PASCAL a `scalar enumeration type'. Example
.XE
    day ::= Mon|Tue|Wed|Thu|Fri|Sat|Sun
.XX
The union of two types can also be represented as an algebraic data type -
for example here is a union of \f(CWnum\fP and \f(CWbool\fP:
.XE
    boolnum ::= Left bool | Right num
.XX
Notice that this is a `labelled union type' (the other kind of union
type, in which the parts of the union are not distinguished by tagging
information, is not permitted in Miranda).
.LP
An algebraic typename can take parameters, thus introducing a family of
types. This is done be using generic type variables as formal
parameters of the \f(CW::=\fP definition. To modify our definition of \f(CWtree\fP
to allow trees with different types of labels at the nodes (instead of
all \f(CWnum\fP as above) we would write
.XE
    tree * ::= Nilt | Node * (tree *) (tree *)
.XX
Now we have many different tree types \- \f(CWtree num\fP, \f(CWtree bool\fP,
\f(CWtree([char]->[char])\fP, and so on. The constructors \f(CWNode\fP and \f(CWNilt\fP
are both polymorphic, with types \f(CWtree *\fP and \f(CW*->tree *->tree *->tree *\fP
respectively.
.LP
Notice that in Miranda objects of a recursive user defined type are not
restricted to being finite. For example we can define the following
infinite tree of type \f(CWtree num\fP:
.XE
    bigtree = Node 1 bigtree bigtree
.XX
.SH 2
Controlling the strictness of constructors
.LP
Definition: a function \f(CWf\fP is strict iff
.XE
    f BOTTOM = BOTTOM
.XX
where \f(CWBOTTOM\fP is the value attributed to expressions which fail to terminate
or terminate with an error. To support non-strict functions the calling
mechanism must not evaluate the arguments before passing them to the
function \- this is what is meant by "lazy evaluation".
.LP
In Miranda constructors are, by default, non-strict in all their fields.
.LP
Example:
.XE
    pair ::= PAIR num num
    fst (PAIR a b) = a
    snd (PAIR a b) = b
.XX
First note that there is a predefined identifier \f(CWundef\fP which denotes
undefined \- evaluating \f(CWundef\fP in a Miranda session gives an error
message. Consider the following Miranda expressions:
.XE
    fst (PAIR 1 undef)
    snd (PAIR undef 1)
.XX
Both evaluate to \f(CW1\fP, that is \f(CWPAIR\fP is non-strict in both arguments.
.LP
The primary reason for making constructors non-strict in Miranda is that
it is necessary to support equational reasoning on Miranda scripts. (In
the example given, elementary equational reasoning from the definition
of \f(CWfst\fP implies that \f(CWfst(PAIR 1 anything)\fP should always have the
value \f(CW1\fP.) It is also as a consequence of constructors being non-strict
that Miranda scripts are able to define infinite data structures.
.LP
It is, however, possible to specify that a given constructor of an
algebraic data type is strict in one or more fields by putting \f(CW!\fP after
the field in the \f(CW::=\fP definition of the type. For example we can
change the above script to make \f(CWPAIR\fP strict in both fields, thus
.XE
    pair ::= PAIR num! num!
    fst (PAIR a b) = a
    snd (PAIR a b) = b
.XX
Now \f(CWfst (PAIR 1 undef)\fP and \f(CWsnd (PAIR undef 1)\fP both evaluate to
undefined. It is a consequence of the \f(CW!\fP annotations that \f(CWPAIR a b\fP
is undefined when either \f(CWa\fP or \f(CWb\fP is undefined. It is also possible to
make \f(CWPAIR\fP strict in just one of its fields by having only one \f(CW!\fP in the
type definition.
.LP
In the case of a recursively defined algebraic type, if all the
constructors having recursive fields are made strict in those fields it
ceases to be possible to construct infinite objects of that type. It is
also possible to deny the possibility of certain infinite structures
while permitting others. For example if we modify the definition of the
tree type first given above as follows
.XE
    tree ::= Nilt | Node num tree! tree
.XX
then it is still possible to construct trees which are infinite in their
right branch but not "left-infinite" ones.
.LP
The main reason for allowing \f(CW!\fP annotations on Miranda data type
definitions is that one of the intended uses of Miranda is as a SEMANTIC
METALANGUAGE, in which to express the denotational semantics of other
programming languages.
.SH
21. Abstract type definitions
.LP
These enable a new data type to be defined by data type abstraction from
an existing type. We give the classic example, that of defining \f(CWstack\fP
as an abstract data type (here based on lists)
.XE
    abstype stack *
    with empty::stack *
         push::*->stack *->stack *
         isempty::stack *->bool
         top::stack *->*
         pop::stack *->stack *

    stack * == [*]
    empty = []
    push a x = a:x
    isempty x = x=[]
    top (a:x) = a
    pop (a:x) = x
.XX
The information given after \f(CWwith\fP is called the `signature' of the
abstract type \- the definitions of the identifiers in the signature are
called the `implementation equations' (these are the six equations given
above). Outside of the implementation equations the information that
stacks are implemented as lists is not available \- \f(CW[]\fP and \f(CWempty\fP for
example are incomparable objects of two different and unrelated types
(\f(CW[*]\fP and \f(CWstack *\fP respectively). Only inside the implementation equations
are the abstract objects treated as being equivalent to their
representations.
.LP
The implementation equations do not have to appear immediately after the
corresponding \f(CWabstype\fP declaration \- they can occur anywhere in the
script. For readability, however, it is strongly recommended that the
implementation equations appear immediately after the \f(CWabstype\fP
declaration.
.LP
Note that in Miranda there is no runtime cost associated with
administering an abstract data type. The responsibility for enforcing
the distinction between stacks and lists, for example, is discharged
entirely at compile time (by the type checker). The runtime
representation of a stack does not require any extra bits to distinguish
it from a list. As a result the Miranda programmer can freely use
abstract data types to structure his programs without incurring any loss
of efficiency by doing so.
.LP
Notice that the mechanism used to introduce abstract data types in
Miranda does not depend on the hiding of identifiers, and in this
respect differs from the traditional approach. A fuller discussion of
the Miranda \f(CWabstype\fP mechanism can be found in [*Turner 85].
.LP
(*) D. A. Turner \fIMiranda: A Non-Strict Functional Language with
Polymorphic Types\fP, Proceedings IFIP Conference on Functional
Programming Languages and Computer Architecture, Nancy, France,
September 1985 (Springer Lecture Notes in Computer Science, vol. 201, pp
1-16).
.SH 2
The print representation of abstract objects
.LP
(\(lqadvanced feature\(rq \- omit on first reading)
.LP
Values belonging to an abstract type are not in general printable. If
the value of a command-level expression is of such a type it will
normally print simply as
.XE
    <abstract ob>
.XX
This is because the special function \f(CWshow\fP (which is actually a family of
functions, see elsewhere) has no general method for converting such
objects to a printable form. It is possible to extend the definition of
\f(CWshow\fP to include the ability to print members of an abstract type, using
some appropriate format. The convention for doing this is to include in
the definition of the abstract type a function with the name \f(CWshowfoo\fP
(where \f(CWfoo\fP is the name of the abstract type involved).
.LP
We illustrate how this is done taking \f(CWstack\fP as the example. Suppose
we decide we wish stacks to print \- using a syntax such that the output
could be read back in (e.g. by \f(CWreadvals\fP \- see elsewhere) to generate the
same stack.
.IP
\f(CWempty\fP is to print as "empty"
.IP
\f(CWpush 1 empty\fP is to print as "(push 1 empty)"
.IP
and so on.
.LP
Note that we decide to fully parenthesise the output for safety \- since
we do not know the larger context in which our stack output may be
embedded.
.LP
Because \f(CWstack\fP is a polymorphic abstraction, showstack will need to
take as a parameter the appropriate show function for the element type
(which is \f(CWnum\fP in the above examples, but could have been any type).
We add to the signature of stack the following function.
.XE
    showstack::(*->[char])->stack *->[char]
.XX
To obtain the output format illustrated above, an appropriate definition
of \f(CWshowstack\fP would be,
.XE
    showstack f [] = "empty"
    showstack f (a:x) = "(push " ++ f a ++ " " ++ showstack f x ++ ")"
.XX
If this definition is included in the script, stacks become printable,
using the specified format. The effect is to extend the behaviour of
the special built-in function \f(CWshow\fP to handle stacks, and all data
structures built using stacks (such as list of tree of stacks, stack of
stacks and so on).
.LP
The general rule is as follows. Let \f(CWfoo\fP be an abstract type name.
To make \f(CWfoo\fP's printable, we need to define a \f(CWshowfoo\fP thus:
.LP
if \f(CWfoo\fP is a simple type (not polymorphic)
.XE
    showfoo :: foo -> [char]
.XX
if \f(CWfoo\fP is polymorphic in one type variable (\f(CWfoo *\fP)
.XE
    showfoo :: (*->[char]) -> foo * -> [char]
.XX
if \f(CWfoo\fP is polymorphic in two type variables (\f(CWfoo * **\fP)
.XE
    showfoo :: (*->[char]) -> (**->[char]) -> foo * ** -> [char]
.XX
and so on. Note that the \f(CWshow\fP function must be declared in the
signature of the abstract type, and that the name of the function is
significant \- if we change its name from \f(CWshowfoo\fP to \f(CWgobbledegook\fP,
its definition will cease to have any effect on the behaviour of \f(CWshow\fP.
It also needs to have the right type, and if it does not, again its
presence will have no effect on the behaviour of \f(CWshow\fP (in this case the
compiler prints a warning message).
.LP
[Note on library directives: If you \f(CW%export\fP an abstract type, \f(CWfoo\fP say,
to another file, it is not necessary to \f(CW%export\fP the \f(CWshowfoo\fP function
explicitly to preserve the correct printing behaviour \- if an abstract
type comes into existence with a \f(CWshow\fP function in its signature the
compiler will `remember' how to print objects of the type even in scopes
where the show function has no name.]
.SH
22. Empty types (also called Placeholder types)
.LP
An empty type has no values belonging to it (apart from the undefined
value, \f(CWundef\fP, which is a member of every type). Empty types are
declared as follows:
.XE
    widget :: type
.XX
this declares \f(CWwidget\fP to be a type but gives it no values.
.LP
Empty types can be used during program development as placeholders for
types whose representation is not yet decided. For example, given the
above declaration we can give type specifications involving \f(CWwidget\fP, e.g.
.XE
    foo :: num->widget->widget
    gronk :: [widget]->widget
.XX
and write code using \f(CWfoo\fP and \f(CWgronk\fP which can be checked for type
correctness. At a later stage the specification of widget as an empty
type can be replaced by a non-empty type definition, using \f(CW==\fP, \f(CW::=\fP or
\f(CWabstype\fP, allowing \f(CWfoo\fP, \f(CWgronk\fP, to be defined.
.LP
Typenames declared as empty can have any arity, e.g.
.XE
    table * ** :: type
.XX
This creates a family of empty typess such as \f(CWtable num bool\fP and so on.
They are all devoid of values (apart from \f(CWundef\fP). The general form
of this kind of specification is
.XE
    tform-list :: type
.XX
where \f(CWtform\fP consists of a typename followed by zero or more generic
type variables (and it is permitted to declare several such types
simultaneously, separated by commas, whence \f(CWtform-list\fP).
.LP
An empty type may be considered equivalent to an algebraic type with no
constructors.
.SH
23. The use of \f(CWshow\fP for converting objects to their print representations
.LP
The need often arises to convert an arbitrary Miranda value to its
printable representation as a string. For numbers, the function
\f(CWshownum\fP (of type \f(CWnum->[char]\fP) can be used for this purpose.
To be able to do this conversion for any type of object would seemingly
require an infinite number of functions, one for each type. As a
solution to this problem Miranda provides a special keyword, \f(CWshow\fP.
.LP
For any object \f(CWx\fP
.XE
    show x
.XX
is a string containing the printable representation of \f(CWx\fP. For example,
if \f(CWx\fP is a number the above expression is equivalent to \f(CWshownum x\fP.
In the general case, however, \f(CWx\fP could be a structured object of arbitrary
complexity. Note that \f(CWshow\fP is a reserved word, not an identifier.
.LP
In fact \f(CWshow\fP behaves under most circumstances as though it was the
name of a function, of type \f(CW*->[char]\fP. For example it can be passed as
a parameter, so that say,
.XE
    map show [a,b,c,d,e]
.XX
is a legal expression of type \f(CW[[char]]\fP.
.LP
There are three important restrictions on the universality of \f(CWshow\fP.
.LP
(i) You cannot \f(CWshow\fP functions in any useful sense. (That would be a
violation of referential transparency.) The result of applying \f(CWshow\fP to
any kind of function is just the string \f(CW"<function>"\fP.
.LP
(ii) You cannot \f(CWshow\fP an abstract object unless an appropriate
show-function was included when the type was defined (see manual section
on Abstract types). The result of applying \f(CWshow\fP to such an object is by
default just the string "<abstract ob>".
.LP
(iii) When it occurs in a script the context in which \f(CWshow\fP is used must
be such as to determine its type monomorphically. An example:
.XE
    my_show x = "hello\en"++show x++"goodbye\en"
.XX
In the absence of any other type information, the compiler will infer
that \f(CWmy_show\fP has type \f(CW*->[char]\fP, and that \f(CWx\fP is of type \f(CW*\fP.
The use of \f(CWshow\fP is therefore polymorphic, and will be rejected as illegal.
.LP
If however we intend that \f(CWmy_show\fP will be used only on objects of type
\f(CWtree\fP, say, and we add to the script the declaration
\f(CWmy_show::tree->[char]\fP, then the above use of \f(CWshow\fP becomes monomorphic,
and will be accepted.
.LP
The essence of restriction (iii) is that \f(CWshow\fP is not a true polymorphic
function of type \f(CW*->[char]\fP, but rather a family of monomorphic functions
with the types \f(CWT->[char]\fP for each possible monotype \f(CWT\fP. The context must
be sufficient for the compiler to determine which member of the family
is required.
.LP
(For technical reasons this restriction applies only in scripts. In
command-level expressions \f(CWshow\fP behaves as if it were a genuine
polymorphic function.)
.SH
24. Syntax of Miranda scripts and expressions
.LP
.XE
script:= decl*                          rhs:= simple_rhs(;)
                                              cases
decl:= def
       tdef                             simple_rhs:= exp whdefs?
       spec
       libdir                           cases:= alt(;) = cases
                                                lastcase(;)
def:= fnform = rhs
      pat = rhs                         alt:= exp , if exp

tdef:= tform == type(;)                 lastcase:= lastalt whdefs?
       tform ::= constructs(;)
       abstype tform-list with sig(;)   lastalt:= exp , if exp
                                                  exp , otherwise
spec:= var-list :: type(;)
       tform-list :: type(;)            whdefs:= where def def*

sig:= spec spec*                        exp:= e1
                                              prefix1
constructs:= construct | constructs           infix
             construct
                                        e1:= simple simple*
construct:= constructor argtype*             prefix e1
            type $constructor type           e1 infix e1
            ( construct ) argtype*
                                        simple:= var
type:= argtype                                   constructor
       typename argtype*                         literal
       type -> type                              readvals
       type $typename type                       show
                                                 ( infix1 e1 )
argtype:= typename                               ( e1 infix )
          typevar                                ( exp-list? )
          ( type-list? )                         [ exp-list? ]
          [ type-list ]                          [ exp .. exp? ]
                                                 [ exp , exp .. exp? ]
tform:= typename typevar*                        [ exp | qualifs ]
        typevar $typename typevar                [ exp // qualifs ]

fnform:= var formal*                    qualifs:= qualifier ; qualifs
         pat $var pat                             qualifier
         ( fnform ) formal*
                                        qualifier:= exp
pat:= formal                                        generator
      -numeral
      constructor formal*               generator:= pat-list <- exp
      pat : pat                                     pat <- exp , exp ..
      pat + nat
      pat $constructor pat              var:= identifier
      ( pat ) formal*
                                        constructor:= IDENTIFIER
formal:= var
         constructor                    typename:= identifier
         literal1
         ( pat-list? )
         [ pat-list? ]
.XX
.SH
25. Comments on the syntax for Miranda scripts
.LP
The syntax equations given express the syntax of Miranda scripts insofar
as this can be done by a context free grammar. It therefore does not
attempt to express the scope rules, nor the requirement that a script be
well-typed, both of which are context sensitive restrictions on the
syntax given here. The formal definition of Miranda [in preparation]
will deal with these matters and also give a denotational semantics for
the language.
.LP
Nevertheless, if the syntax is read in conjunction with the informal
description of the language (see other manual sections and referenced
papers) it should be found fairly informative, especially if the reader
has some previous exposure to this style of language.
.LP
Key to abbreviations in syntax:
.TS
center;
l l l.
alt=alternative	decl=declaration	def=definition	
e1=operator_expression	exp=expression	fnform=function_form	
libdir=library_directive	pat=pattern	qualifs=qualifiers	
rhs=right_hand_side	sig=signature	spec=specification	
tdef=type_definition	tform=typeform	var=variable	
whdefs=where_defs
.TE
.SH 2
Conventions
.LP
We use a variant of BNF, in which non-terminals are represented by
lower case words, \f(CW:=\fP is used as the production symbol, and alternative
productions are written on successive lines. (These departures from
convention are adopted because \f(CW::=\fP and \f(CW|\fP are concrete symbols of the
language.)
.LP
For any non-terminal \f(CWx\fP,
.TS
l lx.
\f(CWx*\fP	means zero or more occurrences of \f(CWx\fP
\f(CWx?\fP	means the presence of \f(CWx\fP is optional
\f(CWx-list\fP	T{
means one or more \f(CWx\fP's (separated by commas if >1)
\f(CWx(;)\fP	means that \f(CWx\fP is followed by an optional semicolon and is subject to the `offside rule' (see section on Layout), so that every token of \f(CWx\fP must lie below or to the right of the first. Provided the layout makes it clear where \f(CWx\fP terminates, the trailing semicolon may be omitted.
T}
.TE
.SH 2
Notes
.LP
The syntax of the library directives (denoted by the non-terminal \f(CWlibdir\fP)
is given in manual section 27/1.)
.LP
Ambiguities in the syntax for \f(CWtype\fP and \f(CWconstruct\fP are resolved by
noting that \f(CW->\fP is less binding than \f(CW$typename\fP or \f(CW$constructor\fP and
that all three are right associative.
.LP
In connection with the productions for argtype, note that type such as
\f(CW[num,bool]\fP is an abbreviation for \f(CW[(num,bool)]\fP and represents the
type of a list of tuples \- the Miranda system itself never uses this
abbreviation when printing a type, but accepts it in user scripts. (Use
of this abbreviation is not recommended \- it will probably be removed
from the syntax at the next release.)
.LP
Ambiguities in the syntax for \f(CWfnform\fP and \f(CWpat\fP are resolved by taking
into account the relative binding powers of the infix operators
involved. Specifically that \f(CW:\fP is right associative and less binding
than \f(CW+\fP, which is left associative, and that \f(CW$constructor\fP, \f(CW$var\fP have a
higher binding power than either of these and are right associative.
.LP
The productions given for \f(CWcases\fP correctly describe the concrete syntax
of these entities, including the way the offside rule is applied to
them. This concrete syntax is in one sense misleading, however. Namely
in that if a \f(CWlastcase\fP with a trailing \f(CWwheredefs\fP is preceded by a
series of alternatives, the scope of the names introduced by the \f(CWwhere\fP
is the whole \f(CWcases\fP in which it occurs, and not just the \f(CWlastcase\fP.
.LP
Note that for compatibility with earlier versions of Miranda the use of
the keyword \f(CWif\fP is optional.
.LP
The ambiguities in the syntax given for \f(CWe1\fP are resolved by taking into
account the relative binding powers of the operators (see manual section
on Operators).
.LP
The syntax of \f(CWidentifier\fP, \f(CWIDENTIFIER\fP, \f(CWliteral\fP, \f(CWliteral1\fP,
\f(CWnumeral\fP, \f(CWnat\fP, \f(CWinfix\fP, \f(CWinfix1\fP, \f(CWprefix\fP, \f(CWprefix1\fP and \f(CWtypevar\fP
are given under Lexical Syntax (see next manual section).
.SH
26. Miranda lexical syntax
.LP
In this section square brackets are used to enclose a set of literal
characters, using lex-style conventions, so e.g. \f(CW[a-z]\fP means a lower case
letter. As usual, \f(CW*\fP and \f(CW?\fP are used to mean zero-or-more, and
zero-or-one, occurrences of the preceding entity. Parentheses are used
for grouping, and subtraction of one syntactic entity from another means
set difference. We also revert to using \f(CW|\fP for alternatives, as in
standard BNF.
.XE
script:= (token | layout)*

layout:= nl | tab | formfeed | space | comment

comment:= vertical_bar vertical_bar (any - nl)* nl

token:= identifier | IDENTIFIER | literal | typevar | delimiter

identifier:= ([a-z] [a-zA-Z0-9_']* ) - delimiter

IDENTIFIER:= [A-Z] [a-zA-Z0-9_']*

literal:= numeral | charconst | stringconst

literal1:= literal - float

numeral:= nat | float

nat:= [0-9] [0-9]* | 0x [0-9a-f] [0-9a-f]* | 0o [0-7] [0-7]*

float:= [0-9]* [.] nat epart? | nat epart

epart:= [e] [+|-]? nat

charconst:= ['] (visible-[\e]|escape) [']

stringconst:= ["] (visible-[\e"]|escape)* ["]

escape:= [\e] ([ntfrb\e'"]|nl|decimal_code)

typevar:= [*][*]*

delimiter:= - | prefix1 | infix1 | other

infix1:= ++ | -- | : | \e/ | & | > | >= | = | ~= | <= | < | + | * |
         / | div | mod | ^ | . | ! | $identifier | $IDENTIFIER

infix:= infix1 | -

prefix1:= ~ | #

prefix:= prefix1 | -

other:= abstype | if | otherwise | readvals | show | type | where |
	with | %export | %free | %include | %insert | %list | %nolist |
	= | == | ::= | :: | => | vertical_bar | // | -> | ; | , | ( |
	) | [ | ] | { | } | <- | .. | $$ | $- | $:- | $+ | $*

vertical_bar:= |
.XX
.SH 2
Notes
.LP
\f(CWvisible\fP means any non-control character, including space (but not
including e.g. newline), \f(CWnl\fP means literal newline, and \f(CWdecimal_code\fP is a
nat in the range 0..255 (maximum length 3 digits).
.LP
Notice that the syntax of \f(CWnumeral\fP does not include negative numbers.
Negative constants, such as \f(CW-3\fP or \f(CW-5.05e-17\fP are parsed by Miranda as
applications of the prefix operator \f(CW-\fP to a positive numeral. This has
no semantic significance.
.LP
Omission \- the definition of \f(CWlayout\fP does not include the additional
comment rules for Literate Scripts (see separate manual section).
.SH
27. The Miranda Library Mechanism
.LP
.SH 2
27/1. Syntax of library directives
.XE
libdir:= %include env(;)            parts:= part part*
         %export parts(;)
         %free { sig }              part:= identifier
                                           fileid
env:= fileid binder? aliases?              +
                                           -identifier
binder:= { binding binding* }
                                    fileid:= "pathname"
binding:= var = exp(;)                       <pathname>
          tform == type(;)

aliases:= alias alias*

alias:= identifier/identifier
        IDENTIFIER/IDENTIFIER
        -identifier
.XX
.SH 3
Notes
.LP
For the definition of \f(CWsig\fP (=signature),
\f(CWvar\fP, \f(CWexp\fP, \f(CWtform\fP and \f(CWtype\fP see the main manual page
on formal syntax of Miranda.
.LP
For the definition of \f(CWidentifier\fP and \f(CWIDENTIFIER\fP see Lexical Syntax.
.SH 2
27/2. The \f(CW%include\fP directive (basic information)
.LP
Suppose the file \f(CW"mylib.m"\fP contains some Miranda declarations (which
could be any kind of legal Miranda declaration, e.g. function definitions,
type definitions etc). To make these in scope in another script, the
latter will contain the directive
.XE
    %include "mylib"
.XX
This can come anywhere in the script (there is for example no
requirement that \f(CW%include\fP directives come at the front) but must be at
top level \- you may not place a \f(CW%include\fP directive inside a \f(CWwhere\fP
clause. The subject of a \f(CW%include\fP directive may itself contain \f(CW%include\fP
directives, and so on (to any reasonable depth).
.LP
By default, the names `exported' from an included script are all those
defined in it at top level, but not those of subsidiary \f(CW%include\fP's.
This can be modified by placing a \f(CW%export\fP directive in the included
script. For a discussion of this and other ways of modifying the effect
of \f(CW%include\fP see the manual section giving a detailed account of the
library directives.
.LP
If the filename in a \f(CW%include\fP directive is enclosed in angle brackets
instead of string quotes, this is understood to be a pathname relative
to the miralib directory. So for example putting in your script
.XE
    %include <ex/matrix>
.XX
brings into scope the definitions exported from the \f(CWmatrix\fP package in
the Miranda examples directory \f(CWex\fP. (*See note below.)
.LP
Finally, note that that the relationship between includor and includee
is unsymmetrical. If file A \f(CW%include\fP's file B, then the declarations of
B are visible to A, but not vice versa.
.LP
There is a simpler (purely textual) directive
.XE
    %insert "file"
.XX
which causes the contents of "file" to be substituted for the \f(CW%insert\fP
directive during lexical analysis. This can occur anywhere in a Miranda
script. See the manual section on compiler directives.
.LP
(*) Note to system administrators: an empty directory \f(CWlocal\fP is
provided under the miralib directory, in which you can place additional
libraries which you wish to make available to all Miranda users at your
site.
.SH 2
27/3. Explanation of library directives
.LP
The three directives \f(CW%include\fP \f(CW%export\fP \f(CW%free\fP constitute the Miranda
library mechanism, which controls the sharing of identifiers between
separately compiled scripts. The \f(CW%free\fP directive is covered in
section 27/4 and will not be discussed further here.
.SH 3
\f(CW%include "file"\fP
.LP
The presence of this directive, anywhere in a Miranda script, causes all
the identifiers exported from the Miranda script \f(CW"file"\fP to be in scope
in the containing script. Note that \f(CW"file"\fP should be the name of a
Miranda source file (by convention these all have names ending in \f(CW.m\fP).
.LP
The following conventions apply to all filenames in library directives:
.IP 1.
A \f(CWfileid\fP can be an arbitrary UNIX pathname
.IP 2.
If the \f(CWfileid\fP given does not end in \f(CW.m\fP this is added.
.IP 3.
If the \f(CWfileid\fP is surrounded by angle brackets instead of string
quotes it is assumed to be a pathname relative to the \f(CWmiralib\fP
directory, otherwise it is taken to be relative to the directory of the
script in which the directive occurs. (Examples, \f(CW"pig"\fP means \f(CW"pig.m"\fP,
\f(CW<stdenv>\fP means \f(CW"/usr/lib/miralib/stdenv.m"\fP)
.LP
In addition (if you are using Berkeley UNIX or a derivative) the \f(CW~\fP
convention of the C shell may be used to abbreviate home directories.
That is \f(CW~\fP abbreviates your own home directory, and \f(CW~jack\fP abbreviates
jack's home directory, at the front of any pathname.
.LP
The file mentioned in a \f(CW%include\fP directive must contain a CORRECT,
CLOSED Miranda script. (That is it must have no syntax or type errors,
and no undefined names.) An attempt to \f(CW%include\fP a file which violates
these conditions will be rejected by the compiler as a syntax error in
the script containing the \f(CW%include\fP statement.
.LP
It is also illegal to \f(CW%include\fP a script which causes nameclashes, either
against top-level identifiers of the including script or those of other
\f(CW%include\fP directives in the script.
.LP
The effect of an \f(CW%include\fP directive can be modified by following it with
one or more aliases (which are used to remove nameclashes between
identifiers exported from the included script and those of the current
script or of other \f(CW%include\fP files). There are two forms of
alias, \f(CWnew/old\fP which renames and \f(CW-old\fP
which suppresses an identifier altogether.
.LP
For example suppose we wish to include the file \f(CW"mike"\fP but it contains
two identifiers, \f(CWf\fP and \f(CWg\fP say, which clash with top-level bindings of
these identifiers in the current script. We wish to use the \f(CW"mike"\fP
definition of \f(CWf\fP, but his \f(CWg\fP is of no interest. The following
directive could be used.
.XE
    %include "mike" -g mike_f/f
.XX
Any other identifiers exported from \f(CW"mike"\fP, not specifically mentioned
in the aliases, will be accepted unchanged.
.LP
It is permitted to alias typenames, and constructors (say \f(CWNEW/OLD\fP) but
typenames and constructors cannot be suppressed by a \f(CW-name\fP alias.
Note that if you alias one or more of the constructors of an algebraic
data type the behaviour of \f(CWshow\fP on objects of that type will be
modified in the appropriate way.
.LP
A file which has been \f(CW%include\fPd may itself contain \f(CW%include\fP directives,
and so on, to any reasonable depth. A (directly or indirectly) cyclic
\f(CW%include\fP is not permitted, however.
.LP
The \f(CW?identifier\fP command can be used to find the ultimate place of
definition of an imported identifier. When aliasing has taken place the
\f(CW?identifier\fP command will give both the current and the original name
of an aliased identifier. If your installed editor is \f(CWvi\fP the
\f(CW??identifier\fP command will open the appropriate source file at the
definition of the identifier. (There is also a command \f(CW/find identifier\fP
which is like \f(CW?identifier\fP
but will recognise an alias under its original name.)
.LP
Every script behaves as though it contained the directive
.XE
    %include <stdenv>
.XX
It is therefore illegal to \f(CW%include\fP the standard environment explicitly,
as this will lead to huge number of name clashes (because it is now
present twice). The \f(CW-stdenv\fP command-line directive suppresses the
implicit inclusion of \f(CW<stdenv>\fP.
.SH 3
\f(CW%export\fP parts
.LP
Any (correct, closed) Miranda script can be \f(CW%include\fPd in another script
(there is no notion of a "module" as something with a different syntax
from an ordinary script). By default the names exported from a script
are all those defined in it, at top level, but none of those acquired by
a %include of another file. This behaviour can be modified (either to
export more or to export less than the default) by placing a \f(CW%export\fP
directive in the script, specifying a list of `parts' to be exported to
an including file.
.LP
The presence of a \f(CW%export\fP directive in a script has no effect on its
behaviour when it is the current script of a Miranda session \- it is
effective only when the script is \f(CW%include\fPd in another. A script may
contain at most one \f(CW%export\fP directive. This can be anywhere in the
script, but to avoid nasty surprises it is advisable to place it near
the top.
.LP
Each `part' listed in the export directive must be one of the following:
.IP
\f(CWidentifier\fP (variable or typename)
.IP
\f(CWfileid\fP (in quotes, conventions as described above)
.IP
the symbol \f(CW+\fP
.IP
\f(CW-identifier\fP
.LP
Notice that constructors need not (and cannot) be listed explicitly in
an \f(CW%export\fP directive \- if you export an algebraic typename, its
constructors are AUTOMATICALLY exported along with it. The consequence
of this is that you cannot use \f(CW%export\fP to create an abstract data type,
by "hiding information" about how an algebraic type was formed. If you
want to create an abstract data type you must use the \f(CWabstype\fP mechanism
\- see section 21.\ \fIAbstract types\fP.
.LP
If a \f(CWfileid\fP is present in the export list, this must be the name of a
file to \f(CW%include\fP in the exporting script, and the effect is that
all the bindings acquired by that \f(CW%include\fP statement (as modified by
aliases if present) are re-exported. Allowing \f(CWfileid\fP's in the export
list is merely a piece of shorthand, which can be used to avoid writing
out long lists of names.
.LP
The symbol \f(CW+\fP is allowed in an export list as an abbreviation for all
the top-level identifiers defined in the current script.
.LP
The default \f(CW%export\fP directive (i.e. that which is assumed if no \f(CW%export\fP
statement is present) is therefore
.XE
    %export +
.XX
This will export all the top-level identifiers of the current script,
but not those acquired by \f(CW%include\fP directives.
.LP
Finally, the notation \f(CW-identifier\fP is allowed in an export list to
indicate that this identifier NOT to be exported. This is useful if you
have used a \f(CWfileid\fP or the symbol \f(CW+\fP to abbreviate a list of names, and
wish to subtract some of these names from the final export list.
.LP
An example \- the following export statement exports all the top-level
identifiers of the current script, except \f(CWflooby\fP.
.XE
    %export + -flooby
.XX
The order of appearance of the items in an export list is of no
significance, and repetitions are ignored. A negative occurrence of an
identifier overrides any number of positive occurrences.
.LP
It is possible to find out what names are exported from a given Miranda
script (or scripts) by calling, from UNIX, the command
\f(CWmira -exports files\fP (the extension \f(CW.m\fP will be added to each file
name if missing). This will list (to stdout) for each file the exported
names together with their types.
.SH 3
Some examples
.LP
(i) There are two scripts, called \f(CW"liba.m"\fP and \f(CW"libb.m"\fP say, containing
useful definitions. For convenience we wish to combine them into a
single larger library called say, \f(CW"libc.m"\fP. The following text inside
the file \f(CW"libc.m"\fP will accomplish this.
.XE
    %export "liba" "libb"
    %include "liba"
    %include "libb"
.XX
You will notice that when \f(CW"libc.m"\fP is compiled, this does NOT cause
recompilation of \f(CW"liba.m"\fP and \f(CW"libb.m"\fP (see section on separate
compilation \- the compiler is able to create an object code file for
\f(CW"libc.m"\fP, called \f(CW"libc.x"\fP, by combining \f(CW"liba.x"\fP and \f(CW"libb.x"\fP in an
appropriate way). This economy in recompilation effort is one reason
why \f(CW%include\fP is a better mechanism than the simpler textual directive
\f(CW%insert\fP (see section on compiler directives).
.LP
We could if we wished add some definitions to \f(CW"libc.m"\fP \- if the
corresponding names are added to the \f(CW%export\fP statement these bindings
will then be exported along with those of the two sublibraries. Of
course if we don't add the names of the locally defined objects to the
\f(CW%export\fP directive they will be `private definitions' of \f(CW"libc.m"\fP, not
visible to includors.
.LP
Recall that if no \f(CW%export\fP is directive is present, then ONLY the
immediate definitions (if any) of \f(CW"libc.m"\fP will be exported. So a
script which contains only \f(CW%include\fP directives and no \f(CW%export\fP cannot be
usefully \f(CW%include\fPd in another script (it is however perfectly acceptable
as a current script).
.LP
(ii) [More technical \- omit on first reading]
.LP
Our second group of examples is chosen to bring out some issues which
arise when exporting types between scripts. Suppose we have the
following script, called "trees.m"
.XE
    tree * ::= NILT | NODE * (tree *) (tree *)
    reflect :: tree *->tree *
    reflect NILT = NILT
    reflect (NODE a x y) = NODE a(reflect y)(reflect x)
.XX
(a) If in another script we write \f(CW%include "trees"\fP, the following
bindings will be imported \- \f(CWtree NILT NODE reflect\fP. Now suppose we
modify the \f(CW"trees.m"\fP by placing in it the following directive \- \f(CW%export
reflect\fP. When the modified \f(CW"trees.m"\fP script is included in another, we
will get the following error message from the compilation of the
including script:
.XE
    MISSING TYPENAME
    the following type is needed but has no name in this scope:
    'tree' of file "trees.m", needed by: reflect;
    typecheck cannot proceed - compilation abandoned
.XX
Explanation: it is illegal to export an identifier to a place where its
type, or any part of its type, is unknown. In this situation we call
reflect a `type-orphan' \- it has lost one of its parents!
.LP
(b) Re-adoption of a type-orphan (a more subtle example). Assuming the
\f(CW"trees.m"\fP script in its original form as above, we construct the
following file \f(CW"treelib.m"\fP
.XE
    %export size
    %include "trees"
    size :: tree *->num
    size NILT = 0
    size (NODE a x y) = 1+size x+size y
.XX
If we \f(CW%include\fP the above script in another as it stands, we will of
course get a missing typename diagnostic for \f(CWsize\fP \- consider however
the following script
.XE
    %include "treelib"
    %include "trees"
    ... (etc)
.XX
Everything is now ok, because a name for \f(CWsize\fP's missing parent is
imported through another route (the second \f(CW%include\fP statement). The
Miranda compiler recognises the \f(CWtree\fP type imported by the second
%include as being the same one as that referred to inside \f(CW"treelib.m"\fP,
because it originates (albeit via different routes) from the SAME
SOURCEFILE. A \f(CWtree\fP type imported from a different original
sourcefile, even if it had the same constructor names with the same
field types, would be recognised as a different type.
.LP
[Note: the Miranda compiler is always able to recognise when the same
source file is inherited via different routes, including in cases
involving files with multiple pathnames due to the presence of (hard or
symblic) links.]
.LP
[Further note: the lexical directive %insert (see compiler directives)
should be regarded as making a textual copy of the material from the
inserted file into the file containing the %insert directive \- if the
text of a type definition (in \f(CW::=\fP or abstype) is copied in this way, the
compiler will regard the \f(CW%insert\fP as having created a new type in each
such case, not identical with that in the inserted file.]
.LP
(c) Last example (typeclash). Finally note that that it is illegal for
the same original type to be imported twice into the same scope even
under different names. Consider the following script
.XE
    %include "trees" shrub/tree Leaf/NILT Fork/NODE -reflect
    %include "trees"
    ... (etc)
.XX
The first \f(CW%include\fP taken on its own is perfectly ok \- we have imported
the \f(CWtree\fP type and renamed everything in it by using aliases. However
we have also inherited the \f(CWtree\fP type under its original name, via the
second \f(CW%include\fP. The compiler will reject the script with the following
message:
.XE
    TYPECLASH - the following type is multiply named:
    'tree' of file "trees.m", as: shrub,tree;
    typecheck cannot proceed - compilation abandoned
.XX
The rule that a type can have at most one name in a given scope applies
to both algebraic types and abstract types (it does not apply to synonym
types, because these are not `real' types but mere macros \- you can
have any number of synonyms for \f(CWtree\fP in scope at the same time \- as
long as the underlying `real' type has a unique name).
.LP
Typeclashes are illegal in Miranda in order to preserve the following
two principles. (i) In any given scope, each possible type must have a
unique canonical form (obtained by expanding out synonyms, and renaming
generic type variables in a standard way). (ii) Each object of a `printable
type' must have, in any given scope, a unique external
representation (ruling out multiply named constructors). The first
principle is necessary to the functioning of the typechecker, the second
is demanded by the requirement that the function \f(CWshow\fP be referentially
transparent.
.SH 2
27/4. The \f(CW%free\fP directive and parametrised scripts
.LP
It is permitted to construct a script containing definitions which are
dependent on information which will be supplied only when the script is
made the subject of a \f(CW%include\fP directive. Such a script is said
to be `parametrised'. This is indicated by the presence in the script of a
directive of the form
.XE
    %free { signature }
.XX
where \f(CWsignature\fP is a list of specifications of the identifiers for
which bindings will be provided at \f(CW%include\fP time. A script may contain
at most one \f(CW%free\fP directive, which must therefore give all the
identifiers on which the script is parametrised. The \f(CW%free\fP directive
may appear anywhere in the script, but for clarity it is recommended
that you place it at or near the top.
.LP
For example a script (called \f(CW"matrices"\fP say) defining the notion of
matrix sum and matrix product, for matrices of as-yet-unspecified
element type, could be written as follows:-
.XE
    %export matmult matadd

    %free { elem :: type
    	    zero :: elem
    	    mult, add :: elem->elem->elem
          }
	
    matrix == [[elem]]

    matadd :: matrix->matrix->matrix
    matadd xx yy = [[add a b|(a,b)<-zip2 x y]|(x,y)<-zip2 xx yy]

    matmult :: matrix->matrix->matrix
    matmult xx yy = outerprod innerprod xx (transpose yy)
    innerprod x y = sum [mult a b|(a,b)<-zip2 x y]
                    where
                    sum = foldr add zero
    outerprod f xx yy = [[f x y|y<-yy]|x<-xx]
.XX
Note that the identifiers declared under \f(CW%free\fP may denote types as well
as values. When we write a \f(CW%include\fP directive for the above script we
must provide bindings for all of its free identifiers. The bindings are
given in braces following the pathname (and before the aliases, if any).
Thus:-
.XE
    %include "matrices" {elem==num; zero=0; mult=*; add=+; }
.XX
In the scope of the script containing the above directive the
identifiers \f(CWmatmult\fP and \f(CWaddmult\fP will be available at type
\f(CW[[num]]->[[num]]->[[num]]\fP and will behave as if their definitions had
been written using \f(CW0\fP, \f(CW(+)\fP, \f(CW(*)\fP in place of the identifiers
\f(CWzero\fP, \f(CWadd\fP, \f(CWmult\fP.
.LP
The order in which the bindings are given is immaterial (it need not be
the order in which the identifiers occurred in the \f(CW%free\fP directive) but
a binding must be given for each free identifier of the \f(CW%include\fPd
script. Note that the binding for a type is given using \f(CW==\fP and for a
value using \f(CW=\fP. If the types of all the bindings (taken together) are
not consistent with the information given in the free directive of the
%included script, or if any required binding is missing, the compiler
will reject the \f(CW%include\fP directive as incorrect.
.LP
The main advantage of a parametrised script is that different bindings
may be given for its free identifiers on different occasions. For
example the same script "matrices" may be invoked with different
bindings to provide a definition of matrix addition and multiplication
over matrices with elements of type bool. Thus:-
.XE
    %include "matrices" {elem==bool; zero=False; mult=&; add=\e/; }
.XX
It is even possible to \f(CW%include\fP the same parametrised script twice in
the same scope (presumably with different bindings for the free
identifiers) but in this case it will be be necessary to alias apart the
two sets of exported identifiers to avoid a nameclash. So we might add
\f(CWb_matadd/matadd b_matmult/matmult\fP to the above directive if it were
being used in the same script as the previous one.
.SH 2
Miscellaneous points
.LP
By default the identifiers declared \f(CW%free\fP in a parametrised script are
not exported from the script. As always this can be overridden by
explicitly listing them in an \f(CW%export\fP directive.
.LP
Free typenames of non-zero arity are declared in the following style.
.XE
    %free { stack * :: type
            table * ** :: type
            ...
          }
.XX
The corresponding bindings could be as follows
.XE
    %include ... {stack * == [*]; table * ** == [(*,**)]; ... }
.XX
When a parametrised script exports a locally created typename (other
than a synonym type), each instantiation of the script by a \f(CW%include\fP is
deemed to create a NEW type (this is relevant to deciding whether or not
two types are the same for the purpose of readopting a type orphan, see
previous manual section). This is because the compiler assumes that an
abstract or algebraic type defined in a parametrised script will in
general have an internal structure that depends on the free identifiers.
.LP
Finally note that the bindings for the free identifiers of a
parametrised script must always be given EXPLICITLY. For example
suppose we wish to \f(CW%include\fP the file \f(CW"matrices"\fP in a script already
containing a type called \f(CWelem\fP over which we intend to do matrix
multiplication. We must write
.XE
    %include "matrices" {elem==elem; etc. }
.XX
The binding \f(CWelem==elem\fP is not redundant, nor is it cyclic, because the
two \f(CWelem\fPs involved refer to two different scopes (on the left of the
binding, that of the includee, and on the right that of the script
containing the directive).
.SH 2
27/5 Separate compilation and \f(CW.x\fP files
.LP
The Miranda compiler compiles to an intermediate code, based on
combinators. When a Miranda expressions are evaluated in the course of
a session this code is executed by an interpreter.
.LP
Since compilation is a complex process (involving lexical analysis,
parsing, type checking and code-generation, as well as a number of other
minor steps) it is undesirable that the results of compiling a script
should just be "thrown away" at the end of a session. To avoid
unnecessary acts of recompilation the Miranda system maintains an
object-code file in association with each source file containing a
Miranda script.
.LP
For each source file, called say \f(CWscript.m\fP, the Miranda system will
create an object code file, called \f(CWscript.x\fP. No action is required by
the user to keep these files up-to-date, since this is taken care of
automatically by the Miranda system. The \f(CW.x\fP files are never referred to
directly by the Miranda user, and you should not try to edit them (they
contain binary data).
.LP
You may however safely remove any \f(CW.x\fP file (if for example you don't wish
it to use up filespace) since this will at worst cause the Miranda
compiler to do some extra work later to recreate it.
.LP
If you select a script as the current script of a Miranda session, and
it has an up-to-date \f(CW.x\fP file, this will be loaded instead, avoiding
recompilation. If the \f(CW.x\fP file does not exist, or any relevant source 
file has been modified since the \f(CW.x\fP file was created, the script will be
recompiled (and a side effect of your having selected this source file
as the current script will be to bring into existence an up-to-date \f(CW.x\fP
file for it).
.LP
[Inductive definition: source file B is `relevant' to source file A iff
file A \f(CW%insert\fPs or \f(CW%include\fPs B or any file to which B is relevant.
For a discussion of \f(CW%include\fP and the other library directives, see the manual
sections on \fIThe Library Mechanism\fP.]
.LP
Note that compiling a script containing \f(CW%include\fP statements will have
the side effect of triggering subsidiary compilation processes for any
relevant source files which have been modified since their corresponding
\f(CWx\fP. file was created. Users familiar with the UNIX program \f(CWmake\fP will
recognise this process as essentially the same as that which happens
when a \f(CWMakefile\fP is obeyed. In the case of Miranda however, the \f(CWmake\fP
process is fully automated by being built into the compiler.
.SH 2
More advanced information
.LP
If you want to check that a given Miranda script has an up-to-date
object code file without entering a Miranda session, this can be
accomplished from UNIX by calling mira with a special flag, thus
.XE
    mira -make script.m
.XX
will force the existence of an up-to-date \f(CWscript.x\fP, performing all
(and only) those compilations which are necessary. Any number of source
files can be given after the \f(CW-make\fP flag (and as usual if a \f(CW.m\fP
extension is omitted it will be added automatically).
.LP
Example: to make sure every Miranda source file in your current
directory has an up-to-date object code file, say \f(CWmira -make *.m\fP.
.LP
Applying \f(CWmira -make\fP to a \f(CW.x\fP file is equivalent to applying it to the
corresponding \f(CW.m\fP file. So another way to make sure everything in your
current directory is up-to-date is to say \f(CWmira -make *.x\fP. This has
the advantage that it will also remove any \f(CW.x\fP files whose \f(CW.m\fP files
no longer exist.
.LP
In the best UNIX tradition \f(CWmira -make\fP does its work silently unless
something is wrong. If the source files are all correct closed scripts
with up-to-date \f(CW.x\fP files, \f(CWmira -make\fP says nothing at all.
If recompilations are necessary it informs you which source files are being
compiled, and, as a last step, the names of any scripts which contain
errors or undefined names are listed, to stdout.
.LP
The exit status of a \f(CWmira -make\fP (relevant if you are a shell
programmer, or wish to include a \f(CWmira -make\fP command in a makefile for
a larger setup) is as follows. If (AFTER any necessary recompilations
have been performed) all the source files have up-to-date \f(CW.x\fP files,
and do not contain any syntax errors, type errors, or undefined names
(these facts are recorded in \f(CW.x\fP files) the exit status will be zero
(=ok), otherwise it will be 1.
.LP
It is possible to find out what names are exported from one or more
Miranda scripts without entering a Miranda session by using the command
.XE
    mira -exports files
.XX
(as always the \f(CW.m\fP extension is added automatically to each filename,
if missing). This command first calls \f(CWmira -make\fP on each file, to
make sure everything is uptodate, and then lists to standard output the
exported names together with their types (one per line). If more than
one file is specified each group of names will be preceded by the name
of the file to which they appertain.
.LP
Note that the export profile of a script includes information about its
free identifiers (if any).
.LP
It is also possible to find out the names of all files on which a given
set of Miranda scripts depend, via \f(CW%include\fP and \f(CW%insert\fP statements, by
using the command
.XE
    mira -sources files
.XX
This lists to standard output, one per line, the names of all relevant
source files. The standard environment, <stdenv>, is always omitted
from the list.
.SH 2
Effect of \f(CWmv\fP and \f(CWrm\fP
.LP
Finally we note a couple of points about the behaviour of Miranda \f(CW.x\fP
files under applications of \f(CWmv\fP and \f(CWrm\fP to their corresponding sources.
.LP
A \f(CW.x\fP file records (inter alia) the names of all relevant source files
relative to the directory in which it is stored, together with their `date
and time last modified'. Note that the UNIX command \f(CWmv\fP does not
alter the time-last-modified of the file being moved. So it is possible
when moving a Miranda source file (or a group of interdependent source
files) from one directory to another to save mira the bother of
recompiling them, simply by moving all the relevant \f(CW.x\fP files into the
new directory along with the sources. (This doesn't work however if you
change the name of any of the source files during the move.)
.LP
[Note that \f(CWtar\fP has the same property, so the up-to-date-ness of
Miranda \f(CW.x\fP files is preserved across a tape dump.]
.LP
If you use \f(CWrm\fP to remove a Miranda source file, the next time you
invoke \f(CWmira\fP with the (now non-existent) file as its current script, it
will promptly remove the corresponding \f(CW.x\fP file. The logic of this is
as follows:- \f(CW.x\fP files must be kept up-to-date with their sources, and
the way to make a \f(CW.x\fP file up-to-date with a non-existent source is to
make it too non-existent. As a consequence it is not possible to send
someone a Miranda object code file without the corresponding source
(mira will delete it as soon as they try to use it!).
.LP
From some points of view this last feature might be regarded as a bug -
a way round it may be provided in a later release of the Miranda system.
.SH
28. The Standard Environment
.LP
We give here, in alphabetical order, a brief explanation of all the
identifiers in the Miranda standard environment, each followed by its
definition (except in a few cases where the definition cannot
conveniently be given in Miranda). The lines marked with a \f(CW>\fP in
column one are formal program text, the other lines in the file are
comment. Note that a number of the functions given here are defined
internally (for speed) even though their definitions could have been
given in Miranda \- in these cases the Miranda definition is given as a
comment. This is the standard environment of Miranda release two.
.LP
\f(CWabs\fP
takes the absolute value of a number \- e.g. \f(CWabs (-3)\fP is \f(CW3\fP,
\f(CWabs 3.5\fP is \f(CW3.5\fP
.XE
> abs :: num->num
> abs x = -x, if x<0
>       =  x, otherwise
.XX
.LP
\f(CWand\fP
applied to a list of truthvalues, takes their logical conjunction.
.XE
> and :: [bool]->bool
> and = foldr (&) True
.XX
.LP
\f(CWarctan\fP
is the trigonometric function, inverse tangent. It returns a
result in the range \f(CW-pi/2\fP to \f(CWpi/2\fP.
See also \f(CWsin\fP, \f(CWcos\fP.
.XE
> arctan :: num->num ||defined internally
.XX
.LP
\f(CWbool\fP
is the type comprising the two truthvalues.
.XE
    bool ::= False | True ||primitive to Miranda
.XX
.LP
\f(CWchar\fP
is the type comprising the Latin-1 character set (e.g. \f(CW'a'\fP, \f(CW'\en'\fP).
.XE
    char :: type  ||primitive to Miranda
.XX
.LP
\f(CWcjustify\fP
applied to a number and a string, centre justifies the string
in a field of the specified width. See also \f(CWljustify\fP, \f(CWrjustify\fP,
\f(CWspaces\fP.
.XE
> cjustify :: num->[char]->[char]
> cjustify n s = spaces lmargin++s++spaces rmargin
>                where
>                margin = n - # s
>                lmargin = margin div 2
>                rmargin = margin - lmargin
.XX
.LP
\f(CWcode\fP
applied to a character returns its code number. Example
.XE
    code 'a' = 97.
.XX
See also \f(CWdecode\fP.
.XE
> code :: char->num  ||defined internally
.XX
.LP
\f(CWconcat\fP
applied to a list of lists, joins them all together into a
single list with \f(CW++\fP. E.g.
.XE
    concat [[1,2],[],[3,4]] = [1,2,3,4].
.XX
.XE
> concat :: [[*]]->[*]
> concat = foldr (++) []
.XX
.LP
\f(CWconst\fP
is a combinator for creating constant-valued functions. E.g.
\f(CW(const 3)\fP is the function that always returns \f(CW3\fP.
.XE
> const :: *->**->*
> const x y = x
.XX
.LP
\f(CWconverse\fP
is a combinator for inverting the order of arguments of a
two-argument function.
.XE
> converse :: (*->**->***)->**->*->***
> converse f a b = f b a
.XX
.LP
\f(CWcos\fP
is the trigonometric cosine function, argument in radians.
.XE
> cos :: num->num   ||defined internally
.XX
.LP
\f(CWdecode\fP
applied to an integer returns the character with that code.
.XE
> decode :: num->char ||defined internally
.XX
.LP
\f(CWdigit\fP
is a predicate on characters. True if the character is a digit.
See also \f(CWletter\fP.
.XE
> digit :: char->bool
> digit x = '0'<=x<='9'
.XX
.LP
\f(CWdrop\fP
applied to a number and a list returns the list with that many
elements removed from the front. If the list has less than the required
number of elements, \f(CWdrop\fP returns \f(CW[]\fP. Example
.XE
    drop 2 [1,2,3,4] = [3,4]
.XX
See also \f(CWtake\fP.
.XE
> drop :: num->[*]->[*]  ||defined internally, as below

  drop (n+1) (a:x) = drop n x
  drop n x = x,                                         if integer n
           = error "drop applied to fractional number", otherwise
.XX
.LP
\f(CWdropwhile\fP
applied to a predicate and a list, removes elements from the
front of the list while the predicate is satisfied. Example:
.XE
    dropwhile digit "123gone" = "gone"
.XX
See also \f(CWtakewhile\fP.
.XE
> dropwhile :: (*->bool)->[*]->[*]
> dropwhile f [] = []
> dropwhile f (a:x) = dropwhile f x, if f a
>                   = a:x,           otherwise
.XX
.LP
\f(CWe\fP
is a transcendental number, the base of natural logarithms.
.XE
> e :: num
> e = exp 1
.XX
.LP
\f(CWentier\fP
when applied to a number returns its integer part, meaning the
largest integer not exceeding it. E.g.
.XE
    entier 1.0 = 1
    entier 3.5 = 3
    entier (-3.5) = -4.
.XX
Notice that for Miranda the number \f(CW1\fP and the number \f(CW1.0\fP are
different values \- for example they yield different results under the
\f(CWinteger\fP test. However \f(CW1=1.0\fP is \f(CWTrue\fP
because of the automatic conversion from integer to float.
.XE
> entier :: num->num  ||defined internally
.XX
A useful fact about \f(CWentier\fP, which relates it to the operators
\f(CWdiv\fP and \f(CWmod\fP, is that the following law holds for any integers
\f(CWa\fP, \f(CWb\fP with \f(CWb~=0\fP and \f(CWa/b\fP within the range
for which integers can be represented exactly as fractional numbers
.XE
    a div b = entier (a/b)
.XX
.LP
\f(CWerror\fP
applied to a string creates an error value with the associated
message. Error values are all equivalent to the undefined value - any
attempt to access the value causes the program to terminate and print
the string as a diagnostic.
.XE
> error :: [char]->*  ||defined internally
.XX
.LP
\f(CWexp\fP
is the exponential function on real numbers. See also \f(CWlog\fP.
.XE
> exp :: num->num   ||defined internally
.XX
.LP
\f(CWfilemode\fP
applied to a string representing the pathname of a UNIX file,
returns a string of length four giving the access permissions of the
current process to the file. The permissions are encoded as (in this
order) \f(CW"drwx"\fP, any permission not granted is replaced by a \f(CW-\fP
character. 
If there is no file at pathname \f(CWp\fP, \f(CWfilemode p\fP returns the
empty string. Example
.XE
    member (filemode f) 'w'
.XX
tests \f(CWf\fP for write permission.
See also \f(CWgetenv\fP, \f(CWread\fP, \f(CWsystem\fP.
.XE
> filemode :: [char]->[char]  ||defined internally
.XX
.LP
\f(CWfilestat\fP
applied to a UNIX pathname returns three integers
\f(CW((inode,device),mtime)\fP, where \f(CWmtime\fP is the
time-last-modified of the file in seconds since
00.00h on 1 Jan 1970. The pair \f(CW(inode,device)\fP identifies a file uniquely,
regardless of the pathname used to reach it.
A non-existent file has inode & device \f(CW(0,-1)\fP and \f(CWmtime 0\fP.
.XE
> filestat :: [char]->((num,num),num)  ||defined internally
.XX
.LP
\f(CWfilter\fP
applied to a predicate and a list, returns a list containing
only those elements that satisfy the predicate. Example
.XE
    filter (>5) [3,7,2,8,1,17] = [7,8,17]
.XX
.XE
> filter :: (*->bool)->[*]->[*]
> filter f x = [a | a<-x; f a]
.XX
.LP
\f(CWfoldl\fP
folds up a list, using a given binary operator and a given start
value, in a left associative way. Example:
.XE
    foldl op r [a,b,c] = (((r $op a) $op b) $op c)
.XX
But note that in order to run in constant space, foldl forces \f(CWop\fP to
evaluate its first parameter. See the definitions of \f(CWproduct\fP,
\f(CWreverse\fP, \f(CWsum\fP for examples of its use. See also \f(CWfoldr\fP.
.XE
> foldl :: (*->**->*)->*->[**]->*  ||defined internally, as below
.XX
.XE
    foldl op r [] = r
    foldl op r (a:x) = strict (foldl op) (op r a) x
                       where
                       strict f x = seq x (f x)
.XX
WARNING:- this definition of \f(CWfoldl\fP differs from that in older versions
of Miranda. The one here is the same as that in Bird and Wadler (1988).
The old definition had the two args of \f(CWop\fP reversed. That is:-
.XE
    old_foldl op r = new_foldl (converse op) r
.XX
the function \f(CWconverse\fP has been added to the standard environment.
.LP
\f(CWfoldl1\fP
folds left over non-empty lists. See the definitions of \f(CWmax\fP, \f(CWmin\fP
for examples of its use.
.XE
> foldl1 :: (*->*->*)->[*]->*  ||defined internally, as below
.XX
.XE
    foldl1 op (a:x) = foldl op a x
    foldl1 op [] = error "foldl1 applied to []"
.XX
.LP
\f(CWfoldr\fP
folds up a list, using a given binary operator and a given start
value, in a right associative way. Example:
.XE
    foldr op r [a,b,c] = a $op (b $op (c $op r))
.XX
See the definitions of \f(CWand\fP, \f(CWconcat\fP, \f(CWor\fP,
for examples of its use.
.XE
> foldr :: (*->**->**)->**->[*]->** ||defined internally, as below

  foldr op r [] = r
  foldr op r (a:x) = op a (foldr op r x) 
.XX
.LP
\f(CWfoldr1\fP
folds right over non-empty lists.
.XE
> foldr1 :: (*->*->*)->[*]->*
> foldr1 op [a] = a
> foldr1 op (a:b:x) = op a (foldr1 op (b:x))
> foldr1 op [] = error "foldr1 applied to []"
.XX
.LP
\f(CWforce\fP
applied to any data structure, returns it, but forces a check
that every part of the structure is defined. Example
.XE
    hd(force x)
.XX
returns the \f(CWhd\fP of \f(CWx\fP, but fully evaluates \f(CWx\fP first (so \f(CWx\fP must be finite).
See also \f(CWseq\fP.
Notice in particular the idiom \f(CWseq (force a) b\fP which
returns \f(CWb\fP but only after fully evaluating \f(CWa\fP.
.XE
> force :: *->* ||defined internally
.XX
.LP
\f(CWfst\fP
returns the first component of a pair. See also \f(CWsnd\fP.
.XE
> fst :: (*,**)->*
> fst (a,b) = a
.XX
.LP
\f(CWgetenv\fP
looks up a string in the user's UNIX environment. Example
.XE
    getenv "HOME"
.XX
returns the pathname of your home directory. [If you want to see what
else is in your UNIX environment, say \f(CWprintenv\fP as a UNIX command.]
.XE
> getenv :: [char]->[char]   ||defined internally
.XX
.LP
\f(CWhd\fP
applied to a non empty list, returns its first element.
It is an error to apply \f(CWhd\fP to the empty list, \f(CW[]\fP.
See also \f(CWtl\fP.
.XE
> hd :: [*]->*
> hd (a:x) = a
> hd [] = error "hd []"
.XX
.LP
\f(CWhugenum\fP
is the largest fractional number that can exist in this implementation
(should be around 1e308 for IEEE standard 64 bit floating point).
See also \f(CWtinynum\fP.
.XE
> hugenum :: num  ||defined internally
.XX
.LP
\f(CWid\fP
is the identity function \- applied to any object it returns it.
.XE
> id :: *->*
> id x = x
.XX
.LP
\f(CWindex\fP
applied to a (finite or infinite) list, returns a list of its
legal subscript values, in ascending order. E.g. \f(CWindex "hippopotamus"\fP
is \f(CW[0,1,2,3,4,5,6,7,8,9,10,11]\fP.
.XE
> index :: [*]->[num]
> index x = f 0 x
>           where
>           f n [] = []
>           f n (a:x) = n:f(n+1)x
.XX
.LP
\f(CWinit\fP
is dual to \f(CWtl\fP, it returns a list without its last component.
Example
.XE
    init [1,2,3,4] = [1,2,3].
.XX
See also \f(CWlast\fP. [Note, by the `dual' of a list processing function we
mean the function which does the same job in a world where all lists
have been reversed.]
.XE
> init :: [*]->[*]
> init (a:x) = [],       if x=[]
>            = a:init x, otherwise
> init [] = error "init []"
.XX
.LP
\f(CWinteger\fP
is a predicate on numbers. True if and only if the number is not fractional.
.XE
> integer :: num->bool    ||defined internally
.XX
.LP
\f(CWiterate f x\fP
returns the infinite list \f(CW[x, f x, f(f x), ... ]\fP
.LP
Example: \f(CWiterate (2*) 1\fP yields a list of the powers of 2.
.XE
> iterate :: (*->*)->*->[*]
> iterate f x = [y | y<-x, f y ..]
.XX
Note use of \f(CW, ..\fP to generate an arbitrary sequence (see manual section
13/2).
.LP
\f(CWlast\fP
applied to a non empty list returns its last element.
This function is the dual of \f(CWhd\fP.
Note that for any non-empty list \f(CWx\fP
.XE
    (init x ++ [last x]) = x
.XX
.XE
> last :: [*]->*    ||defined internally, as below

  last x = x!(#x-1)
.XX
.LP
\f(CWlay\fP
applied to a list of strings, joins them together after appending
a newline character to each string. Example
.XE
    lay ["hello","world"] = "hello\enworld\en"
.XX
Used to format output thus,
.XE
    lay(map show x)
.XX
as a top level expression, causes the elements of the list \f(CWx\fP to be
printed one per line. See also \f(CWlayn\fP, \f(CWlines\fP.
.XE
> lay :: [[char]]->[char]
> lay [] = []
> lay (a:x) = a++"\en"++lay x
.XX
.LP
\f(CWlayn\fP
is similar to \f(CWlay\fP, but produces output with numbered lines.
.XE
> layn :: [[char]]->[char]
> layn x =   f 1 x
>            where
>            f n [] = []
>            f n (a:x) = rjustify 4 (show n) ++") "++a++"\en"++f (n+1) x
.XX
.LP
\f(CWletter\fP
is a predicate on characters. True if the character is a letter.
.XE
> letter :: char->bool
> letter c = 'a'<=c<='z' \e/ 'A'<=c<='Z'
.XX
.LP
\f(CWlimit\fP
applied to a list of values, returns the first value which is
the same as its successor. Useful in testing for convergence.
For example the following Miranda expression computes the square root of 2
by the Newton-Raphson method
.XE
    limit [x | x<-2, 0.5*(x + 2/x).. ]
.XX
.XE
> limit :: [*]->*
> limit (a:b:x) = a,           if a=b
>               = limit (b:x), otherwise
> limit other = error "incorrect use of limit"
.XX
.LP
\f(CWlines\fP
applied to a list of characters containing newlines, returns a
list of lists, by breaking the original into lines. The newline
characters are removed from the result. Example, \f(CWlines\fP applied to
.XE
    "hello world\enit's me,\eneric\en"
.XX
returns \f(CW["hello world","it's me","eric"]\fP. Note that \f(CWlines\fP
treats newline as a terminator, not a separator (although it will tolerate a
missing \f(CW'\en'\fP on the last line).
.XE
> lines :: [char]->[[char]]
> lines [] = []
> lines (a:x) = []:lines x,   if a='\en'
>             = (a:x1):xrest, otherwise
>               where 
>               (x1:xrest) = lines x, if x~=[]
>                          = []:[],   otherwise
>                            ||this handles missing '\en' on last line
.XX
Note that the inverse of \f(CWlines\fP is the function \f(CWlay\fP,
in that applying \f(CWlay\fP to the output of \f(CWlines\fP will
restore the original string (except that a final newline will be added,
if missing in the original string).
.LP
\f(CWljustify\fP
applied to a number and a string, left justifies the string
in a field of the specified width.
.XE
> ljustify :: num->[char]->[char]
> ljustify n s = s++spaces(n - # s)
.XX
.LP
\f(CWlog\fP
applied to a number returns its natural logarithm (i.e. logarithm
to the base \f(CWe\fP). It is the inverse of the exponential function, \f(CWexp\fP.
See also \f(CWlog10\fP. Note that the log functions use a different algorithm
when applied to integer arguments (rather than just converting to float
first) so it is possible to take \f(CWlog\fP, or \f(CWlog10\fP,
of very large integers.
.XE
> log :: num->num     ||defined internally
.XX
.LP
\f(CWlog10\fP
applied to a number returns its logarithm to the base 10.
.XE
> log10 :: num->num      ||defined internally
.XX
.LP
\f(CWmap\fP
applied to a function and a list returns a copy of the list in
which the given function has been applied to every element.
.XE
> map :: (*->**)->[*]->[**]
> map f x = [f a | a<-x]
.XX
.LP
\f(CWmap2\fP
is similar to \f(CWmap\fP, but takes a function of two arguments, and
maps it along two argument lists.
We could also define \f(CWmap3\fP, \f(CWmap4\fP etc.,
but they are much less often needed.
.XE
> map2 :: (*->**->***)->[*]->[**]->[***]
> map2 f x y = [f a b | (a,b)<-zip2 x y]
.XX
Note: the Bird and Wadler function \f(CWzipwith\fP is just an uncurried
version of \f(CWmap2\fP, that is \f(CWzipwith f (x,y)\fP means
\f(CWmap2 f x y\fP.
.LP
\f(CWmax\fP
applied to a list returns the largest element under the built-in
ordering of \f(CW>\fP. Examples
.XE
    max [1,2,12,-6,5] = 12
    max "hippopotamus" = 'u'
.XX
See also \f(CWmin\fP, \f(CWsort\fP.
.XE
> max :: [*]->*
> max = foldl1 max2
.XX
.LP
\f(CWmax2\fP
applied to two values of the same type returns the larger under
the built in ordering of \f(CW>\fP. See also \f(CWmin2\fP.
.XE
> max2 :: *->*->*
> max2 a b = a, if a>=b
>          = b, otherwise
.XX
.LP
\f(CWmember\fP
applied to a list and a value returns \f(CWTrue\fP or \f(CWFalse\fP as the
value is or not present in the list.
.XE
> member :: [*]->*->bool
> member x a = or (map (=a) x)
.XX
.LP
\f(CWmerge\fP
applied to two sorted lists merges them to produce a single
sorted result. Used to define \f(CWsort\fP, see later.
.XE
> merge :: [*]->[*]->[*]  ||defined internally, as below

  merge [] y = y
  merge (a:x) [] = a:x
  merge (a:x) (b:y) = a:merge x (b:y), if a<=b
		    = b:merge (a:x) y, otherwise
.XX
.LP
\f(CWmin\fP
applied to a list returns its least member under \f(CW<\fP.
.XE
> min :: [*]->*
> min = foldl1 min2
.XX
.LP
\f(CWmin2\fP
applied to two values of the same type returns the smaller under
the built in ordering of \f(CW<\fP.
.XE
> min2 :: *->*->*
> min2 a b = b, if a>b
>          = a, otherwise
.XX
.LP
\f(CWmkset\fP
applied to a list returns a copy of the list from which any
duplicated elements have been removed. A list without duplications can
be used to represent a set, whence the name. Works even on infinite
list, but (beware) takes a time quadratic in the number of elements
processed.
.XE
> mkset :: [*]->[*]
> mkset [] = []
> mkset (a:x) = a:filter (~=a) (mkset x)
.XX
.LP
\f(CWneg\fP
is a function of one numeric argument, with the same action as the
unary \f(CW-\fP operator.
.XE
> neg :: num->num
> neg x = -x
.XX
.LP
\f(CWnum\fP
is the type comprising both integer and fractional numbers (such
as \f(CW42\fP, \f(CW-12.73e8\fP).
.XE
    num :: type  ||primitive to Miranda
.XX
.LP
\f(CWnumval\fP
converts a numeric string to the corresponding number \- accepts
optional leading "\f(CW-\fP" followed by integer or floating point number, using
same rules as the Miranda compiler. Strings containing inappropriate
characters cause an error (exception: leading white space is harmless).
.XE
> numval :: [char]->num ||defined internally
.XX
.LP
\f(CWor\fP
applied to a list of truthvalues, takes their logical disjunction.
.XE
> or :: [bool]->bool
> or = foldr (\e/) False
.XX
.LP
\f(CWpi\fP
is the well known real number (the ratio of the circumference of a
circle to its diameter).
.XE
> pi :: num
> pi = 4*arctan 1
.XX
.LP
\f(CWpostfix\fP
takes an element and a list and adds the element to the end of
the list. This is the dual of the prefix operator, \f(CW:\fP.
.XE
> postfix :: *->[*]->[*]
> postfix a x = x ++ [a]
.XX
.LP
\f(CWproduct\fP
applied to list of numbers returns their product.
See also \f(CWsum\fP.
.XE
> product :: [num]->num
> product = foldl (*) 1
.XX
.LP
\f(CWread\fP
returns the contents of file with a given pathname. Provides an
interface to the UNIX filing system. If the file is empty \f(CWread\fP
returns \f(CW[]\fP, but if the file does not exist, or lacks read permission,
\f(CWread\fP causes an error. See also \f(CWfilemode\fP, \f(CWgetenv\fP.
.XE
> read :: [char]->[char]  ||defined internally
.XX
.LP
\f(CWreadb\fP
reads a file as bytes \- useful in a UTF-8 locale, where binary
data may contain illegal characters if read as text. (In a non UTF-8
locale the results of \f(CWread\fP and \f(CWreadb\fP do not differ.)
See manual section 31/9 for more information.
.XE
> readb :: [char]->[char]  ||defined internally
.XX
.LP
\f(CWreadvals\fP
is a family of functions for reading a list of values from a file.
See manual section 31/3.
.LP
\f(CWrep\fP
applied to a number and a value, returns a list containing the
specified number of instances of the value.
(The name is short for `replicate'.) Example
.XE
        rep 6 'o' = "oooooo"
.XX
See also \f(CWrepeat\fP'.
.XE
> rep :: num->*->[*]
> rep n x = take n (repeat x)
.XX
.LP
\f(CWrepeat\fP
applied to a value returns an infinite list, all of whose
elements are the given value.
.XE
> repeat :: *->[*]
> repeat x = xs
>            where xs = x:xs
.XX
.LP
\f(CWreverse\fP
applied to any finite list returns a list of the same elements
in reverse order.
.XE
> reverse :: [*]->[*]
> reverse = foldl (converse(:)) []
.XX
.LP
\f(CWrjustify\fP
applied to a number and a string, right justifies the string
in a field of the specified width.
.XE
> rjustify :: num->[char]->[char]
> rjustify n s = spaces(n - # s)++s
.XX
.LP
\f(CWscan op r\fP
applies \f(CWfoldl op r\fP to every initial segment of a list.
For example \f(CWscan (+) 0 x\fP computes running sums.
.XE
> scan :: (*->**->*)->*->[**]->[*]
> scan op = g 
>           where
>           g r = (r:). rest
>                 where
>                 rest [] = []
>                 rest (a:x) = g (op r a) x
.XX
There is another way to explain \f(CWscan\fP, which makes it clearer why it is
useful. Let \f(CWs0\fP be the initial state of an automaton, and
\f(CWf::state->input->state\fP, its state transition function \- then \f(CWscan f s0\fP
is a function that takes a list of inputs for the automaton and returns
the resulting list of states, starting with \f(CWs0\fP.
.LP
\f(CWseq\fP
applied to two values, returns the second but checks that the
first value is not completely undefined. Sometimes needed, e.g. to
ensure correct synchronisation in interactive programs.
.XE
> seq :: *->**->** ||defined internally
.XX
.LP
\f(CWshow\fP
is a keyword denoting a family of functions for converting values
of different types to their print representations. See manual section
23 for more details.
.LP
\f(CWshownum\fP
applied to a number returns as a string a standard print
representation for it. A special case of the operator \f(CWshow\fP. Applied
to fractional numbers \f(CWshownum\fP gives 16 significant figures (less any
trailing zeros), using a format appropriate to the size of number.
For more detailed control over number format
see \f(CWshowfloat\fP, \f(CWshowscaled\fP.
.XE
> shownum :: num->[char] ||defined internally,
.XX
.LP
\f(CWshowhex\fP, \f(CWshowoct\fP
applied to an integer return its hexadecimal or
octal representation as a string. Note that showhex will also convert
floating point numbers to hexdecimal format as per the C 2011 standard.
.LP
Example:
.XE
    showhex pi => 0x1.921fb54442d18p+1
.XX
the scale factor in \f(CWp\fP is a power of 2 (oddly, this part is in decimal).
.XE
> showhex, showoct :: num->[char] ||defined internally
.XX
.LP
\f(CWshowfloat p x\fP
returns as a string the number \f(CWx\fP printed in floating point format,
that is in the form \f(CWdigits.digits\fP, where the integer
p (>=0) gives the number of digits after the decimal point.
.XE
> showfloat :: num->num->[char] ||defined internally,
.XX
.LP
\f(CWshowscaled p x\fP
returns as a string the number \f(CWx\fP printed in scientific
format, that is in the form \f(CWn.nnnnnne[+/-]nn\fP,
where the integer \f(CWp\fP (>=0) gives the number of digits required
after the decimal point.
.XE
> showscaled :: num->num->[char] ||defined internally,
.XX
.LP
\f(CWsin\fP
is the trigonometric sine function, argument in radians.
.XE
> sin :: num->num  ||defined internally
.XX
.LP
\f(CWsnd\fP
returns the second component of a pair.
.XE
> snd :: (*,**)->**
> snd (a,b) = b
.XX
.LP
\f(CWsort\fP
applied to any finite list sorts the elements of the list into
ascending order on the built in \f(CW<\fP relation. Note that you cannot sort
a list of functions. Example
.XE
    sort "hippopotamus" = "ahimoopppstu"
.XX
The following definition uses merge-sort, which has \fIn\ log\ n\fP worst-case
behaviour.
.XE
> sort :: [*]->[*]
> sort x = x,                                         if n<=1
>	 = merge (sort(take n2 x)) (sort(drop n2 x)), otherwise
>	   where
>	   n = # x
>	   n2 = n div 2
.XX
.LP
\f(CWspaces\fP
applied to a number returns a list of that many spaces.
.XE
> spaces :: num->[char]
> spaces n = rep n ' '
.XX
.LP
\f(CWsqrt\fP
is the square root function on (integer or fractional) numbers.
The result is always fractional.
.XE
> sqrt :: num->num   ||defined internally
.XX
.LP
\f(CWsubtract\fP
is a name for (converse) infix minus. Needed because you
cannot form postsections in \f(CW-\fP. (See manual page 9 on `sections'.)
.LP
Example:
.XE
    subtract 3
.XX
is the function that subtracts 3.
.XE
> subtract :: num->num->num
> subtract x y = y - x 
.XX
.LP
\f(CWsum\fP
applied to list of numbers returns their sum.
.XE
> sum :: [num]->num
> sum = foldl (+) 0
.XX
.LP
\f(CWsys_message\fP
is an algebraic type containing a family of constructors
used to control output to UNIX files. See manual section 31/2 on \fIOutput
to UNIX files.\fP The binary versions Stdoutb etc are used to write binary
data in a UTF-8 locale, see section 31/9 for more information.
.XE
> sys_message ::= Stdout [char] | Stderr [char] | Tofile [char] [char] |
>                 Closefile [char] | Appendfile [char] | System [char] |
>                 Exit num |  Stdoutb [char] |  Tofileb [char] [char]  |
>                 Appendfileb [char]
.XX
.LP
\f(CWsystem\fP
applied to a string causes the string to be executed as a UNIX
shell command (by \f(CWsh\fP). The result returned is a 3-tuple, comprising
the standard_output, error_output, and exit_status respectively,
resulting from the execution of the UNIX command. See manual section
31/1 on \fIInput from UNIX files etc\fP for more details.
.XE
> system :: [char]->([char],[char],num)  ||defined internally
.XX
.LP
\f(CWtake\fP
applied to a number and a list returns the specified number of
elements from the front of the list. If the list has less than the
required number of elements, \f(CWtake\fP returns as many as it can get.
.LP
Examples:
.XE
    take 2 [1,2,3,4] = [1,2]
    take 7 "girls" = "girls"
.XX
.XE
> take :: num->[*]->[*]  ||defined internally, as below
.XX
.XE
  take (n+1) (a:x) = a:take n x
  take n x = [],                                        if integer n
           = error "take applied to fractional number", otherwise
.XX
.LP
\f(CWtakewhile\fP
applied to a predicate and a list, takes elements from the
front of the list while the predicate is satisfied. Example:
.XE
    takewhile digit "123gone" = "123"
.XX
.XE
> takewhile :: (*->bool)->[*]->[*]
> takewhile f [] = []
> takewhile f (a:x) = a:takewhile f x, if f a
>                   = [],              otherwise
.XX
.LP
\f(CWtinynum\fP
is the smallest positive fractional number that can be
distinguished from zero in this implementation
(should be around \f(CW1e-324\fP for IEEE standard 64 bit floating point).
.XE
> tinynum :: num  ||defined internally
.XX
.LP
\f(CWtl\fP
applied to a non empty list returns the list without its first
element. Example, \f(CWtl "snow"\fP is \f(CW"now"\fP.
.XE
> tl :: [*]->[*]
> tl (a:x) = x
> tl [] = error "tl []"
.XX
.LP
\f(CWtranspose\fP
applied to a list of lists, returns their transpose (in the
sense of matrix transpose \- rows and columns are interchanged). Example
.XE
    transpose [[1,2,3],[4,5,6]] = [[1,4],[2,5],[3,6]]
.XX
The following definition is slightly more subtle than is at first sight
necessary, in order to deal correctly with `upper triangular' matrices.
.LP
Example:
.XE
    transpose [[1,2,3],[4,5],[6]] = [[1,4,6],[2,5],[3]]
.XX
.XE
> transpose :: [[*]]->[[*]]
> transpose x = [],                             if x'=[]
>             = map hd x':transpose(map tl x'), otherwise
>               where
>               x' = takewhile (~=[]) x
.XX
It might be thought that this function belongs in a specialised library
of matrix handling functions, but it has been found useful as a general
purpose list processing function, whence its inclusion in the standard
environment.
.LP
\f(CWundef\fP
is a name for the completely undefined value. Any attempt
access it results in an error message. Note that \f(CWundef\fP belongs to
every type.
.XE
> undef :: *
> undef = error "undefined"
.XX
.LP
\f(CWuntil\fP
applied to a predicate, a function and a value, returns the
result of applying the function to the value the smallest number of
times necessary to satisfy the predicate. Example
.XE
    until (>1000) (2*) 1 = 1024
.XX
.XE
> until :: (*->bool)->(*->*)->*->*
> until f g x = x,               if f x
>             = until f g (g x), otherwise
.XX
.LP
\f(CWzip2\fP
applied to two lists returns a list of pairs, formed by tupling
together corresponding elements of the given lists. Example
.XE
    zip2 [0..3] "type" = [(0,'t'),(1,'y'),(2,'p'),(3,'e')]
.XX
This function is often useful in list comprehensions, where it provides
an idiom for traversing two lists in parallel. For example the
following expression returns the scalar product of \f(CWx\fP and \f(CWy\fP
\f(CW(x,y::[num])\fP
.XE
    sum [ a*b | (a,b) <- zip2 x y ]
.XX
.XE
> zip2 :: [*]->[**]->[(*,**)]  ||defined internally, as below

  zip2 (a:x) (b:y) = (a,b):zip2 x y
  zip2 x y = []
.XX
Note that if the lists being zipped are of different lengths, the length
of the result is that of the shortest list (this holds for \f(CWzip2\fP and all
the following \f(CWzip\fP functions).
.LP
\f(CWzip3\fP
is analogous but takes three lists and returns a
list of 3-tuples.
Similarly for \f(CWzip4\fP, \f(CWzip5\fP, \f(CWzip6\fP \- zip functions
above \f(CWzip6\fP are not provided in the standard environment.
.XE
> zip3 (a:x) (b:y) (c:z) = (a,b,c):zip3 x y z
> zip3 x y z = []
> zip4 (a:w) (b:x) (c:y) (d:z) = (a,b,c,d):zip4 w x y z
> zip4 w x y z = []
> zip5 (a:v) (b:w) (c:x) (d:y) (e:z) = (a,b,c,d,e):zip5 v w x y z
> zip5 v w x y z = []
> zip6 (a:u)(b:v)(c:w)(d:x)(e:y)(f:z) = (a,b,c,d,e,f):zip6 u v w x y z
> zip6 u v w x y z = []
.XX
The following is included for compatibility with Bird and Wadler (1988).
The normal Miranda style is to use the curried form \f(CWzip2\fP.
.XE
> zip :: ([*],[**])->[(*,**)]
> zip (x,y) = zip2 x y
.XX
End of definitions of the standard environment
.SH
29. Literate scripts (an alternative comment convention)
.LP
The standard comment convention for Miranda scripts is that anything
rightwards from a pair of vertical bars to the end of a line is taken to
be comment and ignored by the compiler, thus
.XE
||This is a comment
.XX
Everything else in the script is taken to be formal program text.
An inverted style of commenting is also available in Miranda, permitting
the construction of a "literate script" (the name is taken from
Professor Donald Knuth's idea of "literate programming"). In a literate
script EVERYTHING is assumed to be comment, except for lines marked with
the formalising symbol \f(CW>\fP in column 1. For example the following lines
.XE
>  fac 0 = 1
>  fac (n+1) = (n+1)*fac n
.XX
would be taken as formal program text \- and could be preceded and/or
followed by some narrative explaining what the factorial function is and
why we define it in this way.
.LP
To minimise the danger that you will accidentally omit the \f(CW>\fP from one
line of your formal text without the compiler noticing that something is
wrong, the following additional rule applies to Miranda literate scripts -
whenever a group of lines of formal program text is preceded or
followed by some lines of "narrative", the two types of text must be
separated by at least one blank line. You will see that this has been
done for the definition of factorial given above.
(Definition: a "blank line" is one containing only white space.)
.LP
Within the formal sections of a literate script the standard comment
convention still works. For example
.XE
>  result = sum [fac n | n <- [1..50]]  ||NB this is a large number!
.XX
The compiler takes a decision on which comment convention applies by
looking at the first line of a script. If this has a \f(CW>\fP in column 1,
then it is a literate script, otherwise the compiler assumes it is a
conventional script. Typically the first line of a literate script will
just be a comment, e.g.
.XE
> ||This is a literate script
.XX
In fact this manual section is a legal Miranda script, defining \f(CWfac\fP
and \f(CWresult\fP (see first line). 
.LP
An alternative convention is based on the name of the file \- if this
ends in \f(CW.lit.m\fP then it is assumed to be a literate script,
independently of the form of the first line. This makes it possible to
have literate scripts which begin in `narrative' mode.
.LP
As an aid to maintaining good layout in literate scripts, a simple text
formatting program, called \f(CWjust\fP (short for justify), is supplied with
the Miranda system. This leaves untouched the formal sections of the
script and formats the narrative parts to specified width (default 72).
.LP
There is a UNIX manual page for \f(CWjust\fP which gives details of its
behaviour. Note that \f(CWjust\fP is a general purpose text formatting tool
and is not in any way Miranda-specific.
.LP
As an additional aid to the use of document preparation tools in
conjunction with Miranda scripts, the Miranda compiler will recognise
underlined keywords. This applies both to reserved words, such as \f(CWdiv\fP
and \f(CWmod\fP and to directives such as \f(CW%export\fP (underlining of the
initial \f(CW%\fP is optional).
The style of underlining accepted is `backspace-underline-character'
as generated by nroff/troff. It will
also recognise the underlined symbols \f(CW>\fP and \f(CW<\fP as being equivalent to \f(CW>=\fP,
\f(CW<=\fP respectively. This works in both literate scripts and scripts using
the standard comment convention.
.SH 2
Using LaTeX with Miranda literate scripts
.LP
Because of the \f(CW.lit.m\fP convention it is possible for a file to be both
a Miranda script and a LaTeX source file. In such a case the sections
of formal Miranda text (recognised by the Miranda compiler by the \f(CW>\fP in
column 1) will be surrounded by the LaTeX commands
.XE
    \ebegin{verbatim}

    \eend{verbatim}
.XX
A similar arrangement can be made for \f(CWtroff\fP.
.LP
[The 1989 distribution included a program, \f(CWmtotex\fP,
for using \f(CWmira\fP with LaTeX,
but this no longer works and has been removed \- DT]
.SH 2
Acknowledgements
.LP
The \f(CW>\fP inverse-comment convention (and the \(lqblank line\(rq rule)
are due to Richard Bird and Philip Wadler of Oxford University Programming
Research Group, and were first used in their language \(lqOrwell\(rq.
.SH
30. Some guidelines on good programming style in Miranda
.LP
We give here a series of suggested guidelines for good programming style
in Miranda. The list is not meant to be exhaustive. These rules are
also not intended to be followed in all cases, regardless of conflicting
considerations. That is why they are only suggestions for good style
and not grammar rules.
.SH 2
Avoid the indiscriminate use of recursion
.LP
A Miranda script that consists of large number of functions which call
each other in an apparently random fashion is no easier to understand
than, say, a piece of FORTRAN code which is written as a rat's nest of
GOTO statements. An excessive reliance on recursion (especially mutual
recursion) can be an indication of a weak programming style. Some
pointers:
.LP
Use list comprehensions, \f(CW..\fP lists and library functions, in
preference to ad-hoc recursion. For example it is probably clearer to
define factorial by writing
.XE
    fac n = product[1..n]
.XX
than to define it from first principles, as
.XE
    fac 0 = 1
    fac (n+1) = (n+1) * fac n
.XX
and to define the Cartesian product of two lists by a list
comprehension, thus
.XE
    cp x y = [(a,b)|a<-x;b<-y]
.XX
is certainly a lot clearer than the recursive definition,
.XE
    cp (a:x) y = f y ++ cp x y
             where
             f (b:y) = (a,b): f y
             f [] = []
    cp [] y = []
.XX
The standard environment contains a number of useful list processing
functions (e.g. \f(CWmap filter reverse foldr foldl\fP) with whose properties it
is worth becoming familiar. They capture common patterns of recursion
over lists, and can often be used to simplify your code, and reduce the
reliance on `ad-hoc' recursion. Programs using list comprehensions and
standard functions are also likely to run faster (on the current
implementation) than equivalent programs using ad-hoc recursion.
.LP
The standard environment is only a basic collection of useful general
purpose functions. As you get used to programming in Miranda you will
probably begin to discover other useful functions that express common
patterns of recursion (perhaps over data structures other than lists).
It is a good practice to collect such functions in libraries (together
with some explanations of their properties) so that you can reuse them,
and share them with others. Not all of them will survive the test of
time, but it cannot hurt to experiment.
.LP
To cause the definitions from such a library to be in scope in another
script you would use a \f(CW%include\fP directive (see manual section on
library directives).
.SH 2
Avoid unnecessary nesting of definitions
.LP
Scripts that get deeply nested in where-clauses are harder to
understand, harder to reason about formally, harder to debug (because
functions defined inside where's cannot be exercised seperately) slower
to compile, and generally more difficult to work with.
.LP
A well structured script will consist of a series of top-level
definitions, each of which (if it carries a \f(CWwhere\fP clause at all) has a
fairly small number of local definitions. A third level of definition
(\f(CWwhere\fP inside \f(CWwhere\fP) should be used only very occasionally. [And if you
find yourself getting nested four and five levels deep in block
structure you can be pretty sure that your program has gone badly out of
control.]
.LP
A function should normally be placed inside a \f(CWwhere\fP clause only if it is
logically necessary to do so (which will be the case when it has a free
variable which is not in scope outside the \f(CWwhere\fP clause). If your
script consists, of say six functions, one of which solves a problem and
the other five of which are auxiliary to it, it is probably not a good
style to put the five subsidiary functions inside a where clause of the
main one. It is usually better to make all six top level definitions,
with the important one written first, say.
.LP
There are several reasons for this. First that it makes the program
easier to read, since it consists of six separate chunks of information
rather than one big one. Second that the program is much easier to
debug, because each of its functions can be exercised separately, on
appropriate test data, within a Miranda session. Third that this
program structure is more robust for future development \- for example if
we later wish to add a second `main' function that solves a different
problem by using the same five auxiliary functions in another way, we
can do so without having to restructure any existing code.
.LP
There is a temptation to use \f(CWwhere\fP to hide information that is not
relevant at top-level. This may be misguided (especially if it leads to
code with large and complex where-clauses). If you don't wish all of
your functions or data structures to be "visible" from outside, the
proper way to do this is to include a \f(CW%export\fP directive in the script.
.LP
Note also that (in the current implementation) functions defined inside
a \f(CWwhere\fP clause cannot have their types explicitly specified. This is
a further reason to avoid putting structure inside a \f(CWwhere\fP clause that
does not logically have to be there.
.SH 2
Specify the types of top level identifiers
.LP
The Milner type discipline is an impressive advance in compiler
technology. It is also a trap for the unwary. The fact that the
Miranda compiler will accept several hundred lines of code without a
single type specification, and correctly infer the types of all the
identifiers does NOT mean that it is sensible to write code with no type
information. (Compare: compilers will also accept large programs with
no comments in, but that doesn't make such programs sensible.)
.LP
For other than fairly small scripts it is good style to insert an
explicit specification of the type of any top level identifier whose
type is not immediately apparent from its definition. Type
specifications look like this
.XE
    ack::num->num->num
.XX
says that \f(CWack\fP is a function taking two numbers and returning a number.
A type specification can occur anywhere in a script, either before or
after the definition of the corresponding identifier, but common sense
suggests that the best place for it is just before the corresponding
definition.
.LP
If in doubt it is always better to put in a type specification than to
leave it out. The compiler may not need this extra type information but
human beings definitely do. The extra type information becomes
particularly important when your code reaches the level of complexity at
which you start to make type errors.
.LP
If your script contains a type error it is unreasonable to expect the
compiler to correctly locate the real source of the error in the absence
of explicit type declarations. A type error means different parts of
your code are inconsistent with one another in their use of identifiers -
if you have not given the compiler any information about the intended
use of an identifier, you cannot expect it to know which of several
conflicting uses are the `wrong' ones. In such a case it can only tell
you that something is wrong, and indicate the line on which it first
deduced an inconsistency \- which may be many lines later than the `real'
error. Explicit type declarations make it much more likely that the
compiler will spot the `real error' on the line where it actually
occurs.
.LP
Code containing explicit type information is also incomparably easier
for other people to read.
.SH 2
Use safe layout
.LP
This is a point to do with the operation of the offside rule. It is
most easily explained by means of an example. Consider the following
definition, here assumed to be part of a larger script
.XE
    hippo = (rhino - swan)/piglet
            where
            piglet = 17
            rhino = 63
            swan = 29
.XX
Some time after writing this we carry out a global edit to expand \f(CWhippo\fP
to \f(CWhippopotamus\fP. The definition now looks like this.
.XE
    hippopotamus = (rhino - swan)/piglet
    	where
    	piglet = 17
    	rhino = 63
    	swan = 29
.XX
the \f(CWwhere\fP clause has become offside, and the definition will no longer
compile. Worse, it is possible (with a little ingenuity) to construct
examples of layout where changing the length of an identifier will move
a definition from one level of scope to another, so that the script
still compiles but now has a different meaning!!! Replacing an
identifier by a shorter one can cause similar difficulties with layout.
.LP
The layout of the \f(CWhippo\fP definition was unsafe, because the level of
indentation depended on the length of an identifier. There are several
possible styles of `safe' layout. The basic rule to follow is:
.LP
Whenever a right hand side goes on for more than one line
(because it consists of a set of guarded cases, or because it
carries a where clause, or just because it is an expression too
big to fit on one line), you should take a newline BEFORE
starting the rhs, and indent by some standard amount (not
depending on the width of the lhs).
.LP
There are two main styles of safe layout, depending on whether you take
the newline before or after the \f(CW=\fP of the definition. Here are two
possible safe layouts for the \f(CWhippo\fP definition
.XE
    hippo = 
        (rhino - swan)/piglet
        where
        piglet = 17
        rhino = 63
        swan = 29

    hippo 
      = (rhino - swan)/piglet
        where
        piglet = 17
        rhino = 63
        swan = 29
.XX
The reason that either style can be used is that the boundary, for
offside purposes, of a right hand side, is set by the first symbol of
the rhs itself, and not by the preceding \f(CW=\fP sign.
.LP
Both of these layouts have the property that the parse cannot be
affected by edits which alter the lengths of one or more identifiers.
Either of these layout styles also have the advantage that successive
levels of indentation can move to the right by a fixed step \- this makes
code easier to read and lessens the danger that your layout will `fall
off' the right hand edge of the screen (although if you follow the
advice given earlier about avoiding deeply nested block structure this
is in any case unlikely to be a problem).
.LP
It would be convenient if there was a program for reformatting Miranda
scripts with a standard layout. Apart from ensuring that the layout was `safe'
in the above sense, it might make it easier for people to read
each other's code. A layout program of this kind may be provided in
later releases of the system.
.LP
Acknowledgement: The \f(CWhippopotamus\fP example (and the problem of unsafe
layout) was first pointed out by Mark Longley of the University of Kent.
.SH 2
Write order independent code
.LP
When defining functions by pattern matching it is best (except in a few
cases where it leads to real clumsiness of expression) to make sure the
patterns are mutually exclusive, so it does not matter in what order the
cases are written.
.LP
For the same reason it is better style to use sets of guards which are
composed of mutually exclusive boolean expressions. The keyword
\f(CWotherwise\fP sometimes helps to make this less painful.
.LP
By way of illustration of some of the issues here is a definition of a
function \f(CWmerge\fP which combines two already sorted lists into a single
sorted result, eliminating duplicates in the process
.XE
    merge [] y = y
    merge (a:x) [] = (a:x)
    merge (a:x) (b:y)
          =  a:merge x (b:y), if a<b
          =  b:merge (a:x) y, if a>b
          =  a:merge x y,     otherwise
.XX
Note the use of mutually exclusive sets of patterns (it was tempting to
write \f(CWmerge x [] = x\fP as the second case, but the above is probably
better style).
.LP
A related issue to these is that where a function is not everywhere
defined on its argument type, it is good practice to insert an explicit
error case. For example the definition given in the standard
environment for \f(CWhd\fP, the function which extracts the first element of a
list, is
.XE
    hd (a:x) = a
    hd [] = error "hd []"
.XX
Of course if a function is applied to an argument for which no equation
has been given, the Miranda system will print an error message anyway,
but one advantage of putting in an explicit call to \f(CWerror\fP is that the
programmer gets control of the error message. The other (and perhaps
main) advantage is that for someone else reading the script, it
explicitly documents the fact that a certain use of the function is
considered an error.
.SH
31. UNIX/Miranda system interface
.LP
.SH 2
31/1. Input from UNIX files etc.
.LP
The following Miranda functions provide an interface to the UNIX file
system from within Miranda expressions:
.SH 3
\f(CWread :: [char]->[char]\fP
.LP
This takes a string valued argument, which it treats as a UNIX pathname,
and returns the contents of the file or device of that name, also as a
string (i.e. as a list of characters). There is no end-of-file
character, the termination of the file is indicated simply by the end of
the list of characters. The Miranda evaluation terminates with an error
message if the file does not exist or the user does not have read
permission for it.
.LP
A special case: the notation \f(CW$-\fP denotes the contents of the standard
input, as a list of characters. Note that multiple occurrences of \f(CW$-\fP
always denote a single shared input stream. So for example \f(CW($- ++ $-)\fP
reads one lot of data from the terminal and duplicates it.
.LP
(See separate subsection on Input/Output of binary data for the binary
versions \f(CWreadb\fP and \f(CW$:-\fP)
.SH 3
\f(CWfilemode :: [char]->[char]\fP
.LP
Takes a pathname and returns a string representing the access
permissions of the current process to the file of that name. The string
is empty if the file does not exist, otherwise it is of length four
containing, in order, the following characters \- \f(CWd\fP if the file is a
directory, \f(CWr\fP if it is readable, \f(CWw\fP if it is writeable, \f(CWx\fP if it is
executable. Each character not applicable is replaced by \f(CW-\fP. So for
example \f(CW"drwx"\fP is the filemode of a directory with all access
permissions, while "-rw-" is the filemode of a normal file with read and
write but no execute permission.
.SH 3
\f(CWgetenv :: [char]->[char]\fP
.LP
Looks up the string associated with a given name in the current UNIX
environment (see man (2) getenv in the UNIX manual system). For example
.XE
    getenv "HOME"
.XX
returns the name of the current home directory. Returns the empty
string if the given name not present in the environment.
.SH 3
\f(CWsystem :: [char]->([char],[char],num)\fP
.LP
The effect of \f(CWsystem string\fP is that a UNIX process is forked off to
execute \f(CWstring\fP as a shell command (by \f(CW/bin/sh\fP). The result of the
call to \f(CWsystem\fP is a triple containing the standard output, error
output, and exit_status, respectively, resulting from the execution of
the UNIX command. (The exit_status of a UNIX command is a number in the
range \f(CW0..127\fP, with a non-zero exit status usually indicating some kind
of abnormal event.) Note that inspecting the exit_status will force the
Miranda process to wait until the execution of the shell command has
completed \- otherwise the two processes proceed concurrently.
.LP
If the attempt to set up a shell process fails, \f(CWsystem\fP returns the
result \f(CW([],errmess,-1)\fP, where \f(CWerrmess\fP is an error message.
.LP
WARNING: the function \f(CWsystem\fP provides a very general interface to
UNIX. Obviously, this can be abused to cause the evaluation of a
Miranda expression to have side effects on the state of the filing
system. It is not intended to be used in this way \- \f(CWsystem\fP should be
used only to obtain information about the state of the world. If you
wish to change the state of the world, this should be done by placing a
\f(CWSystem\fP message in your output list (see next manual section).
.LP
Since reading data from the terminal would constitute a side effect, the
background process created by \f(CWsystem\fP comes into being with its
standard input closed.
.SH 2
Implementation Restriction
.LP
\f(CWread\fP, \f(CWfilemode\fP, \f(CWgetenv\fP and \f(CWsystem\fP all require their argument
to be at most 1024 characters long.
.SH 2
Note on system reading functions and referential transparency
.LP
Although \f(CWread\fP, \f(CWfilemode\fP, \f(CWgetenv\fP do not have
side effects, they are not referentially transparent because
it cannot be guaranteed that an expression like
.XE
    read "file"
.XX
will return the same result if evaluated twice. Some external event may
have changed the state of the filing system in the meantime. Clearly
the same problem applies to \f(CWsystem\fP \- consider for example the
expression
.XE
    system "date"
.XX
which gets date-and-time as a string. Evaluating this twice in
succession is unlikely to produce the same result.
.LP
Strictly speaking all calls to \f(CWread\fP and the other functions in this
section ought to be evaluated with respect to the state-of-the-world as
it existed before the evaluation of the given Miranda expression
commenced. Otherwise referentially transparent behaviour cannot be
guaranteed. Enforcing this would appear to require, among other things,
taking a copy of the whole filing system before each Miranda
command-level evaluation. For obvious reasons this is not implemented.
.SH 2
31/2. Output to UNIX files etc.
.LP
Since Miranda is a functional language, the evaluation of an expression
cannot in itself cause a side effect on the state of the world. The
side effects occur when the value of the expression is printed. The
value of a command level expression is a list of `system messages',
where the possible forms of message are shown by the following type
declaration,
.XE
  sys_message ::= Stdout [char] | Stderr [char] | Tofile [char] [char] |
                  Closefile [char] | Appendfile [char] | System [char] |
                  Exit num |  Stdoutb [char] |  Tofileb [char] [char]  |
                  Appendfileb [char]
.XX
The system `prints' such a list of messages by reading it in order from
left to right, evaluating and obeying each message in turn as it is
encountered. The effect of the various messages is as follows.
.SH 3
\f(CWStdout string\fP
.LP
The list of characters \f(CWstring\fP is transmitted to the standard output,
which will normally be connected to the user's screen. So for example
the effect of obeying
.XE
    [Stdout "!!!"]
.XX
is that three exclamation marks appear on the screen.
.SH 3
\f(CWStderr string\fP
.LP
The list of characters \f(CWstring\fP is sent to the standard error output.
[Explanation to those unfamiliar with UNIX stream philosophy: all normal
UNIX processes come into existence with a standard input stream, and two
output streams, called standard output and standard error respectively.
Under normal circumstances standard error and standard output are both
connected to the user's screen, but in principle they could be connected
to different places.]
.SH 3
\f(CWTofile fil string\fP
.LP
The characters of the string are transmitted to the file or device whose
UNIX pathname is given by \f(CWfil\fP. Successive \f(CWTofile\fP messages to the
same destination are appended together (i.e. the first such message
causes the file to be opened for writing, and it remains open until the
end of the whole message list). Note that opening a file for output
destroys its previous contents (unless preceded by an \f(CWAppendfile\fP
message, see below).
.SH 3
\f(CWClosefile fil\fP
.LP
The stream which has been opened to the file \f(CWfil\fP (presumably the
subject of some previous \f(CWTofile\fP messages) is closed.
If \f(CWfil\fP was not in fact open, this command has no effect
(i.e. is harmless). All open-for-output streams are automatically closed
at the end of a
message-list evaluation, so it is only necessary to invoke \f(CWClosefile\fP
explicitly if you wish to terminate output to given file during a
message-list evaluation. (One reason why you might want to do this is
so as not to have too many output files open at one time, since many
UNIX systems place a limit on the number of streams which a process can have.)
.SH 3
\f(CWAppendfile fil\fP
.LP
If obeyed before any \f(CWTofile\fP messages to destination \f(CWfil\fP,
causes the file to be opened in `append-mode', so its previous contents
are added to, instead of being replaced.
.LP
See separate subsection on Input/Output of binary data for explanation
of the binary versions \f(CWStdoutb\fP, \f(CWTofileb\fP, \f(CWAppendfileb\fP.
.SH 3
\f(CWSystem string\fP
.LP
Causes \f(CWstring\fP to be executed as a shell command (by \f(CW/bin/sh\fP)
at this point in time. Enables arbitrary UNIX commands to be invoked from
within a Miranda output list. The shell process comes into being with
its streams (standard input, standard output, standard error) inherited
from the Miranda process.
.SH 3
\f(CWExit num\fP
.LP
Causes the UNIX process evaluating the message list to terminate at this
point with exit status \f(CWnum\fP (an integer between 0 and 127).
The remaining messages in the list (if any) are discarded. The exit status
of a Miranda evaluation which terminates other than by a call to Exit
will be 0 if it terminates successfully or 1 if it encounters a runtime
error. The exit status is only relevant if you are using Miranda to
implement a stand-alone UNIX command (see the separate manual page about
this).
.LP
[Explanation: the exit status of a UNIX command is a one byte quantity
which is communicated back to the calling shell and can be tested by it -
the usual convention is that 0 exit status means all ok, anything else
means something was amiss. If you are not into shell programming you
can safely ignore the whole issue.]
.SH 2
The default output mechanism
.LP
We have stated above that the value of a command level expression is
expected to be of type \f(CW[sys_message]\fP.
.LP
If it is not of that type mira applies the following rules:
.IP (i)
if the value is of type \f(CW[char]\fP the characters are directed to
standard output, as if you had written \f(CW[Stdout (expr)]\fP.
.IP (ii)
if it is of another type, \f(CWshow\fP is first applied to convert it to
  type \f(CW[char]\fP, so it is as if you had written \f(CW[Stdout (show (expr))]\fP.
.LP
This explains how the Miranda system is able to function in its standard
`desk-calculator' mode.
.LP
Be aware that if <stdenv> is not loaded (because you invoked \f(CWmira\fP with
\f(CW-stdenv\fP, and the script does not explicitly \f(CW%include <stdenv>\fP)
there will be no type \f(CWsys_message\fP and only the default output mechanism
will be available.
.SH 2
Output redirection
.LP
A Miranda command of the form
.XE
    exp &> pathname
.XX
causes a background process to be set up for the evaluation of \f(CWexp\fP,
with both the standard output and the standard error output of the
process redirected to \f(CWpathname\fP. If \f(CWexp\fP is of type \f(CW[sys_message]\fP,
the destination of \f(CWTofile\fP messages are not affected by the global
redirection \- only messages which would otherwise have gone to the
screen are sent to \f(CWpathname\fP.
.LP
If two (blank separated) pathnames are given after the \f(CW&>\fP, standard
output is redirected to the first file and standard error to the second.
Thus:
.XE
    exp &> outfil errfil
.XX
If the \f(CW&>\fP is replaced by a \f(CW&>>\fP,
instead of overwriting the previous contents,
the relevant output is appended to the end of the file. Thus:
.XE
    exp &>> pathname(s)
.XX
As with the \f(CW&>\fP command either one or two pathnames can be given,
depending on whether you wish standard error to be merged with standard
out, or separated from it.
.LP
Note that a background process created by a \f(CW&>\fP or \f(CW&>>\fP command
has no standard input \- if the expression contains \f(CW$-\fP, the latter will
evaluate to \f(CW[]\fP.
.SH 2
Implementation Restrictions
.LP
Arguments representing pathnames (to Tofile, Appendfile, Closefile) are
restricted to 1024 characters in length \- pathnames longer than this
cause an error message. The shell command supplied to System is also
restricted to 1024 characters in length.
.SH 2
31/3. Reading with interpretation (\f(CWreadvals\fP and \f(CW$+\fP)
.LP
There is a function \f(CWreadvals\fP which takes a string representing a UNIX
pathname, and returns a list of values found in the file of that name.
The values may be represented by arbitrary Miranda expressions, written
one per line. Blank lines, and Miranda style comments (\f(CW||...\fP) are
ignored. If the input file appears to be a teletype, \f(CWreadvals\fP reacts to
syntactically incorrect or wrongly typed data by prompting the user to
repeat the line, and such bad values are omitted from the result list.
If the input file does not appear to be a teletype, bad data causes
readvals to abort with an error message.
.LP
Note that, similarly to \f(CWshow\fP
.IP 1.
\f(CWreadvals\fP is a reserved word, not an identifier.
.IP 2.
the context in which it is used must be such as to determine its
type monomorphically. Extra type specifications may be needed in the
script to meet this condition.
.LP
Here is a simple example of how \f(CWreadvals\fP might be used in a script
.XE
    x :: [num]
    x = readvals "data"
.XX
The file \f(CW"data"\fP should contain expressions of type \f(CWnum\fP
(one per line).
.LP
The \f(CWreadvals\fP function provides Miranda with a simple form of data
persistence \- data can be written to a file (e.g. using \f(CWshow\fP) and
read back using readvals in a later session. Data objects saved in this way
must of course be finite. Notice also that if you wish to save data
containing functions, you will have to set up some special arrangement,
since such data cannot be written out using \f(CWshow\fP.
.LP
Data of abstract type can be written to file using \f(CWshow\fP and read back
with \f(CWreadvals\fP \- provided that an appropriate show-function
was included in the signature of the abstract type
(see the manual section on abstract types).
.LP
Finally note that \f(CW$+\fP behaves exactly like an application of
\f(CWreadvals\fP to the name of the file to which the standard input
is connected. For example
.XE
    sum $+
.XX
read a sequence of numeric expressions from the keyboard (one per line)
up to the next control-D, and then returns their sum.
.SH 2
31/4. Using Miranda to build executable files
.LP
.SH 3
First method (using a `magic string')
.LP
Create a file, \f(CW"prog.m"\fP say, containing a normal Miranda script,
but with first line
.XE
    #! /usr/bin/mira -exec
.XX
The first two characters must be \f(CW#!\fP followed by an optional space and
the absolute pathname of the Miranda interpreter. This may be somewhere
other than \f(CW/usr/bin/mira\fP, the UNIX shell command \f(CWwhich mira\fP
should tell you where it is. The flag \f(CW-exec\fP is necessary and no other
flags should be added.
(Note \f(CW-exec2\fP can be substituted for \f(CW-exec\fP, see below.)
.LP
The remainder of the file can be any legal Miranda script, which may
\f(CW%include\fP other scripts. Somewhere in the file, or in an included file,
there must be a definition of \f(CWmain\fP. When \f(CW"prog.m"\fP is executed
as a UNIX command, the result will be that \f(CWmain\fP is evaluated, using the
same rules as if you had entered it in an interactive session, and the
results sent to the standard output. Remember to give the file execute
permission (e.g. by saying \f(CWchmod +x prog.m\fP).
.LP
A command of this form can take data from the terminal. The notation
\f(CW$-\fP can be used anywhere in the second and later lines of the file to
denote the list of characters taken from the standard input. (That is
\f(CW$-\fP behaves like a Miranda identifier of type \f(CW[char]\fP.)
.LP
The command can be invoked with arguments, e.g.
.XE
    prog.m fig 23
.XX
and the notation \f(CW$*\fP can be used in the script as a Miranda identifier
of type \f(CW[[char]]\fP denoting the argument list, with the convention that
the initial (zero'th) argument is the name of the command. So in this
case the value of \f(CW$*\fP would be
.XE
    ["prog.m","fig","23"]
.XX
If there are no arguments, \f(CW$*\fP will be a singleton list containing just
the command name.
.SH 4
Explanation
.LP
The line beginning \f(CW#!\fP is a standard UNIX incantation, called a `magic
string', indicating that the following pathname is an interpreter to be
invoked with the name of the file in which it occurs as argument (see
under \f(CWexecve\fP in section 2 of the UNIX manual). The flag \f(CW-exec\fP
instructs the Miranda system to evaluate \f(CWmain\fP, which can be of any
type. If \f(CWmain\fP is a string this is sent to stdout, if it is of another
printable type \f(CWshow main\fP is sent to stdout, or if \f(CWmain\fP is
of type \f(CW[sys-message]\fP the sequence of I/O commands is executed.
.SH 4
Examples
.LP
Here is the Miranda "hello world" program
.XE
    #! /usr/bin/mira -exec
    main = "hello world\en"
.XX
The following script is a Miranda version of the UNIX \f(CWcat\fP command \- if
it is invoked without arguments it simply copies its standard input to
its standard output, otherwise it concatenates the contents of its
argument files to the standard output.
.XE
    #! /usr/bin/mira -exec

    main = [Stdout $-], if tl $* = []
         = [Stdout (concat(map read(tl $*)))],     if badargs=[]
         = [Stderr (concat(map errmess badargs))], otherwise
    badargs = [f|f<-tl $*;~member(filemode f)'r']
    errmess f = f++": cannot access\en"
.XX
See the manual pages on input from UNIX files and output to UNIX files
for the explanation of \f(CWread\fP, \f(CWfilemode\fP and the constructors
\f(CWStdout\fP, \f(CWStderr\fP etc.
.LP
The rule that Miranda source files must have names ending in \f(CW.m\fP is not
enforced for \(lqmagic\(rq scripts, in keeping with the UNIX convention that
executables require no special suffix. However a magic script whose
name ends in \f(CW.m\fP can also be made the subject of a Miranda session.
This is advantageous during development, as individual definitions can
be tested. A first line beginning \f(CW#!\fP is ignored by the Miranda compiler
which treats it as a comment. In this situation \f(CW$*\fP has the value
\f(CW[]\fP, since the script was not executed as a command.
.LP
Note also that if your Miranda executable file has the \f(CW.m\fP suffix, a
corresponding \f(CW.x\fP file will be created at its first call, avoiding the
need for mira to recompile it on subsequent calls (unless there has been
an update of the source file).
.SH 4
Notes
.IP (1)
In some UNIX-like systems, \f(CWexecve\fP places a limit on the total
length of the `magic string'.
.IP (2)
Because in many systems (including Linux) \f(CWexecve\fP permits at most
one flag in a magic string, mira does not understand a \f(CW-lib\fP flag given
in conjunction with a \f(CW-exec\fP flag. This is a possible source of
difficulty if you keep the \f(CWmiralib\fP directory at a non-standard place.
One way round this is to set environment variable \f(CWMIRALIB\fP, instead of
using a \f(CW-lib\fP flag. See manual section on flags etc. [To do: more
general mechanism to add other flags to \f(CW-exec\fP in a magic string \- DT]
.IP (3)
If called from the UNIX command line,
.XE
    mira -exec script.m
.XX
will find and evaluate \f(CWmain\fP in \f(CWscript.m\fP and in this situation you can
combine \f(CW-exec\fP with other flags, \f(CW-lib miralib\fP, \f(CW-heap N\fP, etc. preceding the
name of the script. Any additional arguments following \f(CWscript.m\fP will
be found in \f(CW$*\fP.
.SH 4
Debugging stand-alone scripts
.LP
As an aid to debugging a variant flag is available:
.XE
    #!/usr/bin/mira -exec2
    definitions...
.XX
The \f(CW-exec2\fP flag has the same effect as \f(CW-exec\fP but runtime errors (only,
not compile time errors) are redirected to file \f(CWmiralog/prog\fP,
where \f(CWprog\fP is the name of the script.
The redirection takes place if a \f(CWmiralog\fP
directory exists in the current working directory and the process
running the script has write permission to it. This is useful for
debugging cgi scripts written in Miranda, particularly in the not
infrequent situation that they compile without errors and seem to work
fine from the command line but fail when invoked by an http call. (You
will need to create a directory miralog in cgi-bin and chown it to
apache, or whatever personality cgi scripts run as).
.SH 3
Second method (using a `here document')
.LP
Create a file (\f(CW"prog"\fP say) containing the following
.XE
    mira [script] <<!
    exp1
    exp2
    .
    .
    .
    !
.XX
The \f(CW!\fP after \f(CW<<\fP can be replaced by any character sequence \- the same
sequence, on a line by itself, terminates the `here document'.
.LP
Remember to make the file executable (by saying \f(CWchmod +x prog\fP).
Now when \f(CWprog\fP is executed as a UNIX command, the result will be that the
Miranda expressions \f(CWexp1\fP, \f(CWexp2\fP \f(CW...\fP will be evaluated in
the environment defined by \f(CWscript\fP, and the results sent to the standard
output. As usual, if \f(CWscript\fP is omitted, a default name \f(CWscript.m\fP
is assumed. The text following the special redirection \f(CW<<!\fP is called a
\(lqhere-document\(rq.
The contents of the here-document are fed to the \f(CWmira\fP
command in place of its standard input. (So anything you would type to
the Miranda system at top level can appear in the here document.)
.LP
Here-documents are a normal feature of UNIX, not something special to
Miranda. Miranda's only contribution to making this work smoothly is
that it detects when its input is not coming from a terminal, and in
this case suppresses prompts and other extraneous feedback. Note also
that lines beginning \f(CW||\fP are ignored by the Miranda command
interpreter, which gives a way to include comments in the text of the
here-document.
.LP
The program \f(CWprog\fP might be invoked with one or more arguments, for
example,
.XE
    prog big 23
.XX
In the here-document, \f(CW$1\fP can be used to denote the first argument,
\f(CW$2\fP the second and so on \- in this case \f(CWbig\fP and \f(CW23\fP respectively
will be textually substituted for these before the here-document is fed
to mira as input. Arguments not present are replaced by empty text.
Other replacements carried out on the text of the here-document are -
\f(CW$*\fP is replaced by all the arguments together, as a single piece of
text, \f(CW$#\fP is replaced by the number of arguments present (\f(CW2\fP in the
case shown above), and \f(CW$0\fP is replaced by the name of the program being
executed (in this case \f(CWprog\fP).
.LP
If the here-document contains instances of \f(CW$\fP which you don't want
replaced by something (for example inside a Miranda string), you have to
escape them by preceding them with a backslash character. But if the
delimiter after the \f(CW>>\fP is in quotation marks, e.g.
.XE
    mira [script] <<"!"
    stuff
    !
.XX
then no substitutions will take place inside the here-document.
.LP
The drawbacks of commands built in this way are two:
.IP (a)
they have no way of taking information from the terminal during execution
(because the here-document replaces the standard input) and
.IP (b)
the method of access to command line arguments is clumsy.
.SH 2
31/5. How to change the default editor
.LP
The Miranda \f(CW/edit\fP or \f(CW/e\fP command (see manual page on Miranda command
interpreter) invokes an editor. By default this is the screen editor
"vi", but if you wish to use another editor, this is easily changed.
.LP
The Miranda command
.XE
    /editor
.XX
reports the editor currently in use by the Miranda system. To change it
to (for example) pico, say
.XE
    /editor pico
.XX
Alternatively, when next invoking the Miranda system from UNIX you can
supply it with a flag requesting a specific editor by name, as follows:
.XE
    mira -editor pico
.XX
In either case it is only necessary to do this once since the Miranda
system stores this and other information in a file called \f(CW.mirarc\fP in
your home directory \- you should not remove or try to edit this file.
.LP
You can select any editor that is installed on your system. If you are
unfamiliar with \f(CWvi\fP and haven't an editor in mind,
the editor \f(CWpico\fP (if installed) is particularly easy to use \-
it has instructions on screen.
Similar are \f(CWnano\fP (an open source clone of \f(CWpico\fP) and \f(CWjoe\fP.
Other editors include \f(CWemacs\fP and \f(CWgvim\fP \- these both
open a separate editor window.
.LP
The editor you select will be used by both the \f(CW/e\fP command and by
.XE
    ??identifier
.XX
which opens the relevant source file at the definition of identifier.
.SH 3
More advanced information
.LP
The Miranda system is designed to work with an editor which can open a
file at a specified line number. For example to make the editor \f(CWvi\fP
open \f(CWfile\fP at line 13, the UNIX command is
.XE
    vi +13 file
.XX
The Miranda system has built in knowledge of this, so if the installed
editor is \f(CWvi\fP and the compiler has found a syntax error in the script,
the \f(CW/e\fP command will open the script at the line containing the error.
.LP
To retain this ability when substituting another editor, the \f(CW/editor\fP
command requires a template for invoking the chosen editor at a given
line number. In this template the line number is represented by the
character \f(CW!\fP and the filename by \f(CW%\fP. For example the full template
for \f(CWvi\fP would be supplied as follows
.XE
    /editor vi +! %
.XX
If the \f(CW%\fP character does not occur in the template, Miranda will add
the name of the file at the end of the command. So the template for \f(CWvi\fP
could equally well be given as
.XE
    /editor vi +!
.XX
The same formula works for \f(CWpico\fP, \f(CWnano\fP, \f(CWjoe\fP. If the editor is one that
starts up its own window, separate from the Miranda session window (\f(CWgvim\fP
and \f(CWemacs\fP do this), you will want to make the editor run as a concurrent
process by putting \f(CW&\fP at the end of the command, thus
.XE
    /editor emacs +! % &
.XX
Note that in this case you must include \f(CW%\fP where the filename goes,
because adding it after the \f(CW&\fP would not make sense.
.LP
In fact Miranda has built in knowledge of
\f(CWvi\fP, \f(CWpico\fP, \f(CWnano\fP, \f(CWjoe\fP, \f(CWemacs\fP and \f(CWgvim\fP,
so just giving the name of the editor will generate the correct
template in these cases.
.LP
If you install an editor without the capability to be opened at a
specified line number (i.e. you cannot give a template for it
containing the \f(CW!\fP character), the \f(CW/e\fP command loses its ability
to go to the right place after an error, and the \f(CW??\fP command
will be disabled.
.LP
The Miranda system will work without either of these features, but there
is a significant loss of power in the user interface.
.LP
If the installed editor lacks the `open at line number' feature, you may
find it convenient to have the script listed to the screen during
compilation (this feature of the compiler can be switched on and off by
the commands \f(CW/list\fP, \f(CW/nolist\fP). As an assistance to naive users,
the Miranda system turns on \f(CW/list\fP for you if the \f(CW/editor\fP
command is used to install an editor without the `open at line number' feature.
.LP
[Pathological case: if the editor command you wish to install contains a
literal \f(CW!\fP or \f(CW%\fP that you don't want replaced, place a backslash
before the relevant \f(CW!\fP or \f(CW%\fP.
This protects it from being expanded.]
.SH 3
Checking for source updates
.LP
If during a session changes have been made to any relevant source file,
the Miranda system automatically recompiles the current script and any
other scripts which it directly or indirectly \f(CW%include\fPs and which have
been changed. At a minimum this check is performed after each \f(CW/edit\fP
command and after each shell escape.
.LP
A mode of operation possible on a windowing system is to keep an editor
window and Miranda session window both open. In this case more frequent
checking is appropriate and you should say \f(CW/recheck\fP
(see 6 \fISummary of remaining commands\fP).
This sets a flag which tells the Miranda
interpreter to check for source file updates before each evaluation,
instead of only after \f(CW/e\fP and \f(CW!\fP commands.
But remember that you will need to save any edits to file before the
\f(CWmira\fP session can see them.
.LP
As an assistance to naive users, \f(CW/recheck\fP is automatically turned on if
\f(CW/editor\fP is used to install an editor template which includes \f(CW&\fP, the
symbol used in UNIX shell commands to start a concurrent process.
.LP
Say \f(CW/norecheck\fP to revert to the default behaviour.
.SH 2
31/6. How to alter the sizes of workspaces
.LP
The Miranda system uses two main internal workspaces called "heap" and
"dic". If either overflows during a session, a self explanatory error
message is given. The sizes of both areas may changed by the user if
required. Any change made is remembered thereafter and for subsequent
sessions until countermanded.
.LP
The heap contains almost all the data structures created both by the
Miranda compiler and the evaluation system. To compile and/or run very
large scripts you may need a bigger heap. To find out (change) the
current size of the heap say
.XE
    /heap           (or /heap newsize  e.g.   /heap 2000000 )
.XX
The heap size may also be altered by using a flag (see below).
You should be aware that running Miranda processes with a very large heap
may give you slower responses.
.LP
The dictionary is used to store identifiers and file names by the
Miranda compiler. It is unlikely that you will need to change the size
of the dictionary. The current size of the dictionary can be
ascertained by the command
.XE
    /dic
.XX
but it cannot be changed dynamically, from within the Miranda system.
To alter the dictionary size use a flag (see next para).
.LP
The sizes of either or both areas may be set by flags when invoking the
Miranda system. The following shows both possibilities
.XE
    mira -dic 80000 -heap 2000000 [script]
.XX
Note that the size of the heap is given in `cells' (a cell is 9 or 17 bytes
on 32 or 64-bit systems) and the size of the dictionary is in bytes.
.LP
The most recent settings of the workspace sizes are stored in the file
\f(CW.mirarc\fP in the users home directory, and automatically carried over to
the next Miranda session.
.SH 2
31/7. Options, setup files etc.
.LP
The full form of the \f(CWmira\fP command is
.XE
    mira [flags...] [script]
.XX
This command causes a Miranda session to be entered with the given file
as the current script. If no script is specified, a default filename
\f(CWscript.m\fP is assumed. The specified file need not yet exist \- in this
case you will be starting a Miranda session with an empty current
script.
.LP
Note that \f(CW.m\fP is the standard extension for Miranda language source
files \- the \f(CWmira\fP command always adds the \f(CW.m\fP extension,
if missing, to any filename argument denoting a Miranda script.
.LP
The available options are:
.SH 3
\f(CW-lib pathname\fP
.LP
Tells mira to find \f(CWmiralib\fP (directory containing libraries, manual pages
etc.) at \f(CWpathname\fP. The default is to look for \f(CWmiralib\fP of same
version number as the program at
\f(CW/usr/lib/miralib\fP, \f(CW/usr/local/lib/miralib\fP and \f(CW./miralib\fP,
in that order. The \f(CW-lib\fP flag overrides the version number check.
The same effect is obtained by setting an environment
variable \f(CWMIRALIB\fP, see next manual section.
.SH 3
\f(CW-gc\fP
.LP
Switches on a flag causing the garbage collector to print information
each time a garbage collection takes place. This flag can also be
switched on and off from within the Miranda session by the commands
\f(CW/gc\fP, \f(CW/nogc\fP.
.SH 3
\f(CW-count\fP
.LP
Switches on a flag causing statistics to be printed after each
expression evaluation. This flag can also be switched on and off from
within the Miranda session by the commands \f(CW/count\fP, \f(CW/nocount\fP.
.SH 3
\f(CW-list\fP / \f(CW-nolist\fP
.LP
Switches on (off) a flag causing Miranda scripts to be listed to the
screen during compilation. This flag can also be switched on and off
from within the Miranda session by the commands \f(CW/list\fP, \f(CW/nolist\fP.
.SH 3
\f(CW-nostrictif\fP
.LP
Enables the compiler to accept old Miranda scripts with missing
occurrences of the keyword \f(CWif\fP in guard syntax. Probably obsolete but
retained just in case someone needs it.
.SH 3
\f(CW-hush\fP / \f(CW-nohush\fP
.LP
The Miranda system decides whether or not to give prompts and other
feedback by testing its standard input with \f(CWisatty()\fP. If the standard
input does not appear to be a terminal it assumes that prompts would be
inappropriate, otherwise it gives them. In either case this behaviour
can be overriden by an explicit flag (\f(CW-hush\fP for silence,
\f(CW-nohush\fP for prompts etc).
This switch is also available from within a Miranda
session by the commands \f(CW/hush\fP, \f(CW/nohush\fP.
.SH 3
\f(CW-dic SIZE\fP
.LP
Causes the dictionary (used by the compiler to store identifiers etc.)
to be set up with \f(CWSIZE\fP bytes instead of the default 100kb.
.SH 3
\f(CW-heap SIZE\fP
.LP
Causes the heap to be set up with SIZE cells instead of the default
(currently 2,500,000). This can also be done from within the Miranda session
by the command \f(CW/heap SIZE\fP. A cell currently occupies 9/17 bytes on a
32/64-bit system.
.SH 3
\f(CW-editor name\fP
.LP
Causes the resident editor (initially \f(CWvi\fP, unless the environment
variable \f(CWEDITOR\fP was set to something else) to be \f(CWname\fP instead. This
can also be done from within the Miranda session by the command \f(CW/editor name\fP.
.SH 3
\f(CW-UTF-8\fP / \f(CW-noUTF-8\fP
.LP
Assume the current locale is (is not) UTF-8 overriding environment vars
(version 2.044 and later).
.SH 3
\f(CW-stdenv\fP
.LP
Run \f(CWmira\fP without loading the standard environment. Every script that
needs functions from the standard environment will then have to either
explicitly \f(CW%include <stdenv>\fP or define the required functions for
itself. Not recommended as normal practice since it may have unexpected
consequences (for example I/O will be limited by the absence of type
\f(CWsys-message\fP).
.SH 3
\f(CW-object\fP
.LP
Used for debugging the compiler. Modifies behaviour of \f(CW?identifier(s)\fP
to show the associated combinator code, which may or may not be
comprehensible as there is no documentation other than the source code.
.SH 2
Special Calls
.LP
In addition the following special calls to \f(CWmira\fP are available which
do not enter a Miranda session but accomplish another purpose, as
described below.
.SH 3
\f(CWmira -man\fP
.LP
To enter the Miranda online manual system directly from the UNIX shell.
.SH 3
\f(CWmira -exp\fP
.LP
Special call permitting the use of Miranda script as a stand-alone UNIX
command. See separate manual page for details.
.SH 3
\f(CWmira -log\fP
.LP
Same as \f(CW-exp\fP except that it redirects stderr to a file \f(CWlog/mira.errors\fP,
if \f(CWlog\fP directory exists in the current directory and \f(CWmira\fP has write
permission to it.
.SH 3
\f(CWmira -make [sourcefiles]\fP
.LP
Forces a check that all the Miranda source files listed have up-to-date
object code files, triggering compilation processes if necessary (see
manual subsection on the library mechanism: separate compilation).
.SH 3
\f(CWmira -exports [sourcefiles]\fP
.LP
Sends to stdout a list of the identifiers exported (see manual
subsection on library mechanism: separate compilation) from each of the
given Miranda source files, together with their types (may also force
recompilation if needed).
.SH 3
\f(CWmira -sources [sourcefiles]\fP
.LP
Sends to stdout a list of all the Miranda source files on which the
given source files directly or indirectly depend (via \f(CW%include\fP or
\f(CW%insert\fP statements), excluding the standard environment <stdenv>.
.SH 3
\f(CWmira -version\fP
.LP
Gives version information. This information can also be obtained from
within a Miranda session by the command \f(CW/version\fP.
.SH 3
\f(CWmira -V\fP
.LP
More detailed version information.
.SH 2
Setup Files
.LP
The current settings of \f(CWdic\fP, \f(CWheap\fP and \f(CWeditor\fP are saved in the file
\f(CW.mirarc\fP in the users home directory, and are thereby carried over to
the next Miranda session. The settings of the compiler flag which
controls whether or not source is listed to the screen during
compilation (toggled by the commands \f(CW/list\fP and \f(CW/nolist\fP during a Miranda
session) and of the flag which controls the frequency of checking for
source updates (toggled by the commands \f(CW/recheck\fP and \f(CW/norecheck\fP) are also
saved in the users \f(CW.mirarc\fP file.
.LP
The default settings of these entities, which will be picked up by new
users executing \f(CWmira\fP for the first time, are dic 100000 (bytes), heap
2500000 (9/17-byte cells), editor \f(CWvi\fP, nolist, norecheck. The current
settings can be interrogated from a Miranda session by the command
\f(CW/settings\fP or \f(CW/s\fP.
.LP
The defaults can be changed, on a system wide basis, by moving a copy of
a \f(CW.mirarc\fP file containing the desired settings into the \f(CWmiralib\fP
directory (normally found at \f(CW/usr/lib/miralib\fP). The user's local
\f(CW.mirarc\fP file, once created in his home directory by the first call to
mira, will override the global one, however.
.LP
The behaviour of the \f(CWmira\fP program is also sensitive to the settings of
certain environment variables \- see section 31/8.
.SH 3
Output Buffering
.LP
Output from the Miranda system to the user's terminal should not be
line buffered, or some things will not work as they are intended.
There is no problem about input being line buffered, however.
.SH 2
31/8. Environment variables used by Miranda
.LP
(This section may be of particular interest to installers and system
administrators)
.LP
The behaviour of the \f(CWmira\fP program is sensitive to the settings of
certain environment variables.
.LP
An alternative location for the miralib directory may be specified by
setting the environment variable \f(CWMIRALIB\fP. An explicit \f(CW-lib\fP flag, if
present, overrides this.
.LP
The first time it is called (i.e. if no \f(CW.mirarc\fP file is present, either
in the home directory or in miralib) the Miranda system picks up the
name of the resident editor from the environment variable \f(CWEDITOR\fP \- if
this is not set it assumes \f(CWvi\fP.
.LP
At startup (version 2.044 and later) \f(CWmira\fP inspects \f(CWLC_CTYPE\fP or if that
is empty \f(CWLANG\fP, to determine if it is running in a UTF-8 locale. On
Windows/Cygwin this information is taken from the "user-default ANSI
code page". The flag \f(CW-UTF-8\fP or \f(CW-noUTF-8\fP, if present, overrides.
.LP
If the environment variable \f(CWRECHECKMIRA\fP is set (to any non-empty string)
the Miranda system rechecks to see if any relevant source files have
been updated, and performs any necessary recompilation, before each
interaction with the user \- this is the appropriate behaviour if an
editor window is being kept open permanently during the Miranda
session. If this environment variable is not set, the check is
performed only after \f(CW/e\fP commands and \f(CW!\fP escapes.
.LP
To decide what shell to use in \f(CW!\fP escapes, \f(CWmira\fP looks in the
environment variable \f(CWSHELL\fP (this will normally contain the name of the
user's login shell). If no \f(CWSHELL\fP is entered in the environment, \f(CW/bin/sh\fP
is assumed.
.LP
If environment variable \f(CWMIRAPROMPT\fP is set, its contents will be used as
the session prompt, instead of the default prompt \f(CWMiranda \fP (version
2.044 and later).
.LP
If the environment variable \f(CWNOSTRICTIF\fP is set (to any non-empty string)
Miranda accepts old scripts with no \f(CWif\fP after the guard comma.
.LP
For displaying pages of the manual, \f(CWmira\fP uses the program entered in the
environment as \f(CWVIEWER\fP \- if this variable is not set the default is
likely to be \f(CWmore\ -d\fP or (roughly equivalent) \f(CWless\ -EX\fP.
.LP
If you set \f(CWVIEWER\fP to something, you may also need to set an environment
variable \f(CWRETURNTOMENU\fP.
.LP
\f(CWRETURNTOMENU=YES\fP prevents another prompt being given after displaying
each section, causing instead an immediate return to contents page. It
should be \f(CWYES\fP if \f(CWVIEWER\fP is a program that pauses for input at end of
file (e.g. \f(CWless\fP), \f(CWNO\fP if \f(CWVIEWER\fP is a program that quits silently at end
of file (e.g. \f(CWmore\fP, \f(CWless -EX\fP).
.LP
Finally note that a third environment variable \f(CWMENUVIEWER\fP can be set to
choose the program used to display contents pages (by default this is
normally \f(CWcat\fP or \f(CWmore\fP).
.LP
To find the current settings of these display commands enter
.XE
    ???
.XX
to the \(lqnext selection\(rq prompt of the manual system.
.SH 3
How to set an environment variable in your UNIX shell:
.LP
(Reminder/tutorial information)
.LP
Example, setting the environment variable
\f(CWVIEWER\fP to \f(CW/usr/local/view\fP
.IP (i)
if you use a Bourne-like shell (sh ksh bash)
say at the UNIX command level (i.e. before calling Miranda)
.XE
    export VIEWER=/usr/local/view
.XX
to undo the above say \f(CWunset VIEWER\fP,
to make permanent add this line to your \f(CW.profile\fP or \f(CW.bashrc\fP
.IP (ii)
if you use a C shell (\f(CWcsh\fP, \f(CWtcsh\fP)
say at the UNIX command level (i.e. before calling Miranda)
.XE
    setenv VIEWER /usr/local/view
.XX
to undo the above say \f(CWunsetenv VIEWER\fP,
to make permanent add the setenv line to your \f(CW.login\fP or \f(CW.cshrc\fP
.SH 2
31/9 Input/output of binary data
.LP
From version 2.044 Miranda \f(CWstdenv.m\fP includes a function
.XE
    readb :: [char]->[char]
.XX
and new sys-message constructors
.XE
    Stdoutb     :: [char]->sys_message
    Tofileb     :: [char]->[char]->sys_message
    Appendfileb :: [char]->[char]->sys_message
.XX
These behave similarly to (respectively) \f(CWread\fP, \f(CWStdout\fP, \f(CWTofile\fP,
\f(CWAppendfile\fP but are needed in a UTF-8 locale for reading/writing binary
data (for further explanation see below). In a non UTF-8 locale they do
not behave differently from \f(CWread\fP, \f(CWStdout\fP etc but you might still prefer
to use them for handling binary data, for portability reasons.
.LP
The notation \f(CW$:-\fP is used for the binary version of the standard input.
In a non UTF-8 locale \f(CW$:-\fP and \f(CW$-\fP will produce the same results. It is
an error to access both \f(CW$:-\fP and \f(CW$-\fP in the same evaluation.
.SH 3
Explanation
.LP
The locale of a UNIX process is a collection of settings in the
environment which specify, among other things, what character encoding
is in use. To see this information use \f(CWlocale\fP as a shell command.
The analogous concept in Windows is called a \(lqcode page\(rq.
.LP
UTF-8 is a standard for encoding text from a wide variety of languages
as a byte stream, in which ASCII characters (codes 0..127) are
represented by themselves while other symbols are represented by a
sequence of two or more bytes: a `multibyte character'.
.LP
The Miranda type \f(CWchar\fP consists of characters in the range (0..255)
where the codes above 127 represent various accented letters etc.
according to the conventions of Latin-1 (i.e. ISO-8859-1, commonly used
for West European languages). There are national variants on Latin-1
but since Miranda source, outside comments and string and character
constants, uses only ASCII this does not normally cause a problem.
.LP
In a UTF-8 locale: on reading string/character literals or text files
Miranda has to translate multibyte characters to the corresponding point
in the Latin-1 range (128-255). If the text does not conform to the
rules of UTF-8, or includes a character not present in Latin-1, an
\(lqillegal character\(rq error occurs. On output, Miranda strings are
translated back to UTF-8.
.LP
If data being read/written is not text, but binary data of some kind,
translation from/to UTF-8 is not appropriate and could cause \(lqillegal
character\(rq errors, and/or corruption of data. Whence the need for the
byte oriented I/O functions readb etc, which transfer data without any
conversion from/to UTF-8.
.LP
In a non UTF-8 locale, \f(CWread\fP and \f(CWreadb\fP, \f(CWTofile\fP and \f(CWTofileb\fP, etc.
do not differ in their results.
.SH
32. Recent Changes
.SH 2
May 2025 (version 2.067)
.LP
The first maintenance release from \f(CWcodeberg.org/DATurner/miranda\fP
.SH 2
January 2020 (version 2.066)
.LP
The Miranda source code has been revised to conform to the C11 standard
and to run on both 64 and 32 bit platforms. Earlier releases were 32
bit only.
.SH 2
December 2019 (version 2.057)
.LP
Miranda type \f(CWchar\fP now includes all Unicode characters, which can be
specified by hexadecimal escape codes in char and string constants. For
example \f(CW\ex5d2\fP is the Hebrew letter Gimel.
.LP
The lexical syntax of Miranda has been extended to include octal and
hexadecimal numerals \- e.g. \f(CW0o777\fP is \f(CW511\fP and \f(CW0xffffffff\fP is \f(CW4294967295\fP.
.LP
See man section 11 (\fILiterals\fP) for details of both the above.
.LP
Functions \f(CWshowoct, showhex :: num->[char]\fP have been added to the
standard environment.
.LP
Data types with "laws", declared obsolete at release two, have finally
gone. Strictness annotations: \f(CW!\fP on fields of an algebraic data type
remain part of the language, see man section 20 (algebraic data types).
.LP
The flag \f(CW-exp\fP, for executable scripts, has gone and is replaced by
\f(CW-exec\fP, see man section 31/4: \fIUsing Miranda to build UNIX commands\fP.
This is not backwards compatible (sorry) but the change needed is
trivial. If you have a magic script
.XE
    #!/usr/bin/mira -exp
    expression
    definitions...
.XX
change it to
.XE
    #!/usr/bin/mira -exec
    main = expression
    definitions...
.XX
The new mechanism executes \f(CWmain\fP wherever it is in the script (whereas
\f(CW-exp\fP required an expression on the second line).
.SH 2
September 2009 (version 2.044)
.LP
The environment variable \f(CWMIRAPROMPT\fP may be set to a string to be used as
the Miranda session prompt instead of the default "\f(CWMiranda\fP".
.LP
For reading/writing binary files in UTF-8 locale, \f(CWstdenv\fP is extended by
.XE
    readb, Stdoutb, Tofileb, Appendfileb
.XX
these behave similarly to
.XE
    read, Stdout, Tofile, Appendfile
.XX
but transfer data as bytes with no conversions from/to UTF-8. See new
manual section 31/9.
.SH 2
August 2008 (version 2.041, 2.042)
.LP
Miranda now detects if it is in UTF-8 locale and converts from/to UTF-8
on reading/writing string and char values.
.SH 2
May 2006 (version 2.032)
.LP
The commands \f(CW/nostrictif\fP, \f(CW/strictif\fP to control enforcement of \f(CWif\fP in
guard syntax have gone. The \f(CWif\fP has been part of Miranda's syntax
since 1988. In case there are surviving if-less scripts, you can use
.XE
    mira -nostrictif
.XX
or set the environment variable \f(CWNOSTRICTIF\fP to any non-empty string.
.LP
New command \f(CW/recheck\fP makes mira check if any loaded script has been
updated before every evaluation, instead of only after \f(CW/edit\fP (\f(CW/norecheck\fP
to disable). Appropriate if an editor window is running concurrently
with the Miranda session window. The setting is remembered for
subsequent sessions. Formerly enabled by setting environment variable
\f(CWRECHECKMIRA\fP to a non-empty string \- that method still works also.
.LP
\f(CWmira\fP now checks that it has \f(CWmiralib\fP of same version number
and exits with an error message otherwise.
An explicit \f(CWmira -lib <path>\fP overrides this but it is in general
inadvisable to run \f(CWmira\fP with the wrong \f(CWmiralib\fP.
.SH 2
History of Miranda releases
.LP
1 May 1985 \- alpha test, released to University of Kent only.
.LP
October 1985 \- beta test (version 0.292 for VAX, 0.293 for SUN)
Distributed to 88 sites.
.LP
April 1987 \- release one (version 1.009 or 1.016 or 1.019)
Added literate scripts, library mechanism: \f(CW%export\fP, \f(CW%include\fP,
\f(CW(n+k)\fP patterns.
Around 250 sites.
.LP
October 1989 \- release two (versions 2.0xx for various machines)
Added unbounded size integers, \f(CW%free\fP, faster SK reduction machine.
Around 550 sites by mid-90's.
.LP
May 2006 \- revised and released as free software (but not open source).
.LP
Nov 2019 \- revised and made open source.
.LP
Jan 2020 \- revised to C11 standard and made 64 bit compatible.
.SH
33. License
.LP
The Miranda system is Copyright (c) Research Software Limited, 1985-2019
and is distributed under an open source license. For terms see the file
COPYING in the miralib directory.
.SH
34. Bug Reports
.LP
Bug reports should be sent to
.XE
    miranda@groups.io
.XX
First check below, however, in case it is already known. Also check the
downloads section at \f(CWcodeberg.org/DATurner/miranda\fP
in case there is a new version of
Miranda in which your bug may be fixed. When sending a bug report,
please state the version number of your Miranda system and the platform
that it is running on.
.LP
The error messages from the Miranda system are mostly self explanatory.
Note, however, that messages of the form \f(CWimpossible event\fP or
similar indicate that the internal state of the system has become
corrupted. This should be reported as a bug. Segmentation faults also
falls into this category.
.LP
First check if the problem only occurs following a garbage collection.
Garbage collector reports can be turned on by \f(CWmira -gc\fP from the
command line or by \f(CW/gc\fP within a Miranda session. If your error does
appear to be associated with garbage collection you can try running with
a bigger heap and/or getting mira recompiled at a lower level of
optimisation (e.g. \f(CW-O\fP instead of \f(CW-O2\fP, or without \f(CW-O\fP). Miranda uses a
\(lqconservative collector\(rq which scans the C stack to follow things that
are, or appear to be, pointers into the heap. Unfortunately this is
vulnerable to compiler optimisations affecting the state of the stack.
.LP
Even if the problem does appear to be GC-related it is still worth
reporting.
.LP
The source code, orginally written for 32 bit platforms, has been
extensively revised and tested for 64 bit compatibility. It is quite
possible that some hidden \(lqinteger width\(rq problems remain in the code
and will be discovered in use.
.SH 2
List of known bugs, deficiencies, and unimplemented features
.LP
If there is not enough heap to compile the current script, \f(CWmira\fP exits
after reporting this fact. The fix is to increase the heap size:
.XE
    mira -heap N [filename]
.XX
where \f(CWN\fP is a bigger number than you had before.
.LP
It is not currently permitted to give a type specification for an
identifier defined locally, as part of a \f(CWwhere\fP clause. That is (see
formal syntax) \f(CWspec\fP is not allowed after \f(CWwhere\fP.
.LP
When abstract objects are tested for equality or order (under \f(CW<\fP, \f(CW<=\fP etc)
the result is that obtained by applying the operation to the underlying
representation type. In some cases this will be what you want, but in
others it will be wrong \- there ought to be a way of controlling this.
.LP
The standard input cannot be accessed both as a list of characters (with
\f(CW$-\fP) and as a list of values (with \f(CW$+\fP) at the same time. If \f(CW$+\fP is in
use, an occurrence of \f(CW$-\fP will evaluate to \f(CW[]\fP, and vice versa. This is
not referentially transparent \- uses of \f(CW$+\fP and \f(CW$-\fP ought to share data.
.LP
Scripts with multiple occurrences of \f(CW$+\fP also behave opaquely \- each
occurrence of \f(CW$+\fP reads from the terminal independently, and they do not
share data with each other. (Multiple occurrences of \f(CW$+\fP in a single
command-level expression behave transparently, however.)
.LP
There is a subtle issue concerning \f(CWshow\fP and \f(CW%export\fP.
If you define a function which, internally, uses \f(CWshow\fP on an object
of algebraic type,
and then \f(CW%export\fP that function to another scope, the format used by the
\f(CWshow\fP depends on the status of the algebraic type in the NEW scope.
Thus if the type has been aliased the new constructor names will be
used, and if the algebraic type is no longer in scope, it will show as
\f(CW<unprintable>\fP (this latter case can arise if an abstract type based on
the algebraic type is exported, and one of the signature identifiers
invokes \f(CWshow\fP on the base type). Although this behaviour is
defensible, it might be better for each use of \f(CWshow\fP at algebraic type
to be frozen to use the constructor names in the scope where it occurs.
[An analogous issue arises with \f(CWreadvals\fP.]
.SH 2
Implementation restrictions not mentioned elsewhere in the manual
.LP
A shell command called from \f(CWmira\fP using \f(CW!\fP is limited to
1024 characters in length after any implied expansions (e.g. of \f(CW%\fP)
have been performed.
The same restriction applies to the result of expanding out a \f(CW/e\fP
command. The pathnames of Miranda scripts are limited to 1024
characters in length, including the \f(CW.m\fP extension. The name of the
editor supplied for the \f(CW/e\fP command, and the absolute pathnames of the
\f(CWmiralib\fP directory, and of the user's home directory, are also each
limited to 1024 characters in length.
.LP
The name of a Miranda script may not contain spaces (but directory names
with spaces are allowed in pathnames).
