const std = @import("std");

pub const Token = struct {
    kind: Kind,
    start: usize,
    end: usize,
    line: u32,
    col: u32,

    pub const Kind = enum {
        eof,
        invalid,

        identifier,
        string_literal,
        char_literal,
        int_literal,
        float_literal,
        pp_number,

        lbrace,
        rbrace,
        lparen,
        rparen,
        lbracket,
        rbracket,
        semicolon,
        comma,
        colon,
        question,
        tilde,
        dot,
        arrow,
        ellipsis,

        plus,
        minus,
        star,
        slash,
        percent,
        amp,
        pipe,
        caret,
        exclaim,
        eq,
        lt,
        gt,
        plus_plus,
        minus_minus,
        eq_eq,
        neq,
        leq,
        geq,
        lt_lt,
        gt_gt,
        amp_amp,
        pipe_pipe,
        plus_eq,
        minus_eq,
        star_eq,
        slash_eq,
        percent_eq,
        amp_eq,
        pipe_eq,
        caret_eq,
        lt_lt_eq,
        gt_gt_eq,
        hash,
        hash_hash,

        keyword_auto,
        keyword_break,
        keyword_case,
        keyword_char,
        keyword_const,
        keyword_continue,
        keyword_default,
        keyword_do,
        keyword_double,
        keyword_else,
        keyword_enum,
        keyword_extern,
        keyword_float,
        keyword_for,
        keyword_goto,
        keyword_if,
        keyword_inline,
        keyword_int,
        keyword_long,
        keyword_register,
        keyword_restrict,
        keyword_return,
        keyword_short,
        keyword_signed,
        keyword_sizeof,
        keyword_static,
        keyword_struct,
        keyword_switch,
        keyword_typedef,
        keyword_union,
        keyword_unsigned,
        keyword_void,
        keyword_volatile,
        keyword_while,
        keyword__Bool,
        keyword__Complex,
        keyword__Imaginary,
        keyword__attribute__,
        keyword__asm__,
        keyword__inline__,
        keyword__typeof__,
        keyword__extension__,
        keyword__int128,
        keyword__builtin_va_list,
        keyword__has_include,
        keyword__has_include_next,
        keyword__has_attribute,
        keyword__has_builtin,
        keyword__has_feature,
        keyword__has_extension,
        keyword__declspec,
        keyword__cdecl,
        keyword__stdcall,
        keyword__fastcall,
        keyword__thiscall,
        keyword__vectorcall,
        keyword__forceinline,
        keyword__unaligned,
        keyword__uuidof,
        keyword__interface,
        keyword__int8,
        keyword__int16,
        keyword__int32,
        keyword__int64,
        keyword__ptr32,
        keyword__ptr64,
        keyword__w64,
        keyword__wchar_t,
        keyword__except,
        keyword__finally,
        keyword__leave,
        keyword__try,
        keyword_bool,
        keyword_wchar_t,

        pp_include,
        pp_define,
        pp_undef,
        pp_if,
        pp_ifdef,
        pp_ifndef,
        pp_else,
        pp_elif,
        pp_endif,
        pp_pragma,
        pp_error,
        pp_line,
        pp_include_next,
        pp_warning,
    };
};

const keywords = std.StaticStringMap(Token.Kind).initComptime(.{
    .{ "auto", .keyword_auto },
    .{ "break", .keyword_break },
    .{ "case", .keyword_case },
    .{ "char", .keyword_char },
    .{ "const", .keyword_const },
    .{ "continue", .keyword_continue },
    .{ "default", .keyword_default },
    .{ "do", .keyword_do },
    .{ "double", .keyword_double },
    .{ "else", .keyword_else },
    .{ "enum", .keyword_enum },
    .{ "extern", .keyword_extern },
    .{ "float", .keyword_float },
    .{ "for", .keyword_for },
    .{ "goto", .keyword_goto },
    .{ "if", .keyword_if },
    .{ "inline", .keyword_inline },
    .{ "int", .keyword_int },
    .{ "long", .keyword_long },
    .{ "register", .keyword_register },
    .{ "restrict", .keyword_restrict },
    .{ "return", .keyword_return },
    .{ "short", .keyword_short },
    .{ "signed", .keyword_signed },
    .{ "sizeof", .keyword_sizeof },
    .{ "static", .keyword_static },
    .{ "struct", .keyword_struct },
    .{ "switch", .keyword_switch },
    .{ "typedef", .keyword_typedef },
    .{ "union", .keyword_union },
    .{ "unsigned", .keyword_unsigned },
    .{ "void", .keyword_void },
    .{ "volatile", .keyword_volatile },
    .{ "while", .keyword_while },
    .{ "_Bool", .keyword__Bool },
    .{ "_Complex", .keyword__Complex },
    .{ "_Imaginary", .keyword__Imaginary },
    .{ "__attribute__", .keyword__attribute__ },
    .{ "__asm__", .keyword__asm__ },
    .{ "__inline__", .keyword__inline__ },
    .{ "__typeof__", .keyword__typeof__ },
    .{ "__extension__", .keyword__extension__ },
    .{ "__int128", .keyword__int128 },
    .{ "__builtin_va_list", .keyword__builtin_va_list },
    .{ "__has_include", .keyword__has_include },
    .{ "__has_include_next", .keyword__has_include_next },
    .{ "__has_attribute", .keyword__has_attribute },
    .{ "__has_builtin", .keyword__has_builtin },
    .{ "__has_feature", .keyword__has_feature },
    .{ "__has_extension", .keyword__has_extension },
    .{ "__declspec", .keyword__declspec },
    .{ "__cdecl", .keyword__cdecl },
    .{ "__stdcall", .keyword__stdcall },
    .{ "__fastcall", .keyword__fastcall },
    .{ "__thiscall", .keyword__thiscall },
    .{ "__vectorcall", .keyword__vectorcall },
    .{ "__forceinline", .keyword__forceinline },
    .{ "__unaligned", .keyword__unaligned },
    .{ "__uuidof", .keyword__uuidof },
    .{ "__interface", .keyword__interface },
    .{ "__int8", .keyword__int8 },
    .{ "__int16", .keyword__int16 },
    .{ "__int32", .keyword__int32 },
    .{ "__int64", .keyword__int64 },
    .{ "__ptr32", .keyword__ptr32 },
    .{ "__ptr64", .keyword__ptr64 },
    .{ "__w64", .keyword__w64 },
    .{ "__wchar_t", .keyword__wchar_t },
    .{ "__except", .keyword__except },
    .{ "__finally", .keyword__finally },
    .{ "__leave", .keyword__leave },
    .{ "__try", .keyword__try },
    .{ "bool", .keyword_bool },
    .{ "wchar_t", .keyword_wchar_t },
});

