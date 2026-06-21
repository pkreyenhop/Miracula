const std = @import("std");
const word = @import("../runtime/word.zig");
const main = @import("../main.zig");
const clib = @import("../runtime/main_clib.zig");
const lex_state = @import("../parser/lex_state.zig");
const ls = &lex_state.ls;

const Word = main.Word;
const NIL = main.NIL;
const t = main.heap.t;
const h = main.heap.h;
const tp = main.heap.tp;
const hp = main.heap.hp;
extern var tag: [*]u8;

/// Heap list of identifiers hidden from the exported interface (privatised).
/// Populated by fixexports(); cleared by unfixexports().
pub export var internals: Word = NIL;
/// Heap list of types that are needed by the current script but have no name in scope.
/// Non-NIL after readoption() means the dump cannot be used and type errors will be reported.
pub export var tlost: Word = NIL;
var pfrts: Word = NIL;

/// Marks all exported identifiers and privatises the rest.
/// Must be paired with a call to unfixexports() once the dump is written.
pub fn fixexports() void {
    var e = main.rs.exports;
    var f: Word = undefined;
    while (e != NIL) : (e = t(e)) {
        paint(h(e));
    }
    internals = NIL;
    if (main.rs.exports == NIL and ls.exportfiles == NIL and main.rs.embargoes == NIL) {
        e = main.rs.freeids;
        while (e != NIL) : (e = t(e)) {
            internals = main.cons(privatise(h(h(e))), internals);
        }
        f = t(main.files);
        while (f != NIL) : (f = t(f)) {
            var e_def = main.fil_defs(h(f));
            while (e_def != NIL) : (e_def = t(e_def)) {
                if (tag[@intCast(h(e_def))] == clib.ID) {
                    internals = main.cons(privatise(h(e_def)), internals);
                }
            }
        }
    } else {
        f = main.files;
        while (f != NIL) : (f = t(f)) {
            var e_def = main.fil_defs(h(f));
            while (e_def != NIL) : (e_def = t(e_def)) {
                if (tag[@intCast(h(e_def))] == clib.ID and unpainted(h(e_def))) {
                    internals = main.cons(privatise(h(e_def)), internals);
                }
            }
        }
    }
    e = main.rs.exports;
    while (e != NIL) : (e = t(e)) {
        unpaint(h(e));
    }
}

fn paint(x: Word) void {
    tp(x).* = clib.ap(clib.EXPORT, main.id_val(x));
}

fn unpainted(x: Word) bool {
    const v = main.id_val(x);
    return tag[@intCast(v)] != clib.AP or h(v) != clib.EXPORT;
}

fn unpaint(x: Word) void {
    tp(x).* = t(main.id_val(x));
}

/// Reverses the privatisation done by fixexports(), restoring all `internals` to public.
/// No-op when `rs.mkexports != 0` (the dump is being kept for distribution).
pub fn unfixexports() void {
    var i = internals;
    if (main.rs.mkexports) return;
    while (i != NIL) : (i = t(i)) {
        _ = publicise(h(i));
    }
    internals = NIL;
}

fn privatise(x: Word) Word {
    const n = clib.make_pn(x);
    const hash_idx = hash(main.get_id(x));
    const i = h(n);

    if (main.id_type(x) == clib.type_t) {
        tp(main.t_info(x)).* = main.cons(clib.datapair(@as(Word, @intCast(@intFromPtr(clib.getaka(x)))), 0), main.get_here(x));
    }

    if (main.id_val(x) == clib.UNDEF) {
        tp(x).* = clib.ap(clib.datapair(@as(Word, @intCast(@intFromPtr(clib.getaka(x)))), 0), main.get_here(x));
    }

    ls.pnvec.?[@as(usize, @intCast(i))] = x;
    tag[@intCast(n)] = clib.ID;
    hp(n).* = h(x);
    tag[@intCast(x)] = clib.STRCONS;
    hp(x).* = i;

    const current_bucket = ls.namebucket[hash_idx];
    if (h(current_bucket) == x) {
        hp(current_bucket).* = n;
    } else {
        var prev = current_bucket;
        var curr = t(current_bucket);
        while (curr != NIL) {
            if (h(curr) == x) {
                hp(curr).* = n;
                break;
            }
            prev = curr;
            curr = t(curr);
        }
    }
    return n;
}

fn hash(s: [*:0]const u8) usize {
    return (@as(usize, s[0]) + @as(usize, s[word.strlen(s) - 1])) & 127;
}

fn publicise(x: Word) Word {
    const i = main.id_val(x);
    const hash_idx = hash(main.get_id(x));

    tag[@intCast(i)] = clib.ID;
    hp(i).* = h(x);

    const val = t(i);
    if (tag[@intCast(val)] == clib.AP and tag[@intCast(h(val))] == clib.DATAPAIR) {
        tp(i).* = clib.UNDEF;
    }

    const current_bucket = ls.namebucket[hash_idx];
    if (h(current_bucket) == x) {
        hp(current_bucket).* = i;
    } else {
        var prev = current_bucket;
        var curr = t(current_bucket);
        while (curr != NIL) {
            if (h(curr) == x) {
                hp(curr).* = i;
                break;
            }
            prev = curr;
            curr = t(curr);
        }
    }
    return i;
}

