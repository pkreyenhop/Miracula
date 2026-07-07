//! reducer/reduce.zig — the graph-reduction engine (the `reduce()` loop).
//!
//! Miranda programs are compiled to a **combinator graph**: a DAG of binary
//! `AP` (application) cells whose leaves are atoms — the SK-family combinators
//! (`S`/`K`/`I`/`B`/`C`/`Y`/…), built-in operators (`PLUS`, `HD`, `COND`, …),
//! and data cells (`INT`/`DOUBLE`/`CONS`/`CONSTRUCTOR`/…). `reduce(e)` evaluates
//! `e` to **weak head normal form** (WHNF — the outermost constructor/atom is
//! known, arguments may stay unevaluated) by normal-order (lazy) graph
//! reduction, rewriting the graph *in place* so shared sub-expressions are
//! evaluated at most once.
//!
//! **The spine.** The "spine" is the left-ancestor chain of `AP` nodes from the
//! root down to the head atom. Each step the engine unwinds the spine to its
//! head combinator, then applies that combinator's rewrite rule using the
//! argument sub-graphs hanging off the spine's `AP` nodes.
//!
//! **Explicit Spine Stack.** The engine uses an explicit, growable spine stack
//! (`ctx.spine`) to track the traversal down the left-ancestor chain of `AP` nodes,
//! keeping this bookkeeping separate from the graph itself. This replaces the legacy
//! in-graph pointer-reversal encoding, meaning cell fields (`hd`/`tl`) hold real graph
//! values at every instant and no access needs pointer masking. The `ReductionCtx` registers:
//!   * `e`     — the node currently in focus (the candidate redex / result).
//!   * `spine` — the explicit spine stack (see `spine.zig`).
//!   * `hold`  — general-purpose scratch.
//!   * `args`  — scratch slots for a combinator's pulled-out arguments.
//!   * `action`— post-dispatch protocol (see below).
//!
//! **The `action` protocol** tells the loop what to do after a handler runs:
//!   * `ACT_NONE`      — fall through to walk back *up* the spine forcing args.
//!   * `ACT_NEXTREDEX` — the redex was rewritten in place; re-examine from `e`.
//!   * `ACT_DONE`      — `e` is in WHNF; pop up the spine seeking the next arg.
//!
//! **Where the rules live.** This file owns the dispatch loop and the traversal
//! primitives; the per-combinator rewrite rules live in `combinators.zig`,
//! `ready.zig`, `lex.zig`, and `io.zig`, which share the machine primitives via
//! `reduce_core.zig`. NB: the `hdGet`/`downLeft`/classifier/`rewrite_to_*`
//! helpers below are duplicated in `reduce_core.zig` (the copy the handlers
//! import); see that file for the canonical set. Keep the two in lock-step.

const word = @import("../word.zig");
const options = @import("version_options");
const std = @import("std");
const strtab = @import("../strtab.zig");
const core = @import("reduce_core.zig");
const getTag = core.getTag;
const setTag = core.setTag;
const combinators = @import("combinators.zig");
const ready = @import("ready.zig");
const lex_handlers = @import("lex.zig");
const io_handlers = @import("io.zig");
const trace = @import("trace.zig");
const lex = @import("../../parser/lex.zig");
const reduce_rt = @import("../reduce.zig");
const os = @import("../os.zig");
const rt = @import("../runtime_state.zig");
const spine = @import("spine.zig");
const heap_mod = @import("../heap.zig");

/// The interpreter machine word (re-exported from [core]).
pub const Word = core.Word;
/// The reduction machine's register file (re-exported from [core]).
pub const ReductionCtx = core.ReductionCtx;

