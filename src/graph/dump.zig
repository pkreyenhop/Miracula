//! dump.zig (split from graph/heap.zig, Phase 4 step 3,
//! docs/GO_PORT_PLAN.md) — the low-level object-file (`.x`) wire format,
//! **write half**: `dumpScript`/`dumpDefs`/`dumpOb`, the shared low-level cell
//! primitives (`ap`/`datapair`/`mktvar`/`stackp*`/…, now `pub` for the read
//! half to reach), `bindparams`/`unscramble` (`%include` alias resolution),
//! and `unload`/`srcUpdate` (script teardown and staleness checks). The read
//! half (`loadScript`/`loadDefs`) lives in `graph/dump_load.zig`. This is the
//! byte-level counterpart to `compiler/dump.zig`'s higher-level
//! `makedump`/`undump`, which calls through to the functions here.

const std = @import("std");
const word = @import("word.zig");
const strtab = @import("strtab.zig");
const rt = @import("../runtime/runtime_state.zig");
const script_store = @import("../session/script_store.zig");
const config_state = @import("../session/config_state.zig");
const core = @import("../runtime/core_state.zig");
const lex_state = @import("../parser/lex_state.zig");
const compiler_state = @import("../compiler/compiler_state.zig");
const depend_mod = @import("../semantics/depend.zig");
const Value = @import("value.zig").Value;
const files = @import("../io/files.zig");
const lex = @import("../parser/lex.zig");
const print = @import("print.zig");
const os = @import("../os.zig");
const heap_mod = @import("heap.zig");
const Heap = heap_mod.Heap;

const Word = i64;
const wordsize = @sizeOf(Word) * 8;
const bits_15 = 0xffff;
const SIGNBIT = 0x10000000;
const MAXDIGIT = 0x7fff;

const h = heap_mod.h;
const hp = heap_mod.hp;
const t = heap_mod.t;
const tp = heap_mod.tp;
const getTag = heap_mod.getTag;
const cons = heap_mod.cons;
const make = heap_mod.make;
const getId = heap_mod.getId;
const getFil = heap_mod.getFil;
const filTime = heap_mod.filTime;
const filShare = heap_mod.filShare;
const filDefs = heap_mod.filDefs;
const makeFil = heap_mod.makeFil;
const idType = heap_mod.idType;
const idVal = heap_mod.idVal;
const idWho = heap_mod.idWho;
const hdsort = heap_mod.hdsort;
const tArity = heap_mod.tArity;
const getDbl = heap_mod.getDbl;
const stoDbl = heap_mod.stoDbl;
const rest = heap_mod.rest;
const getsmallint = heap_mod.getsmallint;
const stosmallint = heap_mod.stosmallint;
const reverse = heap_mod.reverse;
const mallocPanic = heap_mod.mallocPanic;
const mallocfail = heap_mod.mallocfail;
const setupheap = heap_mod.setupheap;
const cs = compiler_state.cs;
const member = depend_mod.member;
const add1 = depend_mod.add1;
const name = lex.name;
const castPtr = print.castPtr;
const fileMtime = files.fileMtime;
const unlinkObject = files.unlinkObject;
const append1 = heap_mod.append1;
const tClass = heap_mod.tClass;
const constructor = heap_mod.constructor;

/// The index of type variable `x`.
fn gettvar(heap: *Heap, x: Word) Word {
    return heap.t(x);
}

/// Make a type-variable node with index `i`.
pub fn mktvar(heap: *Heap, i: Word) Word {
    return heap.make(.TVAR, 0, i);
}

/// The raw head digit of a bignum cell.
fn digit(heap: *Heap, x: Word) Word {
    return heap.h(x);
}

/// The node tag of the definition's parameter-number field.
fn getPn(heap: *Heap, x: Word) Word {
    return heap.h(x);
}

/// The parameter-number value of a definition cell.
pub fn pnVal(heap: *Heap, x: Word) Word {
    return heap.t(x);
}

/// Pointer to the `who` (blame/location) field of identifier `x`.
pub fn idWhoPtr(heap: *Heap, x: Word) *Word {
    return heap.tp(heap.h(heap.h(x)));
}