/// Signal handler that defers delivery by setting `rs.sigflag`.
/// Installed during dump I/O so that SIGINT cannot corrupt the dump file mid-write.
pub fn sigdefer(_: c_int) callconv(.c) void {
    main.rs.sigflag = 1;
}

/// Repairs type references after loading a dump: re-resolves STRCONS nodes and
/// reports types that are in the dump but missing from the current scope (`tlost`).
pub export fn readoption() void {
    var f: Word = undefined;
    var t_val: Word = undefined;

    pfrts = NIL;
    tlost = NIL;

    if (main.cs.FBS != NIL) {
        f = main.cs.FBS;
        while (f != NIL) : (f = t(f)) {
            t_val = t(h(f));
            while (t_val != NIL) : (t_val = t(t_val)) {
                if (tag[@intCast(h(h(t_val)))] == clib.STRCONS and t(t(h(h(t_val)))) == clib.type_t) {
                    pfrts = main.cons(h(h(t_val)), pfrts);
                }
            }
        }
    }

    var rfl_ptr = main.rs.rfl;
    while (rfl_ptr != NIL) : (rfl_ptr = t(rfl_ptr)) {
        f = main.fil_defs(h(rfl_ptr));
        while (f != NIL) : (f = t(f)) {
            if (tag[@intCast(h(f))] == clib.ID) {
                t_val = main.id_type(h(f));
                if (t_val == clib.type_t) {
                    if (main.t_class(h(f)) == clib.synonym_t) {
                        tp(main.t_info(h(f))).* = fixtype(main.t_info(h(f)), h(f));
                    }
                } else {
                    tp(h(h(f))).* = fixtype(t_val, h(f));
                }
            }
        }
    }

    if (tlost == NIL) return;
    main.cs.TYPERRS += 1;
    word.print("main.cs.MISSING TYPENAME{s}\n", .{if (t(tlost) == NIL) "" else "S"});
    word.print("the following type{s} no name in this scope:\n", .{if (t(tlost) == NIL) " is needed but has" else "s are needed but have"});
    while (tlost != NIL) {
        word.print("\'{s}\' of file \"{s}\", needed by: ", .{ @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(h(main.t_info(h(h(tlost))))))))), @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(t(main.t_info(h(h(tlost))))))))) });
        clib.printlist(@constCast(""), main.alfasort(t(h(tlost))));
        tlost = t(tlost);
    }
}

/// Resolves STRCONS type nodes to their canonical ID form when loading a dump.
/// Adds unresolvable types to `tlost` for deferred error reporting.
pub fn fixtype(t_val: Word, x: Word) Word {
    switch (tag[@intCast(t_val)]) {
        clib.AP, clib.CONS => {
            tp(t_val).* = fixtype(t(t_val), x);
            hp(t_val).* = fixtype(h(t_val), x);
            return t_val;
        },
        clib.STRCONS => {
            if (clib.member(pfrts, t_val) != 0) {
                return t_val;
            }
            var cur_t = t_val;
            while (tag[@intCast(pn_val(cur_t))] != clib.CONS) {
                cur_t = pn_val(cur_t);
            }
            if (tag[@intCast(cur_t)] != clib.ID) {
                var w = tlost;
                while (w != NIL and h(h(w)) != cur_t) {
                    w = t(w);
                }
                if (w == NIL) {
                    tlost = main.cons(main.cons(cur_t, main.cons(x, NIL)), tlost);
                    w = tlost;
                }
                tp(h(w)).* = clib.add1(x, t(h(w)));
            }
            return cur_t;
        },
        else => return t_val,
    }
}

inline fn pn_val(x: Word) Word {
    return t(x);
}

