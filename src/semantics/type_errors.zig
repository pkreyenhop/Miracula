//! type_errors.zig (split from compiler/types.zig, Phase 4 step 3,
//! docs/ZIG_NATIVE_PLAN.md) — type-error reporting (`typeError`/
//! `typeError1`-`typeError8`, `locate`/`sayhere` for source-location
//! context) and type/pattern pretty-printing (`outType*`/`outPattern`/
//! `outFormal*`) used both by error messages and `::` responses.

const std = @import("std");
const word = @import("../graph/word.zig");
const strtab = @import("../graph/strtab.zig");
const heap_mod = @import("../graph/heap.zig");
const Heap = heap_mod.Heap;
const rt = @import("../runtime/runtime_state.zig");
const script_store = @import("../session/script_store.zig");
const core_state = @import("../runtime/core_state.zig");
const compiler_state = @import("../compiler/compiler_state.zig");
const cs = compiler_state.cs;
const infer = @import("infer.zig");
const depend = @import("depend.zig");
const unify_mod = @import("unify.zig");
const lower = @import("lower.zig");

const Word = word.Word;
const Value = @import("../graph/value.zig").Value;
const NIL = word.NIL;
const CMBASE = word.CMBASE;
const CONST = word.CONST;
const PLUS: Word = CMBASE + 54;
const undef_t = word.undef_t;
const bool_t = word.bool_t;
const num_t = word.num_t;
const char_t = word.char_t;
const list_t = word.list_t;
const comma_t: Word = 5;
const arrow_t: Word = 6;
const void_t: Word = 7;
const wrong_t: Word = 8;

const getId = infer.getId;
const idType = infer.idType;
const type_t = infer.type_t;
const tArity = infer.tArity;
const tInfo = infer.tInfo;
const idWho = infer.idWho;
const getStdout = infer.getStdout;
const locateInc = infer.locateInc;
const isCompoundType = infer.isCompoundType;

const member = depend.member;
const add1 = depend.add1;

const redtvars = unify_mod.redtvars;
const subst = unify_mod.subst;
const gettvar = unify_mod.gettvar;

const same = lower.same;
const lastlink = lower.lastlink;

const print_mod = @import("../graph/print.zig");
const out = print_mod.outTerm;
const isChar = heap_mod.isChar;
const charname = print_mod.charname;
const size = heap_mod.size;
const getDbl = heap_mod.getDbl;

/// The node tag of cell `x`.
inline fn getTag(heap: *Heap, x: Word) word.NodeTag {
    return heap.getTag(x);
}

/// Head (`hd`) of cell `x`.
fn h(heap: *Heap, x: Word) Word {
    return heap.h(x);
}

/// Tail (`tl`) of cell `x`.
fn t(heap: *Heap, x: Word) Word {
    return heap.t(x);
}

/// Allocate an application cell `(x y)`.
fn ap(heap: *Heap, x: Word, y: Word) Word {
    return heap_mod.make(heap, .AP, x, y);
}

/// The value (tail) of a private-name node.
fn pnVal(heap: *Heap, x: Word) Word {
    return t(heap, x);
}

/// The sign bit of `x` (bignum negativity test).
fn neg(heap: *Heap, x: Word) Word {
    return h(heap, x) & 0x10000000;
}

