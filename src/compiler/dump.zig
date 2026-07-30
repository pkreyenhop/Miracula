//! dump.zig — the object-file (`.x`) state serialiser. `makedump` writes a
//! compiled script's definitions, types, and export tables to disk and `undump`
//! reloads them, so an unchanged source need not be recompiled. Also handles the
//! export-table fix-up (`fixexports`) and dump-file options (`readoption`).

const std = @import("std");
const word = @import("../graph/word.zig");
const errors = @import("../runtime/errors.zig");
const strtab = @import("../graph/strtab.zig");
const rt = @import("../runtime/runtime_state.zig");
const script_store = @import("../session/script_store.zig");
const config_state = @import("../session/config_state.zig");
const repl_session = @import("../session/repl_session.zig");
const make_state = @import("../session/make_state.zig");
const compiler_state = @import("compiler_state.zig");
const cs = compiler_state.cs;
const abi = @import("../os.zig");
const lex_state = @import("../parser/lex_state.zig");
const heap_mod = @import("../graph/heap.zig");
const dump_mod = @import("../graph/dump.zig");
const depend_mod = @import("../semantics/depend.zig");
const Value = @import("../graph/value.zig").Value;
const Heap = heap_mod.Heap;
const files = @import("../io/files.zig");
const module_loader = @import("module_loader.zig");
const core_state = @import("../runtime/core_state.zig");
const symbols = @import("../semantics/symbols.zig");
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

/// Marks all exported identifiers and privatises the rest.
/// Must be paired with a call to unfixexports() once the dump is written.
pub fn fixexports(heap: *Heap, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState, lexs: *lex_state.LexState) void {
    _ = rs;
    var e = script_store.store().exports;
    var f: Word = undefined;
    while (e != NIL) : (e = t(heap, e)) {
        paint(heap, h(heap, e));
    }
    comp.internals = NIL;
    if (script_store.store().exports == NIL and lexs.exportfiles == NIL and script_store.store().embargoes == NIL) {
        e = script_store.store().freeids;
        while (e != NIL) : (e = t(heap, e)) {
            comp.internals = heap_mod.cons(heap, privatise(heap, lexs, h(heap, h(heap, e))), comp.internals);
        }
        f = t(heap, heap.files);
        while (f != NIL) : (f = t(heap, f)) {
            var e_def = heap_mod.filDefs(h(heap, f));
            while (e_def != NIL) : (e_def = t(heap, e_def)) {
                if (getTag(heap, h(heap, e_def)) == .ID) {
                    comp.internals = heap_mod.cons(heap, privatise(heap, lexs, h(heap, e_def)), comp.internals);
                }
            }
        }
    } else {
        f = heap.files;
        while (f != NIL) : (f = t(heap, f)) {
            var e_def = heap_mod.filDefs(h(heap, f));
            while (e_def != NIL) : (e_def = t(heap, e_def)) {
                if (getTag(heap, h(heap, e_def)) == .ID and unpainted(heap, h(heap, e_def))) {
                    comp.internals = heap_mod.cons(heap, privatise(heap, lexs, h(heap, e_def)), comp.internals);
                }
            }
        }
    }
    e = script_store.store().exports;
    while (e != NIL) : (e = t(heap, e)) {
        unpaint(heap, h(heap, e));
    }
}

/// Mark id `x` as exported by wrapping its value in an `EXPORT` node (dump graph-walk).
fn paint(heap: *Heap, x: Word) void {
    tp(heap, x).* = abi.ap(heap, word.EXPORT, heap_mod.idVal(x));
}

/// Whether id `x` is not marked as exported.
fn unpainted(heap: *Heap, x: Word) bool {
    const v = heap_mod.idVal(x);
    return getTag(heap, v) != .AP or h(heap, v) != word.EXPORT;
}

/// Remove the `EXPORT` mark from id `x`.
fn unpaint(heap: *Heap, x: Word) void {
    tp(heap, x).* = t(heap, heap_mod.idVal(x));
}

/// Reverses the privatisation done by fixexports(), restoring all `internals` to public.
/// No-op when `mkexports` (`//exports`) is set (the dump is being kept for distribution).
pub fn unfixexports(heap: *Heap, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState, lexs: *lex_state.LexState) void {
    _ = rs;
    var i = comp.internals;
    if (make_state.make().mkexports) return;
    while (i != NIL) : (i = t(heap, i)) {
        _ = publicise(heap, lexs, h(heap, i));
    }
    comp.internals = NIL;
}