pub const Tokenizer = struct {
    buffer: []const u8,
    pos: usize,
    line: u32,
    col: u32,

    pub fn init(buffer: []const u8) Tokenizer {
        return .{
            .buffer = buffer,
            .pos = 0,
            .line = 1,
            .col = 1,
        };
    }

    pub fn next(self: *Tokenizer) Token {
        while (self.pos < self.buffer.len) {
            const c = self.buffer[self.pos];
            switch (c) {
                ' ', '\t', '\r', '\n' => {
                    self.skipWhitespace();
                    continue;
                },
                '/' => {
                    if (self.pos + 1 < self.buffer.len) {
                        const next_char = self.buffer[self.pos + 1];
                        if (next_char == '/') {
                            self.skipLineComment();
                            continue;
                        }
                        if (next_char == '*') {
                            self.skipBlockComment();
                            continue;
                        }
                    }
                    return self.punctOrAssign(.slash, .slash, .slash_eq);
                },
                '#' => {
                    if (self.col == 1) {
                        return self.readPreprocessor();
                    }
                    if (self.pos + 1 < self.buffer.len and self.buffer[self.pos + 1] == '#') {
                        return self.makeToken(.hash_hash, self.pos, self.pos + 2);
                    }
                    return self.makeToken(.hash, self.pos, self.pos + 1);
                },
                '\'' => return self.readCharLiteral(),
                '"' => return self.readStringLiteral(),
                'L', 'u', 'U' => {
                    if (self.pos + 1 < self.buffer.len) {
                        const next_char = self.buffer[self.pos + 1];
                        if ((c == 'L' or c == 'u' or c == 'U') and (next_char == '\'' or next_char == '"' or next_char == 'R')) {
                            if (next_char == '\'') return self.readWideCharLiteral();
                            return self.readWideStringLiteral();
                        }
                        if (c == 'u' and self.pos + 2 < self.buffer.len) {
                            if (self.buffer[self.pos + 1] == '8' and (self.buffer[self.pos + 2] == '"' or self.buffer[self.pos + 2] == '\'' or self.buffer[self.pos + 2] == 'R')) {
                                if (self.buffer[self.pos + 2] == '\'') return self.readWideCharLiteral();
                                return self.readWideStringLiteral();
                            }
                        }
                    }
                    return self.readIdentifierOrKeyword();
                },
                '0'...'9' => return self.readNumber(),
                'a'...'l', 'm'...'q', 's'...'t', 'v'...'z', 'A'...'K', 'M'...'Q', 'S'...'T', 'V'...'Z', '_' => {
                    return self.readIdentifierOrKeyword();
                },
                'r', 'R' => {
                    if (self.pos + 1 < self.buffer.len and self.buffer[self.pos + 1] == '"') {
                        self.pos += 1;
                        return self.readRawStringLiteral(self.pos);
                    }
                    return self.readIdentifierOrKeyword();
                },
                '{' => return self.makeToken(.lbrace, self.pos, self.pos + 1),
                '}' => return self.makeToken(.rbrace, self.pos, self.pos + 1),
                '(' => return self.makeToken(.lparen, self.pos, self.pos + 1),
                ')' => return self.makeToken(.rparen, self.pos, self.pos + 1),
                '[' => return self.makeToken(.lbracket, self.pos, self.pos + 1),
                ']' => return self.makeToken(.rbracket, self.pos, self.pos + 1),
                ';' => return self.makeToken(.semicolon, self.pos, self.pos + 1),
                ',' => return self.makeToken(.comma, self.pos, self.pos + 1),
                '?' => return self.makeToken(.question, self.pos, self.pos + 1),
                '~' => return self.makeToken(.tilde, self.pos, self.pos + 1),
                ':' => return self.makeToken(.colon, self.pos, self.pos + 1),
                '+' => return self.punctOrAssign2(.plus, .plus_plus, .plus_eq),
                '-' => {
                    if (self.pos + 1 < self.buffer.len) {
                        const next_char = self.buffer[self.pos + 1];
                        if (next_char == '>') return self.makeToken(.arrow, self.pos, self.pos + 2);
                        if (next_char == '-') return self.makeToken(.minus_minus, self.pos, self.pos + 2);
                    }
                    return self.punctOrAssign(.minus, .minus, .minus_eq);
                },
                '*' => return self.punctOrAssign(.star, .star, .star_eq),
                '%' => return self.punctOrAssign(.percent, .percent, .percent_eq),
                '&' => return self.punctOrAssign2(.amp, .amp_amp, .amp_eq),
                '|' => return self.punctOrAssign2(.pipe, .pipe_pipe, .pipe_eq),
                '^' => return self.punctOrAssign(.caret, .caret, .caret_eq),
                '!' => {
                    if (self.pos + 1 < self.buffer.len and self.buffer[self.pos + 1] == '=') {
                        return self.makeToken(.neq, self.pos, self.pos + 2);
                    }
                    return self.punct(.exclaim);
                },
                '=' => return self.punctOrAssign(.eq, .eq, .eq_eq),
                '<' => {
                    if (self.pos + 1 < self.buffer.len) {
                        const next_char = self.buffer[self.pos + 1];
                        if (next_char == '<') {
                            if (self.pos + 2 < self.buffer.len and self.buffer[self.pos + 2] == '=') {
                                return self.makeToken(.lt_lt_eq, self.pos, self.pos + 3);
                            }
                            return self.makeToken(.lt_lt, self.pos, self.pos + 2);
                        }
                        if (next_char == '=') return self.makeToken(.leq, self.pos, self.pos + 2);
                    }
                    return self.makeToken(.lt, self.pos, self.pos + 1);
                },
                '>' => {
                    if (self.pos + 1 < self.buffer.len) {
                        const next_char = self.buffer[self.pos + 1];
                        if (next_char == '>') {
                            if (self.pos + 2 < self.buffer.len and self.buffer[self.pos + 2] == '=') {
                                return self.makeToken(.gt_gt_eq, self.pos, self.pos + 3);
                            }
                            return self.makeToken(.gt_gt, self.pos, self.pos + 2);
                        }
                        if (next_char == '=') return self.makeToken(.geq, self.pos, self.pos + 2);
                    }
                    return self.makeToken(.gt, self.pos, self.pos + 1);
                },
                '.' => {
                    if (self.pos + 1 < self.buffer.len) {
                        const next_char = self.buffer[self.pos + 1];
                        if (next_char == '.') {
                            if (self.pos + 2 < self.buffer.len and self.buffer[self.pos + 2] == '.') {
                                return self.makeToken(.ellipsis, self.pos, self.pos + 3);
                            }
                        }
                        if (next_char >= '0' and next_char <= '9') {
                            return self.readNumber();
                        }
                    }
                    return self.makeToken(.dot, self.pos, self.pos + 1);
                },
                else => {
                    if (c >= 128 or c == '\\') {
                        if (c == '\\' and self.pos + 1 < self.buffer.len) {
                            const next_char = self.buffer[self.pos + 1];
                            if (next_char == 'U' or next_char == 'u') {
                                return self.readIdentifierOrKeyword();
                            }
                        }
                    }
                    return self.makeErrorToken("unexpected character");
                },
            }
        }
        return .{ .kind = .eof, .start = self.pos, .end = self.pos, .line = self.line, .col = self.col };
    }

    pub fn slice(self: *const Tokenizer, token: Token) []const u8 {
        return self.buffer[token.start..token.end];
    }

    fn makeToken(self: *Tokenizer, kind: Token.Kind, start: usize, end: usize) Token {
        const start_col = self.col;
        self.pos = end;
        self.col += @intCast(end - start);
        return .{ .kind = kind, .start = start, .end = end, .line = self.line, .col = start_col };
    }

    fn makeErrorToken(self: *Tokenizer, _: []const u8) Token {
        defer self.pos += 1;
        return .{ .kind = .invalid, .start = self.pos, .end = self.pos + 1, .line = self.line, .col = self.col };
    }

    fn punct(self: *Tokenizer, kind: Token.Kind) Token {
        return self.makeToken(kind, self.pos, self.pos + 1);
    }

    fn punctOrAssign(self: *Tokenizer, single: Token.Kind, _: Token.Kind, assign: Token.Kind) Token {
        if (self.pos + 1 < self.buffer.len and self.buffer[self.pos + 1] == '=') {
            return self.makeToken(assign, self.pos, self.pos + 2);
        }
        return self.punct(single);
    }

    fn punctOrAssign2(self: *Tokenizer, single: Token.Kind, double: Token.Kind, assign: Token.Kind) Token {
        if (self.pos + 1 < self.buffer.len) {
            const next_char = self.buffer[self.pos + 1];
            if (next_char == '=') return self.makeToken(assign, self.pos, self.pos + 2);
            if (next_char == self.buffer[self.pos]) return self.makeToken(double, self.pos, self.pos + 2);
        }
        return self.punct(single);
    }

    fn skipWhitespace(self: *Tokenizer) void {
        while (self.pos < self.buffer.len) {
            switch (self.buffer[self.pos]) {
                ' ' => {
                    self.pos += 1;
                    self.col += 1;
                },
                '\t' => {
                    self.pos += 1;
                    self.col += 8;
                },
                '\r' => {
                    self.pos += 1;
                },
                '\n' => {
                    self.pos += 1;
                    self.line += 1;
                    self.col = 1;
                },
                else => break,
            }
        }
    }

    fn skipLineComment(self: *Tokenizer) void {
        self.pos += 2;
        self.col += 2;
        while (self.pos < self.buffer.len and self.buffer[self.pos] != '\n') {
            self.pos += 1;
            self.col += 1;
        }
    }

    fn skipBlockComment(self: *Tokenizer) void {
        self.pos += 2;
        self.col += 2;
        while (self.pos + 1 < self.buffer.len) {
            if (self.buffer[self.pos] == '*' and self.buffer[self.pos + 1] == '/') {
                self.pos += 2;
                self.col += 2;
                return;
            }
            if (self.buffer[self.pos] == '\n') {
                self.pos += 1;
                self.line += 1;
                self.col = 1;
            } else {
                self.pos += 1;
                self.col += 1;
            }
        }
        if (self.pos < self.buffer.len) {
            self.pos += 1;
        }
    }

    fn readIdentifierOrKeyword(self: *Tokenizer) Token {
        const start = self.pos;
        while (self.pos < self.buffer.len) {
            const c = self.buffer[self.pos];
            if (isIdentContinue(c)) {
                self.pos += 1;
            } else {
                break;
            }
        }
        const end = self.pos;
        const ident_slice = self.buffer[start..end];
        const kind = keywords.get(ident_slice) orelse .identifier;
        return self.makeToken(kind, start, end);
    }

    fn readNumber(self: *Tokenizer) Token {
        const start = self.pos;
        if (self.buffer[self.pos] == '0' and self.pos + 1 < self.buffer.len) {
            const next_char = self.buffer[self.pos + 1];
            if (next_char == 'x' or next_char == 'X') {
                self.pos += 2;
                while (self.pos < self.buffer.len and isHexDigit(self.buffer[self.pos])) {
                    self.pos += 1;
                }
                return self.finishNumberOrPPNumber(start);
            }
            if (next_char == 'b' or next_char == 'B') {
                self.pos += 2;
                while (self.pos < self.buffer.len and (self.buffer[self.pos] == '0' or self.buffer[self.pos] == '1')) {
                    self.pos += 1;
                }
                return self.finishNumberOrPPNumber(start);
            }
        }
        while (self.pos < self.buffer.len) {
            const c = self.buffer[self.pos];
            if (c >= '0' and c <= '9') {
                self.pos += 1;
            } else {
                break;
            }
        }
        return self.finishNumberOrPPNumber(start);
    }

    fn finishNumberOrPPNumber(self: *Tokenizer, start: usize) Token {
        var has_frac = false;
        var has_exp = false;
        var has_suffix = false;

        if (self.pos < self.buffer.len and self.buffer[self.pos] == '.') {
            has_frac = true;
            self.pos += 1;
            while (self.pos < self.buffer.len and self.buffer[self.pos] >= '0' and self.buffer[self.pos] <= '9') {
                self.pos += 1;
            }
        }

        if (self.pos < self.buffer.len and (self.buffer[self.pos] == 'e' or self.buffer[self.pos] == 'E' or self.buffer[self.pos] == 'p' or self.buffer[self.pos] == 'P')) {
            has_exp = true;
            self.pos += 1;
            if (self.pos < self.buffer.len and (self.buffer[self.pos] == '+' or self.buffer[self.pos] == '-')) {
                self.pos += 1;
            }
            while (self.pos < self.buffer.len and self.buffer[self.pos] >= '0' and self.buffer[self.pos] <= '9') {
                self.pos += 1;
            }
        }

        if (self.pos < self.buffer.len) {
            const c = self.buffer[self.pos];
            if (c == 'f' or c == 'F' or c == 'l' or c == 'L') {
                has_suffix = true;
                self.pos += 1;
            }
            if (self.pos < self.buffer.len and (self.buffer[self.pos] == 'l' or self.buffer[self.pos] == 'L')) {
                if (self.buffer[self.pos - 1] == 'l' or self.buffer[self.pos - 1] == 'L') {
                    has_suffix = true;
                    self.pos += 1;
                }
            }
            if (self.pos < self.buffer.len and (self.buffer[self.pos] == 'u' or self.buffer[self.pos] == 'U')) {
                has_suffix = true;
                self.pos += 1;
                if (self.pos < self.buffer.len and (self.buffer[self.pos] == 'l' or self.buffer[self.pos] == 'L')) {
                    self.pos += 1;
                    if (self.pos < self.buffer.len and (self.buffer[self.pos] == 'l' or self.buffer[self.pos] == 'L')) {
                        self.pos += 1;
                    }
                }
            }
            if (self.pos < self.buffer.len and (self.buffer[self.pos] == 'l' or self.buffer[self.pos] == 'L')) {
                has_suffix = true;
                self.pos += 1;
                if (self.pos < self.buffer.len and (self.buffer[self.pos] == 'u' or self.buffer[self.pos] == 'U')) {
                    self.pos += 1;
                }
            }
        }

        if (self.pos < self.buffer.len and (isIdentStart(self.buffer[self.pos]) or self.buffer[self.pos] == '.')) {
            while (self.pos < self.buffer.len) {
                const c = self.buffer[self.pos];
                if (isIdentContinue(c) or c == '.' or (c >= '0' and c <= '9')) {
                    self.pos += 1;
                } else {
                    break;
                }
            }
            return self.makeToken(.pp_number, start, self.pos);
        }

        const kind: Token.Kind = if (has_frac or has_exp) .float_literal else .int_literal;
        return self.makeToken(kind, start, self.pos);
    }

    fn readStringLiteral(self: *Tokenizer) Token {
        return self.readStringLiteralInner('"', false);
    }

    fn readWideStringLiteral(self: *Tokenizer) Token {
        const start = self.pos;
        if (self.buffer[self.pos] == 'u' and self.pos + 1 < self.buffer.len and self.buffer[self.pos + 1] == '8') {
            self.pos += 2;
        } else {
            self.pos += 1;
        }
        if (self.pos < self.buffer.len and self.buffer[self.pos] == 'R') {
            return self.readRawStringLiteral(start);
        }
        return self.readStringLiteralInner('"', false);
    }

    fn readCharLiteral(self: *Tokenizer) Token {
        return self.readStringLiteralInner('\'', false);
    }

    fn readWideCharLiteral(self: *Tokenizer) Token {
        if (self.pos < self.buffer.len) {
            if (self.buffer[self.pos] == 'u' and self.pos + 1 < self.buffer.len and self.buffer[self.pos + 1] == '8') {
                self.pos += 2;
            } else {
                self.pos += 1;
            }
        }
        return self.readStringLiteralInner('\'', false);
    }

    fn readStringLiteralInner(self: *Tokenizer, quote: u8, _: bool) Token {
        const start = self.pos;
        self.pos += 1;
        _ = self.advancePastQuote(quote);
        const end = self.pos;
        return self.makeToken(if (quote == '"') .string_literal else .char_literal, start, end);
    }

    fn advancePastQuote(self: *Tokenizer, quote: u8) void {
        _ = self.advancePastQuoteAllowNewline(quote, true);
    }

    fn advancePastQuoteAllowNewline(self: *Tokenizer, quote: u8, allow_continuation: bool) void {
        while (self.pos < self.buffer.len) {
            const c = self.buffer[self.pos];
            if (c == quote) {
                self.pos += 1;
                return;
            }
            if (c == '\\') {
                if (self.pos + 1 < self.buffer.len) {
                    const next_char = self.buffer[self.pos + 1];
                    if (next_char == '\n') {
                        self.pos += 2;
                        self.line += 1;
                        continue;
                    }
                    if (next_char == '\r') {
                        self.pos += 2;
                        if (self.pos < self.buffer.len and self.buffer[self.pos] == '\n') {
                            self.pos += 1;
                        }
                        self.line += 1;
                        continue;
                    }
                    self.pos += 2;
                    continue;
                }
            }
            if (c == '\n' and !allow_continuation) {
                return;
            }
            if (c == '\n') {
                self.pos += 1;
                self.line += 1;
            } else {
                self.pos += 1;
            }
        }
    }

    fn readRawStringLiteral(self: *Tokenizer, start: usize) Token {
        self.pos += 1;
        if (self.pos >= self.buffer.len) return self.makeToken(.string_literal, start, self.pos);
        if (self.buffer[self.pos] != '"') return self.makeToken(.string_literal, start, self.pos);
        self.pos += 1;

        const delim_start = self.pos;
        while (self.pos < self.buffer.len and self.buffer[self.pos] != '(') {
            self.pos += 1;
        }
        if (self.pos >= self.buffer.len) return self.makeToken(.string_literal, start, self.pos);
        const delim_len = self.pos - delim_start;
        const delim = self.buffer[delim_start .. delim_start + delim_len];
        self.pos += 1;

        while (self.pos + 1 + delim_len < self.buffer.len) {
            if (self.buffer[self.pos] == ')' and std.mem.eql(u8, self.buffer[self.pos + 1 .. self.pos + 1 + delim_len], delim) and self.buffer[self.pos + 1 + delim_len] == '"') {
                self.pos += 2 + delim_len;
                return self.makeToken(.string_literal, start, self.pos);
            }
            if (self.buffer[self.pos] == '\n') {
                self.pos += 1;
                self.line += 1;
            } else {
                self.pos += 1;
            }
        }
        return self.makeToken(.string_literal, start, self.buffer.len);
    }

    fn readPreprocessor(self: *Tokenizer) Token {
        const start = self.pos;
        const start_col = self.col;
        while (self.pos < self.buffer.len and self.buffer[self.pos] != '\n') {
            if (self.buffer[self.pos] == '\\' and self.pos + 1 < self.buffer.len and self.buffer[self.pos + 1] == '\n') {
                self.pos += 2;
                self.line += 1;
                continue;
            }
            if (self.buffer[self.pos] == '/' and self.pos + 1 < self.buffer.len) {
                if (self.buffer[self.pos + 1] == '/') {
                    self.skipLineComment();
                    continue;
                }
                if (self.buffer[self.pos + 1] == '*') {
                    self.skipBlockComment();
                    continue;
                }
            }
            self.pos += 1;
        }
        const end = self.pos;
        self.col = start_col + @as(u32, @intCast(end - start));
        const line_start = start + 1;
        var i: usize = line_start;
        while (i < end and (self.buffer[i] == ' ' or self.buffer[i] == '\t')) {
            i += 1;
        }
        const directive_start = i;
        while (i < end and isIdentContinue(self.buffer[i])) {
            i += 1;
        }
        const directive = self.buffer[directive_start..i];

        const pp_map = std.StaticStringMap(Token.Kind).initComptime(.{
            .{ "include", .pp_include },
            .{ "include_next", .pp_include_next },
            .{ "define", .pp_define },
            .{ "undef", .pp_undef },
            .{ "if", .pp_if },
            .{ "ifdef", .pp_ifdef },
            .{ "ifndef", .pp_ifndef },
            .{ "else", .pp_else },
            .{ "elif", .pp_elif },
            .{ "endif", .pp_endif },
            .{ "pragma", .pp_pragma },
            .{ "error", .pp_error },
            .{ "line", .pp_line },
            .{ "warning", .pp_warning },
        });

        const kind = pp_map.get(directive) orelse .pp_number;
        self.pos = end;
        return .{ .kind = kind, .start = start, .end = end, .line = self.line, .col = start_col };
    }
};

