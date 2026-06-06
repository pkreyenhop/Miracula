const std = @import("std");

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("signal.h");
    @cInclude("setjmp.h");
    @cInclude("data.h");
    @cInclude("combs.h");
});

const Word = c_long;
const ATOMLIMIT = c.ATOMLIMIT;
const NIL = c.NIL;
const NILS = c.NILS;
const STRCONS = c.STRCONS;
const INT = c.INT;
const DOUBLE = c.DOUBLE;
const ID = c.ID;
const UNICODE = c.UNICODE;
const CONS = c.CONS;

export var hd: ?[*]Word = null;
export var tl: ?[*]Word = null;
export var tag: ?[*]u8 = null;

extern fn reverse(x: Word) Word;
extern fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int;
extern fn fpe_error(sig: c_int) void;

const fpdatum = if (@sizeOf(Word) == 4)
    extern union {
        real: f64,
        bits: extern struct {
            left: Word,
            right: Word,
        },
    }
else if (@sizeOf(Word) == 8)
    extern union {
        real: f64,
        bits: Word,
    }
else
    @compileError("platform has unknown word size");

var charname_buffer: [8]u8 = undefined;

fn h(x: Word) Word {
    if (x < ATOMLIMIT) return 0;
    return hd.?[@as(usize, @intCast(x)) * 2];
}

fn hp(x: Word) *Word {
    std.debug.assert(x >= ATOMLIMIT);
    return &hd.?[@as(usize, @intCast(x)) * 2];
}

fn t(x: Word) Word {
    if (x < ATOMLIMIT) return 0;
    return tl.?[@as(usize, @intCast(x)) * 2];
}

fn tp(x: Word) *Word {
    std.debug.assert(x >= ATOMLIMIT);
    return &tl.?[@as(usize, @intCast(x)) * 2];
}

fn cons(x: Word, y: Word) Word {
    return make(CONS, x, y);
}

fn idWho(x: Word) Word {
    return t(h(h(x)));
}

fn getId(x: Word) [*:0]const u8 {
    return @ptrFromInt(@as(usize, @intCast(h(h(h(x))))));
}

export fn sto_char(ch: c_int) Word {
    return if (ch < 256) ch else make(UNICODE, ch, 0);
}

export fn get_char(x: Word) Word {
    if (x < 256) return x;
    if (tag.?[@intCast(x)] == UNICODE) return h(x);
    std.debug.print("impossible event in get_char(x), tag[x]=={d}\n", .{tag.?[@intCast(x)]});
    c.exit(1);
}

export fn is_char(x: Word) c_int {
    if (0 <= x and x < 256) return 1;
    if (x >= 0 and tag.?[@intCast(x)] == UNICODE) return 1;
    return 0;
}

export fn get_here(x: Word) Word {
    const y = idWho(x);
    return if (tag.?[@intCast(y)] == CONS) t(y) else y;
}

export fn getaka(x: Word) [*:0]const u8 {
    const y = idWho(x);
    return if (tag.?[@intCast(y)] != CONS) getId(x) else @ptrFromInt(@as(usize, @intCast(h(h(y)))));
}

export fn append1(x: Word, y: Word) Word {
    var x1 = x;
    if (x1 == nil()) return y;
    while (t(x1) != nil()) x1 = t(x1);
    tp(x1).* = y;
    return x;
}

export fn hdsort(input: Word) Word {
    var x = input;
    var a: Word = nil();
    var b: Word = nil();
    if (x == nil()) return nil();
    if (t(x) == nil()) return x;
    while (x != nil()) {
        const hold = a;
        a = cons(h(x), b);
        b = hold;
        x = t(x);
    }
    a = hdsort(a);
    b = hdsort(b);
    while (a != nil() and b != nil()) {
        if (strcmp(getId(h(h(a))), getId(h(h(b)))) < 0) {
            x = cons(h(a), x);
            a = t(a);
        } else {
            x = cons(h(b), x);
            b = t(b);
        }
    }
    if (a == nil()) a = b;
    while (a != nil()) {
        x = cons(h(a), x);
        a = t(a);
    }
    return reverse(x);
}