/// Pointer to the type field of identifier `x`.
pub fn idTypePtr(heap: *Heap, x: Word) *Word {
    return heap.tp(heap.h(x));
}

/// Pointer to the value field of identifier `x`.
pub fn idValPtr(heap: *Heap, x: Word) *Word {
    return heap.tp(x);
}

/// Pointer to the parameter-number value field of definition cell `x`.
pub fn pnValPtr(heap: *Heap, x: Word) *Word {
    return heap.tp(x);
}

/// Push `val` onto the dump scratch stack (`dstack`).
pub fn stackpPush(heap: *Heap, val: Word) void {
    heap.stackp.?[0] = val;
    heap.stackp = heap.stackp.? + 1;
}

/// Pop and return the top of the dump scratch stack.
pub fn stackpPop(heap: *Heap) Word {
    heap.stackp = heap.stackp.? - 1;
    return heap.stackp.?[0];
}

/// The top of the dump scratch stack, without popping.
pub fn stackpTop(heap: *Heap) Word {
    return (heap.stackp.? - 1)[0];
}

/// Overwrite the top of the dump scratch stack.
pub fn stackpSetTop(heap: *Heap, val: Word) void {
    (heap.stackp.? - 1)[0] = val;
}

/// A `(x . y)` pair used to record type-arity mismatches during `bindparams`.
pub fn datapair(heap: *Heap, x: Word, y: Word) Word {
    return heap.make(.DATAPAIR, x, y);
}

/// A `(file . line)` source-location cell.
pub fn fileinfo(heap: *Heap, x: Word, y: Word) Word {
    return heap.make(.FILEINFO, x, y);
}

/// Collapse a `STARTREADVALS`-delimited run of loaded values into `x`.
pub fn readvals(heap: *Heap, x: Word, y: Word) Word {
    return heap.make(.STARTREADVALS, x, y);
}

/// Allocate an `AP` (application) cell `(x @ y)`.
pub fn ap(heap: *Heap, x: Word, y: Word) Word {
    return heap.make(.AP, x, y);
}

/// Set the path prefix used to relativise dumped file names.
pub fn setprefix(heap: *Heap, p: [*:0]const u8) void {
    const p_len = std.mem.len(p);
    if (p_len >= heap.prefix.len) {
        mallocfail("prefix buffer overflow");
    }
    @memcpy(heap.prefix[0..p_len], p[0..p_len]);
    heap.prefix[p_len] = 0;

    var last_slash: ?usize = null;
    var i: usize = p_len;
    while (i > 0) {
        i -= 1;
        if (heap.prefix[i] == '/') {
            last_slash = i;
            break;
        }
    }
    if (last_slash) |idx| {
        heap.prefix[idx + 1] = 0;
        heap.preflen = @intCast(idx + 1);
    } else {
        heap.prefix[0] = 0;
        heap.preflen = 0;
    }
}

/// Rewrite path `p` relative to the dump prefix.
pub fn mkrel(heap: *Heap, p: [*:0]const u8) [*:0]const u8 {
    const p_len = std.mem.len(p);
    const prefix_len = @as(usize, @intCast(heap.preflen));
    if (prefix_len <= p_len and std.mem.eql(u8, heap.prefix[0..prefix_len], p[0..prefix_len])) {
        return @ptrCast(p + prefix_len);
    }
    if (p[0] == '/') {
        return p;
    }
    _ = word.printErr("impossible event in mkrelative\n", .{});
    return p;
}

/// Whether the object file for `t_ptr` exists and is up to date.
pub fn okdump(core_st: *core.CoreState, t_ptr: [*:0]const u8) bool {
    var obf: [120]u8 = undefined;
    const t_len = std.mem.len(t_ptr);
    if (t_len >= obf.len) {
        return false;
    }
    @memcpy(obf[0..t_len], t_ptr[0..t_len]);
    obf[t_len] = 0;

    const suffix_str = std.mem.span(core_st.obsuffix);
    const suffix_len = suffix_str.len;
    if (t_len + suffix_len - 1 >= obf.len) {
        return false;
    }
    @memcpy(obf[t_len - 1 .. t_len - 1 + suffix_len], suffix_str.ptr);
    obf[t_len - 1 + suffix_len] = 0;

    const f = word.fopen(&obf, "r") orelse return false;
    defer _ = word.fclose(f);

    const ch1 = os.getc(f);
    const ch2 = os.getc(f);
    if (ch1 == word.XVERSION and ch2 != 0) {
        return true;
    }
    return false;
}