fn isIdentStart(c: u8) bool {
    return switch (c) {
        'a'...'z', 'A'...'Z', '_' => true,
        else => false,
    };
}

fn isIdentContinue(c: u8) bool {
    return switch (c) {
        'a'...'z', 'A'...'Z', '0'...'9', '_' => true,
        else => false,
    };
}

fn isHexDigit(c: u8) bool {
    return switch (c) {
        '0'...'9', 'a'...'f', 'A'...'F' => true,
        else => false,
    };
}

test "empty input produces eof" {
    var tok = Tokenizer.init("");
    const t = tok.next();
    try std.testing.expectEqual(Token.Kind.eof, t.kind);
}

test "single character tokens" {
    const src = "{}();,?~:[]";
    var tok = Tokenizer.init(src);
    try std.testing.expectEqual(Token.Kind.lbrace, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.rbrace, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.lparen, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.rparen, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.semicolon, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.comma, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.question, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.tilde, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.colon, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.lbracket, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.rbracket, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.eof, tok.next().kind);
}

test "arithmetic operators" {
    const src = "+ - * / % ++ -- ->";
    var tok = Tokenizer.init(src);
    try std.testing.expectEqual(Token.Kind.plus, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.minus, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.star, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.slash, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.percent, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.plus_plus, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.minus_minus, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.arrow, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.eof, tok.next().kind);
}

