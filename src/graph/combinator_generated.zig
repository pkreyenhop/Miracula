//! GENERATED FILE — run `python3 scripts/generate_combinators.py --write`.
//! Canonical source: spec/combinators.json.

pub const base: i64 = 306;
pub const count: usize = 141;

pub const Comb = enum(u16) {
    S = 0,
    K = 1,
    Y = 2,
    C = 3,
    B = 4,
    CB = 5,
    I = 6,
    HD = 7,
    TL = 8,
    BODY = 9,
    LAST = 10,
    S_p = 11,
    U = 12,
    Uf = 13,
    U_ = 14,
    Ug = 15,
    COND = 16,
    EQ = 17,
    NEQ = 18,
    NEG = 19,
    AND = 20,
    OR = 21,
    NOT = 22,
    APPEND = 23,
    STEP = 24,
    STEPUNTIL = 25,
    GENSEQ = 26,
    MAP = 27,
    ZIP = 28,
    TAKE = 29,
    DROP = 30,
    FLATMAP = 31,
    FILTER = 32,
    FOLDL = 33,
    MERGE = 34,
    FOLDL1 = 35,
    LIST_LAST = 36,
    FOLDR = 37,
    MATCH = 38,
    MATCHINT = 39,
    TRY = 40,
    SUBSCRIPT = 41,
    ATLEAST = 42,
    P = 43,
    B_p = 44,
    C_p = 45,
    S1 = 46,
    B1 = 47,
    C1 = 48,
    ITERATE = 49,
    ITERATE1 = 50,
    SEQ = 51,
    FORCE = 52,
    MINUS = 53,
    PLUS = 54,
    TIMES = 55,
    INTDIV = 56,
    FDIV = 57,
    MOD = 58,
    GR = 59,
    GRE = 60,
    POWER = 61,
    CODE = 62,
    DECODE = 63,
    LENGTH = 64,
    ARCTAN_FN = 65,
    EXP_FN = 66,
    ENTIER_FN = 67,
    LOG_FN = 68,
    LOG10_FN = 69,
    SIN_FN = 70,
    COS_FN = 71,
    SQRT_FN = 72,
    FILEMODE = 73,
    FILESTAT = 74,
    GETENV = 75,
    EXEC = 76,
    WAIT = 77,
    INTEGER = 78,
    SHOWNUM = 79,
    SHOWHEX = 80,
    SHOWOCT = 81,
    SHOWSCALED = 82,
    SHOWFLOAT = 83,
    NUMVAL = 84,
    STARTREAD = 85,
    STARTREADBIN = 86,
    NB_STARTREAD = 87,
    READVALS = 88,
    NB_READ = 89,
    READ = 90,
    READBIN = 91,
    GETARGS = 92,
    Ush = 93,
    Ush1 = 94,
    KI = 95,
    G_ERROR = 96,
    G_ALT = 97,
    G_OPT = 98,
    G_STAR = 99,
    G_FBSTAR = 100,
    G_SYMB = 101,
    G_ANY = 102,
    G_SUCHTHAT = 103,
    G_END = 104,
    G_STATE = 105,
    G_SEQ = 106,
    G_RULE = 107,
    G_UNIT = 108,
    G_ZERO = 109,
    G_CLOSE = 110,
    G_COUNT = 111,
    LEX_RPT = 112,
    LEX_RPT1 = 113,
    LEX_TRY = 114,
    LEX_TRY_ = 115,
    LEX_TRY1 = 116,
    LEX_TRY1_ = 117,
    DESTREV = 118,
    LEX_COUNT = 119,
    LEX_COUNT0 = 120,
    LEX_FAIL = 121,
    LEX_STRING = 122,
    LEX_CLASS = 123,
    LEX_CHAR = 124,
    LEX_DOT = 125,
    LEX_SEQ = 126,
    LEX_OR = 127,
    LEX_RCONTEXT = 128,
    LEX_STAR = 129,
    LEX_OPT = 130,
    MKSTRICT = 131,
    BADCASE = 132,
    CONFERROR = 133,
    ERROR = 134,
    FAIL = 135,
    False = 136,
    True = 137,
    NIL = 138,
    NILS = 139,
    UNDEF = 140,
};

