//! dump.zig (split from graph/heap.zig, Phase 4 step 3,
//! docs/ZIG_NATIVE_PLAN.md) — the low-level object-file (`.x`) wire format:
//! `dumpScript`/`loadScript` (and the `dumpDefs`/`dumpOb`/`loadDefs` graph
//! walk they drive), `bindparams`/`unscramble` (`%include` alias resolution),
//! and `unload`/`srcUpdate` (script teardown and staleness checks). This is
//! the byte-level counterpart to `compiler/dump.zig`'s higher-level
//! `makedump`/`undump`, which calls through to the functions here.

const std = @import("std");
const word = @import("word.zig");
const strtab = @import("strtab.zig");
const rt = @import("../runtime/runtime_state.zig");
const config_state = @import("../session/config_state.zig");
const core = @import("../runtime/core_state.zig");
const lex_state = @import("../parser/lex_state.zig");
const compiler_state = @import("../compiler/compiler_state.zig");
const depend_mod = @import("../semantics/depend.zig");
const files = @import("../io/files.zig");
const lex = @import("../parser/lex.zig");
const print = @import("print.zig");
const os = @import("../os.zig");
const heap_mod = @import("heap.zig");

const Word = i64;
const wordsize = @sizeOf(Word) * 8;
const bits_15 = 0xffff;
const SIGNBIT = 0x10000000;
const MAXDIGIT = 0x7fff;

const heap = heap_mod.heap;
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
fn gettvar(x: Word) Word {
    return t(x);
}

/// Make a type-variable node with index `i`.
fn mktvar(i: Word) Word {
    return make(.TVAR, 0, i);
}

/// The raw head digit of a bignum cell.
fn digit(x: Word) Word {
    return h(x);
}

/// The node tag of the definition's parameter-number field.
fn getPn(x: Word) Word {
    return h(x);
}

/// The parameter-number value of a definition cell.
fn pnVal(x: Word) Word {
    return t(x);
}

/// Pointer to the `who` (blame/location) field of identifier `x`.
fn idWhoPtr(x: Word) *Word {
    return tp(h(h(x)));
}

/// Pointer to the type field of identifier `x`.
fn idTypePtr(x: Word) *Word {
    return tp(h(x));
}

/// Pointer to the value field of identifier `x`.
fn idValPtr(x: Word) *Word {
    return tp(x);
}

/// Pointer to the parameter-number value field of definition cell `x`.
fn pnValPtr(x: Word) *Word {
    return tp(x);
}

/// Push `val` onto the dump scratch stack (`dstack`).
fn stackpPush(val: Word) void {
    heap().stackp.?[0] = val;
    heap().stackp = heap().stackp.? + 1;
}

/// Pop and return the top of the dump scratch stack.
fn stackpPop() Word {
    heap().stackp = heap().stackp.? - 1;
    return heap().stackp.?[0];
}

/// The top of the dump scratch stack, without popping.
fn stackpTop() Word {
    return (heap().stackp.? - 1)[0];
}

/// Overwrite the top of the dump scratch stack.
fn stackpSetTop(val: Word) void {
    (heap().stackp.? - 1)[0] = val;
}

/// A `(x . y)` pair used to record type-arity mismatches during `bindparams`.
fn datapair(x: Word, y: Word) Word {
    return make(.DATAPAIR, x, y);
}

/// A `(file . line)` source-location cell.
fn fileinfo(x: Word, y: Word) Word {
    return make(.FILEINFO, x, y);
}

/// Collapse a `STARTREADVALS`-delimited run of loaded values into `x`.
fn readvals(x: Word, y: Word) Word {
    return make(.STARTREADVALS, x, y);
}

/// Allocate an `AP` (application) cell `(x @ y)`.
fn ap(x: Word, y: Word) Word {
    return make(.AP, x, y);
}

