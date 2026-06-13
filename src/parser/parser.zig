const std = @import("std");
const ast = @import("ast.zig");
const token_filter = @import("token_filter.zig");
const diagnostics = @import("diagnostics.zig");
const pratt = @import("pratt.zig");

const TokenFilter = token_filter.TokenFilter;
const Diagnostics = diagnostics.Diagnostics;
const Token = token_filter.Token;
const TokenId = token_filter.TokenId;

pub const Parser = struct {
    arena: std.heap.ArenaAllocator,
    filter: TokenFilter,
    diags: Diagnostics,

    pub fn init(allocator: std.mem.Allocator) Parser {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const arena_alloc = arena.allocator();
        return .{
            .arena = arena,
            .filter = TokenFilter.init(arena_alloc),
            .diags = Diagnostics.init(allocator),
        };
    }

    pub fn deinit(self: *Parser) void {
        self.arena.deinit();
        self.diags.deinit();
    }

    pub fn parseModule(self: *Parser) !ast.Module {
        var defs = std.array_list.Managed(ast.Definition).init(self.arena.allocator());
        
        while (true) {
            const tok = try self.filter.peek();
            if (tok.id == .eof) {
                break;
            }
            
            // Skip semicolons, offside markers, or other layout tokens at the top-level
            if (tok.id == .semicolon or tok.id == .offside or tok.id == .elseq or tok.id == .lbegin) {
                _ = try self.filter.next();
                continue;
            }
            
            const def = try self.parseDefinition();
            try defs.append(def);
        }
        
        return ast.Module{
            .definitions = defs.items,
        };
    }

    pub fn parseDefinition(self: *Parser) !ast.Definition {
        const name_tok = try self.filter.next();
        if (name_tok.id != .name) {
            try self.diags.addError(name_tok.line, name_tok.column, "Expected definition name");
            return error.SyntaxError;
        }
        
        var params = std.array_list.Managed(ast.Pattern).init(self.arena.allocator());
        while (true) {
            const next_tok = try self.filter.peek();
            if (next_tok.id == .equals) {
                _ = try self.filter.next(); // consume '='
                break;
            }
            const param = try self.parsePattern();
            try params.append(param);
        }
        
        const body = try self.parseExpression(0);
        
        return ast.Definition{
            .name = name_tok.text,
            .params = params.items,
            .body = body,
            .where_clause = null,
            .loc = .{
                .line = name_tok.line,
                .column = name_tok.column,
            },
        };
    }

    pub fn parsePattern(self: *Parser) !ast.Pattern {
        const tok = try self.filter.next();
        switch (tok.id) {
            .name => {
                return ast.Pattern{ .identifier = tok.text };
            },
            .const_val => {
                const val = try std.fmt.parseInt(i64, tok.text, 0);
                return ast.Pattern{ .integer = val };
            },
            else => {
                try self.diags.addError(tok.line, tok.column, "Unexpected token in pattern");
                return error.SyntaxError;
            },
        }
    }

    pub fn parseExpression(self: *Parser, min_bp: u8) !ast.Expression {
        return pratt.parseExpression(self, min_bp);
    }
};