test "comparison and bitwise operators" {
    const src = "== != < > <= >= << >> && || & | ^ !";
    var tok = Tokenizer.init(src);
    try std.testing.expectEqual(Token.Kind.eq_eq, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.neq, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.lt, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.gt, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.leq, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.geq, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.lt_lt, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.gt_gt, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.amp_amp, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.pipe_pipe, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.amp, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.pipe, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.caret, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.exclaim, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.eof, tok.next().kind);
}

test "assignment operators" {
    const src = "= += -= *= /= %= &= |= ^= <<= >>=";
    var tok = Tokenizer.init(src);
    try std.testing.expectEqual(Token.Kind.eq, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.plus_eq, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.minus_eq, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.star_eq, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.slash_eq, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.percent_eq, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.amp_eq, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.pipe_eq, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.caret_eq, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.lt_lt_eq, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.gt_gt_eq, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.eof, tok.next().kind);
}

test "null preprocessor directive" {
    var tok = Tokenizer.init("#\nint");
    try std.testing.expectEqual(Token.Kind.pp_number, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_int, tok.next().kind);
}

test "hash_hash separator after preprocessor" {
    var tok = Tokenizer.init("#define CONCAT(a,b) a ## b\n");
    try std.testing.expectEqual(Token.Kind.pp_define, tok.next().kind);
}