/// Record the current definition name `s` for error messages.
pub fn locate(heap: *Heap, s: [*:0]const u8) void {
    cs().TYPERRS += 1;
    if (cs().TYPERRS == 1 or cs().lastloc != cs().current_id) {
        if (cs().current_id != 0) {
            if (getTag(heap, cs().current_id) == .DATAPAIR) {
                locateInc(heap);
                _ = word.print("{s} in binding for {s}\n", .{ s, strtab.strOf(strtab.table(), h(heap, cs().current_id)) });
                return;
            }
            var x = cs().current_id;
            _ = word.print("{s} in definition of ", .{s});
            while (getTag(heap, x) == .CONS) {
                if (getTag(heap, t(heap, x)) == .ID and member(heap, Value.fromRaw(script_store.store().fnts), Value.fromRaw(t(heap, x))) != 0) {
                    _ = word.print("nonterminal ", .{});
                    x = h(heap, x);
                } else {
                    outFormal1(heap, getStdout().?, h(heap, x));
                    _ = word.print(", subdef of ", .{});
                    x = t(heap, x);
                }
            }
            _ = word.print("{s}", .{getId(heap, x)});
            _ = word.print("\n", .{});
        } else {
            _ = word.print("{s} in expression\n", .{s});
        }
    }
    if (cs().lineptr != 0) {
        sayhere(heap, cs().lineptr, 0);
    } else if (cs().current_id != 0 and idWho(heap, cs().current_id) != NIL) {
        sayhere(heap, idWho(heap, cs().current_id), 0);
    }
    cs().lastloc = cs().current_id;
}

/// The source location of right-hand side `r`.
pub fn rhsHere(heap: *Heap, r: Word) Word {
    if (getTag(heap, r) == .LABEL) {
        return h(heap, r);
    }
    if (getTag(heap, r) == .TRIES) {
        return h(heap, h(heap, lastlink(heap, t(heap, r))));
    }
    return 0;
}

/// Print a source-location marker `h_val` (with optional newline).
pub fn sayhere(heap: *Heap, h_val: Word, nl: Word) void {
    var h_node = h_val;
    if (getTag(heap, h_node) != .FILEINFO) {
        h_node = rhsHere(heap, h_node);
        if (getTag(heap, h_node) != .FILEINFO) {
            _ = word.printErr("(impossible event in sayhere)\n", .{});
            return;
        }
    }
    const h_str = strtab.strOf(strtab.table(), h(heap, h_node));
    const eq = std.mem.eql(u8, std.mem.span(h_str), std.mem.span(script_store.store().current_script.?));
    const prefix: [*:0]const u8 = if (eq) "" else "%insert file ";
    word.print("(line {d:>3} of {s}\"{s}\")", .{ t(heap, h_node), prefix, h_str });
    if (nl != 0) {
        _ = word.print("\n", .{});
    } else {
        _ = word.print(" ", .{});
    }
    if (eq) {
        if (core_state.s().errline == 0) {
            core_state.s().errline = t(heap, h_node);
        }
    } else {
        if (core_state.s().errs == 0) {
            core_state.s().errs = h_node;
        }
    }
}

/// Print the inferred type of `x` (the `::` response).
pub fn reportType(heap: *Heap, x: Word) void {
    _ = word.print("{s}", .{getId(heap, x)});
    if (idType(heap, x) == type_t) {
        const arity = tArity(heap, x);
        if (arity > 5) {
            _ = word.print("(arity {d})", .{arity});
        } else {
            var i: Word = 1;
            while (i <= arity) : (i += 1) {
                _ = word.print(" ", .{});
                var j: Word = 0;
                while (j < i) : (j += 1) {
                    _ = word.print("*", .{});
                }
            }
        }
    }
    _ = word.print(" :: ", .{});
    outType(heap, idType(heap, x));
}

/// Report a type mismatch between `t1_val` and `t2_val` (`a`/`b` name the sides).
pub fn typeError(heap: *Heap, a: [*:0]const u8, b: [*:0]const u8, t1_val: Word, t2_val: Word) void {
    var t1 = redtvars(heap, ap(heap, subst(heap, t1_val), subst(heap, t2_val)));
    const t2 = t(heap, t1);
    t1 = h(heap, t1);
    locate(heap, "type error");
    _ = word.print("cannot {s} ", .{a});
    outType(heap, t1);
    _ = word.print(" {s} ", .{b});
    outType(heap, t2);
    _ = word.print("\n", .{});
}

/// Report type error variant 1 for `x`.
pub fn typeError1(heap: *Heap, x: Word) void {
    locate(heap, "type error");
    _ = word.print("typename used as identifier ({s})\n", .{getId(heap, x)});
}