export fn charname(ch: Word) [*:0]const u8 {
    return switch (ch) {
        '\n' => "\\n",
        '\t' => "\\t",
        '\x08' => "\\b",
        '\x0c' => "\\f",
        '\r' => "\\r",
        '\\' => "\\\\",
        '\'' => "\\'",
        '"' => "\\\"",
        else => blk: {
            if (ch < 32 or ch > 126) {
                const text = std.fmt.bufPrintZ(&charname_buffer, "\\{d}", .{ch}) catch unreachable;
                break :blk text.ptr;
            }
            charname_buffer[0] = @intCast(ch);
            charname_buffer[1] = 0;
            break :blk @as([*:0]const u8, @ptrCast(charname_buffer[0..].ptr));
        },
    };
}

export fn outr(file: ?*c.FILE, value: f64) void {
    const magnitude = if (value < 0) -value else value;
    if (magnitude >= 1000.0 or magnitude <= 0.001) {
        _ = c.fprintf(file, "%e", value);
    } else {
        _ = c.fprintf(file, "%f", value);
    }
}

export fn get_dbl(x: Word) f64 {
    var r: fpdatum = undefined;
    if (comptime @sizeOf(Word) == 4) {
        r.bits.left = h(x);
        r.bits.right = t(x);
    } else {
        r.bits = h(x);
    }
    return r.real;
}

export fn sto_dbl(R_val: f64) Word {
    if (!std.math.isFinite(R_val)) {
        fpe_error(c.SIGFPE);
    }
    var r: fpdatum = undefined;
    r.real = R_val;
    if (comptime @sizeOf(Word) == 4) {
        return make(DOUBLE, r.bits.left, r.bits.right);
    } else {
        return make(DOUBLE, r.bits, 0);
    }
}

export fn setdbl(x: Word, R_val: f64) void {
    if (!std.math.isFinite(R_val)) {
        fpe_error(c.SIGFPE);
    }
    var r: fpdatum = undefined;
    r.real = R_val;
    tag.?[@intCast(x)] = DOUBLE;
    if (comptime @sizeOf(Word) == 4) {
        hp(x).* = r.bits.left;
        tp(x).* = r.bits.right;
    } else {
        hp(x).* = r.bits;
        tp(x).* = 0;
    }
}

fn nil() Word {
    return 306 + 138;
}

export var SPACE: Word = 1250000;
export var listp: Word = ATOMLIMIT - 1;
export var files: Word = 0;
export var current_file: Word = 0;
export var cellcount: i64 = 0;
export var claims: c_long = 0;
export var nogcs: c_long = 0;
export var dstack: ?[*]Word = null;
export var stackp: ?[*]Word = null;
export var collecting: c_int = 0;

var heap: ?[*]Word = null;
var dlim: ?[*]Word = null;

extern var SPACELIMIT: Word;
extern var atgc: c_int;
extern var loading: c_int;
extern var compiling: c_int;
extern var rv_expr: Word;
extern var rv_script: Word;
extern var cstack: ?[*]Word;
extern var fileq: Word;
extern var primenv: Word;
extern var ideep: c_int;
extern var make_status: Word;
extern var idsused: Word;
extern var eprodnts: Word;
extern var nonterminals: Word;
extern var ntmap: Word;
extern var ihlist: Word;
extern var ntspecmap: Word;
extern var gvars: Word;
extern var lexvar: Word;
extern var common_stdin: Word;
extern var common_stdinb: Word;
extern var cook_stdin: Word;
extern var margstack: Word;
extern var vergstack: Word;
extern var litstack: Word;
extern var linostack: Word;
extern var prefixstack: Word;
extern var oldfiles: Word;
extern var includees: Word;
extern var freeids: Word;
extern var exports: Word;
extern var exportfiles: Word;
extern var internals: Word;
extern var CLASHES: Word;
extern var ALIASES: Word;
extern var SUPPRESSED: Word;
extern var TSUPPRESSED: Word;
extern var DETROP: Word;
extern var MISSING: Word;
extern var FBS: Word;
extern var lexstates: Word;
extern var lexdefs: Word;
extern var namebucket: [128]Word;
extern var nextpn: Word;
extern var pnvec: ?[*]Word;
extern var lastname: Word;
extern var suppressids: Word;
extern var lastexp: Word;
extern var nill: Word;
extern var standardout: Word;
extern var big_one: Word;
extern var yyval: Word;
extern var yylval: Word;
extern var R: Word;
extern var TABSTRS: Word;
extern var SGC: Word;
extern var ND: Word;
extern var SBND: Word;
extern var NT: Word;
extern var current_id: Word;
extern var meta_pending: Word;
extern var newtyps: Word;
extern var showchain: Word;
extern var errs: Word;
extern var tfnum: Word;
extern var tfbool: Word;
extern var tfbool2: Word;
extern var tfnum2: Word;
extern var tfstrstr: Word;
extern var tfnumnum: Word;
extern var ltchar: Word;
extern var bnf_t: Word;
extern var exec_t: Word;
extern var read_t: Word;
extern var filestat_t: Word;
extern var tstep: Word;
extern var tstepuntil: Word;
extern var tvmap: Word;
extern var localtvmap: Word;
extern var SUBST: [hashsize]Word;
extern var outfilq: Word;
extern var waiting: Word;

