const std = @import("std");

export fn hash(input: [*:0]const u8) c_int {
    var s = input;
    var h: c_int = s[0];
    if (h != 0) {
        s += 1;
        while (s[0] != 0) : (s += 1) {
            h ^= s[0];
        }
    }
    return h & 127;
}

export fn isconstrname(input: [*:0]const u8) c_int {
    var s = input;
    if (s[0] == '$') s += 1;
    return if (std.ascii.isUpper(s[0])) 1 else 0;
}

export fn okid(ch: c_int) c_int {
    return if ((ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or
        ch == '_' or
        ch == '\'') 1 else 0;
}

export fn okulid(ch: c_int) c_int {
    return if ((ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or
        ch == '_' or
        ch == 0x08 or
        ch == '\'') 1 else 0;
}

export fn okpath(ch: c_int) c_int {
    return if (ch != '"' and ch != '\n' and ch != '>') 1 else 0;
}

test "hash matches xor into seven-bit bucket" {
    try std.testing.expectEqual(@as(c_int, 0), hash(""));
    try std.testing.expectEqual(@as(c_int, 'a'), hash("a"));
    try std.testing.expectEqual(@as(c_int, ('a' ^ 'b' ^ 'c') & 127), hash("abc"));
}

test "identifier classification matches Miranda lexer rules" {
    try std.testing.expect(isconstrname("Name") == 1);
    try std.testing.expect(isconstrname("$Name") == 1);
    try std.testing.expect(isconstrname("name") == 0);
    try std.testing.expect(okid('a') == 1);
    try std.testing.expect(okid('\'') == 1);
    try std.testing.expect(okid('-') == 0);
    try std.testing.expect(okulid(0x08) == 1);
    try std.testing.expect(okulid('-') == 0);
    try std.testing.expect(okpath('a') == 1);
    try std.testing.expect(okpath('"') == 0);
    try std.testing.expect(okpath('\n') == 0);
    try std.testing.expect(okpath('>') == 0);
}