/// Report type error variant 2 for `x`.
pub fn typeError2(heap: *Heap, x: Word) void {
    if (core_state.s().compiling != 0) {
        return;
    }
    cs().TYPERRS += 1;
    _ = word.print("undefined name - {s}\n", .{getId(heap, x)});
}

/// Report type error variant 3 for `x`.
pub fn typeError3(heap: *Heap, x: Word) void {
    locate(heap, "error");
    _ = word.print("constructor \"{s}\" used at wrong arity in formal\n", .{getId(heap, x)});
}

/// Report type error variant 4 for `x`.
pub fn typeError4(heap: *Heap, x: Word) void {
    locate(heap, "error");
    _ = word.print("illegal object \"", .{});
    outPattern(heap, getStdout().?, x);
    _ = word.print("\" as head of formal\n", .{});
}

/// Report type error variant 5 for `x`.
pub fn typeError5(heap: *Heap, x: Word) void {
    locate(heap, "error");
    _ = word.print("undeclared constructor \"", .{});
    outPattern(heap, getStdout().?, x);
    _ = word.print("\" in formal\n", .{});
    cs().ND = add1(heap, Value.fromRaw(x), Value.fromRaw(cs().ND)).toRaw();
}

/// Report type error variant 6 (`x` applied to `f`/`a`).
pub fn typeError6(heap: *Heap, x: Word, f: Word, a: Word) void {
    cs().TYPERRS += 1;
    _ = word.print("incorrect declaration ", .{});
    sayhere(heap, cs().lineptr, 1);
    _ = word.print("specified, {s} :: ", .{getId(heap, x)});
    outType(heap, f);
    _ = word.print("\n", .{});
    _ = word.print("inferred,  {s} :: ", .{getId(heap, x)});
    outType(heap, redtvars(heap, subst(heap, a)));
    _ = word.print("\n", .{});
}

/// Report type error variant 7 between `a` and `b`.
pub fn typeError7(heap: *Heap, a: Word, b: Word) void {
    locate(heap, "type error");
    _ = word.print("\nrhs of lex rule :: ", .{});
    outType(heap, redtvars(heap, subst(heap, b)));
    _ = word.print("\n type expected  :: ", .{});
    outType(heap, redtvars(heap, subst(heap, a)));
    _ = word.print("\n", .{});
}

/// Report type error variant 8 between `t1_val` and `t2_val`.
pub fn typeError8(heap: *Heap, t1_val: Word, t2_val: Word) void {
    var t1 = subst(heap, t1_val);
    var t2 = subst(heap, t2_val);
    if (same(heap, h(heap, t1), h(heap, t2)) != 0) {
        t1 = t(heap, t1);
        t2 = t(heap, t2);
    }
    t1 = redtvars(heap, ap(heap, t1, t2));
    t2 = t(heap, t1);
    t1 = h(heap, t1);
    const big = size(t1) >= 10 or size(t2) >= 10;
    locate(heap, "type error");
    const prefix: [*:0]const u8 = if (big) "\n " else " ";
    _ = word.print("cannot unify{s} ", .{prefix});
    outType(heap, t1);
    const infix: [*:0]const u8 = if (big) "\nwith\n  " else " with ";
    _ = word.print("{s}", .{infix});
    outType(heap, t2);
    _ = word.print("\n", .{});
}

/// Whether a type node is a function (`->`) type.
pub fn isArrowType(heap: *Heap, t_val: Word) bool {
    return getTag(heap, t_val) == .AP and getTag(heap, h(heap, t_val)) == .AP and h(heap, h(heap, t_val)) == arrow_t;
}
/// Whether a type node is a tuple (comma) type.
fn isCommaType(heap: *Heap, t_val: Word) bool {
    return getTag(heap, t_val) == .AP and getTag(heap, h(heap, t_val)) == .AP and h(heap, h(heap, t_val)) == comma_t;
}
/// Whether a type node is a list type.
fn isListType(heap: *Heap, t_val: Word) bool {
    return getTag(heap, t_val) == .AP and h(heap, t_val) == list_t;
}