extern fn outstats() void;
extern fn initclock() void;
extern var current_script: [*:0]const u8;
extern var speclocs: Word;
extern var algshfns: Word;
extern var embargoes: Word;
extern var rfl: Word;
extern var bereaved: Word;
extern var ld_stuff: Word;
extern var detrop: Word;
extern var tlost: Word;

const hashsize = c.hashsize;

fn TOP() Word {
    return SPACE + ATOMLIMIT;
}

fn BIGTOP() Word {
    return SPACELIMIT + ATOMLIMIT;
}

export fn trueheapsize() Word {
    return if (nogcs == 0) listp - ATOMLIMIT + 1 else SPACE;
}

export fn setupheap() void {
    const size = @as(usize, @intCast(SPACELIMIT));
    const ptr = c.malloc(size * @sizeOf(Word) * 2) orelse {
        mallocfail("heap");
        unreachable;
    };
    heap = @ptrCast(@alignCast(ptr));
    
    const bigtop_val = @as(usize, @intCast(BIGTOP()));
    const tag_ptr = c.calloc(bigtop_val + 1, @sizeOf(u8)) orelse {
        mallocfail("heap");
        unreachable;
    };
    tag = @ptrCast(@alignCast(tag_ptr));
    
    hd = heap.? - @as(usize, @intCast(ATOMLIMIT * 2));
    tl = hd.? + 1;
    if (SPACE > SPACELIMIT) {
        SPACE = SPACELIMIT;
    }
}

export fn resetheap() void {
    if (SPACELIMIT < trueheapsize()) {
        const stderr = getStderr().?;
        _ = c.fprintf(stderr, "impossible event in resetheap\n");
        c.exit(1);
    }
    const size = @as(usize, @intCast(SPACELIMIT));
    const ptr = c.realloc(heap, size * @sizeOf(Word) * 2) orelse {
        mallocfail("heap");
        unreachable;
    };
    heap = @ptrCast(@alignCast(ptr));
    
    const bigtop_val = @as(usize, @intCast(BIGTOP()));
    const tag_ptr = c.realloc(tag, bigtop_val + 1) orelse {
        mallocfail("heap");
        unreachable;
    };
    tag = @ptrCast(@alignCast(tag_ptr));
    
    hd = heap.? - @as(usize, @intCast(ATOMLIMIT * 2));
    tl = hd.? + 1;
    tag.?[@intCast(bigtop_val)] = 0;
    if (SPACE > SPACELIMIT) {
        SPACE = SPACELIMIT;
    }
    if (SPACE < 1250000 and 1250000 <= SPACELIMIT) {
        SPACE = 1250000;
        tag.?[@intCast(TOP())] = 0;
    }
}

export fn mallocfail(x: [*:0]const u8) void {
    const stderr = getStderr().?;
    _ = c.fprintf(stderr, "panic: cannot find enough free space for %s\n", x);
    c.exit(1);
}

export fn resetgcstats() void {
    cellcount = -claims;
    nogcs = 0;
    initclock();
}

fn poschar(val: u8) bool {
    const signed_val = @as(i8, @bitCast(val));
    return signed_val > 0;
}

