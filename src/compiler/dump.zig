//! dump.zig — the object-file (`.x`) state serialiser. `makedump` writes a
//! compiled script's definitions, types, and export tables to disk and `undump`
//! reloads them, so an unchanged source need not be recompiled. Also handles the
//! export-table fix-up (`fixexports`) and dump-file options (`readoption`).

const std = @import("std");
const word = @import("../runtime/word.zig");
const errors = @import("../runtime/errors.zig");
const strtab = @import("../runtime/strtab.zig");
const rt = @import("../runtime/runtime_state.zig");
const compiler_state = @import("compiler_state.zig");
const cs = compiler_state.cs;
const abi = @import("../runtime/main_clib.zig");
const lex_state = @import("../parser/lex_state.zig");
const heap_mod = @import("../runtime/heap.zig");
const Heap = heap_mod.Heap;
const files = @import("../io/files.zig");
const module_loader = @import("module_loader.zig");
const signals_mod = @import("../io/signals.zig");
const core_state = @import("../runtime/core_state.zig");
const ls = lex_state.ls;

const Word = word.Word;
const NIL = word.NIL;
const t = heap_mod.t;
const h = heap_mod.h;
const tp = heap_mod.tp;
const hp = heap_mod.hp;
inline fn getTag(heap: *Heap, x: Word) word.NodeTag {
    return heap.getTag(x);
}
inline fn setTag(heap: *Heap, x: Word, val: word.NodeTag) void {
    heap.setTag(x, val);
}

/// Heap list of identifiers hidden from the exported interface (privatised).
/// Populated by fixexports(); cleared by unfixexports().
pub var internals: Word = NIL;
/// Heap list of types that are needed by the current script but have no name in scope.
/// Non-NIL after readoption() means the dump cannot be used and type errors will be reported.
pub var tlost: Word = NIL;
var pfrts: Word = NIL;

/// Marks all exported identifiers and privatises the rest.
/// Must be paired with a call to unfixexports() once the dump is written.
pub fn fixexports(heap: *Heap) void {
    var e = rt.rs.exports;
    var f: Word = undefined;
    while (e != NIL) : (e = t(e)) {
        paint(h(e));
    }
    internals = NIL;
    if (rt.rs.exports == NIL and ls.exportfiles == NIL and rt.rs.embargoes == NIL) {
        e = rt.rs.freeids;
        while (e != NIL) : (e = t(e)) {
            internals = heap_mod.cons(privatise(heap, h(h(e))), internals);
        }
        f = t(heap.files);
        while (f != NIL) : (f = t(f)) {
            var e_def = heap_mod.filDefs(h(f));
            while (e_def != NIL) : (e_def = t(e_def)) {
                if (getTag(heap, h(e_def)) == .ID) {
                    internals = heap_mod.cons(privatise(heap, h(e_def)), internals);
                }
            }
        }
    } else {
        f = heap.files;
        while (f != NIL) : (f = t(f)) {
            var e_def = heap_mod.filDefs(h(f));
            while (e_def != NIL) : (e_def = t(e_def)) {
                if (getTag(heap, h(e_def)) == .ID and unpainted(heap, h(e_def))) {
                    internals = heap_mod.cons(privatise(heap, h(e_def)), internals);
                }
            }
        }
    }
    e = rt.rs.exports;
    while (e != NIL) : (e = t(e)) {
        unpaint(h(e));
    }
}

/// Mark id `x` as exported by wrapping its value in an `EXPORT` node (dump graph-walk).
fn paint(x: Word) void {
    tp(x).* = abi.ap(word.EXPORT, heap_mod.idVal(x));
}

/// Whether id `x` is not marked as exported.
fn unpainted(heap: *Heap, x: Word) bool {
    const v = heap_mod.idVal(x);
    return getTag(heap, v) != .AP or h(v) != word.EXPORT;
}

/// Remove the `EXPORT` mark from id `x`.
fn unpaint(x: Word) void {
    tp(x).* = t(heap_mod.idVal(x));
}