/// Reduce `e_val` to weak head normal form and return the resulting node.
/// Drives the graph in place; the returned `Word` is the rewritten root.
pub fn reduce(e_val: Word) core.ReduceError!Word {
    // Fresh machine state: a fresh, empty Spine (see spine.zig) -- registered
    // as a GC root for the duration (reduce() is recursive, so nested calls
    // each get their own, nested LIFO with this one; see Spine.register).
    var ctx: ReductionCtx = undefined;
    ctx.e = e_val;
    ctx.heap = heap_mod.heap();
    ctx.eval = reduce_rt.ev();
    ctx.rs = rt.rs();
    ctx.spine = spine.Spine.init(rt.allocator, &ctx.eval.spine_buffer_pool);
    ctx.spine.register(&ctx.eval.gc_roots_head);
    defer ctx.spine.deinit(&ctx.eval.spine_buffer_pool);
    defer ctx.spine.unregister(&ctx.eval.gc_roots_head);
    ctx.hold = 0;
    ctx.args[0] = 0;
    ctx.args[1] = 0;
    ctx.args[2] = 0;
    ctx.args[3] = 0;
    ctx.action = word.ACT_NONE;

    main_loop: while (true) {
        // (1) Unwind the left spine: descend through `AP` nodes (reversing
        //     pointers) until `e` is the head atom/combinator/data node.
        while (isAp(ctx.heap, ctx.e)) {
            downLeft(&ctx);
        }

        if (@as(u64, @bitCast(ctx.e)) >= word.ATOMLIMIT) {
            try dispatchNonCombinatorHead(&ctx);
        } else {
            ctx.eval.cycles += 1; // one reduction step (the perf counter)
            if (ctx.eval.cycles & 0xFFF == 0 and rt.interrupt_flag.load(.acquire)) {
                return error.Interrupted;
            }
            trace.step(&ctx.eval.trace, ctx.e); // per-combinator histogram (compiled out when off)
            ctx.action = word.ACT_NONE;

            // (2) Dispatch on the head. A bare combinator/operator atom selects a
            //     rewrite handler; anything else falls to the tag switch below.
            switch (ctx.e) {
                word.S => try combinators.handleS(&ctx),
                word.B => try combinators.handleB(&ctx),
                word.CB => try combinators.handleCB(&ctx),
                word.C => try combinators.handleC(&ctx),
                word.Y => try combinators.handleY(&ctx),
                word.K => try combinators.handleK(&ctx),
                word.KI => try combinators.handleKI(&ctx),
                word.S1 => try combinators.handleS1(&ctx),
                word.B1 => try combinators.handleB1(&ctx),
                word.C1 => try combinators.handleC1(&ctx),
                word.S_p => try combinators.handleS_p(&ctx),
                word.B_p => try combinators.handleB_p(&ctx),
                word.C_p => try combinators.handleC_p(&ctx),
                word.ITERATE => try combinators.handleITERATE(&ctx),
                word.ITERATE1 => try combinators.handleITERATE1(&ctx),
                word.P, word.G_RULE => try combinators.handleP(&ctx),
                word.U => try combinators.handleU(&ctx),
                word.Uf => try combinators.handleUf(&ctx),
                word.ATLEAST => try combinators.handleATLEAST(&ctx),
                word.U_ => try combinators.handleU_(&ctx),
                word.Ug => try combinators.handleUg(&ctx),
                word.MATCH => try combinators.handleMATCH(&ctx),
                word.MATCHINT => try combinators.handleMATCHINT(&ctx),
                word.GENSEQ => try combinators.handleGENSEQ(&ctx),
                word.MAP => try combinators.handleMAP(&ctx),
                word.FLATMAP => try combinators.handleFLATMAP(&ctx),
                word.FILTER => try combinators.handleFILTER(&ctx),
                word.LIST_LAST => try combinators.handleLIST_LAST(&ctx),
                word.LENGTH => try combinators.handleLENGTH(&ctx),
                word.DROP => try combinators.handleDROP(&ctx),
                word.SUBSCRIPT => try combinators.handleSUBSCRIPT(&ctx),
                word.FOLDL1 => try combinators.handleFOLDL1(&ctx),
                word.FOLDL => try combinators.handleFOLDL(&ctx),
                word.FOLDR => try combinators.handleFOLDR(&ctx),
                word.BADCASE => try combinators.handleBADCASE(&ctx),
                word.GETARGS => try combinators.handleGETARGS(&ctx),
                word.CONFERROR => try combinators.handleCONFERROR(&ctx),
                word.ERROR => try combinators.handleERROR(&ctx),
                word.WAIT => try combinators.handleWAIT(&ctx),
                word.TRY => try combinators.handleTRY(&ctx),
                word.FAIL => try combinators.handleFAIL(&ctx),
                word.Ush1 => try combinators.handleUsh1(&ctx),
                word.MKSTRICT => try combinators.handleMKSTRICT(&ctx),

                word.I => try combinators.handleI(&ctx),

                word.SEQ, word.FORCE, word.HD, word.TL, word.BODY, word.LAST, word.EXEC, word.FILEMODE, word.FILESTAT, word.GETENV, word.INTEGER, word.NUMVAL, word.TAKE, word.STARTREAD, word.STARTREADBIN, word.NB_STARTREAD, word.COND, word.APPEND, word.AND, word.OR, word.NOT, word.NEG, word.CODE, word.DECODE, word.SHOWNUM, word.SHOWHEX, word.SHOWOCT, word.ARCTAN_FN, word.EXP_FN, word.ENTIER_FN, word.LOG_FN, word.LOG10_FN, word.SIN_FN, word.COS_FN, word.SQRT_FN => try combinators.handleStrictMonadic(&ctx),

                word.ZIP, word.STEP, word.EQ, word.NEQ, word.PLUS, word.MINUS, word.TIMES, word.INTDIV, word.FDIV, word.MOD, word.GRE, word.GR, word.POWER, word.SHOWSCALED, word.SHOWFLOAT, word.MERGE => try combinators.handleStrictDiadic(&ctx),

                word.Ush, word.STEPUNTIL => try combinators.handleStrictTriadic(&ctx),

                // Grammar Combinators (lex.zig)
                word.G_ERROR => try lex_handlers.handle_G_ERROR(&ctx),
                word.G_ALT => try lex_handlers.handle_G_ALT(&ctx),
                word.G_OPT => try lex_handlers.handle_G_OPT(&ctx),
                word.G_STAR => try lex_handlers.handle_G_STAR(&ctx),
                word.G_FBSTAR => try lex_handlers.handle_G_FBSTAR(&ctx),
                word.G_SYMB => try lex_handlers.handle_G_SYMB(&ctx),
                word.G_ANY => try lex_handlers.handle_G_ANY(&ctx),
                word.G_SUCHTHAT => try lex_handlers.handle_G_SUCHTHAT(&ctx),
                word.G_END => try lex_handlers.handle_G_END(&ctx),
                word.G_STATE => try lex_handlers.handle_G_STATE(&ctx),
                word.G_SEQ => try lex_handlers.handle_G_SEQ(&ctx),
                word.G_UNIT => try lex_handlers.handle_G_UNIT(&ctx),
                word.G_ZERO => try lex_handlers.handle_G_ZERO(&ctx),
                word.G_CLOSE => try lex_handlers.handle_G_CLOSE(&ctx),
                word.G_COUNT => try lex_handlers.handle_G_COUNT(&ctx),

                // Lexer Combinators (lex.zig)
                word.LEX_RPT1 => try lex_handlers.handle_LEX_RPT1(&ctx),
                word.LEX_RPT => try lex_handlers.handle_LEX_RPT(&ctx),
                word.LEX_TRY => try lex_handlers.handle_LEX_TRY(&ctx),
                word.LEX_TRY_ => try lex_handlers.handle_LEX_TRY_(&ctx),
                word.LEX_TRY1 => try lex_handlers.handle_LEX_TRY1(&ctx),
                word.LEX_TRY1_ => try lex_handlers.handle_LEX_TRY1_(&ctx),
                word.DESTREV => try lex_handlers.handle_DESTREV(&ctx),
                word.LEX_COUNT0 => try lex_handlers.handle_LEX_COUNT0(&ctx),
                word.LEX_COUNT => try lex_handlers.handle_LEX_COUNT(&ctx),
                word.LEX_STRING => try lex_handlers.handle_LEX_STRING(&ctx),
                word.LEX_CLASS => try lex_handlers.handle_LEX_CLASS(&ctx),
                word.LEX_DOT => try lex_handlers.handle_LEX_DOT(&ctx),
                word.LEX_CHAR => try lex_handlers.handle_LEX_CHAR(&ctx),
                word.LEX_SEQ => try lex_handlers.handle_LEX_SEQ(&ctx),
                word.LEX_OR => try lex_handlers.handle_LEX_OR(&ctx),
                word.LEX_RCONTEXT => try lex_handlers.handle_LEX_RCONTEXT(&ctx),
                word.LEX_STAR => try lex_handlers.handle_LEX_STAR(&ctx),
                word.LEX_OPT => try lex_handlers.handle_LEX_OPT(&ctx),

                // IO (io.zig)
                word.READ => io_handlers.handle_READ(&ctx),
                word.READBIN => io_handlers.handle_READBIN(&ctx),
                word.READVALS => io_handlers.handle_READVALS(&ctx),

                else => {
                    // Non-combinator atoms (like True, False, etc.) are already in WHNF.
                    ctx.action = word.ACT_DONE;
                },
            }
        }

        // A handler rewrote the redex in place and wants it re-examined.
        if (ctx.action == word.ACT_NEXTREDEX) {
            continue :main_loop;
        }

        // (3) `e` is in WHNF. Walk back up the spine, forcing each ancestor
        //     `AP`'s right argument in turn, until the spine is exhausted or a
        //     rule rewrote the graph and wants the redex re-examined.
        if (try forceSpineArguments(&ctx)) |result| {
            return result;
        }
    }
}