export fn make(t_val: u8, x: Word, y: Word) Word {
    while (true) {
        listp += 1;
        if (!poschar(tag.?[@intCast(listp)])) {
            break;
        }
    }
    if (listp == TOP()) {
        if (SPACE != SPACELIMIT) {
            if (compiling == 0) {
                SPACE = SPACELIMIT;
            } else if (claims <= @divTrunc(SPACE, 4) and nogcs > 1) {
                var wait: Word = 0;
                const sp = SPACE;
                if (wait != 0) {
                    wait -= 1;
                } else {
                    SPACE += @divTrunc(SPACE, 2);
                    wait = 2;
                    SPACE = 5000 * (1 + @divTrunc(SPACE - 1, 5000));
                }
                if (SPACE > SPACELIMIT) {
                    SPACE = SPACELIMIT;
                }
                if (atgc != 0 and SPACE > sp) {
                    _ = c.fprintf(getStderr().?, "\n<<increase heap from %ld to %ld>>\n", sp, SPACE);
                }
            }
        }
        if (listp == TOP()) {
            gc();
            if (t_val > c.STRCONS) {
                mark(x);
            }
            if (t_val >= c.INT) {
                mark(y);
            }
            return make(t_val, x, y);
        }
    }
    claims += 1;
    tag.?[@intCast(listp)] = t_val;
    hp(listp).* = x;
    tp(listp).* = y;
    return listp;
}

export fn gc() void {
    var env: c.jmp_buf = undefined;
    if (c.setjmp(&env) != 0) {
        return;
    }
    collecting = 1;
    var idx = @as(usize, @intCast(ATOMLIMIT));
    if (atgc != 0) {
        _ = c.fprintf(getStderr().?, "\n<<gc after %ld claims>>\n", claims);
    }
    if (claims <= @divTrunc(SPACE, 10) and nogcs > 1 and SPACE == SPACELIMIT) {
        var hnogcs: Word = 0;
        if (nogcs == hnogcs) {
            _ = c.fprintf(getStderr().?, "<<not enough heap space -- task abandoned>>\n");
            if (compiling == 0) {
                outstats();
            }
            if (compiling != 0 and ideep == 0) {
                _ = c.fprintf(getStderr().?, "not enough heap to compile current script\n");
                _ = c.fprintf(getStderr().?, "script = \"%s\", heap = %ld\n", current_script, SPACE);
            }
            c.exit(1);
        } else {
            hnogcs = nogcs + 1;
        }
    }
    nogcs += 1;
    
    while (tag.?[idx] != 0) {
        const signed_val = @as(i8, @bitCast(tag.?[idx]));
        tag.?[idx] = @bitCast(-signed_val);
        idx += 1;
    }
    
    bases();
    listp = ATOMLIMIT - 1;
    cellcount += claims;
    claims = 0;
    collecting = 0;
    c.longjmp(&env, 1);
}

export fn gcpatch() void {
    var idx = @as(usize, @intCast(ATOMLIMIT));
    while (tag.?[idx] != 0) : (idx += 1) {
        const val = tag.?[idx];
        const signed_val = @as(i8, @bitCast(val));
        if (signed_val < 0) {
            tag.?[idx] = @bitCast(-signed_val);
        }
    }
}