/// Reverses the privatisation done by fixexports(), restoring all `internals` to public.
/// No-op when `rs.mkexports != 0` (the dump is being kept for distribution).
pub fn unfixexports(heap: *Heap) void {
    var i = internals;
    if (rt.rs.mkexports) return;
    while (i != NIL) : (i = t(i)) {
        _ = publicise(heap, h(i));
    }
    internals = NIL;
}

/// Move id `x` out of the public name bucket into a private name (for `%export` filtering).
fn privatise(heap: *Heap, x: Word) Word {
    const n = abi.makePn(x);
    const hash_idx = hash(heap_mod.getId(x));
    const i = h(n);

    if (heap_mod.idType(x) == word.type_t) {
        tp(heap_mod.tInfo(x)).* = heap_mod.cons(abi.datapair(@as(Word, strtab.strBits(strtab.table, abi.getaka(x))), 0), heap_mod.getHere(x));
    }

    if (heap_mod.idVal(x) == word.UNDEF) {
        tp(x).* = abi.ap(abi.datapair(@as(Word, strtab.strBits(strtab.table, abi.getaka(x))), 0), heap_mod.getHere(x));
    }

    ls.pnvec.?[@as(usize, @intCast(i))] = x;
    setTag(heap, n, .ID);
    hp(n).* = h(x);
    setTag(heap, x, .STRCONS);
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

/// Hash a C-string into a 0..127 name-bucket index (first + last byte).
fn hash(s: [*:0]const u8) usize {
    return (@as(usize, s[0]) + @as(usize, s[word.strlen(s) - 1])) & 127;
}

/// Restore a privatised id `x` to the public name bucket.
fn publicise(heap: *Heap, x: Word) Word {
    const i = heap_mod.idVal(x);
    const hash_idx = hash(heap_mod.getId(x));

    setTag(heap, i, .ID);
    hp(i).* = h(x);

    const val = t(i);
    if (getTag(heap, val) == .AP and getTag(heap, h(val)) == .DATAPAIR) {
        tp(i).* = word.UNDEF;
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
    rt.rs.sigflag = 1;
}

/// Repairs type references after loading a dump: re-resolves STRCONS nodes and
/// reports types that are in the dump but missing from the current scope (`tlost`).
pub fn readoption(heap: *Heap, comp: *compiler_state.CompilerState) void {
    var f: Word = undefined;
    var t_val: Word = undefined;

    pfrts = NIL;
    tlost = NIL;

    if (comp.FBS != NIL) {
        f = comp.FBS;
        while (f != NIL) : (f = t(f)) {
            t_val = t(h(f));
            while (t_val != NIL) : (t_val = t(t_val)) {
                if (getTag(heap, h(h(t_val))) == .STRCONS and t(t(h(h(t_val)))) == word.type_t) {
                    pfrts = heap_mod.cons(h(h(t_val)), pfrts);
                }
            }
        }
    }

    var rfl_ptr = rt.rs.rfl;
    while (rfl_ptr != NIL) : (rfl_ptr = t(rfl_ptr)) {
        f = heap_mod.filDefs(h(rfl_ptr));
        while (f != NIL) : (f = t(f)) {
            if (getTag(heap, h(f)) == .ID) {
                t_val = heap_mod.idType(h(f));
                if (t_val == word.type_t) {
                    if (heap_mod.tClass(h(f)) == word.synonym_t) {
                        tp(heap_mod.tInfo(h(f))).* = fixtype(heap, heap_mod.tInfo(h(f)), h(f));
                    }
                } else {
                    tp(h(h(f))).* = fixtype(heap, t_val, h(f));
                }
            }
        }
    }

    if (tlost == NIL) return;
    comp.TYPERRS += 1;
    word.print("cs.MISSING TYPENAME{s}\n", .{if (t(tlost) == NIL) "" else "S"});
    word.print("the following type{s} no name in this scope:\n", .{if (t(tlost) == NIL) " is needed but has" else "s are needed but have"});
    while (tlost != NIL) {
        word.print("\'{s}\' of file \"{s}\", needed by: ", .{ strtab.strOf(strtab.table, h(h(heap_mod.tInfo(h(h(tlost)))))), strtab.strOf(strtab.table, h(t(heap_mod.tInfo(h(h(tlost)))))) });
        abi.printlist(heap, @constCast(""), heap_mod.alfasort(t(h(tlost))));
        tlost = t(tlost);
    }
}

/// Resolves STRCONS type nodes to their canonical ID form when loading a dump.
/// Adds unresolvable types to `tlost` for deferred error reporting.
pub fn fixtype(heap: *Heap, t_val: Word, x: Word) Word {
    switch (getTag(heap, t_val)) {
        .AP, .CONS => {
            tp(t_val).* = fixtype(heap, t(t_val), x);
            hp(t_val).* = fixtype(heap, h(t_val), x);
            return t_val;
        },
        .STRCONS => {
            if (abi.member(heap, pfrts, t_val) != 0) {
                return t_val;
            }
            var cur_t = t_val;
            while (getTag(heap, pnVal(cur_t)) != .CONS) {
                cur_t = pnVal(cur_t);
            }
            if (getTag(heap, cur_t) != .ID) {
                var w = tlost;
                while (w != NIL and h(h(w)) != cur_t) {
                    w = t(w);
                }
                if (w == NIL) {
                    tlost = heap_mod.cons(heap_mod.cons(cur_t, heap_mod.cons(x, NIL)), tlost);
                    w = tlost;
                }
                tp(h(w)).* = abi.add1(heap, x, t(h(w)));
            }
            return cur_t;
        },
        else => return t_val,
    }
}

inline fn pnVal(x: Word) Word {
    return t(x);
}

/// Loads `t_val` from its pre-compiled dump file (.mx suffix) if the dump is newer
/// than the source, otherwise falls back to `loadfile()`. Handles the case where
/// the source does not exist (initialising-only panic) or the dump is missing/stale.
pub fn undump(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState, t_val: [*:0]const u8) void {
    var obf: [abi.pnlim]u8 = undefined;
    var f: ?*word.FILE = null;
    var flen: Word = undefined;
    var t1: Word = undefined;
    var t2: Word = undefined;
    var oldsig: usize = 0;

    if (files.isMirandaSource(t_val) == 0 and rt.rs.initialising == 0) {
        module_loader.loadfile(heap, core, comp, t_val);
        return;
    }

    flen = @intCast(word.strlen(t_val));
    t1 = files.fileMtime(t_val);
    if (flen > abi.pnlim) {
        word.print("sorry, pathname too long (limit={}): {s}\n", .{ abi.pnlim, std.mem.span(t_val) });
        return;
    }

    _ = word.strcpy(&obf, t_val);
    _ = word.strcpy(obf[@intCast(flen - 1)..].ptr, core.obsuffix);
    t2 = files.fileMtime(@as([*:0]const u8, @ptrCast(&obf)));
    if (t2 != 0 and t1 == 0) {
        t2 = 0;
        _ = abi.unlink(@as([*:0]const u8, @ptrCast(&obf)));
    }
    if (t2 == 0 or t2 < t1) {
        module_loader.loadfile(heap, core, comp, t_val);
        return;
    }

    f = word.fopen(&obf, "r");
    if (f == null) {
        word.print("cannot open {s}\n", .{std.mem.span(@as([*:0]const u8, @ptrCast(&obf)))});
        module_loader.loadfile(heap, core, comp, t_val);
        return;
    }

    rt.rs.current_script = @constCast(t_val);
    core.loading = 1;
    rt.rs.oldfiles = NIL;
    heap_mod.unload(comp);

    if (rt.rs.initialising == 0 and !rt.rs.making) {
        rt.rs.sigflag = 0;
        oldsig = signals_mod.signals(abi.SIGINT, @intFromPtr(&sigdefer));
    }

    heap.files = abi.loadScript(core, comp, f.?, @constCast(t_val), NIL, NIL, if (!rt.rs.making and rt.rs.initialising == 0) 1 else 0);
    _ = word.fclose(f.?);

    if (comp.BAD_DUMP != 0) {
        _ = abi.unlink(@as([*:0]const u8, @ptrCast(&obf)));
        heap_mod.unload(comp);
        comp.CLASHES = NIL;
        heap.stackp = heap.dstack;
        word.print("warning: {s} contains incorrect data (file removed)\n", .{std.mem.span(@as([*:0]const u8, @ptrCast(&obf)))});
        if (comp.BAD_DUMP == -1) {
            word.print("(unrecognised dump format)\n", .{});
        } else if (comp.BAD_DUMP == 1) {
            word.print("(wrong source file)\n", .{});
        } else {
            word.print("(error {})\n", .{comp.BAD_DUMP});
        }
    }

    if (rt.rs.initialising == 0 and !rt.rs.making) {
        _ = signals_mod.signals(abi.SIGINT, oldsig);
    }
    if (rt.rs.sigflag != 0) {
        rt.rs.sigflag = 0;
        if (oldsig > 1) {
            const handler: *const fn (c_int) callconv(.c) void = @ptrFromInt(oldsig);
            handler(abi.SIGINT);
        }
    }

    if (comp.CLASHES != NIL) {
        if (rt.rs.ideep == 0) {
            word.print("cannot load {s} ", .{std.mem.span(@as([*:0]const u8, @ptrCast(&obf)))});
            abi.printlist(heap, @constCast("due to name clashes: "), heap_mod.alfasort(comp.CLASHES));
        }
        heap_mod.unload(comp);
        core.loading = 0;
        return;
    }

    if (comp.BAD_DUMP != 0 or heap_mod.srcUpdate() != 0 or heap.files == NIL or comp.ND != NIL) {
        if (rt.rs.initialising != 0) {
            errors.fatal("panic: %s contains errors\n", .{.{@as([*:0]const u8, @ptrCast(&obf))}});
        }
        module_loader.loadfile(heap, core, comp, t_val);
    } else {
        if (rt.rs.verbosity != 0 or rt.rs.magic or rt.rs.mkexports) {
            if (heap.files == NIL) {
                word.print("{s} contains syntax error\n", .{std.mem.span(t_val)});
            } else {
                if (comp.ND != NIL) {
                    word.print("{s} contains undefined names or type errors\n", .{std.mem.span(t_val)});
                } else if (!rt.rs.making and !rt.rs.magic) {
                    word.print("{s}\n", .{std.mem.span(t_val)});
                }
            }
        }
    }

    if (heap.files != NIL and !rt.rs.making and rt.rs.initialising == 0) {
        unfixexports(heap);
    }
    core.loading = 0;
}

/// Writes a binary dump of the current heap state to the .mx file corresponding to
/// `rs.current_script`. Installs `sigdefer` during the write so a SIGINT cannot
/// leave a partial dump; re-raises any deferred signal afterward.
pub fn makedump(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState) void {
    const obf = &rt.rs.linebuf;
    var f: ?*word.FILE = null;
    _ = word.strcpy(obf, rt.rs.current_script.?);
    const len = word.strlen(obf);
    _ = word.strcpy(obf[len - 1 ..].ptr, core.obsuffix);
    f = word.fopen(obf, "w");
    if (f == null) {
        word.print("WARNING: CANNOT WRITE TO {s}\n", .{std.mem.span(@as([*:0]const u8, @ptrCast(obf)))});
        if (word.strcmp(rt.rs.current_script.?, &rt.rs.PRELUDE) == 0 or word.strcmp(rt.rs.current_script.?, &rt.rs.STDENV) == 0) {
            word.print("TO FIX THIS PROBLEM PLEASE GET SUPER-USER TO EXECUTE `mira'\n", .{});
        }
        if (rt.rs.making and rt.rs.make_status == 0) {
            rt.rs.make_status = 1;
        }
        return;
    }
    rt.rs.unlinkme = @ptrCast(obf);
    abi.setprefix(rt.rs.current_script.?);
    abi.dumpScript(core, comp, heap.files, f.?);
    rt.rs.unlinkme = null;
    _ = word.fclose(f.?);
}

test "dump NIL sentinel is consistent" {
    try std.testing.expectEqual(word.NIL, NIL);
}