/// The error line number recorded in a bad object file for `t_ptr`.
pub fn geterrlin(heap: *Heap, core_st: *core.CoreState, lexs: *lex_state.LexState, t_ptr: [*:0]const u8) Word {
    var obf: [120]u8 = undefined;
    const t_len = std.mem.len(t_ptr);
    if (t_len >= obf.len) {
        return 0;
    }
    @memcpy(obf[0..t_len], t_ptr[0..t_len]);
    obf[t_len] = 0;

    const suffix_str = std.mem.span(core_st.obsuffix);
    const suffix_len = suffix_str.len;
    if (t_len + suffix_len - 1 >= obf.len) {
        return 0;
    }
    @memcpy(obf[t_len - 1 .. t_len - 1 + suffix_len], suffix_str.ptr);
    obf[t_len - 1 + suffix_len] = 0;

    const f = word.fopen(&obf, "r") orelse return 0;
    defer _ = word.fclose(f);

    const ch1 = os.getc(f);
    if (ch1 != word.XVERSION) {
        return 0;
    }

    const ch2 = os.getc(f);
    if (ch2 != 0 and ch2 != 1) {
        return 0;
    }

    const el = getword(f);

    // now check this is right dump
    setprefix(heap, t_ptr);
    var ch = os.getc(f);
    lexs.dicq = lexs.dicp;
    if (ch != '/') {
        const prefix_len = @as(usize, @intCast(heap.preflen));
        @memcpy(lexs.dicp[0..prefix_len], heap.prefix[0..prefix_len]);
        lexs.dicp[prefix_len] = 0;
        lexs.dicq = lexs.dicp + prefix_len;
    }

    // locate wrt current posn
    lexs.dicq[0] = @intCast(ch);
    lexs.dicq += 1;

    while (true) {
        ch = os.getc(f);
        lexs.dicq[0] = @intCast(ch);
        lexs.dicq += 1;
        if (ch == 0 or ch == os.EOF) {
            break;
        }
    }

    const mtime = getword(f);
    if (os.strcmp(lexs.dicp, t_ptr) != 0 or mtime != fileMtime(t_ptr)) {
        return 0; // wrong dump
    }

    return el;
}

pub fn getword(file: ?*word.Stream) Word {
    var s: i32 = 0;
    var i: usize = @sizeOf(Word);
    var x = @as(Word, @intCast(os.getc(file)));
    while (i > 1) {
        i -= 1;
        s += 8;
        const next_ch = @as(Word, @intCast(os.getc(file)));
        x |= next_ch << @intCast(s);
    }
    return x;
}

/// Write a size-prefixed tagged `Word` to dump `file`.
pub fn putword(x_val: Word, file: ?*word.Stream) void {
    var x = x_val;
    var i: usize = @sizeOf(Word);
    _ = word.putc(@intCast(x & 255), file);
    while (i > 1) {
        i -= 1;
        x >>= 8;
        _ = word.putc(@intCast(x & 255), file);
    }
}

/// Write a 32-bit int to dump `file`.
pub fn putint(n: i32, file: ?*word.Stream) void {
    _ = word.fwrite(&n, @sizeOf(i32), 1, file);
}

/// Read a 32-bit int from dump `file`.
pub fn getint(file: ?*word.Stream) i32 {
    var r: i32 = 0;
    _ = word.fread(&r, @sizeOf(i32), 1, file);
    return r;
}

/// Write the double in cell `x` to dump `file`.
pub fn putdbl(x: Word, file: ?*word.Stream) void {
    var d = getDbl(x);
    _ = word.fwrite(&d, @sizeOf(f64), 1, file);
}