/// Move id `x` out of the public dictionary into a private name (for `%export` filtering).
///
/// `nm` is captured *before* `x`'s tag is mutated below (`getId` navigates
/// `x`'s own head chain, which the mutation rewrites) — same ordering the
/// legacy `hash_idx = hash(getId(x))` computation used, just replacing a
/// bucket-chain search with a direct rebind now that the dictionary is
/// keyed by name (`semantics/symbols.zig`, GO_PORT_PLAN.md Phase 1 step 6).
fn privatise(heap: *Heap, lexs: *lex_state.LexState, x: Word) Word {
    const n = abi.makePn(heap, x);
    const nm = std.mem.span(heap_mod.getId(x));
    const i = h(heap, n);

    if (heap_mod.idType(x) == word.type_t) {
        tp(heap, heap_mod.tInfo(x)).* = heap_mod.cons(heap, abi.datapair(heap, @as(Word, strtab.strBits(strtab.table(), abi.getaka(x))), 0), heap_mod.getHere(x));
    }

    if (heap_mod.idVal(x) == word.UNDEF) {
        tp(heap, x).* = abi.ap(heap, abi.datapair(heap, @as(Word, strtab.strBits(strtab.table(), abi.getaka(x))), 0), heap_mod.getHere(x));
    }

    lexs.pnvec.?[@as(usize, @intCast(i))] = x;
    setTag(heap, n, .ID);
    hp(heap, n).* = h(heap, x);
    setTag(heap, x, .STRCONS);
    hp(heap, x).* = i;

    symbols.syms().rebind(rt.allocator, nm, Value.fromRaw(n)) catch heap_mod.mallocPanic("symbols dictionary");
    return n;
}

/// Restore a privatised id back to the public dictionary. `x` here is
/// actually the private `n` node `privatise` returned (see its callers,
/// which iterate `comp.internals` — the list of `privatise`'s return
/// values) — its head still mirrors the original id's head (`privatise` set
/// `hp(n).* = h(orig_x)`), so `getId(x)` resolves the same name `privatise`
/// captured, and `idVal(x)` (`t(x)`, untouched by `privatise`) recovers the
/// original cell reference.
fn publicise(heap: *Heap, lexs: *lex_state.LexState, x: Word) Word {
    _ = lexs;
    const i = heap_mod.idVal(x);
    const nm = std.mem.span(heap_mod.getId(x));

    setTag(heap, i, .ID);
    hp(heap, i).* = h(heap, x);

    const val = t(heap, i);
    if (getTag(heap, val) == .AP and getTag(heap, h(heap, val)) == .DATAPAIR) {
        tp(heap, i).* = word.UNDEF;
    }

    symbols.syms().rebind(rt.allocator, nm, Value.fromRaw(i)) catch heap_mod.mallocPanic("symbols dictionary");
    return i;
}

/// Repairs type references after loading a dump: re-resolves STRCONS nodes and
/// reports types that are in the dump but missing from the current scope (`tlost`).
pub fn readoption(heap: *Heap, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState) void {
    _ = rs;
    var f: Word = undefined;
    var t_val: Word = undefined;

    comp.pfrts = NIL;
    comp.tlost = NIL;

    if (comp.FBS != NIL) {
        f = comp.FBS;
        while (f != NIL) : (f = t(heap, f)) {
            t_val = t(heap, h(heap, f));
            while (t_val != NIL) : (t_val = t(heap, t_val)) {
                if (getTag(heap, h(heap, h(heap, t_val))) == .STRCONS and t(heap, t(heap, h(heap, h(heap, t_val)))) == word.type_t) {
                    comp.pfrts = heap_mod.cons(heap, h(heap, h(heap, t_val)), comp.pfrts);
                }
            }
        }
    }

    var rfl_ptr = script_store.store().rfl;
    while (rfl_ptr != NIL) : (rfl_ptr = t(heap, rfl_ptr)) {
        f = heap_mod.filDefs(h(heap, rfl_ptr));
        while (f != NIL) : (f = t(heap, f)) {
            if (getTag(heap, h(heap, f)) == .ID) {
                t_val = heap_mod.idType(h(heap, f));
                if (t_val == word.type_t) {
                    if (heap_mod.tClass(h(heap, f)) == word.synonym_t) {
                        tp(heap, heap_mod.tInfo(h(heap, f))).* = fixtype(heap, comp, heap_mod.tInfo(h(heap, f)), h(heap, f));
                    }
                } else {
                    tp(heap, h(heap, h(heap, f))).* = fixtype(heap, comp, t_val, h(heap, f));
                }
            }
        }
    }

    if (comp.tlost == NIL) return;
    comp.TYPERRS += 1;
    word.print("cs.MISSING TYPENAME{s}\n", .{if (t(heap, comp.tlost) == NIL) "" else "S"});
    word.print("the following type{s} no name in this scope:\n", .{if (t(heap, comp.tlost) == NIL) " is needed but has" else "s are needed but have"});
    while (comp.tlost != NIL) {
        word.print("\'{s}\' of file \"{s}\", needed by: ", .{ strtab.strOf(strtab.table(), h(heap, h(heap, heap_mod.tInfo(h(heap, h(heap, comp.tlost)))))), strtab.strOf(strtab.table(), h(heap, t(heap, heap_mod.tInfo(h(heap, h(heap, comp.tlost)))))) });
        abi.printlist(heap, @constCast(""), depend_mod.alfasort(heap, Value.fromRaw(t(heap, h(heap, comp.tlost)))).toRaw());
        comp.tlost = t(heap, comp.tlost);
    }
}