test "ellipsis and dot" {
    const src = "... .";
    var tok = Tokenizer.init(src);
    try std.testing.expectEqual(Token.Kind.ellipsis, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.dot, tok.next().kind);
}

test "C keywords" {
    const src = "int long unsigned return sizeof struct enum typedef void const volatile static extern inline goto switch case break continue default for while do if else float double char short signed";
    var tok = Tokenizer.init(src);
    try std.testing.expectEqual(Token.Kind.keyword_int, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_long, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_unsigned, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_return, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_sizeof, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_struct, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_enum, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_typedef, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_void, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_const, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_volatile, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_static, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_extern, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_inline, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_goto, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_switch, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_case, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_break, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_continue, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_default, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_for, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_while, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_do, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_if, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_else, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_float, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_double, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_char, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_short, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_signed, tok.next().kind);
}

test "GNU/MSVC extensions" {
    const src = "__attribute__ __asm__ __typeof__ __extension__ __int128 __declspec __cdecl __stdcall __fastcall __thiscall bool wchar_t __int8 __int16 __int32 __int64 __ptr32 __ptr64 __w64 __forceinline __unaligned __uuidof __interface";
    var tok = Tokenizer.init(src);
    try std.testing.expectEqual(Token.Kind.keyword__attribute__, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__asm__, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__typeof__, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__extension__, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__int128, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__declspec, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__cdecl, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__stdcall, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__fastcall, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__thiscall, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_bool, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_wchar_t, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__int8, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__int16, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__int32, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__int64, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__ptr32, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__ptr64, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__w64, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__forceinline, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__unaligned, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__uuidof, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__interface, tok.next().kind);
}