pub const S: i64 = 306;
pub const K: i64 = 307;
pub const Y: i64 = 308;
pub const C: i64 = 309;
pub const B: i64 = 310;
pub const CB: i64 = 311;
pub const I: i64 = 312;
pub const HD: i64 = 313;
pub const TL: i64 = 314;
pub const BODY: i64 = 315;
pub const LAST: i64 = 316;
pub const S_p: i64 = 317;
pub const U: i64 = 318;
pub const Uf: i64 = 319;
pub const U_: i64 = 320;
pub const Ug: i64 = 321;
pub const COND: i64 = 322;
pub const EQ: i64 = 323;
pub const NEQ: i64 = 324;
pub const NEG: i64 = 325;
pub const AND: i64 = 326;
pub const OR: i64 = 327;
pub const NOT: i64 = 328;
pub const APPEND: i64 = 329;
pub const STEP: i64 = 330;
pub const STEPUNTIL: i64 = 331;
pub const GENSEQ: i64 = 332;
pub const MAP: i64 = 333;
pub const ZIP: i64 = 334;
pub const TAKE: i64 = 335;
pub const DROP: i64 = 336;
pub const FLATMAP: i64 = 337;
pub const FILTER: i64 = 338;
pub const FOLDL: i64 = 339;
pub const MERGE: i64 = 340;
pub const FOLDL1: i64 = 341;
pub const LIST_LAST: i64 = 342;
pub const FOLDR: i64 = 343;
pub const MATCH: i64 = 344;
pub const MATCHINT: i64 = 345;
pub const TRY: i64 = 346;
pub const SUBSCRIPT: i64 = 347;
pub const ATLEAST: i64 = 348;
pub const P: i64 = 349;
pub const B_p: i64 = 350;
pub const C_p: i64 = 351;
pub const S1: i64 = 352;
pub const B1: i64 = 353;
pub const C1: i64 = 354;
pub const ITERATE: i64 = 355;
pub const ITERATE1: i64 = 356;
pub const SEQ: i64 = 357;
pub const FORCE: i64 = 358;
pub const MINUS: i64 = 359;
pub const PLUS: i64 = 360;
pub const TIMES: i64 = 361;
pub const INTDIV: i64 = 362;
pub const FDIV: i64 = 363;
pub const MOD: i64 = 364;
pub const GR: i64 = 365;
pub const GRE: i64 = 366;
pub const POWER: i64 = 367;
pub const CODE: i64 = 368;
pub const DECODE: i64 = 369;
pub const LENGTH: i64 = 370;
pub const ARCTAN_FN: i64 = 371;
pub const EXP_FN: i64 = 372;
pub const ENTIER_FN: i64 = 373;
pub const LOG_FN: i64 = 374;
pub const LOG10_FN: i64 = 375;
pub const SIN_FN: i64 = 376;
pub const COS_FN: i64 = 377;
pub const SQRT_FN: i64 = 378;
pub const FILEMODE: i64 = 379;
pub const FILESTAT: i64 = 380;
pub const GETENV: i64 = 381;
pub const EXEC: i64 = 382;
pub const WAIT: i64 = 383;
pub const INTEGER: i64 = 384;
pub const SHOWNUM: i64 = 385;
pub const SHOWHEX: i64 = 386;
pub const SHOWOCT: i64 = 387;
pub const SHOWSCALED: i64 = 388;
pub const SHOWFLOAT: i64 = 389;
pub const NUMVAL: i64 = 390;
pub const STARTREAD: i64 = 391;
pub const STARTREADBIN: i64 = 392;
pub const NB_STARTREAD: i64 = 393;
pub const READVALS: i64 = 394;
pub const NB_READ: i64 = 395;
pub const READ: i64 = 396;
pub const READBIN: i64 = 397;
pub const GETARGS: i64 = 398;
pub const Ush: i64 = 399;
pub const Ush1: i64 = 400;
pub const KI: i64 = 401;
pub const G_ERROR: i64 = 402;
pub const G_ALT: i64 = 403;
pub const G_OPT: i64 = 404;
pub const G_STAR: i64 = 405;
pub const G_FBSTAR: i64 = 406;
pub const G_SYMB: i64 = 407;
pub const G_ANY: i64 = 408;
pub const G_SUCHTHAT: i64 = 409;
pub const G_END: i64 = 410;
pub const G_STATE: i64 = 411;
pub const G_SEQ: i64 = 412;
pub const G_RULE: i64 = 413;
pub const G_UNIT: i64 = 414;
pub const G_ZERO: i64 = 415;
pub const G_CLOSE: i64 = 416;
pub const G_COUNT: i64 = 417;
pub const LEX_RPT: i64 = 418;
pub const LEX_RPT1: i64 = 419;
pub const LEX_TRY: i64 = 420;
pub const LEX_TRY_: i64 = 421;
pub const LEX_TRY1: i64 = 422;
pub const LEX_TRY1_: i64 = 423;
pub const DESTREV: i64 = 424;
pub const LEX_COUNT: i64 = 425;
pub const LEX_COUNT0: i64 = 426;
pub const LEX_FAIL: i64 = 427;
pub const LEX_STRING: i64 = 428;
pub const LEX_CLASS: i64 = 429;
pub const LEX_CHAR: i64 = 430;
pub const LEX_DOT: i64 = 431;
pub const LEX_SEQ: i64 = 432;
pub const LEX_OR: i64 = 433;
pub const LEX_RCONTEXT: i64 = 434;
pub const LEX_STAR: i64 = 435;
pub const LEX_OPT: i64 = 436;
pub const MKSTRICT: i64 = 437;
pub const BADCASE: i64 = 438;
pub const CONFERROR: i64 = 439;
pub const ERROR: i64 = 440;
pub const FAIL: i64 = 441;
pub const False: i64 = 442;
pub const True: i64 = 443;
pub const NIL: i64 = 444;
pub const NILS: i64 = 445;
pub const UNDEF: i64 = 446;