/// Resolves STRCONS type nodes to their canonical ID form when loading a dump.
/// Adds unresolvable types to `tlost` for deferred error reporting.
pub fn fixtype(heap: *Heap, comp: *compiler_state.CompilerState, t_val: Word, x: Word) Word {
    switch (getTag(heap, t_val)) {
        .AP, .CONS => {
            tp(heap, t_val).* = fixtype(heap, comp, t(heap, t_val), x);
            hp(heap, t_val).* = fixtype(heap, comp, h(heap, t_val), x);
            return t_val;
        },
        .STRCONS => {
            if (abi.member(heap, Value.fromRaw(comp.pfrts), Value.fromRaw(t_val)) != 0) {
                return t_val;
            }
            var cur_t = t_val;
            while (getTag(heap, pnVal(heap, cur_t)) != .CONS) {
                cur_t = pnVal(heap, cur_t);
            }
            if (getTag(heap, cur_t) != .ID) {
                var w = comp.tlost;
                while (w != NIL and h(heap, h(heap, w)) != cur_t) {
                    w = t(heap, w);
                }
                if (w == NIL) {
                    comp.tlost = heap_mod.cons(heap, heap_mod.cons(heap, cur_t, heap_mod.cons(heap, x, NIL)), comp.tlost);
                    w = comp.tlost;
                }
                tp(heap, h(heap, w)).* = abi.add1(heap, Value.fromRaw(x), Value.fromRaw(t(heap, h(heap, w)))).toRaw();
            }
            return cur_t;
        },
        else => return t_val,
    }
}

inline fn pnVal(heap: *Heap, x: Word) Word {
    return t(heap, x);
}

