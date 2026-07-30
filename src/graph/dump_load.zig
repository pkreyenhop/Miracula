//! dump_load.zig (split from graph/dump.zig for the Go port's <1000-line file
//! ratchet, docs/GO_PORT_PLAN.md P4) — the read half of the `.x` wire format:
//! `loadScript`/`loadDefs`. The write half (`dumpScript`/`dumpDefs`/`dumpOb`)
//! and the shared low-level cell primitives stay in `dump.zig`; the moved
//! bodies below reach them verbatim through the `dump.*` aliases.

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

const dump = @import("dump.zig");
const ap = dump.ap;
const datapair = dump.datapair;
const fileinfo = dump.fileinfo;
const readvals = dump.readvals;
const mktvar = dump.mktvar;
const idTypePtr = dump.idTypePtr;
const idValPtr = dump.idValPtr;
const idWhoPtr = dump.idWhoPtr;
const pnVal = dump.pnVal;
const pnValPtr = dump.pnValPtr;
const stackpPush = dump.stackpPush;
const stackpPop = dump.stackpPop;
const stackpTop = dump.stackpTop;
const stackpSetTop = dump.stackpSetTop;
const dsetup = dump.dsetup;
const dgrow = dump.dgrow;
const setprefix = dump.setprefix;
const getword = dump.getword;
const getint = dump.getint;
const getdbl = dump.getdbl;
const bindparams = dump.bindparams;
const unscramble = dump.unscramble;
const dumpOb = dump.dumpOb;

/// Load a script graph from a dump `file`, binding params and aliases.
pub fn loadScript(heap: *Heap, core_st: *core.CoreState, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState, lexs: *lex_state.LexState, file: ?*word.Stream, src: [*:0]const u8, aliases: Word, params: Word, main_flag: Word) Word {
    comp.TORPHANS = 0;
    comp.BAD_DUMP = 0;
    comp.CLASHES = word.NIL;
    dsetup(heap);
    setprefix(heap, src);
    if (os.getc(file) != wordsize or os.getc(file) != word.XVERSION) {
        comp.BAD_DUMP = -1;
        return word.NIL;
    }
    if (aliases != word.NIL) {
        var a = aliases;
        comp.ALIASES = aliases;
        while (a != word.NIL) : (a = heap.t(a)) {
            const old = heap.t(heap.h(a));
            const new_id = heap.h(heap.h(a));
            const hold = heap.cons(idWho(old), heap.cons(idType(old), idVal(old)));
            idTypePtr(heap, old).* = word.alias_t;
            idValPtr(heap, old).* = new_id;
            if (heap.getTag(new_id) == .ID) {
                if ((idType(new_id) != word.undef_t or idVal(new_id) != word.UNDEF) and idType(new_id) != word.alias_t) {
                    comp.CLASHES = add1(heap, Value.fromRaw(new_id), Value.fromRaw(comp.CLASHES)).toRaw();
                }
            }
            heap.hp(heap.h(a)).* = hold;
        }
        if (comp.CLASHES != word.NIL) {
            comp.BAD_DUMP = -2;
            unscramble(heap, comp, aliases);
            return word.NIL;
        }
        a = aliases;
        while (a != word.NIL) : (a = heap.t(a)) {
            const ch = idVal(heap.t(heap.h(a)));
            if (heap.getTag(ch) == .ID) {
                if (idType(ch) != word.alias_t) {
                    idTypePtr(heap, ch).* = word.new_t;
                }
            }
        }
    }
    heap.PNBASE = lexs.nextpn;
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
            _ = os.strcpy(lexs.dicp, &heap.prefix);
            lexs.dicq = lexs.dicp + @as(usize, @intCast(heap.preflen));
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
                    unscramble(heap, comp, aliases);
                }
                return word.NIL;
            }
        }
        heap.CFN = getId(name(heap));
        files_list = heap.cons(makeFil(heap.CFN, ch, s, loadDefs(heap, comp, rs, lexs, file)), files_list);
        ch = os.getc(file);
    }
    if (ch == os.EOF or comp.BAD_DUMP != 0) {
        if (comp.BAD_DUMP == 0) {
            comp.BAD_DUMP = 2;
        }
        if (aliases != word.NIL) {
            unscramble(heap, comp, aliases);
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
                _ = os.strcpy(lexs.dicp, &heap.prefix);
                lexs.dicq = lexs.dicp + @as(usize, @intCast(heap.preflen));
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
            if (script_store.store().oldfiles == word.NIL) {
                if (os.strcmp(lexs.dicp, src) != 0) {
                    comp.BAD_DUMP = 1;
                    if (aliases != word.NIL) {
                        unscramble(heap, comp, aliases);
                    }
                    return word.NIL;
                }
            }
            script_store.store().oldfiles = heap.cons(makeFil(getId(name(heap)), ch, 0, word.NIL), script_store.store().oldfiles);
        }
        if (aliases != word.NIL) {
            unscramble(heap, comp, aliases);
        }
        return word.NIL;
    }
    comp.algshfns = append1(comp.algshfns, loadDefs(heap, comp, rs, lexs, file));
    comp.ND = loadDefs(heap, comp, rs, lexs, file);
    if (comp.ND == word.True) {
        comp.ND = word.NIL;
        comp.TORPHANS = 1;
    }
    comp.SGC = append1(comp.SGC, loadDefs(heap, comp, rs, lexs, file));
    if (main_flag != 0 or script_store.store().includees == word.NIL) {
        script_store.store().freeids = loadDefs(heap, comp, rs, lexs, file);
    } else {
        bindparams(heap, comp, loadDefs(heap, comp, rs, lexs, file), hdsort(params));
    }
    if (aliases != word.NIL) {
        unscramble(heap, comp, aliases);
    }
    if (main_flag != 0) {
        comp.internals = loadDefs(heap, comp, rs, lexs, file);
    }
    return reverse(files_list);
}