test "identifier" {
    var tok = Tokenizer.init("foo_bar123 _tmp");
    const t1 = tok.next();
    try std.testing.expectEqual(Token.Kind.identifier, t1.kind);
    try std.testing.expectEqualStrings("foo_bar123", tok.slice(t1));
    try std.testing.expectEqualStrings("_tmp", tok.slice(tok.next()));
}

test "decimal integer literal" {
    var tok = Tokenizer.init("42");
    const t = tok.next();
    try std.testing.expectEqual(Token.Kind.int_literal, t.kind);
    try std.testing.expectEqualStrings("42", tok.slice(t));
}

test "hex integer literal" {
    var tok = Tokenizer.init("0xFF");
    const t = tok.next();
    try std.testing.expectEqual(Token.Kind.int_literal, t.kind);
    try std.testing.expectEqualStrings("0xFF", tok.slice(t));
}

test "binary integer literal (GNU extension)" {
    var tok = Tokenizer.init("0b1010");
    const t = tok.next();
    try std.testing.expectEqual(Token.Kind.int_literal, t.kind);
    try std.testing.expectEqualStrings("0b1010", tok.slice(t));
}

test "integer with suffix" {
    var tok = Tokenizer.init("42ULL 0xABCDul 12345678u 0lu");
    const t1 = tok.next();
    try std.testing.expectEqual(Token.Kind.int_literal, t1.kind);
    try std.testing.expectEqualStrings("42ULL", tok.slice(t1));
    try std.testing.expectEqualStrings("0xABCDul", tok.slice(tok.next()));
    try std.testing.expectEqualStrings("12345678u", tok.slice(tok.next()));
    try std.testing.expectEqualStrings("0lu", tok.slice(tok.next()));
}