/// Step (2b) of the main dispatch: the head of the spine is not a bare
/// combinator/operator atom, so dispatch on its cell tag instead. Chases
/// private names and defined names to their bound value, recognizes an
/// already-saturated constructor application as WHNF, and reports the
/// handful of "impossible" states (undefined name, black hole, corrupt tag)
/// that indicate a bug rather than a normal reduction step.
fn dispatchNonCombinatorHead(ctx: *ReductionCtx) core.ReduceError!void {
    if (abnormal(ctx.e)) {
        word.printErr("\nBLACK HOLE\n", .{});
        reduce_rt.outstats();
        os.exit(1);
    }

    switch (getTag(ctx.heap, ctx.e)) {
        // A private-name placeholder: chase to its bound value.
        .STRCONS => {
            ctx.e = pnVal(ctx.heap, ctx.e);
            if (ctx.e == word.UNDEF or ctx.e == word.FREE) {
                word.printErr("\nimpossible event in reduce - undefined pname\n", .{});
                if (options.is_strict) {
                    std.debug.panic("impossible event in reduce - undefined pname", .{});
                } else {
                    os.exit(1);
                }
            }
            ctx.action = word.ACT_NEXTREDEX;
        },
        .DATAPAIR => {
            upLeft(ctx);
            word.printErr("\nUNDEFINED NAME (specified as \"{s}\" in {s})\n", .{ strtab.strOf(strtab.table(), hdGet(ctx.heap, hdGet(ctx.heap, ctx.e))), strtab.strOf(strtab.table(), tlGet(ctx.heap, ctx.e)) });
            reduce_rt.outstats();
            os.exit(1);
        },
        // A defined name: substitute its value and re-examine.
        .ID => {
            if (idVal(ctx.heap, ctx.e) == word.UNDEF or idVal(ctx.heap, ctx.e) == word.FREE) {
                word.printErr("\nUNDEFINED NAME - {s}\n", .{getId(ctx.heap, ctx.e)});
                reduce_rt.outstats();
                os.exit(1);
            }
            ctx.e = idVal(ctx.heap, ctx.e);
            ctx.action = word.ACT_NEXTREDEX;
        },
        // A saturated constructor application is already WHNF: pop
        // the whole spine back to the root, then we are done.
        .CONSTRUCTOR => {
            while (true) {
                if (upleft(ctx)) {
                    ctx.action = word.ACT_DONE;
                    break;
                }
            }
        },
        .STARTREADVALS => {
            try io_handlers.handle_STARTREADVALS(ctx);
        },
        // Already a head-normal value (data leaf): nothing to rewrite.
        .ATOM, .INT, .UNICODE, .DOUBLE, .CONS => {
            ctx.action = word.ACT_DONE;
        },
        else => {
            word.printErr("\nimpossible tag ({}) in reduce\n", .{@intFromEnum(getTag(ctx.heap, ctx.e))});
            if (options.is_strict) {
                std.debug.panic("impossible tag ({}) in reduce", .{@intFromEnum(getTag(ctx.heap, ctx.e))});
            } else {
                os.exit(1);
            }
        },
    }
}

