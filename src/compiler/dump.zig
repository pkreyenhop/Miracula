const std = @import("std");
const main = @import("../main.zig");
const clib = @import("../runtime/main_clib.zig");

const Word = main.Word;
const NIL = main.NIL;
const t = main.heap.t;
const h = main.heap.h;
const tp = main.heap.tp;
const hp = main.heap.hp;
extern var tag: [*]u8;

pub export var internals: Word = NIL;
pub export var tlost: Word = NIL;
var pfrts: Word = NIL;

pub fn fixexports() void {
    var e = main.rs.exports;
    var f: Word = undefined;
    while (e != NIL) : (e = t(e)) {
        paint(h(e));
    }
    internals = NIL;
    if (main.rs.exports == NIL and main.exportfiles == NIL and main.rs.embargoes == NIL) {
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

pub fn unfixexports() void {
    var i = internals;
    if (main.rs.mkexports != 0) return;
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

    main.pnvec.?[@as(usize, @intCast(i))] = x;
    tag[@intCast(n)] = clib.ID;
    hp(n).* = h(x);
    tag[@intCast(x)] = clib.STRCONS;
    hp(x).* = i;

    const current_bucket = main.namebucket[hash_idx];
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
    return (@as(usize, s[0]) + @as(usize, s[clib.strlen(s) - 1])) & 127;
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

    const current_bucket = main.namebucket[hash_idx];
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

pub fn sigdefer(_: c_int) callconv(.c) void {
    main.rs.sigflag = 1;
}

pub export fn readoption() void {
    var f: Word = undefined;
    var t_val: Word = undefined;

    pfrts = NIL;
    tlost = NIL;

    if (main.FBS != NIL) {
        f = main.FBS;
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
    main.TYPERRS += 1;
    _ = clib.printf("MISSING TYPENAME%s\n", .{.{if (t(tlost) == NIL) @as([*:0]const u8, "") else @as([*:0]const u8, "S")}});
    _ = clib.printf("the following type%s no name in this scope:\n", .{.{if (t(tlost) == NIL) @as([*:0]const u8, " is needed but has") else @as([*:0]const u8, "s are needed but have")}});
    while (tlost != NIL) {
        _ = clib.printf("\'%s\' of file \"%s\", needed by: ", .{.{@as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(h(main.t_info(h(h(tlost))))))))), @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(t(main.t_info(h(h(tlost)))))))))}});
        clib.printlist(@constCast(""), main.alfasort(t(h(tlost))));
        tlost = t(tlost);
    }
}

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

    flen = @intCast(clib.strlen(t_val));
    t1 = @intCast(main.fm_time(t_val));
    if (flen > clib.pnlim) {
        _ = clib.printf("sorry, pathname too long (limit=%d): %s\n", .{.{clib.pnlim, t_val}});
        return;
    }

    _ = clib.strcpy(&obf, t_val);
    _ = clib.strcpy(obf[@intCast(flen - 1)..].ptr, main.obsuffix);
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
        _ = clib.printf("cannot open %s\n", .{.{@as([*:0]const u8, @ptrCast(&obf))}});
        main.loadfile(t_val);
        return;
    }

    main.rs.current_script = @constCast(t_val);
    main.loading = 1;
    main.rs.oldfiles = NIL;
    main.unload();

    if (main.rs.initialising == 0 and main.rs.making == 0) {
        main.rs.sigflag = 0;
        oldsig = main.signals(clib.SIGINT, @intFromPtr(&sigdefer));
    }

    main.files = clib.load_script(f.?, @constCast(t_val), NIL, NIL, if (main.rs.making == 0 and main.rs.initialising == 0) 1 else 0);
    _ = clib.fclose(f.?);

    if (main.BAD_DUMP != 0) {
        _ = clib.unlink(@as([*:0]const u8, @ptrCast(&obf)));
        main.unload();
        main.CLASHES = NIL;
        main.stackp = main.dstack;
        _ = clib.printf("warning: %s contains incorrect data (file removed)\n", .{.{@as([*:0]const u8, @ptrCast(&obf))}});
        if (main.BAD_DUMP == -1) {
            _ = clib.printf("(unrecognised dump format)\n", .{.{}});
        } else if (main.BAD_DUMP == 1) {
            _ = clib.printf("(wrong source file)\n", .{.{}});
        } else {
            _ = clib.printf("(error %ld)\n", .{.{main.BAD_DUMP}});
        }
    }

    if (main.rs.initialising == 0 and main.rs.making == 0) {
        _ = main.signals(clib.SIGINT, oldsig);
    }
    if (main.rs.sigflag != 0) {
        main.rs.sigflag = 0;
        if (oldsig > 1) {
            const handler: *const fn (c_int) callconv(.c) void = @ptrFromInt(oldsig);
            handler(clib.SIGINT);
        }
    }

    if (main.CLASHES != NIL) {
        if (main.rs.ideep == 0) {
            _ = clib.printf("cannot load %s ", .{.{@as([*:0]const u8, @ptrCast(&obf))}});
            clib.printlist(@constCast("due to name clashes: "), main.alfasort(main.CLASHES));
        }
        main.unload();
        main.loading = 0;
        return;
    }

    if (main.BAD_DUMP != 0 or main.src_update() != 0) {
        main.loadfile(t_val);
    } else if (main.rs.initialising != 0) {
        if (main.ND != NIL or main.files == NIL) {
            _ = clib.fprintf(main.getStderr(), "panic: %s contains errors\n", .{.{@as([*:0]const u8, @ptrCast(&obf))}});
            clib.exit(1);
        }
    } else {
        if (main.rs.verbosity != 0 or main.rs.magic != 0 or main.rs.mkexports != 0) {
            if (main.files == NIL) {
                _ = clib.printf("%s contains syntax error\n", .{.{t_val}});
            } else {
                if (main.ND != NIL) {
                    _ = clib.printf("%s contains undefined names or type errors\n", .{.{t_val}});
                } else if (main.rs.making == 0 and main.rs.magic == 0) {
                    _ = clib.printf("%s\n", .{.{t_val}});
                }
            }
        }
    }

    if (main.files != NIL and main.rs.making == 0 and main.rs.initialising == 0) {
        unfixexports();
    }
    main.loading = 0;
}

pub fn makedump() void {
    const obf = &main.rs.linebuf;
    var f: ?*clib.FILE = null;
    _ = clib.strcpy(obf, main.rs.current_script.?);
    const len = clib.strlen(obf);
    _ = clib.strcpy(obf[len - 1 ..].ptr, main.obsuffix);
    f = clib.fopen(obf, "w");
    if (f == null) {
        _ = clib.printf("WARNING: CANNOT WRITE TO %s\n", .{.{@as([*:0]const u8, @ptrCast(obf))}});
        if (clib.strcmp(main.rs.current_script.?, &main.rs.PRELUDE) == 0 or clib.strcmp(main.rs.current_script.?, &main.rs.STDENV) == 0) {
            _ = clib.printf("TO FIX THIS PROBLEM PLEASE GET SUPER-USER TO EXECUTE `mira'\n", .{.{}});
        }
        if (main.rs.making != 0 and main.rs.make_status == 0) {
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