/// Loads `t_val` from its pre-compiled dump file (.mx suffix) if the dump is newer
/// than the source, otherwise falls back to `loadfile()`. Handles the case where
/// the source does not exist (initialising-only panic) or the dump is missing/stale.
pub fn undump(t_val: [*:0]const u8) void {
    var obf: [clib.pnlim]u8 = undefined;
    var f: ?*clib.FILE = null;
    var flen: Word = undefined;
    var t1: clib.time_t = undefined;
    var t2: clib.time_t = undefined;
    var oldsig: usize = 0;

    if (main.normal(t_val) == 0 and main.rs.initialising == 0) {
        main.loadfile(t_val);
        return;
    }

    flen = @intCast(word.strlen(t_val));
    t1 = @intCast(main.fm_time(t_val));
    if (flen > clib.pnlim) {
        word.print("sorry, pathname too long (limit={}): {s}\n", .{ clib.pnlim, std.mem.span(t_val) });
        return;
    }

    _ = word.strcpy(&obf, t_val);
    _ = word.strcpy(obf[@intCast(flen - 1)..].ptr, main.obsuffix);
    t2 = @intCast(main.fm_time(@as([*:0]const u8, @ptrCast(&obf))));
    if (t2 != 0 and t1 == 0) {
        t2 = 0;
        _ = clib.unlink(@as([*:0]const u8, @ptrCast(&obf)));
    }
    if (t2 == 0 or t2 < t1) {
        main.loadfile(t_val);
        return;
    }

    f = clib.fopen(&obf, "r");
    if (f == null) {
        word.print("cannot open {s}\n", .{std.mem.span(@as([*:0]const u8, @ptrCast(&obf)))});
        main.loadfile(t_val);
        return;
    }

    main.rs.current_script = @constCast(t_val);
    main.loading = 1;
    main.rs.oldfiles = NIL;
    main.unload();

    if (main.rs.initialising == 0 and !main.rs.making) {
        main.rs.sigflag = 0;
        oldsig = main.signals(clib.SIGINT, @intFromPtr(&sigdefer));
    }

    main.files = clib.load_script(f.?, @constCast(t_val), NIL, NIL, if (!main.rs.making and main.rs.initialising == 0) 1 else 0);
    _ = clib.fclose(f.?);

    if (main.cs.BAD_DUMP != 0) {
        _ = clib.unlink(@as([*:0]const u8, @ptrCast(&obf)));
        main.unload();
        main.cs.CLASHES = NIL;
        main.stackp = main.dstack;
        word.print("warning: {s} contains incorrect data (file removed)\n", .{std.mem.span(@as([*:0]const u8, @ptrCast(&obf)))});
        if (main.cs.BAD_DUMP == -1) {
            word.print("(unrecognised dump format)\n", .{});
        } else if (main.cs.BAD_DUMP == 1) {
            word.print("(wrong source file)\n", .{});
        } else {
            word.print("(error {})\n", .{main.cs.BAD_DUMP});
        }
    }

    if (main.rs.initialising == 0 and !main.rs.making) {
        _ = main.signals(clib.SIGINT, oldsig);
    }
    if (main.rs.sigflag != 0) {
        main.rs.sigflag = 0;
        if (oldsig > 1) {
            const handler: *const fn (c_int) callconv(.c) void = @ptrFromInt(oldsig);
            handler(clib.SIGINT);
        }
    }

    if (main.cs.CLASHES != NIL) {
        if (main.rs.ideep == 0) {
            word.print("cannot load {s} ", .{std.mem.span(@as([*:0]const u8, @ptrCast(&obf)))});
            clib.printlist(@constCast("due to name clashes: "), main.alfasort(main.cs.CLASHES));
        }
        main.unload();
        main.loading = 0;
        return;
    }

    if (main.cs.BAD_DUMP != 0 or main.src_update() != 0) {
        main.loadfile(t_val);
    } else if (main.rs.initialising != 0) {
        if (main.cs.ND != NIL or main.files == NIL) {
            main.fatal("panic: %s contains errors\n", .{.{@as([*:0]const u8, @ptrCast(&obf))}});
        }
    } else {
        if (main.rs.verbosity != 0 or main.rs.magic or main.rs.mkexports) {
            if (main.files == NIL) {
                word.print("{s} contains syntax error\n", .{std.mem.span(t_val)});
            } else {
                if (main.cs.ND != NIL) {
                    word.print("{s} contains undefined names or type errors\n", .{std.mem.span(t_val)});
                } else if (!main.rs.making and !main.rs.magic) {
                    word.print("{s}\n", .{std.mem.span(t_val)});
                }
            }
        }
    }

    if (main.files != NIL and !main.rs.making and main.rs.initialising == 0) {
        unfixexports();
    }
    main.loading = 0;
}

/// Writes a binary dump of the current heap state to the .mx file corresponding to
/// `rs.current_script`. Installs `sigdefer` during the write so a SIGINT cannot
/// leave a partial dump; re-raises any deferred signal afterward.
pub fn makedump() void {
    const obf = &main.rs.linebuf;
    var f: ?*clib.FILE = null;
    _ = word.strcpy(obf, main.rs.current_script.?);
    const len = word.strlen(obf);
    _ = word.strcpy(obf[len - 1 ..].ptr, main.obsuffix);
    f = clib.fopen(obf, "w");
    if (f == null) {
        word.print("WARNING: CANNOT WRITE TO {s}\n", .{std.mem.span(@as([*:0]const u8, @ptrCast(obf)))});
        if (word.strcmp(main.rs.current_script.?, &main.rs.PRELUDE) == 0 or word.strcmp(main.rs.current_script.?, &main.rs.STDENV) == 0) {
            word.print("TO FIX THIS PROBLEM PLEASE GET SUPER-USER TO EXECUTE `mira'\n", .{});
        }
        if (main.rs.making and main.rs.make_status == 0) {
            main.rs.make_status = 1;
        }
        return;
    }
    main.rs.unlinkme = @ptrCast(obf);
    clib.setprefix(main.rs.current_script.?);
    clib.dump_script(main.files, f.?);
    main.rs.unlinkme = null;
    _ = clib.fclose(f.?);
}

test "dump NIL sentinel is consistent" {
    try std.testing.expectEqual(main.NIL, NIL);
}