/// Read a double from dump `file` (as a `DOUBLE` node). A non-finite value
/// can only come from a corrupt dump (a well-formed one was itself written
/// from a value `stoDbl`/`setdbl` already accepted) — flagged the same way
/// other dump corruption is, via `BAD_DUMP`, rather than threading a Zig
/// error through the whole dump-loading loop.
pub fn getdbl(file: ?*word.Stream) Word {
    var d: f64 = 0;
    _ = word.fread(&d, @sizeOf(f64), 1, file);
    return stoDbl(d) catch {
        cs().BAD_DUMP = 1;
        return word.NIL;
    };
}

/// Write the loaded files/definitions graph to dump `file`.
pub fn dumpScript(heap: *Heap, core_st: *core.CoreState, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState, files_val: Word, file: ?*word.Stream) void {
    _ = rs;
    _ = word.putc(@intCast(wordsize), file);
    _ = word.putc(word.XVERSION, file);

    if (files_val == word.NIL) {
        _ = word.putc(0, file);
        putword(core_st.errline, file);
        var x = script_store.store().oldfiles;
        while (x != word.NIL) : (x = heap.t(x)) {
            _ = word.fprint(file, "{s}", .{mkrel(heap, getFil(heap.h(x)) orelse "")});
            _ = word.putc(0, file);
            putword(filTime(heap.h(x)), file);
        }
        return;
    }

    if (comp.ND != word.NIL) {
        _ = word.putc(1, file);
        putword(core_st.errline, file);
    }

    var f_list = files_val;
    while (f_list != word.NIL) : (f_list = heap.t(f_list)) {
        heap.CFN = getFil(heap.h(f_list)) orelse "";
        _ = word.fprint(file, "{s}", .{mkrel(heap, heap.CFN.?)});
        _ = word.putc(0, file);
        putword(filTime(heap.h(f_list)), file);
        _ = word.putc(@intCast(filShare(heap.h(f_list))), file);
        dumpDefs(heap, filDefs(heap.h(f_list)), file);
    }
    _ = word.putc(0, file);
    dumpDefs(heap, comp.algshfns, file);
    if (comp.ND == word.NIL and script_store.store().bereaved != word.NIL) {
        dumpOb(word.True, file);
    } else {
        dumpOb(comp.ND, file);
    }
    _ = word.putc(word.DEF_X, file);
    dumpOb(comp.SGC, file);
    _ = word.putc(word.DEF_X, file);
    dumpOb(script_store.store().freeids, file);
    _ = word.putc(word.DEF_X, file);
    dumpDefs(heap, comp.internals, file);
}

/// Write a definition list to dump `file`.
pub fn dumpDefs(heap: *Heap, defs_val: Word, file: ?*word.Stream) void {
    var defs = defs_val;
    while (defs != word.NIL) : (defs = heap.t(defs)) {
        const item = heap.h(defs);
        if (heap.getTag(item) == .STRCONS) {
            const v = getPn(heap, item);
            dumpOb(pnVal(heap, item), file);
            if (v > bits_15) {
                _ = word.putc(word.PN1_X, file);
                putint(@intCast(v), file);
            } else {
                _ = word.putc(word.PN_X, file);
                _ = word.putc(@intCast(v & 255), file);
                _ = word.putc(@intCast(v >> 8), file);
            }
            _ = word.putc(word.DEF_X, file);
        } else {
            dumpOb(idVal(item), file);
            dumpOb(idType(item), file);
            dumpOb(idWho(item), file);
            _ = word.putc(word.ID_X, file);
            _ = word.fprint(file, "{s}", .{getId(item)});
            _ = word.putc(0, file);
            _ = word.putc(word.DEF_X, file);
        }
    }
    _ = word.putc(word.DEF_X, file);
}