/// Print a type expression `t_val`.
pub fn outType(heap: *Heap, t_val: Word) void {
    var type_node = t_val;
    while (isArrowType(heap, type_node)) {
        outType1(heap, t(heap, h(heap, type_node)));
        _ = word.print("->", .{});
        type_node = t(heap, type_node);
    }
    outType1(heap, type_node);
}

/// Print a type at the next precedence level.
pub fn outType1(heap: *Heap, t_val: Word) void {
    var type_node = t_val;
    if (isCompoundType(heap, type_node) and !isCommaType(heap, type_node) and !isListType(heap, type_node) and !isArrowType(heap, type_node)) {
        outType1(heap, h(heap, type_node));
        _ = word.print(" ", .{});
        type_node = t(heap, type_node);
    }
    outType2(heap, type_node);
}

/// Print a primary (atomic) type.
pub fn outType2(heap: *Heap, t_val: Word) void {
    if (isListType(heap, t_val)) {
        _ = word.print("[", .{});
        outType(heap, t(heap, t_val));
        _ = word.print("]", .{});
    } else if (isCompoundType(heap, t_val)) {
        _ = word.print("(", .{});
        outTypeList(heap, t_val);
        if (isCommaType(heap, t_val) and t(heap, t_val) == void_t) {
            _ = word.print(",", .{});
        }
        _ = word.print(")", .{});
    } else {
        switch (t_val) {
            bool_t => {
                _ = word.print("bool", .{});
            },
            num_t => {
                _ = word.print("num", .{});
            },
            char_t => {
                _ = word.print("char", .{});
            },
            wrong_t => {
                _ = word.print("WRONG", .{});
            },
            undef_t => {
                _ = word.print("UNKNOWN", .{});
            },
            void_t => {
                _ = word.print("()", .{});
            },
            type_t => {
                _ = word.print("type", .{});
            },
            else => {
                switch (getTag(heap, t_val)) {
                    .ID => {
                        _ = word.print("{s}", .{getId(heap, t_val)});
                    },
                    .TVAR => {
                        var n = gettvar(heap, t_val);
                        if (n > 0 and n < 7) {
                            while (n > 0) : (n -= 1) {
                                _ = word.print("*", .{});
                            }
                        } else {
                            _ = word.print("{d}", .{n});
                        }
                    },
                    .STRCONS => {
                        const pn_val_node = pnVal(heap, t_val);
                        if (getTag(heap, pn_val_node) == .ID) {
                            _ = word.print("{s}", .{getId(heap, pn_val_node)});
                        } else if (std.mem.eql(u8, std.mem.span(strtab.strOf(strtab.table(), h(heap, t(heap, tInfo(heap, t_val))))), std.mem.span(script_store.store().current_script.?))) {
                            _ = word.print("{s}", .{strtab.strOf(strtab.table(), h(heap, h(heap, tInfo(heap, t_val))))});
                        } else {
                            _ = word.print("`{s}@{s}'", .{ strtab.strOf(strtab.table(), h(heap, h(heap, tInfo(heap, t_val)))), strtab.strOf(strtab.table(), h(heap, t(heap, tInfo(heap, t_val)))) });
                        }
                    },
                    else => {
                        _ = word.print("<BADLY FORMED TYPE:{d},{d},{d}>", .{ @intFromEnum(getTag(heap, t_val)), h(heap, t_val), t(heap, t_val) });
                    },
                }
            },
        }
    }
}

/// Print a comma-separated list of types.
pub fn outTypeList(heap: *Heap, t_val: Word) void {
    var type_node = t_val;
    while (isCommaType(heap, type_node)) {
        outType(heap, t(heap, h(heap, type_node)));
        type_node = t(heap, type_node);
        if (isCommaType(heap, type_node)) {
            _ = word.print(",", .{});
        } else if (type_node != void_t) {
            _ = word.print("<>", .{});
        }
    }
    if (type_node == void_t) {
        return;
    }
    outType(heap, type_node);
}