/// Set the path prefix used to relativise dumped file names.
pub fn setprefix(p: [*:0]const u8) void {
    const p_len = std.mem.len(p);
    if (p_len >= heap().prefix.len) {
        mallocfail("prefix buffer overflow");
    }
    @memcpy(heap().prefix[0..p_len], p[0..p_len]);
    heap().prefix[p_len] = 0;

    var last_slash: ?usize = null;
    var i: usize = p_len;
    while (i > 0) {
        i -= 1;
        if (heap().prefix[i] == '/') {
            last_slash = i;
            break;
        }
    }
    if (last_slash) |idx| {
        heap().prefix[idx + 1] = 0;
        heap().preflen = @intCast(idx + 1);
    } else {
        heap().prefix[0] = 0;
        heap().preflen = 0;
    }
}

/// Rewrite path `p` relative to the dump prefix.
pub fn mkrel(p: [*:0]const u8) [*:0]const u8 {
    const p_len = std.mem.len(p);
    const prefix_len = @as(usize, @intCast(heap().preflen));
    if (prefix_len <= p_len and std.mem.eql(u8, heap().prefix[0..prefix_len], p[0..prefix_len])) {
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
pub fn geterrlin(core_st: *core.CoreState, lexs: *lex_state.LexState, t_ptr: [*:0]const u8) Word {
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
    setprefix(t_ptr);
    var ch = os.getc(f);
    lexs.dicq = lexs.dicp;
    if (ch != '/') {
        const prefix_len = @as(usize, @intCast(heap().preflen));
        @memcpy(lexs.dicp[0..prefix_len], heap().prefix[0..prefix_len]);
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
pub fn dumpScript(core_st: *core.CoreState, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState, files_val: Word, file: ?*word.Stream) void {
    _ = word.putc(@intCast(wordsize), file);
    _ = word.putc(word.XVERSION, file);

    if (files_val == word.NIL) {
        _ = word.putc(0, file);
        putword(core_st.errline, file);
        var x = rs.oldfiles;
        while (x != word.NIL) : (x = t(x)) {
            _ = word.fprint(file, "{s}", .{mkrel(getFil(h(x)) orelse "")});
            _ = word.putc(0, file);
            putword(filTime(h(x)), file);
        }
        return;
    }

    if (comp.ND != word.NIL) {
        _ = word.putc(1, file);
        putword(core_st.errline, file);
    }

    var f_list = files_val;
    while (f_list != word.NIL) : (f_list = t(f_list)) {
        heap().CFN = getFil(h(f_list)) orelse "";
        _ = word.fprint(file, "{s}", .{mkrel(heap().CFN.?)});
        _ = word.putc(0, file);
        putword(filTime(h(f_list)), file);
        _ = word.putc(@intCast(filShare(h(f_list))), file);
        dumpDefs(filDefs(h(f_list)), file);
    }
    _ = word.putc(0, file);
    dumpDefs(comp.algshfns, file);
    if (comp.ND == word.NIL and rs.bereaved != word.NIL) {
        dumpOb(word.True, file);
    } else {
        dumpOb(comp.ND, file);
    }
    _ = word.putc(word.DEF_X, file);
    dumpOb(comp.SGC, file);
    _ = word.putc(word.DEF_X, file);
    dumpOb(rs.freeids, file);
    _ = word.putc(word.DEF_X, file);
    dumpDefs(comp.internals, file);
}

/// Write a definition list to dump `file`.
pub fn dumpDefs(defs_val: Word, file: ?*word.Stream) void {
    var defs = defs_val;
    while (defs != word.NIL) : (defs = t(defs)) {
        const item = h(defs);
        if (getTag(item) == .STRCONS) {
            const v = getPn(item);
            dumpOb(pnVal(item), file);
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
pub fn dumpOb(x: Word, file: ?*word.Stream) void {
    switch (heap().getTag(x)) {
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
            _ = word.putc(@intCast(gettvar(x)), file);
            if (gettvar(x) > 255) {
                std.debug.print("panic, tvar too large\n", .{});
            }
        },
        .INT => {
            var curr = x;
            const d = digit(curr);
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
                putint(@intCast(digit(curr)), file);
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
            putint(@intCast(h(x)), file);
        },
        .DATAPAIR => {
            _ = word.fprint(file, "{c}{s}", .{ @as(u8, @intCast(word.AKA_X)), castPtr(h(x)) });
            _ = word.putc(0, file);
        },
        .FILEINFO => {
            var line = t(x);
            const path = castPtr(h(x));
            if (os.strcmp(path, heap().CFN.?) == 0) {
                _ = word.putc(word.HERE_X, file);
            } else {
                _ = word.fprint(file, "{c}{s}", .{ @as(u8, @intCast(word.HERE_X)), mkrel(path) });
            }
            _ = word.putc(0, file);
            _ = word.putc(@intCast(line & 255), file);
            line >>= 8;
            _ = word.putc(@intCast(line & 255), file);
            if (line > 255) {
                std.debug.print("impossible line number {d} in dumpOb\n", .{t(x)});
            }
        },
        .CONSTRUCTOR => {
            dumpOb(t(x), file);
            _ = word.putc(word.CONSTRUCT_X, file);
            _ = word.putc(@intCast(h(x) & 255), file);
            _ = word.putc(@intCast(h(x) >> 8), file);
        },
        .STARTREADVALS => {
            dumpOb(t(x), file);
            _ = word.putc(word.RV_X, file);
        },
        .ID => {
            _ = word.fprint(file, "{c}{s}", .{ @as(u8, @intCast(word.ID_X)), getId(x) });
            _ = word.putc(0, file);
        },
        .STRCONS => {
            const v = getPn(x);
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
            dumpOb(h(x), file);
            dumpOb(t(x), file);
            _ = word.putc(word.AP_X, file);
        },
        .CONS => {
            dumpOb(t(x), file);
            dumpOb(h(x), file);
            _ = word.putc(word.CONS_X, file);
        },
        else => {
            std.debug.print("impossible tag {d} in dumpOb\n", .{heap().getTag(x)});
        },
    }
}

/// Load a script graph from a dump `file`, binding params and aliases.
pub fn loadScript(core_st: *core.CoreState, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState, lexs: *lex_state.LexState, file: ?*word.Stream, src: [*:0]const u8, aliases: Word, params: Word, main_flag: Word) Word {
    comp.TORPHANS = 0;
    comp.BAD_DUMP = 0;
    comp.CLASHES = word.NIL;
    dsetup();
    setprefix(src);
    if (os.getc(file) != wordsize or os.getc(file) != word.XVERSION) {
        comp.BAD_DUMP = -1;
        return word.NIL;
    }
    if (aliases != word.NIL) {
        var a = aliases;
        comp.ALIASES = aliases;
        while (a != word.NIL) : (a = t(a)) {
            const old = t(h(a));
            const new_id = h(h(a));
            const hold = cons(idWho(old), cons(idType(old), idVal(old)));
            idTypePtr(old).* = word.alias_t;
            idValPtr(old).* = new_id;
            if (getTag(new_id) == .ID) {
                if ((idType(new_id) != word.undef_t or idVal(new_id) != word.UNDEF) and idType(new_id) != word.alias_t) {
                    comp.CLASHES = add1(heap(), new_id, comp.CLASHES);
                }
            }
            hp(h(a)).* = hold;
        }
        if (comp.CLASHES != word.NIL) {
            comp.BAD_DUMP = -2;
            unscramble(comp, aliases);
            return word.NIL;
        }
        a = aliases;
        while (a != word.NIL) : (a = t(a)) {
            const ch = idVal(t(h(a)));
            if (getTag(ch) == .ID) {
                if (idType(ch) != word.alias_t) {
                    idTypePtr(ch).* = word.new_t;
                }
            }
        }
    }
    heap().PNBASE = lexs.nextpn;
    comp.SUPPRESSED = word.NIL;
    comp.TSUPPRESSED = word.NIL;

    var files_list: Word = word.NIL;
    var ch: Word = os.getc(file);
    while (ch != 0 and ch != os.EOF and comp.BAD_DUMP == 0) {
        var s: Word = 0;
        var holde: Word = 0;
        lexs.dicq = lexs.dicp;
        if (files_list == word.NIL and ch == 1) {
            holde = getword(file);
            ch = os.getc(file);
            if (main_flag != 0) {
                core_st.errline = holde;
            }
        }
        if (ch != '/') {
            _ = os.strcpy(lexs.dicp, &heap().prefix);
            lexs.dicq = lexs.dicp + @as(usize, @intCast(heap().preflen));
        }
        lexs.dicq[0] = @intCast(ch);
        lexs.dicq += 1;
        while (true) {
            ch = os.getc(file);
            lexs.dicq[0] = @intCast(ch);
            lexs.dicq += 1;
            if (ch == 0 or ch == os.EOF) {
                break;
            }
        }
        if (@intFromPtr(lexs.dicq) - @intFromPtr(lexs.dicp) > config_state.config().DICSPACE) {
            lex.dicovflo();
        }
        ch = getword(file);
        s = os.getc(file);
        if (files_list == word.NIL) {
            if (os.strcmp(lexs.dicp, src) != 0) {
                comp.BAD_DUMP = 1;
                if (aliases != word.NIL) {
                    unscramble(comp, aliases);
                }
                return word.NIL;
            }
        }
        heap().CFN = getId(name(heap()));
        files_list = cons(makeFil(heap().CFN, ch, s, loadDefs(comp, rs, lexs, file)), files_list);
        ch = os.getc(file);
    }
    if (ch == os.EOF or comp.BAD_DUMP != 0) {
        if (comp.BAD_DUMP == 0) {
            comp.BAD_DUMP = 2;
        }
        if (aliases != word.NIL) {
            unscramble(comp, aliases);
        }
        return files_list;
    }
    if (files_list == word.NIL) {
        ch = getword(file);
        if (main_flag != 0) {
            core_st.errline = ch;
        }
        while (true) {
            ch = os.getc(file);
            if (ch == os.EOF) {
                break;
            }
            lexs.dicq = lexs.dicp;
            if (ch != '/') {
                _ = os.strcpy(lexs.dicp, &heap().prefix);
                lexs.dicq = lexs.dicp + @as(usize, @intCast(heap().preflen));
            }
            lexs.dicq[0] = @intCast(ch);
            lexs.dicq += 1;
            while (true) {
                ch = os.getc(file);
                lexs.dicq[0] = @intCast(ch);
                lexs.dicq += 1;
                if (ch == 0 or ch == os.EOF) {
                    break;
                }
            }
            if (@intFromPtr(lexs.dicq) - @intFromPtr(lexs.dicp) > config_state.config().DICSPACE) {
                lex.dicovflo();
            }
            ch = getword(file);
            if (rs.oldfiles == word.NIL) {
                if (os.strcmp(lexs.dicp, src) != 0) {
                    comp.BAD_DUMP = 1;
                    if (aliases != word.NIL) {
                        unscramble(comp, aliases);
                    }
                    return word.NIL;
                }
            }
            rs.oldfiles = cons(makeFil(getId(name(heap())), ch, 0, word.NIL), rs.oldfiles);
        }
        if (aliases != word.NIL) {
            unscramble(comp, aliases);
        }
        return word.NIL;
    }
    comp.algshfns = append1(comp.algshfns, loadDefs(comp, rs, lexs, file));
    comp.ND = loadDefs(comp, rs, lexs, file);
    if (comp.ND == word.True) {
        comp.ND = word.NIL;
        comp.TORPHANS = 1;
    }
    comp.SGC = append1(comp.SGC, loadDefs(comp, rs, lexs, file));
    if (main_flag != 0 or rs.includees == word.NIL) {
        rs.freeids = loadDefs(comp, rs, lexs, file);
    } else {
        bindparams(comp, loadDefs(comp, rs, lexs, file), hdsort(params));
    }
    if (aliases != word.NIL) {
        unscramble(comp, aliases);
    }
    if (main_flag != 0) {
        comp.internals = loadDefs(comp, rs, lexs, file);
    }
    return reverse(files_list);
}

/// Bind a `%include`'s formal parameters to the actual arguments.
pub fn bindparams(comp: *compiler_state.CompilerState, formal_val: Word, actual_val: Word) void {
    var formal = formal_val;
    var actual = actual_val;
    var badkind: Word = word.NIL;
    comp.DETROP = word.NIL;
    comp.MISSING = word.NIL;
    comp.FBS = cons(formal, comp.FBS);

    while (true) {
        var a: Word = 0;
        var f: [*:0]const u8 = undefined;
        while (formal != word.NIL and (actual == word.NIL or blk: {
            f = castPtr(h(h(t(h(formal)))));
            a = h(h(actual));
            break :blk os.strcmp(f, getId(a)) < 0;
        })) {
            comp.MISSING = cons(h(t(h(formal))), comp.MISSING);
            formal = t(formal);
        }
        if (actual == word.NIL) {
            break;
        }
        if (formal == word.NIL or os.strcmp(f, getId(a)) != 0) {
            comp.DETROP = cons(a, comp.DETROP);
        } else {
            const fa = if (t(t(h(formal))) == word.type_t) tArity(h(h(formal))) else -1;
            const ta = if (getTag(h(actual)) == .AP) tArity(h(actual)) else -1;
            if (fa != ta) {
                badkind = cons(cons(h(h(actual)), datapair(fa, ta)), badkind);
            }
            idValPtr(h(h(formal))).* = t(h(actual));
            formal = t(formal);
        }
        actual = t(actual);
    }

    var bk = badkind;
    while (bk != word.NIL) : (bk = t(bk)) {
        comp.DETROP = cons(h(bk), comp.DETROP);
    }
}

/// Resolve `%include` aliases in the freshly-loaded graph.
pub fn unscramble(comp: *compiler_state.CompilerState, aliases: Word) void {
    var a = aliases;
    while (a != word.NIL) : (a = t(a)) {
        const old = t(h(a));
        var hold = h(h(a));
        const new_id = idVal(old);
        hp(h(a)).* = new_id;
        idWhoPtr(old).* = h(hold);
        hold = t(hold);
        idTypePtr(old).* = h(hold);
        idValPtr(old).* = t(hold);
    }
    var al = comp.ALIASES;
    a = word.NIL;
    while (al != word.NIL) : (al = t(al)) {
        const new_id = h(h(al));
        const old = t(h(al));
        if (getTag(new_id) != .ID) {
            if (member(heap(), comp.SUPPRESSED, new_id) == 0) {
                a = cons(old, a);
            }
            continue;
        }
        if (idType(new_id) == word.new_t) {
            idTypePtr(new_id).* = word.undef_t;
        }
        if (idType(new_id) == word.undef_t) {
            a = cons(old, a);
        } else if (member(heap(), comp.CLASHES, new_id) == 0) {
            if (getTag(idWho(new_id)) != .CONS) {
                idWhoPtr(new_id).* = cons(datapair(strtab.strBits(strtab.table(), getId(old)), 0), idWho(new_id));
            }
        }
    }
    comp.ALIASES = a;
}

/// Allocate the dump scratch stack (`dstack`).
pub fn dsetup() void {
    if (heap().dstack == null) {
        const slice = rt.allocator.alloc(Word, 1000) catch mallocPanic("dstack");
        heap().dstack = slice.ptr;
        heap().dlim = heap().dstack.? + 1000;
        heap().allocated_dstack_size = 1000;
    }
    heap().stackp = heap().dstack;
}

/// Grow the dump scratch stack when it overflows.
pub fn dgrow() void {
    const hold = heap().dstack.?;
    const num_elements = heap().dlim.? - hold;
    const old_slice = hold[0..heap().allocated_dstack_size];
    const new_size = num_elements * 2;
    const slice = rt.allocator.realloc(old_slice, new_size) catch mallocPanic("dstack");
    heap().dstack = slice.ptr;
    heap().dlim = heap().dstack.? + new_size;
    heap().stackp = heap().dstack.? + (heap().stackp.? - hold);
    heap().allocated_dstack_size = new_size;
}

/// Load a definition list from a dump `file`.
///
/// Tests: dumpOb / loadDefs: roundtrip a cons of two ints through the .x format
pub fn loadDefs(comp: *compiler_state.CompilerState, rs: *rt.RuntimeState, lexs: *lex_state.LexState, file: ?*word.Stream) Word {
    _ = rs;
    var ch = os.getc(file);
    var defs: Word = word.NIL;
    while (ch != os.EOF) {
        if (heap().stackp == heap().dlim) {
            dgrow();
        }
        switch (ch) {
            word.CHAR_X => {
                stackpPush(os.getc(file) + 128);
            },
            word.TVAR_X => {
                stackpPush(mktvar(os.getc(file)));
            },
            word.SHORT_X => {
                var val = os.getc(file);
                if ((val & 128) != 0) {
                    val = val | (~@as(c_int, 127));
                }
                stackpPush(stosmallint(val));
            },
            word.INT_X => {
                const val = getint(file);
                stackpPush(make(.INT, val, 0));
                var x = &tp(stackpTop()).*;
                var next = getint(file);
                while (next != -1) {
                    x.* = make(.INT, next, 0);
                    x = &tp(x.*).*;
                    next = getint(file);
                }
            },
            word.DBL_X => {
                stackpPush(getdbl(file));
            },
            word.UNICODE_X => {
                stackpPush(make(.UNICODE, getint(file), 0));
            },
            word.PN_X => {
                var val = os.getc(file);
                val = val | (os.getc(file) << 8);
                const idx = heap().PNBASE + val;
                stackpPush(if (idx < lexs.nextpn) lexs.pnvec.?[@intCast(idx)] else lex.stoPn(idx));
            },
            word.PN1_X => {
                const idx = heap().PNBASE + getint(file);
                stackpPush(if (idx < lexs.nextpn) lexs.pnvec.?[@intCast(idx)] else lex.stoPn(idx));
            },
            word.CONSTRUCT_X => {
                var val = os.getc(file);
                val = val | (os.getc(file) << 8);
                stackpSetTop(constructor(heap(), val, stackpTop()));
            },
            word.RV_X => {
                stackpSetTop(readvals(0, stackpTop()));
                comp.rv_script = 1;
            },
            word.ID_X => {
                lexs.dicq = lexs.dicp;
                while (true) {
                    const next = os.getc(file);
                    lexs.dicq[0] = @intCast(next);
                    lexs.dicq += 1;
                    if (next == 0 or next == os.EOF) {
                        break;
                    }
                }
                if (@intFromPtr(lexs.dicq) - @intFromPtr(lexs.dicp) > config_state.config().DICSPACE) {
                    lex.dicovflo();
                }
                stackpPush(name(heap()));
                const top = stackpTop();
                if (idType(top) == word.new_t) {
                    comp.CLASHES = add1(heap(), top, comp.CLASHES);
                    stackpSetTop(word.NIL);
                } else if (idType(top) == word.alias_t) {
                    stackpSetTop(idVal(top));
                }
            },
            word.AKA_X => {
                lexs.dicq = lexs.dicp;
                while (true) {
                    const next = os.getc(file);
                    lexs.dicq[0] = @intCast(next);
                    lexs.dicq += 1;
                    if (next == 0 or next == os.EOF) {
                        break;
                    }
                }
                if (@intFromPtr(lexs.dicq) - @intFromPtr(lexs.dicp) > config_state.config().DICSPACE) {
                    lex.dicovflo();
                }
                stackpPush(datapair(strtab.strBits(strtab.table(), getId(name(heap()))), 0));
            },
            word.HERE_X => {
                lexs.dicq = lexs.dicp;
                var next = os.getc(file);
                if (next == 0) {
                    next = os.getc(file);
                    next = next | (os.getc(file) << 8);
                    stackpPush(fileinfo(strtab.strBits(strtab.table(), heap().CFN.?), next));
                } else {
                    if (next != '/') {
                        _ = os.strcpy(lexs.dicp, &heap().prefix);
                        lexs.dicq = lexs.dicp + @as(usize, @intCast(heap().preflen));
                    }
                    lexs.dicq[0] = @intCast(next);
                    lexs.dicq += 1;
                    while (true) {
                        const val = os.getc(file);
                        lexs.dicq[0] = @intCast(val);
                        lexs.dicq += 1;
                        if (val == 0 or val == os.EOF) {
                            break;
                        }
                    }
                    if (@intFromPtr(lexs.dicq) - @intFromPtr(lexs.dicp) > config_state.config().DICSPACE) {
                        lex.dicovflo();
                    }
                    var line = os.getc(file);
                    line = line | (os.getc(file) << 8);
                    stackpPush(fileinfo(strtab.strBits(strtab.table(), getId(name(heap()))), line));
                }
            },
            word.DEF_X => {
                const diff = heap().stackp.? - heap().dstack.?;
                switch (diff) {
                    0 => {
                        return reverse(defs);
                    },
                    1 => {
                        return stackpPop();
                    },
                    2 => {
                        const ch_val = stackpPop();
                        pnValPtr(ch_val).* = stackpPop();
                        defs = cons(ch_val, defs);
                    },
                    4 => {
                        const top = stackpTop();
                        if (getTag(top) != .ID) {
                            if (top == word.NIL) {
                                heap().stackp = heap().stackp.? - 4;
                                ch = os.getc(file);
                                continue;
                            }
                            const ch_val = stackpPop();
                            comp.SUPPRESSED = cons(ch_val, comp.SUPPRESSED);
                            _ = stackpPop(); // who
                            const who_val = stackpTop();
                            const akap = if (getTag(who_val) == .CONS) h(who_val) else word.NIL;
                            const type_val = stackpPop(); // type
                            pnValPtr(ch_val).* = stackpPop();

                            if (type_val == word.type_t and tClass(ch_val) != word.synonym_t) {
                                var a = comp.ALIASES;
                                while (a != word.NIL and idVal(t(h(a))) != ch_val) : (a = t(a)) {}
                                if (a != word.NIL) {
                                    comp.TSUPPRESSED = cons(t(h(a)), comp.TSUPPRESSED);
                                }
                            } else if (pnVal(ch_val) == word.UNDEF) {
                                var akap_val = akap;
                                if (akap_val == word.NIL) {
                                    var a = comp.ALIASES;
                                    while (a != word.NIL) : (a = t(a)) {
                                        if (idVal(t(h(a))) == ch_val) {
                                            akap_val = datapair(strtab.strBits(strtab.table(), getId(t(h(a)))), 0);
                                            break;
                                        }
                                    }
                                }
                                pnValPtr(ch_val).* = ap(akap_val, fileinfo(strtab.strBits(strtab.table(), heap().CFN.?), 0));
                            }
                            defs = cons(ch_val, defs);
                            ch = os.getc(file);
                            continue;
                        }
                        const top_val = stackpTop();
                        if (idType(top_val) != word.new_t and (idType(top_val) != word.undef_t or idVal(top_val) != word.UNDEF)) {
                            if (idType(top_val) == word.alias_t) {
                                var a = comp.ALIASES;
                                while (a != word.NIL and t(h(a)) != top_val) : (a = t(a)) {}
                                if (a == word.NIL) {
                                    std.debug.print("impossible event in cyclic alias ({s})\n", .{getId(top_val)});
                                    heap().stackp = heap().stackp.? - 4;
                                    ch = os.getc(file);
                                    continue;
                                }
                                defs = cons(stackpPop(), defs);
                                hp(h(h(a))).* = stackpPop(); // who
                                hp(t(h(h(a)))).* = stackpPop(); // type
                                tp(t(h(h(a)))).* = stackpPop(); // value
                                ch = os.getc(file);
                                continue;
                            }
                            comp.CLASHES = add1(heap(), top_val, comp.CLASHES);
                            heap().stackp = heap().stackp.? - 4;
                        } else {
                            defs = cons(stackpPop(), defs);
                            idWhoPtr(h(defs)).* = stackpPop();
                            idTypePtr(h(defs)).* = stackpPop();
                            idValPtr(h(defs)).* = stackpPop();
                        }
                    },
                    else => {
                        std.debug.print("unexpected stack diff in loadDefs\n", .{});
                    },
                }
            },
            word.AP_X => {
                const ch_val = stackpPop();
                const top = stackpTop();
                if (top == word.READ and ch_val == 0) {
                    stackpSetTop(lexs.common_stdin);
                } else if (top == word.READBIN and ch_val == 0) {
                    stackpSetTop(lexs.common_stdinb);
                } else {
                    stackpSetTop(ap(top, ch_val));
                }
            },
            word.CONS_X => {
                const ch_val = stackpPop();
                stackpSetTop(cons(ch_val, stackpTop()));
            },
            else => {
                stackpPush(if (ch > 127) ch + 256 else ch);
            },
        }
        ch = os.getc(file);
    }
    comp.BAD_DUMP = 4;
    return defs;
}

/// Clear the values of all ids defined in `d_val` (on unload).
pub fn unsetids(d_val: Word) void {
    var d = d_val;
    while (d != word.NIL and d != 0) : (d = t(d)) {
        const item = h(d);
        if (getTag(item) == .ID) {
            tp(item).* = word.UNDEF;
            tp(h(h(item))).* = word.NIL;
            tp(h(item)).* = word.undef_t;
        }
    }
}

/// Unload the current script: clear its definitions from the environment.
pub fn unload(comp: *compiler_state.CompilerState, rs: *rt.RuntimeState, lexs: *lex_state.LexState) void {
    rs.sorted = 0;
    comp.speclocs = word.NIL;
    lexs.nextpn = 0;
    comp.rv_script = 0;
    comp.algshfns = word.NIL;
    unsetids(comp.newtyps);
    comp.newtyps = word.NIL;
    unsetids(rs.freeids);
    rs.freeids = word.NIL;
    rs.includees = word.NIL;
    comp.SGC = word.NIL;
    comp.TABSTRS = word.NIL;
    comp.ND = word.NIL;
    unsetids(comp.internals);
    comp.internals = word.NIL;
    while (heap().files != word.NIL and heap().files != 0) : (heap().files = t(heap().files)) {
        const fil = h(heap().files);
        unsetids(t(fil));
        tp(fil).* = word.NIL;
    }
    var ld = rs.ld_stuff;
    while (ld != word.NIL and ld != 0) : (ld = t(ld)) {
        var x = h(ld);
        while (x != word.NIL and x != 0) : (x = t(x)) {
            unsetids(t(h(x)));
        }
    }
    rs.ld_stuff = word.NIL;
}

/// Whether any loaded source file has changed on disk since load (1/0).
pub fn srcUpdate(rs: *rt.RuntimeState) c_int {
    var ft: Word = undefined;
    var f = if (heap().files == word.NIL) rs.oldfiles else heap().files;
    while (f != word.NIL) {
        const _fil_path: [*:0]const u8 = strtab.strOf(strtab.table(), h(h(h(h(f)))));
        if ((fileMtime(_fil_path)) != filTime(h(f))) {
            ft = fileMtime(_fil_path);
            if (ft == 0) {
                unlinkObject(core.s(), _fil_path);
            }
            return 1;
        }
        f = t(f);
    }
    return 0;
}

test "dumpOb / loadDefs: roundtrip a cons of two ints through the .x format" {
    // 1. Initialize heap and stack
    config_state.config().SPACELIMIT = 10000;
    setupheap();
    dsetup();

    // 2. Build a representative structure: a cons pair of two small integers
    const item1 = stosmallint(42);
    const item2 = stosmallint(100);
    const list = cons(item1, item2);

    // 3. Open a temp file for writing
    const filename = "test_roundtrip.dump";
    const f_write = word.fopen(filename, "w");
    try std.testing.expect(f_write != null);

    // 4. Dump the object structure
    dumpOb(list, f_write);
    _ = word.fclose(f_write.?);

    // 5. Open the temp file for reading
    const f_read = word.fopen(filename, "r");
    try std.testing.expect(f_read != null);

    // 6. Load it back using loadDefs (which pushes it onto stackp)
    const old_stackp = heap().stackp;
    _ = loadDefs(cs(), rt.rs(), lex_state.ls(), f_read);
    _ = word.fclose(f_read.?);

    // Clean up temp file
    _ = os.unlink(filename);

    // 7. Verify structural equality
    try std.testing.expect(@intFromPtr(heap().stackp.?) > @intFromPtr(old_stackp.?));
    const loaded = stackpTop();

    try std.testing.expectEqual(word.NodeTag.CONS, heap().getTag(loaded));
    const loaded_h = h(loaded);
    const loaded_t = t(loaded);

    try std.testing.expectEqual(word.NodeTag.INT, heap().getTag(loaded_h));
    try std.testing.expectEqual(@as(Word, 42), getsmallint(loaded_h));
    try std.testing.expectEqual(word.NodeTag.INT, heap().getTag(loaded_t));
    try std.testing.expectEqual(@as(Word, 100), getsmallint(loaded_t));
}