/// Write one object (graph node) to dump `file`.
///
/// Tests: dumpOb / loadDefs: roundtrip a cons of two ints through the .x format
///
/// Deliberately kept ambient (no `heap: *Heap` receiver), unlike the rest of
/// this file: a receiver-threaded version measurably regresses -- an extra
/// pointer's worth of stack frame, multiplied across `dumpOb`'s unbounded
/// per-list-element recursion depth (it recurses on `.CONS`'s tail *before*
/// its head, so it can't be tail-call optimised), pushed a ~1000-element
/// list dump from working to a stack overflow (confirmed via the "compile
/// time stress guard" integration test and bisected to exactly this
/// function). Revisit once `dumpOb` itself is restructured to walk its own
/// `stackpPush`/`stackpPop` scratch stack explicitly instead of recursing —
/// `loadDefs`, its inverse, already does this — rather than receiver-thread
/// a function whose recursion depth is proportional to user data size.
pub fn dumpOb(x: Word, file: ?*word.Stream) void {
    switch (heap_mod.heap().getTag(x)) {
        .ATOM => {
            if (x < 128) {
                _ = word.putc(@intCast(x), file);
            } else if (x >= 384) {
                _ = word.putc(@intCast(x - 256), file);
            } else {
                _ = word.putc(word.CHAR_X, file);
                _ = word.putc(@intCast(x - 128), file);
            }
        },
        .TVAR => {
            _ = word.putc(word.TVAR_X, file);
            _ = word.putc(@intCast(gettvarAmbient(x)), file);
            if (gettvarAmbient(x) > 255) {
                std.debug.print("panic, tvar too large\n", .{});
            }
        },
        .INT => {
            var curr = x;
            const d = digit(heap_mod.heap(), curr);
            if (rest(curr) == 0 and (d & MAXDIGIT) <= 127) {
                var signed_d = d;
                if ((d & SIGNBIT) != 0) {
                    signed_d = -@as(Word, @intCast(d & MAXDIGIT));
                }
                _ = word.putc(word.SHORT_X, file);
                _ = word.putc(@intCast(signed_d), file);
                return;
            }
            _ = word.putc(word.INT_X, file);
            putint(@intCast(d), file);
            curr = rest(curr);
            while (curr != 0) {
                putint(@intCast(digit(heap_mod.heap(), curr)), file);
                curr = rest(curr);
            }
            putint(-1, file);
        },
        .DOUBLE => {
            _ = word.putc(word.DBL_X, file);
            putdbl(x, file);
        },
        .UNICODE => {
            _ = word.putc(word.UNICODE_X, file);
            putint(@intCast(h(heap_mod.heap(), x)), file);
        },
        .DATAPAIR => {
            _ = word.fprint(file, "{c}{s}", .{ @as(u8, @intCast(word.AKA_X)), castPtr(h(heap_mod.heap(), x)) });
            _ = word.putc(0, file);
        },
        .FILEINFO => {
            var line = t(heap_mod.heap(), x);
            const path = castPtr(h(heap_mod.heap(), x));
            if (os.strcmp(path, heap_mod.heap().CFN.?) == 0) {
                _ = word.putc(word.HERE_X, file);
            } else {
                _ = word.fprint(file, "{c}{s}", .{ @as(u8, @intCast(word.HERE_X)), mkrel(heap_mod.heap(), path) });
            }
            _ = word.putc(0, file);
            _ = word.putc(@intCast(line & 255), file);
            line >>= 8;
            _ = word.putc(@intCast(line & 255), file);
            if (line > 255) {
                std.debug.print("impossible line number {d} in dumpOb\n", .{t(heap_mod.heap(), x)});
            }
        },
        .CONSTRUCTOR => {
            dumpOb(t(heap_mod.heap(), x), file);
            _ = word.putc(word.CONSTRUCT_X, file);
            _ = word.putc(@intCast(h(heap_mod.heap(), x) & 255), file);
            _ = word.putc(@intCast(h(heap_mod.heap(), x) >> 8), file);
        },
        .STARTREADVALS => {
            dumpOb(t(heap_mod.heap(), x), file);
            _ = word.putc(word.RV_X, file);
        },
        .ID => {
            _ = word.fprint(file, "{c}{s}", .{ @as(u8, @intCast(word.ID_X)), getId(x) });
            _ = word.putc(0, file);
        },
        .STRCONS => {
            const v = getPn(heap_mod.heap(), x);
            if (v > bits_15) {
                _ = word.putc(word.PN1_X, file);
                putint(@intCast(v), file);
            } else {
                _ = word.putc(word.PN_X, file);
                _ = word.putc(@intCast(v & 255), file);
                _ = word.putc(@intCast(v >> 8), file);
            }
        },
        .AP => {
            dumpOb(h(heap_mod.heap(), x), file);
            dumpOb(t(heap_mod.heap(), x), file);
            _ = word.putc(word.AP_X, file);
        },
        .CONS => {
            dumpOb(t(heap_mod.heap(), x), file);
            dumpOb(h(heap_mod.heap(), x), file);
            _ = word.putc(word.CONS_X, file);
        },
        else => {
            std.debug.print("impossible tag {d} in dumpOb\n", .{heap_mod.heap().getTag(x)});
        },
    }
}