test "float literal" {
    var tok = Tokenizer.init("3.14 1.0e10 2.5f .5");
    const t1 = tok.next();
    try std.testing.expectEqual(Token.Kind.float_literal, t1.kind);
    try std.testing.expectEqualStrings("3.14", tok.slice(t1));
    try std.testing.expectEqualStrings("1.0e10", tok.slice(tok.next()));
    try std.testing.expectEqualStrings("2.5f", tok.slice(tok.next()));
    try std.testing.expectEqualStrings(".5", tok.slice(tok.next()));
}

test "string literal" {
    var tok = Tokenizer.init("\"hello world\"");
    const t = tok.next();
    try std.testing.expectEqual(Token.Kind.string_literal, t.kind);
    try std.testing.expectEqualStrings("\"hello world\"", tok.slice(t));
}

test "char literal" {
    var tok = Tokenizer.init("'x' '\\n' '\\x41'");
    try std.testing.expectEqual(Token.Kind.char_literal, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.char_literal, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.char_literal, tok.next().kind);
}

test "wide string literal" {
    var tok = Tokenizer.init("L\"hello\" u\"hello\" U\"hello\" u8\"hello\"");
    try std.testing.expectEqual(Token.Kind.string_literal, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.string_literal, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.string_literal, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.string_literal, tok.next().kind);
}

test "wide char literal" {
    var tok = Tokenizer.init("L'x' u'x' U'x' u8'x'");
    try std.testing.expectEqual(Token.Kind.char_literal, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.char_literal, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.char_literal, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.char_literal, tok.next().kind);
}

test "string literal with escape" {
    var tok = Tokenizer.init("\"hello\\nworld\"");
    const t = tok.next();
    try std.testing.expectEqual(Token.Kind.string_literal, t.kind);
    try std.testing.expectEqualStrings("\"hello\\nworld\"", tok.slice(t));
}

test "line comment" {
    var tok = Tokenizer.init("int // this is a comment\nx;");
    try std.testing.expectEqual(Token.Kind.keyword_int, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.identifier, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.semicolon, tok.next().kind);
}

test "block comment" {
    var tok = Tokenizer.init("int /* comment */ x;");
    try std.testing.expectEqual(Token.Kind.keyword_int, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.identifier, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.semicolon, tok.next().kind);
}

test "multiline block comment" {
    var tok = Tokenizer.init("/* line1\nline2\nline3 */ int");
    try std.testing.expectEqual(Token.Kind.keyword_int, tok.next().kind);
    try std.testing.expectEqual(@as(u32, 3), tok.line);
}

