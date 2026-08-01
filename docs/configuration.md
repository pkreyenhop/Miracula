# Miranda configuration precedence

The Go Miranda command resolves configuration in this order, with later
sources overriding earlier ones:

1. compiled defaults and the library installed beside the executable;
2. the installation-wide `<miralib>/.mirarc`;
3. environment (`MIRALIB`, `EDITOR`, and locale variables);
4. the user's `$HOME/.mirarc`;
5. one-session environment controls (`MIRAPROMPT`, `RECHECKMIRA`, and
   `NOSTRICTIF`);
6. command-line flags.

Only the historical sticky settings are written to `$HOME/.mirarc`: heap and
dictionary capacities, editor template, source listing, and automatic
rechecking. Prompt, counting, GC reporting, hush mode, UTF-8 override,
strict-if compatibility, object display, and library overrides remain local to
the current invocation.

`SHELL` selects the shell for escapes and system commands. The built-in manual
pager intentionally replaces external `VIEWER` and `MENUVIEWER` programs; its
effective compatibility settings are shown by entering `???` in a manual menu.

The production Go release supports macOS only. Historical manual statements
about the earlier C implementation's Linux and other Unix targets remain
historical facts and do not describe support for this Go cutover.