/// Ambient-singleton form of `gettvar`, for `dumpOb` (see its own doc for why
/// it stays ambient rather than receiver-threaded).
fn gettvarAmbient(x: Word) Word {
    return t(heap_mod.heap(), x);
}

/// Bind a `%include`'s formal parameters to the actual arguments.
pub fn bindparams(heap: *Heap, comp: *compiler_state.CompilerState, formal_val: Word, actual_val: Word) void {
    var formal = formal_val;
    var actual = actual_val;
    var badkind: Word = word.NIL;
    comp.DETROP = word.NIL;
    comp.MISSING = word.NIL;
    comp.FBS = heap.cons(formal, comp.FBS);

    while (true) {
        var a: Word = 0;
        var f: [*:0]const u8 = undefined;
        while (formal != word.NIL and (actual == word.NIL or blk: {
            f = castPtr(heap.h(heap.h(heap.t(heap.h(formal)))));
            a = heap.h(heap.h(actual));
            break :blk os.strcmp(f, getId(a).ptr) < 0;
        })) {
            comp.MISSING = heap.cons(heap.h(heap.t(heap.h(formal))), comp.MISSING);
            formal = heap.t(formal);
        }
        if (actual == word.NIL) {
            break;
        }
        if (formal == word.NIL or os.strcmp(f, getId(a).ptr) != 0) {
            comp.DETROP = heap.cons(a, comp.DETROP);
        } else {
            const fa = if (heap.t(heap.t(heap.h(formal))) == word.type_t) tArity(heap.h(heap.h(formal))) else -1;
            const ta = if (heap.getTag(heap.h(actual)) == .AP) tArity(heap.h(actual)) else -1;
            if (fa != ta) {
                badkind = heap.cons(heap.cons(heap.h(heap.h(actual)), datapair(heap, fa, ta)), badkind);
            }
            idValPtr(heap, heap.h(heap.h(formal))).* = heap.t(heap.h(actual));
            formal = heap.t(formal);
        }
        actual = heap.t(actual);
    }

    var bk = badkind;
    while (bk != word.NIL) : (bk = heap.t(bk)) {
        comp.DETROP = heap.cons(heap.h(bk), comp.DETROP);
    }
}

/// Resolve `%include` aliases in the freshly-loaded graph.
pub fn unscramble(heap: *Heap, comp: *compiler_state.CompilerState, aliases: Word) void {
    var a = aliases;
    while (a != word.NIL) : (a = heap.t(a)) {
        const old = heap.t(heap.h(a));
        var hold = heap.h(heap.h(a));
        const new_id = idVal(old);
        heap.hp(heap.h(a)).* = new_id;
        idWhoPtr(heap, old).* = heap.h(hold);
        hold = heap.t(hold);
        idTypePtr(heap, old).* = heap.h(hold);
        idValPtr(heap, old).* = heap.t(hold);
    }
    var al = comp.ALIASES;
    a = word.NIL;
    while (al != word.NIL) : (al = heap.t(al)) {
        const new_id = heap.h(heap.h(al));
        const old = heap.t(heap.h(al));
        if (heap.getTag(new_id) != .ID) {
            if (member(heap, Value.fromRaw(comp.SUPPRESSED), Value.fromRaw(new_id)) == 0) {
                a = heap.cons(old, a);
            }
            continue;
        }
        if (idType(new_id) == word.new_t) {
            idTypePtr(heap, new_id).* = word.undef_t;
        }
        if (idType(new_id) == word.undef_t) {
            a = heap.cons(old, a);
        } else if (member(heap, Value.fromRaw(comp.CLASHES), Value.fromRaw(new_id)) == 0) {
            if (heap.getTag(idWho(new_id)) != .CONS) {
                idWhoPtr(heap, new_id).* = heap.cons(datapair(heap, strtab.strBits(strtab.table(), getId(old)), 0), idWho(new_id));
            }
        }
    }
    comp.ALIASES = a;
}