/// Load a definition list from a dump `file`.
///
/// Tests: dumpOb / loadDefs: roundtrip a cons of two ints through the .x format
pub fn loadDefs(heap: *Heap, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState, lexs: *lex_state.LexState, file: ?*word.Stream) Word {
    _ = rs;
    var ch = os.getc(file);
    var defs: Word = word.NIL;
    while (ch != os.EOF) {
        if (heap.stackp == heap.dlim) {
            dgrow(heap);
        }
        switch (ch) {
            word.CHAR_X => {
                stackpPush(heap, os.getc(file) + 128);
            },
            word.TVAR_X => {
                stackpPush(heap, mktvar(heap, os.getc(file)));
            },
            word.SHORT_X => {
                var val = os.getc(file);
                if ((val & 128) != 0) {
                    val = val | (~@as(c_int, 127));
                }
                stackpPush(heap, stosmallint(val));
            },
            word.INT_X => {
                const val = getint(file);
                stackpPush(heap, heap.make(.INT, val, 0));
                var x = &heap.tp(stackpTop(heap)).*;
                var next = getint(file);
                while (next != -1) {
                    x.* = heap.make(.INT, next, 0);
                    x = &heap.tp(x.*).*;
                    next = getint(file);
                }
            },
            word.DBL_X => {
                stackpPush(heap, getdbl(file));
            },
            word.UNICODE_X => {
                stackpPush(heap, heap.make(.UNICODE, getint(file), 0));
            },
            word.PN_X => {
                var val = os.getc(file);
                val = val | (os.getc(file) << 8);
                const idx = heap.PNBASE + val;
                stackpPush(heap, if (idx < lexs.nextpn) lexs.pnvec.?[@intCast(idx)] else lex.stoPn(heap, idx));
            },
            word.PN1_X => {
                const idx = heap.PNBASE + getint(file);
                stackpPush(heap, if (idx < lexs.nextpn) lexs.pnvec.?[@intCast(idx)] else lex.stoPn(heap, idx));
            },
            word.CONSTRUCT_X => {
                var val = os.getc(file);
                val = val | (os.getc(file) << 8);
                stackpSetTop(heap, constructor(heap, val, stackpTop(heap)));
            },
            word.RV_X => {
                stackpSetTop(heap, readvals(heap, 0, stackpTop(heap)));
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
                stackpPush(heap, name(heap));
                const top = stackpTop(heap);
                if (idType(top) == word.new_t) {
                    comp.CLASHES = add1(heap, Value.fromRaw(top), Value.fromRaw(comp.CLASHES)).toRaw();
                    stackpSetTop(heap, word.NIL);
                } else if (idType(top) == word.alias_t) {
                    stackpSetTop(heap, idVal(top));
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
                stackpPush(heap, datapair(heap, strtab.strBits(strtab.table(), getId(name(heap))), 0));
            },
            word.HERE_X => {
                lexs.dicq = lexs.dicp;
                var next = os.getc(file);
                if (next == 0) {
                    next = os.getc(file);
                    next = next | (os.getc(file) << 8);
                    stackpPush(heap, fileinfo(heap, strtab.strBits(strtab.table(), heap.CFN.?), next));
                } else {
                    if (next != '/') {
                        _ = os.strcpy(lexs.dicp, &heap.prefix);
                        lexs.dicq = lexs.dicp + @as(usize, @intCast(heap.preflen));
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
                    stackpPush(heap, fileinfo(heap, strtab.strBits(strtab.table(), getId(name(heap))), line));
                }
            },
            word.DEF_X => {
                const diff = heap.stackp.? - heap.dstack.?;
                switch (diff) {
                    0 => {
                        return reverse(defs);
                    },
                    1 => {
                        return stackpPop(heap);
                    },
                    2 => {
                        const ch_val = stackpPop(heap);
                        pnValPtr(heap, ch_val).* = stackpPop(heap);
                        defs = heap.cons(ch_val, defs);
                    },
                    4 => {
                        const top = stackpTop(heap);
                        if (heap.getTag(top) != .ID) {
                            if (top == word.NIL) {
                                heap.stackp = heap.stackp.? - 4;
                                ch = os.getc(file);
                                continue;
                            }
                            const ch_val = stackpPop(heap);
                            comp.SUPPRESSED = heap.cons(ch_val, comp.SUPPRESSED);
                            _ = stackpPop(heap); // who
                            const who_val = stackpTop(heap);
                            const akap = if (heap.getTag(who_val) == .CONS) heap.h(who_val) else word.NIL;
                            const type_val = stackpPop(heap); // type
                            pnValPtr(heap, ch_val).* = stackpPop(heap);

                            if (type_val == word.type_t and tClass(ch_val) != word.synonym_t) {
                                var a = comp.ALIASES;
                                while (a != word.NIL and idVal(heap.t(heap.h(a))) != ch_val) : (a = heap.t(a)) {}
                                if (a != word.NIL) {
                                    comp.TSUPPRESSED = heap.cons(heap.t(heap.h(a)), comp.TSUPPRESSED);
                                }
                            } else if (pnVal(heap, ch_val) == word.UNDEF) {
                                var akap_val = akap;
                                if (akap_val == word.NIL) {
                                    var a = comp.ALIASES;
                                    while (a != word.NIL) : (a = heap.t(a)) {
                                        if (idVal(heap.t(heap.h(a))) == ch_val) {
                                            akap_val = datapair(heap, strtab.strBits(strtab.table(), getId(heap.t(heap.h(a)))), 0);
                                            break;
                                        }
                                    }
                                }
                                pnValPtr(heap, ch_val).* = ap(heap, akap_val, fileinfo(heap, strtab.strBits(strtab.table(), heap.CFN.?), 0));
                            }
                            defs = heap.cons(ch_val, defs);
                            ch = os.getc(file);
                            continue;
                        }
                        const top_val = stackpTop(heap);
                        if (idType(top_val) != word.new_t and (idType(top_val) != word.undef_t or idVal(top_val) != word.UNDEF)) {
                            if (idType(top_val) == word.alias_t) {
                                var a = comp.ALIASES;
                                while (a != word.NIL and heap.t(heap.h(a)) != top_val) : (a = heap.t(a)) {}
                                if (a == word.NIL) {
                                    std.debug.print("impossible event in cyclic alias ({s})\n", .{getId(top_val)});
                                    heap.stackp = heap.stackp.? - 4;
                                    ch = os.getc(file);
                                    continue;
                                }
                                defs = heap.cons(stackpPop(heap), defs);
                                heap.hp(heap.h(heap.h(a))).* = stackpPop(heap); // who
                                heap.hp(heap.t(heap.h(heap.h(a)))).* = stackpPop(heap); // type
                                heap.tp(heap.t(heap.h(heap.h(a)))).* = stackpPop(heap); // value
                                ch = os.getc(file);
                                continue;
                            }
                            comp.CLASHES = add1(heap, Value.fromRaw(top_val), Value.fromRaw(comp.CLASHES)).toRaw();
                            heap.stackp = heap.stackp.? - 4;
                        } else {
                            defs = heap.cons(stackpPop(heap), defs);
                            idWhoPtr(heap, heap.h(defs)).* = stackpPop(heap);
                            idTypePtr(heap, heap.h(defs)).* = stackpPop(heap);
                            idValPtr(heap, heap.h(defs)).* = stackpPop(heap);
                        }
                    },
                    else => {
                        std.debug.print("unexpected stack diff in loadDefs\n", .{});
                    },
                }
            },
            word.AP_X => {
                const ch_val = stackpPop(heap);
                const top = stackpTop(heap);
                if (top == word.READ and ch_val == 0) {
                    stackpSetTop(heap, lexs.common_stdin);
                } else if (top == word.READBIN and ch_val == 0) {
                    stackpSetTop(heap, lexs.common_stdinb);
                } else {
                    stackpSetTop(heap, ap(heap, top, ch_val));
                }
            },
            word.CONS_X => {
                const ch_val = stackpPop(heap);
                stackpSetTop(heap, heap.cons(ch_val, stackpTop(heap)));
            },
            else => {
                stackpPush(heap, if (ch > 127) ch + 256 else ch);
            },
        }
        ch = os.getc(file);
    }
    comp.BAD_DUMP = 4;
    return defs;
}

test "dumpOb / loadDefs: roundtrip a cons of two ints through the .x format" {
    // 1. Initialize heap and stack
    config_state.config().SPACELIMIT = 10000;
    setupheap();
    const heap_val = heap_mod.heap();
    dsetup(heap_val);

    // 2. Build a representative structure: a cons pair of two small integers
    const item1 = stosmallint(42);
    const item2 = stosmallint(100);
    const list = cons(heap_val, item1, item2);

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
    const old_stackp = heap_val.stackp;
    _ = loadDefs(heap_val, cs(), rt.rs(), lex_state.ls(), f_read);
    _ = word.fclose(f_read.?);

    // Clean up temp file
    _ = os.unlink(filename);

    // 7. Verify structural equality
    try std.testing.expect(@intFromPtr(heap_val.stackp.?) > @intFromPtr(old_stackp.?));
    const loaded = stackpTop(heap_val);

    try std.testing.expectEqual(word.NodeTag.CONS, heap_val.getTag(loaded));
    const loaded_h = heap_val.h(loaded);
    const loaded_t = heap_val.t(loaded);

    try std.testing.expectEqual(word.NodeTag.INT, heap_val.getTag(loaded_h));
    try std.testing.expectEqual(@as(Word, 42), getsmallint(loaded_h));
    try std.testing.expectEqual(word.NodeTag.INT, heap_val.getTag(loaded_t));
    try std.testing.expectEqual(@as(Word, 100), getsmallint(loaded_t));
}