/// Step (3) of the main loop: once a handler leaves `ctx.e` in WHNF, walk
/// back up the spine, forcing each ancestor `AP`'s right argument (so strict
/// operators find their operands ready) and applying `ready.handleReadyState`
/// once an argument has been reduced. Returns the final WHNF value once the
/// whole spine is unwound; returns `null` if the graph was rewritten and
/// `reduce()`'s main loop should re-examine `ctx.e` from the top.
fn forceSpineArguments(ctx: *ReductionCtx) core.ReduceError!?Word {
    while (true) {
        if (ctx.spine.isEmpty()) {
            return ctx.e;
        }

        upRight(ctx);

        if (isAp(ctx.heap, ctx.e)) {
            downLeft(ctx);
            downRight(ctx);
            return null;
        }

        try ready.handleReadyState(ctx);
        if (ctx.action == word.ACT_NEXTREDEX) {
            return null;
        }
    }
}
/// Re-export of [reduce_rt.print] (the graph-value printer).
pub const print = reduce_rt.print;
/// Re-export of [reduce_rt.badcaseError] (the no-matching-case abort).
pub const badcaseError = reduce_rt.badcaseError;
/// Re-export of [reduce_rt.confError] (the conformality-error abort).
pub const confError = reduce_rt.confError;
/// Re-export of [lex.convArgs] (command-line args as a Miranda list).
pub const convArgs = lex.convArgs;
/// Re-export of [reduce_rt.getstring] (a char list flattened to a C string).
pub const getstring = reduce_rt.getstring;
/// Re-export of [reduce_rt.head] (the head atom of an application spine).
pub const head = reduce_rt.head;
/// Re-export of [reduce_rt.force] (deep evaluation to normal form).
pub const force = reduce_rt.force;