/// The argument of the outermost type application of `x`.
pub fn tail(heap: *Heap, x_in: Word) Word {
    var x = x_in;
    cs().allchars = 1;
    while (getTag(heap, x) == .CONS) {
        const char_res = isChar(h(heap, x));
        cs().allchars = if (char_res) cs().allchars & 1 else 0;
        x = t(heap, x);
    }
    return x;
}

/// Print a formal parameter at the next precedence level.
pub fn outFormal1(heap: *Heap, f: *word.Stream, x_in: Word) void {
    var x = x_in;
    if (h(heap, x) == CONST) {
        x = t(heap, x);
    }
    if (x == NIL) {
        _ = (f).print("[]", .{});
        return;
    }
    switch (getTag(heap, x)) {
        .CONS => {
            if (tail(heap, x) == NIL) {
                if (cs().allchars != 0) {
                    _ = (f).print("\"", .{});
                    while (x != NIL) {
                        _ = (f).print("{s}", .{charname(heap, h(heap, x))});
                        x = t(heap, x);
                    }
                    _ = (f).print("\"", .{});
                } else {
                    _ = (f).print("[", .{});
                    while (x != heap.nill and x != NIL) {
                        outPattern(heap, f, h(heap, x));
                        x = t(heap, x);
                        if (x != heap.nill and x != NIL) {
                            _ = (f).print(",", .{});
                        }
                    }
                    _ = (f).print("]", .{});
                }
            } else {
                _ = (f).print("(", .{});
                outPattern(heap, f, x);
                _ = (f).print(")", .{});
            }
        },
        .AP => {
            _ = (f).print("(", .{});
            outPattern(heap, f, x);
            _ = (f).print(")", .{});
        },
        .TCONS, .PAIR => {
            _ = (f).print("(", .{});
            while (getTag(heap, x) == .TCONS) {
                outPattern(heap, f, h(heap, x));
                x = t(heap, x);
                _ = (f).print(",", .{});
            }
            outPattern(heap, f, h(heap, x));
            _ = (f).print(",", .{});
            outPattern(heap, f, t(heap, x));
            _ = (f).print(")", .{});
        },
        .INT => {
            if (neg(heap, x) != 0) {
                _ = (f).print("(", .{});
                out(heap, f, x);
                _ = (f).print(")", .{});
            } else {
                out(heap, f, x);
            }
        },
        .DOUBLE => {
            if (getDbl(x) < 0) {
                _ = (f).print("(", .{});
                out(heap, f, x);
                _ = (f).print(")", .{});
            } else {
                out(heap, f, x);
            }
        },
        else => {
            out(heap, f, x);
        },
    }
}

/// Print a pattern `x`.
pub fn outPattern(heap: *Heap, f: *word.Stream, x: Word) void {
    if (getTag(heap, x) == .CONS) {
        if (h(heap, x) == CONST and (getTag(heap, t(heap, x)) == .INT or getTag(heap, t(heap, x)) == .DOUBLE)) {
            out(heap, f, t(heap, x));
        } else if (h(heap, x) != CONST and tail(heap, x) != NIL) {
            outFormal(heap, f, h(heap, x));
            _ = (f).print(":", .{});
            outPattern(heap, f, t(heap, x));
        } else {
            outFormal(heap, f, x);
        }
    } else {
        outFormal(heap, f, x);
    }
}

/// Print a formal parameter `x`.
pub fn outFormal(heap: *Heap, f: *word.Stream, x: Word) void {
    if (getTag(heap, x) != .AP) {
        outFormal1(heap, f, x);
    } else if (getTag(heap, h(heap, x)) == .AP and h(heap, h(heap, x)) == PLUS) {
        outFormal(heap, f, t(heap, x));
        _ = (f).print("+", .{});
        out(heap, f, t(heap, h(heap, x)));
    } else {
        outFormal(heap, f, h(heap, x));
        _ = (f).print(" ", .{});
        outFormal1(heap, f, t(heap, x));
    }
}
