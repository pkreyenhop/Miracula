const std = @import("std");
const ast = @import("ast.zig");
const token_filter = @import("token_filter.zig");
const Diagnostics = @import("diagnostics.zig").Diagnostics;
const Token = token_filter.Token;
const TokenId = token_filter.TokenId;
const Expression = ast.Expression;

pub const OpInfo = struct {
    id: TokenId,
    symbol: []const u8,
    lbp: u8,
    rbp: u8,
};

pub const operators = [_]OpInfo{
    .{ .id = .plus, .symbol = "+", .lbp = 60, .rbp = 60 },
    .{ .id = .minus, .symbol = "-", .lbp = 60, .rbp = 60 },
    .{ .id = .times, .symbol = "*", .lbp = 70, .rbp = 70 },
    .{ .id = .slash, .symbol = "/", .lbp = 70, .rbp = 70 },
};

pub fn getInfixOpInfo(id: TokenId) ?OpInfo {
    for (operators) |op| {
        if (op.id == id) {
            return op;
        }
    }
    return null;
}

pub fn canStartExpression(id: TokenId) bool {
    return switch (id) {
        .name, .cname, .const_val, .lparen, .lbracket => true,
        else => false,
    };
}

pub fn parseExpression(parser: anytype, min_bp: u8) anyerror!Expression {
    var lhs = try parsePrefix(parser);
    
    while (true) {
        const next_tok = try parser.filter.peek();
        
        // Handle function application (left-associative, high binding power)
        if (canStartExpression(next_tok.id)) {
            const app_bp = 90;
            if (app_bp < min_bp) {
                break;
            }
            
            const arg = try parseExpression(parser, app_bp);
            
            const func_alloc = try parser.arena.allocator().create(Expression);
            func_alloc.* = lhs;
            const arg_alloc = try parser.arena.allocator().create(Expression);
            arg_alloc.* = arg;
            
            lhs = Expression{
                .application = .{
                    .func = func_alloc,
                    .arg = arg_alloc,
                },
            };
            continue;
        }
        
        // Handle infix binary operators
        const op_info = getInfixOpInfo(next_tok.id) orelse break;
        if (op_info.lbp < min_bp) {
            break;
        }
        
        // Consume operator token
        _ = try parser.filter.next();
        
        const rhs = try parseExpression(parser, op_info.rbp);
        
        const lhs_alloc = try parser.arena.allocator().create(Expression);
        lhs_alloc.* = lhs;
        const rhs_alloc = try parser.arena.allocator().create(Expression);
        rhs_alloc.* = rhs;
        
        lhs = Expression{
            .infix = .{
                .op = op_info.symbol,
                .lhs = lhs_alloc,
                .rhs = rhs_alloc,
            },
        };
    }
    
    return lhs;
}

fn parsePrefix(parser: anytype) anyerror!Expression {
    const tok = try parser.filter.next();
    switch (tok.id) {
        .name => {
            return Expression{ .identifier = tok.text };
        },
        .const_val => {
            // Determine if it's float or integer
            if (std.mem.indexOfScalar(u8, tok.text, '.') != null or std.mem.indexOfScalar(u8, tok.text, 'e') != null or std.mem.indexOfScalar(u8, tok.text, 'E') != null) {
                const val = try std.fmt.parseFloat(f64, tok.text);
                return Expression{ .float = val };
            } else {
                const val = try std.fmt.parseInt(i64, tok.text, 0);
                return Expression{ .integer = val };
            }
        },
        .minus => {
            // Unary negation
            const rbp = 80;
            const rhs = try parseExpression(parser, rbp);
            const rhs_alloc = try parser.arena.allocator().create(Expression);
            rhs_alloc.* = rhs;
            return Expression{
                .prefix = .{
                    .op = "-",
                    .rhs = rhs_alloc,
                },
            };
        },
        .lparen => {
            // Check if next token is an infix operator to support right sections, e.g. (+1)
            const next_tok = try parser.filter.peek();
            if (getInfixOpInfo(next_tok.id) != null) {
                const op_tok = try parser.filter.next();
                const rhs = try parseExpression(parser, 0);
                const rparen = try parser.filter.next();
                if (rparen.id != .rparen) {
                    try parser.diags.addError(rparen.line, rparen.column, "Expected ')' in section");
                    return error.SyntaxError;
                }
                const rhs_alloc = try parser.arena.allocator().create(Expression);
                rhs_alloc.* = rhs;
                return Expression{
                    .prefix = .{
                        .op = op_tok.text,
                        .rhs = rhs_alloc,
                    },
                };
            }

            // Parenthesized expression
            const expr = try parseExpression(parser, 0);
            const rparen = try parser.filter.next();
            if (rparen.id != .rparen) {
                try parser.diags.addError(rparen.line, rparen.column, "Expected ')'");
                return error.SyntaxError;
            }
            return expr;
        },
        else => {
            try parser.diags.addError(tok.line, tok.column, "Unexpected token in expression prefix");
            return error.SyntaxError;
        },
    }
}