pub const cleanPtr = core.cleanPtr;

// --- Cell access through the spine word --------------------------------------
// Direct heap cell read/write accessors. These mirror `reduce_core.zig`; keep
// both in sync.

pub const hdGet = core.hdGet;

pub const hdSet = core.hdSet;

pub const tlGet = core.tlGet;

pub const tlSet = core.tlSet;

// --- Pointer-reversal traversal (matches the C reducer exactly) ---------------
// Each `downX` step makes `e` the child and `s` the (reversed) parent, storing
// the old `s` back into the node so the matching `upX` can restore it. The
// lowercase wrappers (`downright`/`upleft`) first test `s < 0` (the BACKSTOP /
// bottom-of-spine sentinel) and report it rather than walking off the bottom.

pub const downLeft = core.downLeft;

pub const downRight = core.downRight;

pub const downright = core.downright;

pub const upLeft = core.upLeft;

pub const upleft = core.upleft;

pub const upRight = core.upRight;

pub const GETARG = core.GETARG;

pub const getarg = core.getarg;

pub const simpl = core.simpl;

// --- Node classifiers --------------------------------------------------------
// A negative `Word` is never a valid cell handle (it is a marked spine word or
// the BACKSTOP sentinel), so every predicate guards with `!abnormal(x)` before
// reading the tag.

pub const abnormal = core.abnormal;
pub const isAp = core.isAp;
pub const isNum = core.isNum;
pub const isConstructor = core.isConstructor;
pub const isInt = core.isInt;
pub const isDouble = core.isDouble;
pub const isAtom = core.isAtom;
pub const isStrcons = core.isStrcons;
pub const isId = core.isId;
pub const idVal = core.idVal;
pub const isDatapair = core.isDatapair;
pub const isStartreadvals = core.isStartreadvals;
pub const isCons = core.isCons;
pub const isUnicode = core.isUnicode;

// --- In-place rewrites -------------------------------------------------------
// Handlers finish by overwriting the redex with their result. `rewriteToValue`
// installs an `I value` indirection (shared); the `rewriteToCons*` variants
// re-tag the redex cell directly; the `rewrite_to_compare_*` ones fold a
// comparison to a boolean. All leave the redex pointing at the new value.

pub const rewriteToValue = core.rewriteToValue;

pub const rewriteToNil = core.rewriteToNil;

pub const rewriteToFail = core.rewriteToFail;

pub const rewriteToFailure = core.rewriteToFailure;

pub const rewriteToConsHead = core.rewriteToConsHead;

pub const rewriteToCons = core.rewriteToCons;

pub const rewriteToExistingTail = core.rewriteToExistingTail;

pub const ap = core.ap;

pub const rewriteToMatchResult = core.rewriteToMatchResult;

pub const rewriteToIntMatchResult = core.rewriteToIntMatchResult;

pub const rewriteToString = core.rewriteToString;

pub const cons = core.cons;

pub const ap2 = core.ap2;

// --- Number / name field accessors -------------------------------------------
// A bignum is a chain of `INT` cells; the sign lives in `SIGNBIT` of the leading
// digit. `neg`/`poz` test it; `getsmallint`/`forceDbl`/`coerceDbl` decode a
// value; `pnVal`/`getId`/`constrName` read name-node fields.

pub const neg = core.neg;
pub const poz = core.poz;
pub const pnVal = core.pnVal;
pub const getId = core.getId;
pub const constrName = core.constrName;
pub const suppressed = core.suppressed;

pub const getStderr = core.getStderr;
pub const getStdout = core.getStdout;
pub const getStdin = core.getStdin;

pub const forceDbl = core.forceDbl;

pub const coerceDbl = core.coerceDbl;

pub const rewriteToCompareEq = core.rewriteToCompareEq;

pub const rewriteToCompareNeq = core.rewriteToCompareNeq;

pub const rewriteToCompareGt = core.rewriteToCompareGt;

pub const rewriteToCompareGe = core.rewriteToCompareGe;

pub const bigzero = core.bigzero;

pub const getsmallint = core.getsmallint;
