const std = @import("std");

pub const SourceLocation = struct {
    line: usize,
    column: usize,
};

pub const Module = struct {
    definitions: []Definition,
};

pub const Definition = struct {
    name: []const u8,
    params: []Pattern,
    body: Expression,
    where_clause: ?WhereClause = null,
    loc: SourceLocation,
};

pub const Pattern = union(enum) {
    identifier: []const u8,
    integer: i64,
    constructor: struct {
        name: []const u8,
        args: []Pattern,
    },
    tuple: []Pattern,
    list: []Pattern,
    wildcard,
};

pub const WhereClause = struct {
    definitions: []Definition,
};

pub const TypeDefinition = struct {
    name: []const u8,
    params: [][]const u8,
    constructors: []Constructor,
    loc: SourceLocation,

    pub const Constructor = struct {
        name: []const u8,
        args: []TypeExpr,
    };
};

pub const TypeExpr = union(enum) {
    tvar: []const u8,
    tcon: struct {
        name: []const u8,
        args: []TypeExpr,
    },
    func: struct {
        arg: *TypeExpr,
        ret: *TypeExpr,
    },
    list: *TypeExpr,
    tuple: []TypeExpr,
};

pub const Expression = union(enum) {
    identifier: []const u8,
    integer: i64,
    float: f64,
    string: []const u8,
    application: struct {
        func: *Expression,
        arg: *Expression,
    },
    lambda: struct {
        params: []Pattern,
        body: *Expression,
    },
    infix: struct {
        op: []const u8,
        lhs: *Expression,
        rhs: *Expression,
    },
    prefix: struct {
        op: []const u8,
        rhs: *Expression,
    },
    tuple: []Expression,
    list: []Expression,
    @"if": struct {
        cond: *Expression,
        then_branch: *Expression,
        else_branch: *Expression,
    },
    case: struct {
        val: *Expression,
        rules: []CaseRule,
    },
    where: struct {
        expr: *Expression,
        clause: WhereClause,
    },

    pub const CaseRule = struct {
        pattern: Pattern,
        body: Expression,
        cond: ?Expression = null,
    };

    pub fn format(self: Expression, com_str: []const u8, options: anytype, writer: anytype) !void {
        _ = com_str;
        _ = options;
        switch (self) {
            .identifier => |name| try writer.writeAll(name),
            .integer => |val| try writer.print("{}", .{val}),
            .float => |val| try writer.print("{d}", .{val}),
            .string => |val| try writer.print("\"{s}\"", .{val}),
            .application => |app| {
                try writer.writeAll("(");
                try app.func.format("", .{}, writer);
                try writer.writeAll(" ");
                try app.arg.format("", .{}, writer);
                try writer.writeAll(")");
            },
            .infix => |inf| {
                try writer.print("({s} ", .{inf.op});
                try inf.lhs.format("", .{}, writer);
                try writer.writeAll(" ");
                try inf.rhs.format("", .{}, writer);
                try writer.writeAll(")");
            },
            .prefix => |pref| {
                try writer.print("({s} ", .{pref.op});
                try pref.rhs.format("", .{}, writer);
                try writer.writeAll(")");
            },
            else => try writer.writeAll("?"),
        }
    }
};

pub fn formatPattern(pattern: Pattern, writer: anytype) !void {
    switch (pattern) {
        .identifier => |name| try writer.writeAll(name),
        .integer => |val| try writer.print("{}", .{val}),
        else => try writer.writeAll("?"),
    }
}

pub fn formatDefinition(def: Definition, writer: anytype) !void {
    try writer.print("Definition name={s} params=[", .{def.name});
    for (def.params, 0..) |param, i| {
        if (i > 0) try writer.writeAll(",");
        try formatPattern(param, writer);
    }
    try writer.writeAll("] body=");
    try def.body.format("", .{}, writer);
}