test "line counting" {
    var tok = Tokenizer.init("int\nlong\nvoid");
    try std.testing.expectEqual(Token.Kind.keyword_int, tok.next().kind);
    try std.testing.expectEqual(@as(u32, 1), tok.line);
    try std.testing.expectEqual(Token.Kind.keyword_long, tok.next().kind);
    try std.testing.expectEqual(@as(u32, 2), tok.line);
    try std.testing.expectEqual(Token.Kind.keyword_void, tok.next().kind);
    try std.testing.expectEqual(@as(u32, 3), tok.line);
}

test "column counting" {
    var tok = Tokenizer.init("  int  x;");
    try std.testing.expectEqual(Token.Kind.keyword_int, tok.next().kind);
    try std.testing.expectEqual(@as(u32, 6), tok.col);
    try std.testing.expectEqual(Token.Kind.identifier, tok.next().kind);
    try std.testing.expectEqual(@as(u32, 9), tok.col);
}

test "preprocessor include" {
    var tok = Tokenizer.init("#include <stdio.h>\nint");
    try std.testing.expectEqual(Token.Kind.pp_include, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_int, tok.next().kind);
}

test "preprocessor define" {
    var tok = Tokenizer.init("#define MAX 100\nint");
    try std.testing.expectEqual(Token.Kind.pp_define, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_int, tok.next().kind);
}

test "preprocessor ifdef" {
    var tok = Tokenizer.init("#ifdef __APPLE__\nint x;\n#endif\n");
    try std.testing.expectEqual(Token.Kind.pp_ifdef, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_int, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.identifier, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.semicolon, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.pp_endif, tok.next().kind);
}

test "preprocessor with continuation" {
    var tok = Tokenizer.init("#define MACRO \\\n    value\nint");
    try std.testing.expectEqual(Token.Kind.pp_define, tok.next().kind);
    try std.testing.expectEqual(@as(u32, 2), tok.line);
    try std.testing.expectEqual(Token.Kind.keyword_int, tok.next().kind);
    try std.testing.expectEqual(@as(u32, 3), tok.line);
}

test "raw string literal" {
    var tok = Tokenizer.init("R\"(hello\nworld)\"");
    try std.testing.expectEqual(Token.Kind.string_literal, tok.next().kind);
}

test "raw string with delimiter" {
    var tok = Tokenizer.init("R\"foo(hello)foo\"");
    const t = tok.next();
    try std.testing.expectEqual(Token.Kind.string_literal, t.kind);
}

test "preprocessing number with dots and identifiers" {
    var tok = Tokenizer.init("1.2.3.4");
    const t = tok.next();
    try std.testing.expectEqual(Token.Kind.pp_number, t.kind);
    try std.testing.expectEqualStrings("1.2.3.4", tok.slice(t));
}

test "token positions are correct" {
    var tok = Tokenizer.init("int x = 42;");
    const t1 = tok.next();
    try std.testing.expectEqual(@as(usize, 0), t1.start);
    try std.testing.expectEqual(@as(usize, 3), t1.end);
    const t2 = tok.next();
    try std.testing.expectEqual(@as(usize, 4), t2.start);
    try std.testing.expectEqual(@as(usize, 5), t2.end);
    const t3 = tok.next();
    try std.testing.expectEqual(@as(usize, 6), t3.start);
    try std.testing.expectEqual(@as(usize, 7), t3.end);
    const t4 = tok.next();
    try std.testing.expectEqual(@as(usize, 8), t4.start);
    try std.testing.expectEqual(@as(usize, 10), t4.end);
    const t5 = tok.next();
    try std.testing.expectEqual(@as(usize, 10), t5.start);
    try std.testing.expectEqual(@as(usize, 11), t5.end);
}

test "small real-world snippet" {
    const src = "int main(void) { return 0; }";
    var tok = Tokenizer.init(src);
    try std.testing.expectEqual(Token.Kind.keyword_int, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.identifier, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.lparen, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_void, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.rparen, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.lbrace, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword_return, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.int_literal, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.semicolon, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.rbrace, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.eof, tok.next().kind);
}

test "has_include and friends" {
    var tok = Tokenizer.init("__has_include __has_include_next __has_attribute __has_builtin __has_feature __has_extension");
    try std.testing.expectEqual(Token.Kind.keyword__has_include, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__has_include_next, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__has_attribute, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__has_builtin, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__has_feature, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__has_extension, tok.next().kind);
}

test "MSVC __except __finally __leave __try" {
    var tok = Tokenizer.init("__except __finally __leave __try");
    try std.testing.expectEqual(Token.Kind.keyword__except, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__finally, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__leave, tok.next().kind);
    try std.testing.expectEqual(Token.Kind.keyword__try, tok.next().kind);
}

test "pp_number with identifier suffix" {
    var tok = Tokenizer.init("123abc");
    const t = tok.next();
    try std.testing.expectEqual(Token.Kind.pp_number, t.kind);
    try std.testing.expectEqualStrings("123abc", tok.slice(t));
}

test "dot leading to float not pp_number" {
    var tok = Tokenizer.init(".5");
    const t = tok.next();
    try std.testing.expectEqual(Token.Kind.float_literal, t.kind);
    try std.testing.expectEqualStrings(".5", tok.slice(t));
}