/// Loads `t_val` from its pre-compiled dump file (.mx suffix) if the dump is newer
/// than the source, otherwise falls back to `loadfile()`. Handles the case where
/// the source does not exist (initialising-only panic) or the dump is missing/stale.
pub fn undump(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState, t_val: [*:0]const u8) void {
    var obf: [abi.pnlim]u8 = undefined;
    var f: ?*word.Stream = null;
    var flen: Word = undefined;
    var t1: Word = undefined;
    var t2: Word = undefined;

    if (files.isMirandaSource(t_val) == 0 and rs.initialising == 0) {
        module_loader.loadfile(heap, core, comp, rs, ls(), t_val) catch {};
        return;
    }

    flen = @intCast(std.mem.len(t_val));
    t1 = files.fileMtime(t_val);
    if (flen > abi.pnlim) {
        word.print("sorry, pathname too long (limit={}): {s}\n", .{ abi.pnlim, std.mem.span(t_val) });
        return;
    }

    {
        const t_val_span = std.mem.span(t_val);
        @memcpy(obf[0..t_val_span.len], t_val_span);
        obf[t_val_span.len] = 0;
        const suffix_span = std.mem.span(core.obsuffix);
        const base: usize = @intCast(flen - 1);
        @memcpy(obf[base..][0..suffix_span.len], suffix_span);
        obf[base + suffix_span.len] = 0;
    }
    t2 = files.fileMtime(@as([*:0]const u8, @ptrCast(&obf)));
    if (t2 != 0 and t1 == 0) {
        t2 = 0;
        _ = abi.unlink(@as([*:0]const u8, @ptrCast(&obf)));
    }
    if (t2 == 0 or t2 < t1) {
        module_loader.loadfile(heap, core, comp, rs, ls(), t_val) catch {};
        return;
    }

    f = word.fopen(&obf, "r");
    if (f == null) {
        word.print("cannot open {s}\n", .{std.mem.span(@as([*:0]const u8, @ptrCast(&obf)))});
        module_loader.loadfile(heap, core, comp, rs, ls(), t_val) catch {};
        return;
    }

    script_store.store().current_script = @constCast(t_val);
    core.loading = 1;
    script_store.store().oldfiles = NIL;
    dump_mod.unload(heap, comp, rs, ls());

    heap.files = abi.loadScript(heap, core, comp, rs, ls(), f.?, @constCast(t_val), NIL, NIL, if (!make_state.make().making and rs.initialising == 0) 1 else 0);
    _ = word.fclose(f.?);

    if (comp.BAD_DUMP != 0) {
        _ = abi.unlink(@as([*:0]const u8, @ptrCast(&obf)));
        dump_mod.unload(heap, comp, rs, ls());
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

    if (comp.CLASHES != NIL) {
        if (rs.ideep == 0) {
            word.print("cannot load {s} ", .{std.mem.span(@as([*:0]const u8, @ptrCast(&obf)))});
            abi.printlist(heap, @constCast("due to name clashes: "), depend_mod.alfasort(heap, Value.fromRaw(comp.CLASHES)).toRaw());
        }
        dump_mod.unload(heap, comp, rs, ls());
        core.loading = 0;
        return;
    }

    if (comp.BAD_DUMP != 0 or dump_mod.srcUpdate(heap, rs) != 0 or heap.files == NIL or comp.ND != NIL) {
        if (rs.initialising != 0) {
            errors.fatal("panic: {s} contains errors\n", .{@as([*:0]const u8, @ptrCast(&obf))});
        }
        module_loader.loadfile(heap, core, comp, rs, ls(), t_val) catch {};
    } else {
        if (repl_session.session().verbosity != 0 or rs.magic or make_state.make().mkexports) {
            if (heap.files == NIL) {
                word.print("{s} contains syntax error\n", .{std.mem.span(t_val)});
            } else {
                if (comp.ND != NIL) {
                    word.print("{s} contains undefined names or type errors\n", .{std.mem.span(t_val)});
                } else if (!make_state.make().making and !rs.magic) {
                    word.print("{s}\n", .{std.mem.span(t_val)});
                }
            }
        }
    }

    if (heap.files != NIL and !make_state.make().making and rs.initialising == 0) {
        unfixexports(heap, comp, rs, ls());
    }
    core.loading = 0;
}

/// Writes a binary dump of the current heap state to the .mx file corresponding to
/// `script_store.store().current_script`. A SIGINT mid-write is harmless (Phase 3,
/// docs/GO_PORT_PLAN.md): the installed handler only sets a polled flag, so
/// no signal-deferral dance is needed here -- an interrupted write completes
/// normally and, if it somehow leaves a corrupt dump, `undump`'s `BAD_DUMP`
/// check deletes it on the next load anyway.
pub fn makedump(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState) void {
    const obf = &rs.linebuf;
    var f: ?*word.Stream = null;
    {
        const script_span = std.mem.span(script_store.store().current_script.?);
        @memcpy(obf[0..script_span.len], script_span);
        obf[script_span.len] = 0;
        const suffix_span = std.mem.span(core.obsuffix);
        const base = script_span.len - 1;
        @memcpy(obf[base..][0..suffix_span.len], suffix_span);
        obf[base + suffix_span.len] = 0;
    }
    f = word.fopen(obf, "w");
    if (f == null) {
        word.print("WARNING: CANNOT WRITE TO {s}\n", .{std.mem.span(@as([*:0]const u8, @ptrCast(obf)))});
        const current_script_span = std.mem.span(script_store.store().current_script.?);
        if (std.mem.eql(u8, current_script_span, std.mem.span(@as([*:0]const u8, @ptrCast(&config_state.config().PRELUDE)))) or std.mem.eql(u8, current_script_span, std.mem.span(@as([*:0]const u8, @ptrCast(&config_state.config().STDENV))))) {
            word.print("TO FIX THIS PROBLEM PLEASE GET SUPER-USER TO EXECUTE `mira'\n", .{});
        }
        if (make_state.make().making and make_state.make().make_status == 0) {
            make_state.make().make_status = 1;
        }
        return;
    }
    abi.setprefix(heap, script_store.store().current_script.?);
    abi.dumpScript(heap, core, comp, rs, heap.files, f.?);
    _ = word.fclose(f.?);
}

test "dump NIL sentinel is consistent" {
    try std.testing.expectEqual(word.NIL, NIL);
}