export fn bases() void {
    var p: [*]Word = undefined;
    p = @ptrCast(@alignCast(&p));
    const cstack_ptr = cstack.?;
    if (@intFromPtr(p) < @intFromPtr(cstack_ptr)) {
        p += 1;
        while (@intFromPtr(p) < @intFromPtr(cstack_ptr)) : (p += 1) {
            mark(p[0]);
        }
    } else {
        p -= 1;
        while (@intFromPtr(p) > @intFromPtr(cstack_ptr)) : (p -= 1) {
            mark(p[0]);
        }
    }
    mark(cstack_ptr[0]);

    mark(outfilq);
    mark(waiting);
    if (compiling != 0 or rv_expr != 0 or rv_script != 0) {
        mark(make_status);
        mark(primenv);
        mark(fileq);
        mark(idsused);
        mark(eprodnts);
        mark(nonterminals);
        mark(ntmap);
        mark(ihlist);
        mark(ntspecmap);
        mark(gvars);
        mark(lexvar);
        mark(common_stdin);
        mark(common_stdinb);
        mark(cook_stdin);
        mark(margstack);
        mark(vergstack);
        mark(litstack);
        mark(linostack);
        mark(prefixstack);
        mark(files);
        mark(oldfiles);
        mark(includees);
        mark(freeids);
        mark(exports);
        mark(internals);
        mark(CLASHES);
        mark(ALIASES);
        mark(SUPPRESSED);
        mark(TSUPPRESSED);
        mark(DETROP);
        mark(MISSING);
        mark(FBS);
        mark(lexstates);
        mark(lexdefs);
        var i: usize = 0;
        while (i < 128) : (i += 1) {
            if (namebucket[i] != 0) {
                mark(namebucket[i]);
            }
        }
        const p_dstack = dstack;
        const p_stackp = stackp;
        if (p_dstack != null and p_stackp != null) {
            var curr = p_dstack.?;
            const end = p_stackp.?;
            while (@intFromPtr(curr) < @intFromPtr(end)) : (curr += 1) {
                mark(curr[0]);
            }
        }
        if (loading != 0) {
            mark(algshfns);
            mark(speclocs);
            mark(exportfiles);
            mark(embargoes);
            mark(rfl);
            mark(detrop);
            mark(bereaved);
            mark(ld_stuff);
            mark(tlost);
            i = 0;
            const nextpn_val = @as(usize, @intCast(nextpn));
            while (i < nextpn_val) : (i += 1) {
                mark(pnvec.?[i]);
            }
        }
        mark(lastname);
        mark(suppressids);
        mark(lastexp);
        mark(nill);
        mark(standardout);
        mark(big_one);
        mark(yyval);
        mark(yylval);
        mark(R);
        mark(TABSTRS);
        mark(SGC);
        mark(ND);
        mark(SBND);
        mark(NT);
        mark(current_id);
        mark(meta_pending);
        mark(newtyps);
        mark(showchain);
        mark(errs);
        mark(tfnum);
        mark(tfbool);
        mark(tfbool2);
        mark(tfnum2);
        mark(tfstrstr);
        mark(tfnumnum);
        mark(ltchar);
        mark(bnf_t);
        mark(exec_t);
        mark(read_t);
        mark(filestat_t);
        mark(tstep);
        mark(tstepuntil);
        mark(tvmap);
        mark(localtvmap);
        i = 0;
        while (i < hashsize) : (i += 1) {
            mark(SUBST[i]);
        }
    }
}

fn isptr(x: Word) bool {
    return x >= ATOMLIMIT and x < TOP();
}

fn negchar(val: u8) bool {
    const signed_val = @as(i8, @bitCast(val));
    return signed_val < 0;
}

export fn mark(x_val: Word) void {
    var x = x_val & ~c.tlptrbits;
    while (isptr(x) and negchar(tag.?[@intCast(x)])) {
        const p1 = &tag.?[@intCast(x)];
        const signed_tag = @as(i8, @bitCast(p1.*));
        const new_signed_tag = -signed_tag;
        p1.* = @bitCast(new_signed_tag);
        
        const new_tag = p1.*;
        if (new_tag > c.STRCONS) {
            mark(h(x));
        }
        if (new_tag >= c.INT) {
            x = t(x) & ~c.tlptrbits;
        } else {
            break;
        }
    }
}

fn getStderr() ?*c.FILE {
    const T = @TypeOf(c.stderr);
    if (comptime @typeInfo(T) == .@"fn") {
        return c.stderr();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return c.stderr();
    } else {
        return c.stderr;
    }
}

export var prefix: [c.pnlim]u8 = undefined;
export var preflen: Word = 0;

extern var obsuffix: [*:0]const u8;
extern var dicp: [*:0]u8;
extern var dicq: [*:0]u8;
extern fn fm_time(path: [*:0]const u8) Word;

export fn sto_id(p1: [*:0]const u8) Word {
    return make(c.ID, cons(make(c.STRCONS, @intCast(@intFromPtr(p1)), c.NIL), c.undef_t), c.UNDEF);
}

export fn getword(file: ?*c.FILE) Word {
    var s: i32 = 0;
    var i: usize = @sizeOf(Word);
    var x = @as(Word, @intCast(c.getc(file)));
    while (i > 1) {
        i -= 1;
        s += 8;
        const next_ch = @as(Word, @intCast(c.getc(file)));
        x |= next_ch << @intCast(s);
    }
    return x;
}

export fn putword(x_val: Word, file: ?*c.FILE) void {
    var x = x_val;
    var i: usize = @sizeOf(Word);
    _ = c.putc(@intCast(x & 255), file);
    while (i > 1) {
        i -= 1;
        x >>= 8;
        _ = c.putc(@intCast(x & 255), file);
    }
}