pub const cmbnms: [count + 1]?[*:0]const u8 = .{
    "S",
    "K",
    "Y",
    "C",
    "B",
    "CB",
    "I",
    "HD",
    "TL",
    "BODY",
    "LAST",
    "S_p",
    "U",
    "Uf",
    "U_",
    "Ug",
    "COND",
    "EQ",
    "NEQ",
    "NEG",
    "AND",
    "OR",
    "NOT",
    "APPEND",
    "STEP",
    "STEPUNTIL",
    "GENSEQ",
    "MAP",
    "ZIP",
    "TAKE",
    "DROP",
    "FLATMAP",
    "FILTER",
    "FOLDL",
    "MERGE",
    "FOLDL1",
    "LIST_LAST",
    "FOLDR",
    "MATCH",
    "MATCHINT",
    "TRY",
    "SUBSCRIPT",
    "ATLEAST",
    "P",
    "B_p",
    "C_p",
    "S1",
    "B1",
    "C1",
    "ITERATE",
    "ITERATE1",
    "SEQ",
    "FORCE",
    "MINUS",
    "PLUS",
    "TIMES",
    "INTDIV",
    "FDIV",
    "MOD",
    "GR",
    "GRE",
    "POWER",
    "CODE",
    "DECODE",
    "LENGTH",
    "ARCTAN_FN",
    "EXP_FN",
    "ENTIER_FN",
    "LOG_FN",
    "LOG10_FN",
    "SIN_FN",
    "COS_FN",
    "SQRT_FN",
    "FILEMODE",
    "FILESTAT",
    "GETENV",
    "EXEC",
    "WAIT",
    "INTEGER",
    "SHOWNUM",
    "SHOWHEX",
    "SHOWOCT",
    "SHOWSCALED",
    "SHOWFLOAT",
    "NUMVAL",
    "STARTREAD",
    "STARTREADBIN",
    "NB_STARTREAD",
    "READVALS",
    "NB_READ",
    "READ",
    "READBIN",
    "GETARGS",
    "Ush",
    "Ush1",
    "KI",
    "G_ERROR",
    "G_ALT",
    "G_OPT",
    "G_STAR",
    "G_FBSTAR",
    "G_SYMB",
    "G_ANY",
    "G_SUCHTHAT",
    "G_END",
    "G_STATE",
    "G_SEQ",
    "G_RULE",
    "G_UNIT",
    "G_ZERO",
    "G_CLOSE",
    "G_COUNT",
    "LEX_RPT",
    "LEX_RPT1",
    "LEX_TRY",
    "LEX_TRY_",
    "LEX_TRY1",
    "LEX_TRY1_",
    "DESTREV",
    "LEX_COUNT",
    "LEX_COUNT0",
    "LEX_FAIL",
    "LEX_STRING",
    "LEX_CLASS",
    "LEX_CHAR",
    "LEX_DOT",
    "LEX_SEQ",
    "LEX_OR",
    "LEX_RCONTEXT",
    "LEX_STAR",
    "LEX_OPT",
    "MKSTRICT",
    "BADCASE",
    "CONFERROR",
    "ERROR",
    "FAIL",
    "False",
    "True",
    "NIL",
    "NILS",
    "UNDEF",
    null,
};