/// Allocate the dump scratch stack (`dstack`).
pub fn dsetup(heap: *Heap) void {
    if (heap.dstack == null) {
        const slice = rt.allocator.alloc(Word, 1000) catch mallocPanic("dstack");
        heap.dstack = slice.ptr;
        heap.dlim = heap.dstack.? + 1000;
        heap.allocated_dstack_size = 1000;
    }
    heap.stackp = heap.dstack;
}

/// Grow the dump scratch stack when it overflows.
pub fn dgrow(heap: *Heap) void {
    const hold = heap.dstack.?;
    const num_elements = heap.dlim.? - hold;
    const old_slice = hold[0..heap.allocated_dstack_size];
    const new_size = num_elements * 2;
    const slice = rt.allocator.realloc(old_slice, new_size) catch mallocPanic("dstack");
    heap.dstack = slice.ptr;
    heap.dlim = heap.dstack.? + new_size;
    heap.stackp = heap.dstack.? + (heap.stackp.? - hold);
    heap.allocated_dstack_size = new_size;
}

/// Clear the values of all ids defined in `d_val` (on unload).
pub fn unsetids(heap: *Heap, d_val: Word) void {
    var d = d_val;
    while (d != word.NIL and d != 0) : (d = heap.t(d)) {
        const item = heap.h(d);
        if (heap.getTag(item) == .ID) {
            heap.tp(item).* = word.UNDEF;
            heap.tp(heap.h(heap.h(item))).* = word.NIL;
            heap.tp(heap.h(item)).* = word.undef_t;
        }
    }
}

/// Unload the current script: clear its definitions from the environment.
pub fn unload(heap: *Heap, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState, lexs: *lex_state.LexState) void {
    _ = rs;
    script_store.store().sorted = 0;
    comp.speclocs = word.NIL;
    lexs.nextpn = 0;
    comp.rv_script = 0;
    comp.algshfns = word.NIL;
    unsetids(heap, comp.newtyps);
    comp.newtyps = word.NIL;
    unsetids(heap, script_store.store().freeids);
    script_store.store().freeids = word.NIL;
    script_store.store().includees = word.NIL;
    comp.SGC = word.NIL;
    comp.TABSTRS = word.NIL;
    comp.ND = word.NIL;
    unsetids(heap, comp.internals);
    comp.internals = word.NIL;
    while (heap.files != word.NIL and heap.files != 0) : (heap.files = heap.t(heap.files)) {
        const fil = heap.h(heap.files);
        unsetids(heap, heap.t(fil));
        heap.tp(fil).* = word.NIL;
    }
    var ld = script_store.store().ld_stuff;
    while (ld != word.NIL and ld != 0) : (ld = heap.t(ld)) {
        var x = heap.h(ld);
        while (x != word.NIL and x != 0) : (x = heap.t(x)) {
            unsetids(heap, heap.t(heap.h(x)));
        }
    }
    script_store.store().ld_stuff = word.NIL;
}

/// Whether any loaded source file has changed on disk since load (1/0).
pub fn srcUpdate(heap: *Heap, rs: *rt.RuntimeState) i32 {
    _ = rs;
    var ft: Word = undefined;
    var f = if (heap.files == word.NIL) script_store.store().oldfiles else heap.files;
    while (f != word.NIL) {
        const _fil_path: [*:0]const u8 = strtab.strOf(strtab.table(), heap.h(heap.h(heap.h(heap.h(f)))));
        if ((fileMtime(_fil_path)) != filTime(heap.h(f))) {
            ft = fileMtime(_fil_path);
            if (ft == 0) {
                unlinkObject(core.s(), _fil_path);
            }
            return 1;
        }
        f = heap.t(f);
    }
    return 0;
}