export fn setprefix(p: [*:0]const u8) void {
    const p_len = std.mem.len(p);
    if (p_len >= prefix.len) {
        mallocfail("prefix buffer overflow");
    }
    @memcpy(prefix[0..p_len], p[0..p_len]);
    prefix[p_len] = 0;
    
    var last_slash: ?usize = null;
    var i: usize = p_len;
    while (i > 0) {
        i -= 1;
        if (prefix[i] == '/') {
            last_slash = i;
            break;
        }
    }
    if (last_slash) |idx| {
        prefix[idx + 1] = 0;
        preflen = @intCast(idx + 1);
    } else {
        prefix[0] = 0;
        preflen = 0;
    }
}

export fn mkrel(p: [*:0]const u8) [*:0]const u8 {
    const p_len = std.mem.len(p);
    const prefix_len = @as(usize, @intCast(preflen));
    if (prefix_len <= p_len and std.mem.eql(u8, prefix[0..prefix_len], p[0..prefix_len])) {
        return @ptrCast(p + prefix_len);
    }
    if (p[0] == '/') {
        return p;
    }
    const stderr = getStderr().?;
    _ = c.fprintf(stderr, "impossible event in mkrelative\n");
    return p;
}

export fn okdump(t_ptr: [*:0]const u8) c_int {
    var obf: [120]u8 = undefined;
    const t_len = std.mem.len(t_ptr);
    if (t_len >= obf.len) {
        return 0;
    }
    @memcpy(obf[0..t_len], t_ptr[0..t_len]);
    obf[t_len] = 0;
    
    const suffix_str = std.mem.span(obsuffix);
    const suffix_len = suffix_str.len;
    if (t_len + suffix_len - 1 >= obf.len) {
        return 0;
    }
    @memcpy(obf[t_len - 1 .. t_len - 1 + suffix_len], suffix_str.ptr);
    obf[t_len - 1 + suffix_len] = 0;
    
    const f = c.fopen(&obf, "r") orelse return 0;
    defer _ = c.fclose(f);
    
    const ch1 = c.getc(f);
    const ch2 = c.getc(f);
    if (ch1 == c.XVERSION and ch2 != 0) {
        return 1;
    }
    return 0;
}

export fn geterrlin(t_ptr: [*:0]const u8) Word {
    var obf: [120]u8 = undefined;
    const t_len = std.mem.len(t_ptr);
    if (t_len >= obf.len) {
        return 0;
    }
    @memcpy(obf[0..t_len], t_ptr[0..t_len]);
    obf[t_len] = 0;
    
    const suffix_str = std.mem.span(obsuffix);
    const suffix_len = suffix_str.len;
    if (t_len + suffix_len - 1 >= obf.len) {
        return 0;
    }
    @memcpy(obf[t_len - 1 .. t_len - 1 + suffix_len], suffix_str.ptr);
    obf[t_len - 1 + suffix_len] = 0;
    
    const f = c.fopen(&obf, "r") orelse return 0;
    defer _ = c.fclose(f);
    
    const ch1 = c.getc(f);
    if (ch1 != c.XVERSION) {
        return 0;
    }
    
    const ch2 = c.getc(f);
    if (ch2 != 0 and ch2 != 1) {
        return 0;
    }
    
    const el = getword(f);
    
    // now check this is right dump
    setprefix(t_ptr);
    var ch = c.getc(f);
    dicq = dicp;
    if (ch != '/') {
        const prefix_len = @as(usize, @intCast(preflen));
        @memcpy(dicp[0..prefix_len], prefix[0..prefix_len]);
        dicp[prefix_len] = 0;
        dicq = dicp + prefix_len;
    }
    
    // locate wrt current posn
    dicq[0] = @intCast(ch);
    dicq += 1;
    
    while (true) {
        ch = c.getc(f);
        dicq[0] = @intCast(ch);
        dicq += 1;
        if (ch == 0 or ch == c.EOF) {
            break;
        }
    }
    
    const mtime = getword(f);
    if (c.strcmp(dicp, t_ptr) != 0 or mtime != fm_time(t_ptr)) {
        return 0; // wrong dump
    }
    
    return el;
}


test "sto_char returns atoms for Latin-1 values" {
    try std.testing.expectEqual(@as(Word, 65), sto_char(65));
    try std.testing.expectEqual(@as(c_int, 1), is_char(65));
}
