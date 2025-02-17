// From https://github.com/marler8997/html-css-renderer/blob/master/HtmlTokenizer.zig
///
/// An html5 tokenizer.
/// Implements the state machine described here:
///     https://html.spec.whatwg.org/multipage/parsing.html#tokenization
/// This tokenizer does not perform any processing/allocation, it simply
/// splits the input text into higher-level tokens.
const Tokenizer = @This();

const std = @import("std");

const log = std.log.scoped(.tokenizer);

return_attrs: bool = false,
idx: u32 = 0,
current: u8 = undefined,
state: State = .data,
deferred_token: ?Token = null,
last_start_tag_name: []const u8 = "",

const DOCTYPE = "DOCTYPE";
const form_feed = 0xc;

pub const Span = struct {
    start: u32,
    end: u32,
    pub fn slice(self: Span, src: []const u8) []const u8 {
        return src[self.start..self.end];
    }
};

pub const TokenError = enum {
    abrupt_closing_of_empty_comment,
    abrupt_doctype_public_identifier,
    abrupt_doctype_system_identifier,

    // Custom error
    deprecated_and_unsupported,

    end_tag_with_trailing_solidus,
    eof_before_tag_name,
    eof_in_attribute_value,
    eof_in_cdata,
    eof_in_comment,
    eof_in_doctype,
    eof_in_script_html_comment_like_text,
    eof_in_tag,

    incorrectly_opened_comment,
    incorrectly_closed_comment,

    invalid_character_sequence_after_doctype_name,
    invalid_first_character_of_tag_name,
    missing_attribute_value,
    missing_doctype_name,
    missing_doctype_public_identifier,
    missing_doctype_system_identifier,
    missing_end_tag_name,
    missing_quote_before_doctype_public_identifier,

    missing_quote_before_doctype_system_identifier,
    missing_whitespace_after_doctype_public_keyword,
    missing_whitespace_after_doctype_system_keyword,
    missing_whitespace_before_doctype_name,
    missing_whitespace_between_attributes,
    missing_whitespace_between_doctype_public_and_system_identifiers,

    nested_comment,

    unexpected_character_after_doctype_system_identifier,
    unexpected_character_in_attribute_name,
    unexpected_character_in_unquoted_attribute_value,
    unexpected_equals_sign_before_attribute_name,
    unexpected_null_character,
    unexpected_solidus_in_tag,
};

pub const Token = union(enum) {
    // Only returned when return_attrs == true
    tag_name: Span,
    attr: struct {
        // NOTE: process the name_raw by replacing
        //     - upper-case ascii alpha with lower case (add 0x20)
        //     - 0 with U+FFFD
        name_raw: Span,
        // NOTE: process value...somehow...
        value_raw: ?struct {
            quote: enum { none, single, double },
            span: Span,
        },
    },

    // Returned during normal operation
    doctype: Doctype,
    tag: Tag,

    comment: Span,
    text: Span,
    parse_error: struct {
        tag: TokenError,
        span: Span,
    },

    pub const Doctype = struct {
        span: Span,
        name_raw: ?Span,
        extra: Span = .{ .start = 0, .end = 0 },
        force_quirks: bool,
    };

    pub const Tag = struct {
        span: Span,
        name: Span,
        kind: enum {
            start,
            start_attrs,
            start_self,
            start_attrs_self,
            end,
        },

        pub fn isVoid(st: @This(), src: []const u8) bool {
            std.debug.assert(st.name.end != 0);
            const void_tags: []const []const u8 = &.{
                "area", "base",   "br",
                "col",  "embed",  "hr",
                "img",  "input",  "link",
                "meta", "source", "track",
                "wbr",
            };

            for (void_tags) |t| {
                if (std.ascii.eqlIgnoreCase(st.name.slice(src), t)) {
                    return true;
                }
            }
            return false;
        }
    };
};

const Data = struct {
    data_start: u32,
    tag_start: u32,
    name_start: u32 = 0,
};
const State = union(enum) {
    text: struct {
        start: u32,
        whitespace_only: bool = true,
        whitespace_streak: u32 = 0,
    },

    data: void,
    rcdata: u32,
    rawtext: u32,
    script_data: u32,
    plaintext: u32,
    tag_open: u32,
    end_tag_open: u32,
    tag_name: Token.Tag,

    rcdata_less_than_sign: Data,
    rcdata_end_tag_open: Data,
    rcdata_end_tag_name: Data,

    rawtext_less_than_sign: Data,
    rawtext_end_tag_open: Data,
    rawtext_end_tag_name: Data,

    script_data_less_than_sign: Data,
    script_data_end_tag_open: Data,
    script_data_end_tag_name: Data,
    script_data_escape_start: Data,
    script_data_escape_start_dash: Data,
    script_data_escaped: Data,
    script_data_escaped_dash: Data,
    script_data_escaped_dash_dash: Data,
    script_data_escaped_less_than_sign: Data,
    script_data_escaped_end_tag_open: Data,
    script_data_escaped_end_tag_name: Data,
    script_data_double_escape_start: Data,
    script_data_double_escaped: Data,
    script_data_double_escaped_dash: Data,
    script_data_double_escaped_dash_dash: Data,
    script_data_double_escaped_less_than_sign: Data,
    script_data_double_escape_end: Data,

    character_reference: void,

    markup_declaration_open: u32,
    doctype: u32,
    before_doctype_name: u32,
    doctype_name: struct {
        lbracket: u32,
        name_start: u32,
    },
    after_doctype_name: struct {
        lbracket: u32,
        name_raw: Span,
    },

    after_doctype_public_kw: Token.Doctype,
    before_doctype_public_identifier: Token.Doctype,
    doctype_public_identifier_double: Token.Doctype,
    doctype_public_identifier_single: Token.Doctype,
    after_doctype_public_identifier: Token.Doctype,

    beteen_doctype_public_and_system_identifiers: Token.Doctype,
    after_doctype_system_kw: Token.Doctype,

    before_doctype_system_identifier: Token.Doctype,
    doctype_system_identifier_double: Token.Doctype,
    doctype_system_identifier_single: Token.Doctype,
    after_doctype_system_identifier: Token.Doctype,

    comment_start: u32,
    comment_start_dash: u32,
    comment: u32,
    comment_less_than_sign: u32,
    comment_less_than_sign_bang: u32,
    comment_less_than_sign_bang_dash: u32,
    comment_less_than_sign_bang_dash_dash: u32,
    comment_end_dash: u32,
    comment_end: u32,
    comment_end_bang: u32,
    self_closing_start_tag: Token.Tag,
    before_attribute_name: Token.Tag,
    attribute_name: struct {
        tag: Token.Tag,
        name_start: u32,
    },
    after_attribute_name: struct {
        tag: Token.Tag,
        name_raw: Span,
    },
    before_attribute_value: struct {
        tag: Token.Tag,
        name_raw: Span,
        equal_sign: u32,
    },
    attribute_value: struct {
        tag: Token.Tag,
        quote: enum { double, single },
        name_raw: Span,
        value_start: u32,
    },
    attribute_value_unquoted: struct {
        tag: Token.Tag,
        name_raw: Span,
        value_start: u32,
    },
    after_attribute_value: struct {
        tag: Token.Tag,
        attr_value_end: u32,
    },
    bogus_comment: u32,

    bogus_doctype: Token.Doctype,
    cdata_section: u32,
    cdata_section_bracket: u32,
    cdata_section_end: u32,

    eof: void,
};

fn consume(self: *Tokenizer, src: []const u8) bool {
    if (self.idx == src.len) {
        return false;
    }
    self.current = src[self.idx];
    self.idx += 1;
    return true;
}

pub fn next(self: *Tokenizer, src: []const u8) ?Token {
    if (self.deferred_token) |t| {
        const token_copy = t;
        self.deferred_token = null;
        return token_copy;
    }
    const result = self.next2(src) orelse return null;
    if (result.deferred) |d| {
        self.deferred_token = d;
    }
    return result.token;
}

fn next2(self: *Tokenizer, src: []const u8) ?struct {
    token: Token,
    deferred: ?Token = null,
} {
    while (true) {
        log.debug("{any}", .{self.state});
        switch (self.state) {
            .text => |state| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    if (!state.whitespace_only) {
                        return .{
                            .token = .{
                                .text = .{
                                    .start = state.start,
                                    .end = self.idx - state.whitespace_streak,
                                },
                            },
                        };
                    }
                    return null;
                } else switch (self.current) {
                    //'&' => {} we don't process character references in the tokenizer
                    '<' => {
                        self.state = .{ .tag_open = self.idx - 1 };
                        if (!state.whitespace_only) {
                            return .{
                                .token = .{
                                    .text = .{
                                        .start = state.start,
                                        .end = self.idx - 1 - state.whitespace_streak,
                                    },
                                },
                            };
                        }
                    },
                    0 => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_null_character,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    else => {
                        if (state.whitespace_only) {
                            self.state.text.start = self.idx - 1;
                            self.state.text.whitespace_only = std.ascii.isWhitespace(
                                self.current,
                            );
                        } else {
                            if (std.ascii.isWhitespace(self.current)) {
                                self.state.text.whitespace_streak += 1;
                            } else {
                                self.state.text.whitespace_streak = 0;
                            }
                        }
                    },
                }
            },

            //https://html.spec.whatwg.org/multipage/parsing.html#data-state
            .data => {
                // EOF
                // Emit an end-of-file token.
                if (!self.consume(src)) {
                    self.state = .eof;
                    return null;
                } else switch (self.current) {
                    // U+0026 AMPERSAND (&)
                    // Set the return state to the data state. Switch to the character reference state.
                    //'&' => {} we don't process character references in the tokenizer

                    // U+003C LESS-THAN SIGN (<)
                    // Switch to the tag open state.
                    '<' => self.state = .{ .tag_open = self.idx - 1 },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Emit the current input character as a character token.
                    0 => {
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_null_character,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // Anything else
                    // Emit the current input character as a character token.
                    else => self.state = .{
                        .text = .{
                            .start = self.idx - 1,
                            .whitespace_only = std.ascii.isWhitespace(self.current),
                        },
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rcdata-state
            .rcdata => |start| {
                if (!self.consume(src)) {
                    // EOF
                    // Emit an end-of-file token.
                    self.state = .eof;
                    return null;
                } else switch (self.current) {
                    // U+0026 AMPERSAND (&)
                    // Set the return state to the RCDATA state. Switch to the character reference state.
                    // '&' => @panic("TODO"),
                    // U+003C LESS-THAN SIGN (<)
                    // Switch to the RCDATA less-than sign state.
                    '<' => self.state = .{
                        .rcdata_less_than_sign = .{
                            .data_start = start,
                            .tag_start = self.idx - 1,
                            .name_start = 0, // not known yet
                        },
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Emit a U+FFFD REPLACEMENT CHARACTER character token.
                    0 => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_null_character,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // Anything else
                    // Emit the current input character as a character token.
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rawtext-state
            .rawtext => |start| {
                if (!self.consume(src)) {
                    // EOF
                    // Emit an end-of-file token.
                    self.state = .eof;
                    return null;
                } else switch (self.current) {
                    // U+003C LESS-THAN SIGN (<)
                    // Switch to the RAWTEXT less-than sign state.
                    '<' => self.state = .{
                        .rawtext_less_than_sign = .{
                            .data_start = start,
                            .tag_start = self.idx - 1,
                            .name_start = 0, // not known yet
                        },
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Emit a U+FFFD REPLACEMENT CHARACTER character token.
                    0 => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_null_character,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // Anything else
                    // Emit the current input character as a character token.
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-state
            .script_data => |start| {
                if (!self.consume(src)) {
                    // EOF
                    // Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .text = .{
                                .start = start,
                                .end = self.idx,
                            },
                        },
                    };
                }
                switch (self.current) {
                    // U+003C LESS-THAN SIGN (<)
                    // Switch to the script data less-than sign state.
                    '<' => self.state = .{
                        .script_data_less_than_sign = .{
                            .data_start = start,
                            .tag_start = self.idx - 1,
                        },
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Emit a U+FFFD REPLACEMENT CHARACTER character token.
                    0 => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_null_character,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // Anything else
                    // Emit the current input character as a character token.
                    else => {
                        // Since we don't emit single chars,
                        // we will instead emit a text token
                        // when appropriate.
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#plaintext-state
            .plaintext => |start| {
                if (!self.consume(src)) {
                    // EOF
                    // Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .deprecated_and_unsupported,
                                .span = .{ .start = start, .end = self.idx },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Emit a U+FFFD REPLACEMENT CHARACTER character token.
                    0 => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_null_character,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // Anything else
                    // Emit the current input character as a character token.
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#tag-open-state
            .tag_open => |lbracket| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-before-tag-name parse error. Emit a U+003C LESS-THAN SIGN character token and an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_before_tag_name,
                                .span = .{
                                    .start = lbracket,
                                    .end = self.idx,
                                },
                            },
                        },
                        // .deferred = .{
                        //     .char = .{
                        //         .start = tag_open_start,
                        //         .end = self.idx,
                        //     },
                        // },
                    };
                }
                switch (self.current) {
                    // U+0021 EXCLAMATION MARK (!)
                    // Switch to the markup declaration open state.
                    '!' => self.state = .{
                        .markup_declaration_open = lbracket,
                    },

                    // U+002F SOLIDUS (/)
                    // Switch to the end tag open state.
                    '/' => self.state = .{
                        .end_tag_open = lbracket,
                    },
                    // U+003F QUESTION MARK (?)
                    // This is an unexpected-question-mark-instead-of-tag-name parse error. Create a comment token whose data is the empty string. Reconsume in the bogus comment state.
                    '?' => {
                        self.idx -= 1;
                        self.state = .{ .bogus_comment = self.idx };
                    },
                    else => |c| if (isAsciiAlpha(c)) {
                        // ASCII alpha
                        // Create a new start tag token, set its tag name to the empty string. Reconsume in the tag name state.
                        self.state = .{
                            .tag_name = .{
                                .kind = .start,
                                .name = .{
                                    .start = self.idx - 1,
                                    .end = 0,
                                },
                                .span = .{
                                    .start = lbracket,
                                    .end = 0,
                                },
                            },
                        };
                    } else {
                        // Anything else
                        // This is an invalid-first-character-of-tag-name parse error. Emit a U+003C LESS-THAN SIGN character token. Reconsume in the data state.
                        self.state = .data;
                        self.idx -= 1;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .invalid_first_character_of_tag_name,
                                    .span = .{
                                        .start = self.idx,
                                        .end = self.idx + 1,
                                    },
                                },
                            },
                            // .deferred = .{
                            //     .char = .{
                            //         .start = tag_open_start,
                            //         .end = tag_open_start + 1,
                            //     },
                            // },
                        };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#end-tag-open-state
            .end_tag_open => |lbracket| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-before-tag-name parse error. Emit a U+003C LESS-THAN SIGN character token, a U+002F SOLIDUS character token and an end-of-file token.
                    self.state = .data;
                    self.idx -= 1;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_before_tag_name,
                                .span = .{
                                    .start = self.idx,
                                    .end = self.idx + 1,
                                },
                            },
                        },

                        // .deferred = .{
                        //     .char = .{
                        //         .start = tag_open_start,
                        //         .end = tag_open_start + 1,
                        //     },
                        // },
                    };
                }
                switch (self.current) {
                    // U+003E GREATER-THAN SIGN (>)
                    // This is a missing-end-tag-name parse error. Switch to the data state.
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_end_tag_name,
                                    .span = .{
                                        .start = lbracket,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    else => |c| if (isAsciiAlpha(c)) {
                        // ASCII alpha
                        // Create a new end tag token, set its tag name to the empty string. Reconsume in the tag name state.
                        self.state = .{
                            .tag_name = .{
                                .kind = .end,

                                .name = .{
                                    .start = self.idx - 1,
                                    .end = 0,
                                },
                                .span = .{
                                    .start = lbracket,
                                    .end = 0,
                                },
                            },
                        };
                    } else {
                        // Anything else
                        // This is an invalid-first-character-of-tag-name parse error. Create a comment token whose data is the empty string. Reconsume in the bogus comment state.
                        self.state = .{ .bogus_comment = self.idx - 1 };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .invalid_first_character_of_tag_name,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#tag-name-state
            .tag_name => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-tag parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_tag,
                                .span = .{
                                    .start = state.span.start,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Switch to the before attribute name state.
                    '\t', '\n', form_feed, ' ' => {
                        var tag = state;
                        tag.name.end = self.idx - 1;
                        self.state = .{ .before_attribute_name = tag };

                        if (self.return_attrs) {
                            return .{ .token = .{ .tag_name = tag.name } };
                        }
                    },
                    // U+002F SOLIDUS (/)
                    // Switch to the self-closing start tag state.
                    '/' => {
                        var tag = state;
                        tag.name.end = self.idx - 1;
                        self.state = .{
                            .self_closing_start_tag = tag,
                        };
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current tag token.
                    '>' => {
                        var tag = state;
                        tag.name.end = self.idx - 1;
                        tag.span.end = self.idx;

                        self.state = .data;
                        if (self.return_attrs) {
                            return .{ .token = .{ .tag_name = tag.name } };
                        } else {
                            return .{ .token = .{ .tag = tag } };
                        }
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current tag token's tag name.
                    0 => return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .unexpected_null_character,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    },
                    // ASCII upper alpha
                    // Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the current tag token's tag name.
                    // Anything else
                    // Append the current input character to the current tag token's tag name.
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rcdata-less-than-sign-state
            .rcdata_less_than_sign => |state| {
                if (!self.consume(src)) {
                    self.idx -= 1;
                    self.state = .{ .rcdata = state.data_start };
                } else switch (self.current) {
                    // U+002F SOLIDUS (/)
                    // Set the temporary buffer to the empty string. Switch to the RCDATA end tag open state.
                    '/' => self.state = .{ .rcdata_end_tag_open = state },
                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token. Reconsume in the RCDATA state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .rcdata = state.data_start };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#rcdata-end-tag-open-state
            .rcdata_end_tag_open => |state| {
                if (!self.consume(src)) {
                    self.idx -= 1;
                    self.state = .{ .rcdata = state.data_start };
                } else switch (self.current) {
                    // ASCII alpha
                    // Create a new end tag token, set its tag name to the empty string. Reconsume in the RCDATA end tag name state.
                    'a'...'z', 'A'...'Z' => {
                        var new = state;
                        new.name_start = self.idx - 1;
                        self.state = .{ .rcdata_end_tag_name = new };
                    },
                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token and a U+002F SOLIDUS character token. Reconsume in the RCDATA state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .rcdata = state.data_start };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#rcdata-end-tag-name-state
            .rcdata_end_tag_name => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .rcdata = state.data_start };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // If the current end tag token is an appropriate end tag token, then switch to the before attribute name state. Otherwise, treat it as per the "anything else" entry below.
                    '\t', '\n', form_feed, ' ' => {
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = 0, // not yet known
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_appropriate = std.ascii.eqlIgnoreCase(
                            self.last_start_tag_name,
                            tag.name.slice(src),
                        );
                        if (is_appropriate) {
                            self.state = .{ .before_attribute_name = tag };
                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{ .token = .{ .text = txt } };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .rcdata = state.data_start };
                        }
                    },
                    // U+002F SOLIDUS (/)
                    // If the current end tag token is an appropriate end tag token, then switch to the self-closing start tag state. Otherwise, treat it as per the "anything else" entry below.
                    '/' => {
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = 0, // not yet known
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_appropriate = std.ascii.eqlIgnoreCase(
                            self.last_start_tag_name,
                            tag.name.slice(src),
                        );
                        if (is_appropriate) {
                            self.state = .{ .before_attribute_name = tag };

                            const err: Token = .{
                                .parse_error = .{
                                    .tag = .end_tag_with_trailing_solidus,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            };

                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{
                                    .token = .{ .text = txt },
                                    .deferred = err,
                                };
                            } else {
                                return .{ .token = err };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .rcdata = state.data_start };
                        }
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // If the current end tag token is an appropriate end tag token, then switch to the data state and emit the current tag token. Otherwise, treat it as per the "anything else" entry below.
                    '>' => {
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = self.idx,
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_appropriate = std.ascii.eqlIgnoreCase(
                            self.last_start_tag_name,
                            tag.name.slice(src),
                        );
                        if (is_appropriate) {
                            self.state = .data;
                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{
                                    .token = .{ .text = txt },
                                    .deferred = .{ .tag = tag },
                                };
                            } else {
                                return .{ .token = .{ .tag = tag } };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .rcdata = state.data_start };
                        }
                    },

                    // ASCII upper alpha
                    // Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the current tag token's tag name. Append the current input character to the temporary buffer.
                    // ASCII lower alpha
                    // Append the current input character to the current tag token's tag name. Append the current input character to the temporary buffer.
                    'a'...'z', 'A'...'Z' => {},

                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token, a U+002F SOLIDUS character token, and a character token for each of the characters in the temporary buffer (in the order they were added to the buffer). Reconsume in the RCDATA state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .rcdata = state.data_start };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rawtext-less-than-sign-state
            .rawtext_less_than_sign => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .rawtext = state.data_start };
                } else switch (self.current) {
                    // U+002F SOLIDUS (/)
                    // Set the temporary buffer to the empty string. Switch to the RAWTEXT end tag open state.
                    '/' => self.state = .{ .rawtext_end_tag_open = state },

                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token. Reconsume in the RAWTEXT state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .rawtext = state.data_start };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rawtext-end-tag-open-state
            .rawtext_end_tag_open => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .rawtext = state.data_start };
                } else switch (self.current) {
                    // ASCII alpha
                    // Create a new end tag token, set its tag name to the empty string. Reconsume in the RAWTEXT end tag name state.
                    'a'...'z', 'A'...'Z' => {
                        self.idx -= 1;
                        var new = state;
                        new.name_start = self.idx;
                        self.state = .{ .rawtext_end_tag_name = new };
                    },
                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token and a U+002F SOLIDUS character token. Reconsume in the RAWTEXT state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .rawtext = state.data_start };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rawtext-end-tag-name-state
            .rawtext_end_tag_name => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .rawtext = state.data_start };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // If the current end tag token is an appropriate end tag token, then switch to the before attribute name state. Otherwise, treat it as per the "anything else" entry below.
                    '\t', '\n', form_feed, ' ' => {
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = 0, // not yet known
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_appropriate = std.ascii.eqlIgnoreCase(
                            self.last_start_tag_name,
                            tag.name.slice(src),
                        );
                        if (is_appropriate) {
                            self.state = .{ .before_attribute_name = tag };
                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{ .token = .{ .text = txt } };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .rawtext = state.data_start };
                        }
                    },

                    // U+002F SOLIDUS (/)
                    // If the current end tag token is an appropriate end tag token, then switch to the self-closing start tag state. Otherwise, treat it as per the "anything else" entry below.
                    '/' => {
                        // What? A self-closing end tag?
                        // The spec is impicitly relying on how their
                        // state-changing side effects are supposed to combine.
                        // It's unclear if we are meant to trust the leading or
                        // the trailing slash.
                        // Let's just report an error, but for convenience,
                        // we're also going to change state to before_attribute_name
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = 0, // not yet known
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_appropriate = std.ascii.eqlIgnoreCase(
                            self.last_start_tag_name,
                            tag.name.slice(src),
                        );
                        if (is_appropriate) {
                            self.state = .{ .self_closing_start_tag = tag };

                            const err: Token = .{
                                .parse_error = .{
                                    .tag = .end_tag_with_trailing_solidus,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            };

                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{
                                    .token = .{ .text = txt },
                                    .deferred = err,
                                };
                            } else {
                                return .{ .token = err };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .rawtext = state.data_start };
                        }
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // If the current end tag token is an appropriate end tag token, then switch to the data state and emit the current tag token. Otherwise, treat it as per the "anything else" entry below.
                    '>' => {
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = self.idx,
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_appropriate = std.ascii.eqlIgnoreCase(
                            self.last_start_tag_name,
                            tag.name.slice(src),
                        );
                        if (is_appropriate) {
                            self.state = .data;
                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{
                                    .token = .{ .text = txt },
                                    .deferred = .{ .tag = tag },
                                };
                            } else {
                                return .{ .token = .{ .tag = tag } };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .rawtext = state.data_start };
                        }
                    },
                    // ASCII upper alpha
                    // Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the current tag token's tag name. Append the current input character to the temporary buffer.
                    // ASCII lower alpha
                    // Append the current input character to the current tag token's tag name. Append the current input character to the temporary buffer.
                    'a'...'z', 'A'...'Z' => {},

                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token, a U+002F SOLIDUS character token, and a character token for each of the characters in the temporary buffer (in the order they were added to the buffer). Reconsume in the RAWTEXT state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .rawtext = state.data_start };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-less-than-sign-state
            .script_data_less_than_sign => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data = state.data_start };
                } else switch (self.current) {
                    // U+002F SOLIDUS (/)
                    // Set the temporary buffer to the empty string. Switch to the script data end tag open state.
                    '/' => self.state = .{ .script_data_end_tag_open = state },
                    // U+0021 EXCLAMATION MARK (!)
                    // Switch to the script data escape start state. Emit a U+003C LESS-THAN SIGN character token and a U+0021 EXCLAMATION MARK character token.
                    '!' => self.state = .{ .script_data_escape_start = state },
                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token. Reconsume in the script data state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data = state.data_start };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-end-tag-open-state
            .script_data_end_tag_open => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data = state.data_start };
                } else switch (self.current) {
                    // ASCII alpha
                    // Create a new end tag token, set its tag name to the empty string. Reconsume in the script data end tag name state.
                    'a'...'z', 'A'...'Z' => {
                        self.idx -= 1;
                        var new = state;
                        new.name_start = self.idx;

                        self.state = .{ .script_data_end_tag_name = new };
                    },
                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token and a U+002F SOLIDUS character token. Reconsume in the script data state
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data = state.data_start };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-end-tag-name-state
            .script_data_end_tag_name => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data = state.data_start };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // If the current end tag token is an appropriate end tag token, then switch to the before attribute name state. Otherwise, treat it as per the "anything else" entry below.
                    '\t', '\n', form_feed, ' ' => {
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = 0, // not yet known
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_script = std.ascii.eqlIgnoreCase(
                            "script",
                            tag.name.slice(src),
                        );
                        if (is_script) {
                            self.state = .{ .before_attribute_name = tag };
                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{ .token = .{ .text = txt } };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .script_data = state.data_start };
                        }
                    },
                    // U+002F SOLIDUS (/)
                    // If the current end tag token is an appropriate end tag token, then switch to the self-closing start tag state. Otherwise, treat it as per the "anything else" entry below.
                    '/' => {
                        // What? A self-closing end tag?
                        // The spec is impicitly relying on how their
                        // state-changing side effects are supposed to combine.
                        // It's unclear if we are meant to trust the leading or
                        // the trailing slash.
                        // Let's just report an error, but for convenience,
                        // we're also going to change state to before_attribute_name
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = 0, // not yet known
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_script = std.ascii.eqlIgnoreCase(
                            "script",
                            tag.name.slice(src),
                        );
                        if (is_script) {
                            self.state = .{ .before_attribute_name = tag };

                            const err: Token = .{
                                .parse_error = .{
                                    .tag = .end_tag_with_trailing_solidus,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            };

                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{
                                    .token = .{ .text = txt },
                                    .deferred = err,
                                };
                            } else {
                                return .{ .token = err };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .script_data = state.data_start };
                        }
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // If the current end tag token is an appropriate end tag token, then switch to the data state and emit the current tag token. Otherwise, treat it as per the "anything else" entry below.
                    // NOTE: An appropriate end tag token is an end tag token whose tag name matches the tag name of the last start tag to have been emitted from this tokenizer, if any. If no start tag has been emitted from this tokenizer, then no end tag token is appropriate.
                    '>' => {
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = self.idx,
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_script = std.ascii.eqlIgnoreCase(
                            "script",
                            tag.name.slice(src),
                        );
                        if (is_script) {
                            self.state = .data;
                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{
                                    .token = .{ .text = txt },
                                    .deferred = .{ .tag = tag },
                                };
                            } else {
                                return .{ .token = .{ .tag = tag } };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .script_data = state.data_start };
                        }
                    },
                    // ASCII upper alpha
                    // Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the current tag token's tag name. Append the current input character to the temporary buffer.
                    // ASCII lower alpha
                    // Append the current input character to the current tag token's tag name. Append the current input character to the temporary buffer.
                    'a'...'z', 'A'...'Z' => {},
                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token, a U+002F SOLIDUS character token, and a character token for each of the characters in the temporary buffer (in the order they were added to the buffer). Reconsume in the script data state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data = state.data_start };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escape-start-state
            .script_data_escape_start => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data = state.data_start };
                } else switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the script data escape start dash state. Emit a U+002D HYPHEN-MINUS character token.
                    '-' => self.state = .{
                        .script_data_escape_start_dash = state,
                    },
                    // Anything else
                    // Reconsume in the script data state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data = state.data_start };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escape-start-dash-state
            .script_data_escape_start_dash => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data = state.data_start };
                } else switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the script data escaped dash dash state. Emit a U+002D HYPHEN-MINUS character token.
                    '-' => self.state = .{
                        .script_data_escaped_dash_dash = state,
                    },
                    // Anything else
                    // Reconsume in the script data state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data = state.data_start };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escaped-state
            .script_data_escaped => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-script-html-comment-like-text parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_script_html_comment_like_text,
                                .span = .{
                                    .start = state.tag_start,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the script data escaped dash state. Emit a U+002D HYPHEN-MINUS character token.
                    '-' => self.state = .{
                        .script_data_escaped_dash = state,
                    },
                    // U+003C LESS-THAN SIGN (<)
                    // Switch to the script data escaped less-than sign state.
                    '<' => self.state = .{
                        .script_data_escaped_less_than_sign = state,
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Emit a U+FFFD REPLACEMENT CHARACTER character token.
                    0 => {
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_null_character,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // Anything else
                    // Emit the current input character as a character token.
                    else => {},
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escaped-dash-state
            .script_data_escaped_dash => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-script-html-comment-like-text parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_script_html_comment_like_text,
                                .span = .{
                                    .start = state.tag_start,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the script data escaped dash dash state. Emit a U+002D HYPHEN-MINUS character token.
                    '-' => self.state = .{
                        .script_data_escaped_dash_dash = state,
                    },
                    // U+003C LESS-THAN SIGN (<)
                    // Switch to the script data escaped less-than sign state.
                    '<' => self.state = .{
                        .script_data_escaped_less_than_sign = state,
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Switch to the script data escaped state. Emit a U+FFFD REPLACEMENT CHARACTER character token.
                    0 => {
                        self.state = .{ .script_data_escaped = state };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_null_character,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // Anything else
                    // Switch to the script data escaped state. Emit the current input character as a character token.
                    else => self.state = .{ .script_data_escaped = state },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escaped-dash-dash-state
            .script_data_escaped_dash_dash => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-script-html-comment-like-text parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_script_html_comment_like_text,
                                .span = .{
                                    .start = state.tag_start,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Emit a U+002D HYPHEN-MINUS character token.
                    '-' => {},
                    // U+003C LESS-THAN SIGN (<)
                    // Switch to the script data escaped less-than sign state.
                    '<' => self.state = .{
                        .script_data_escaped_less_than_sign = state,
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the script data state. Emit a U+003E GREATER-THAN SIGN character token.
                    '>' => self.state = .{ .script_data = state.data_start },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Switch to the script data escaped state. Emit a U+FFFD REPLACEMENT CHARACTER character token.
                    0 => {
                        self.state = .{ .script_data_escaped = state };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_null_character,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // Anything else
                    // Switch to the script data escaped state. Emit the current input character as a character token.
                    else => self.state = .{ .script_data = state.data_start },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escaped-less-than-sign-state
            .script_data_escaped_less_than_sign => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data_escaped = state };
                } else switch (self.current) {
                    // U+002F SOLIDUS (/)
                    // Set the temporary buffer to the empty string. Switch to the script data escaped end tag open state.
                    '/' => self.state = .{
                        .script_data_escaped_end_tag_open = state,
                    },
                    // ASCII alpha
                    // Set the temporary buffer to the empty string. Emit a U+003C LESS-THAN SIGN character token. Reconsume in the script data double escape start state.
                    'a'...'z', 'A'...'Z' => {
                        self.idx -= 1;
                        @panic("TODO");
                    },
                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token. Reconsume in the script data escaped state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data_escaped = state };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escaped-end-tag-open-state
            .script_data_escaped_end_tag_open => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data_escaped = state };
                } else switch (self.current) {
                    // ASCII alpha
                    // Create a new end tag token, set its tag name to the empty string. Reconsume in the script data escaped end tag name state.
                    'a'...'z', 'A'...'Z' => {
                        self.idx -= 1;
                        @panic("TODO");
                    },
                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token and a U+002F SOLIDUS character token. Reconsume in the script data escaped state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data_escaped = state };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escaped-end-tag-name-state
            .script_data_escaped_end_tag_name => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data_escaped = state };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // If the current end tag token is an appropriate end tag token, then switch to the before attribute name state. Otherwise, treat it as per the "anything else" entry below.
                    '\t', '\n', form_feed, ' ' => {
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = 0, // not yet known
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_script = std.ascii.eqlIgnoreCase(
                            "script",
                            tag.name.slice(src),
                        );
                        if (is_script) {
                            self.state = .{ .before_attribute_name = tag };
                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{ .token = .{ .text = txt } };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .script_data_escaped = state };
                        }
                    },
                    // U+002F SOLIDUS (/)
                    // If the current end tag token is an appropriate end tag token, then switch to the self-closing start tag state. Otherwise, treat it as per the "anything else" entry below.
                    '/' => {
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = 0, // not yet known
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_script = std.ascii.eqlIgnoreCase(
                            "script",
                            tag.name.slice(src),
                        );
                        if (is_script) {
                            self.state = .{ .before_attribute_name = tag };

                            const err: Token = .{
                                .parse_error = .{
                                    .tag = .end_tag_with_trailing_solidus,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            };

                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{
                                    .token = .{ .text = txt },
                                    .deferred = err,
                                };
                            } else {
                                return .{ .token = err };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{
                                .script_data_escaped = state,
                            };
                        }
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // If the current end tag token is an appropriate end tag token, then switch to the data state and emit the current tag token. Otherwise, treat it as per the "anything else" entry below.
                    '>' => {
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = self.idx,
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_script = std.ascii.eqlIgnoreCase(
                            "script",
                            tag.name.slice(src),
                        );
                        if (is_script) {
                            self.state = .data;
                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{
                                    .token = .{ .text = txt },
                                    .deferred = .{ .tag = tag },
                                };
                            } else {
                                return .{ .token = .{ .tag = tag } };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .script_data = state.data_start };
                        }
                    },

                    // ASCII upper alpha
                    // Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the current tag token's tag name. Append the current input character to the temporary buffer.
                    // ASCII lower alpha
                    // Append the current input character to the current tag token's tag name. Append the current input character to the temporary buffer.
                    'a'...'z', 'A'...'Z' => {},

                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token, a U+002F SOLIDUS character token, and a character token for each of the characters in the temporary buffer (in the order they were added to the buffer). Reconsume in the script data escaped state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data_escaped = state };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-double-escape-start-state
            .script_data_double_escape_start => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data_escaped = state };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // U+002F SOLIDUS (/)
                    // U+003E GREATER-THAN SIGN (>)
                    // If the temporary buffer is the string "script", then switch to the script data double escaped state. Otherwise, switch to the script data escaped state. Emit the current input character as a character token.
                    '\t', '\n', form_feed, ' ', '/', '>' => {
                        const name: Span = .{
                            .start = state.name_start,
                            .end = self.idx - 1,
                        };
                        const is_script = std.ascii.eqlIgnoreCase(
                            "script",
                            name.slice(src),
                        );
                        if (is_script) {
                            self.state = .{
                                .script_data_double_escaped = state,
                            };
                        } else {
                            self.state = .{
                                .script_data_escaped = state,
                            };
                        }
                    },
                    // ASCII upper alpha
                    // Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the temporary buffer. Emit the current input character as a character token.
                    // ASCII lower alpha
                    // Append the current input character to the temporary buffer. Emit the current input character as a character token.
                    'a'...'z', 'A'...'Z' => {},

                    // Anything else
                    // Reconsume in the script data escaped state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data_escaped = state };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-double-escaped-state
            .script_data_double_escaped => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-script-html-comment-like-text parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_script_html_comment_like_text,
                                .span = .{
                                    .start = state.tag_start,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the script data double escaped dash state. Emit a U+002D HYPHEN-MINUS character token.
                    '-' => self.state = .{
                        .script_data_double_escaped_dash = state,
                    },
                    // U+003C LESS-THAN SIGN (<)
                    // Switch to the script data double escaped less-than sign state. Emit a U+003C LESS-THAN SIGN character token.
                    '<' => self.state = .{
                        .script_data_double_escaped_less_than_sign = state,
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Emit a U+FFFD REPLACEMENT CHARACTER character token.
                    0 => {
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_null_character,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // Anything else
                    // Emit the current input character as a character token.
                    else => {},
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-double-escaped-dash-state
            .script_data_double_escaped_dash => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-script-html-comment-like-text parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_script_html_comment_like_text,
                                .span = .{
                                    .start = state.tag_start,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the script data double escaped dash dash state. Emit a U+002D HYPHEN-MINUS character token.
                    '-' => self.state = .{
                        .script_data_double_escaped_dash_dash = state,
                    },
                    // U+003C LESS-THAN SIGN (<)
                    // Switch to the script data double escaped less-than sign state. Emit a U+003C LESS-THAN SIGN character token.
                    '<' => self.state = .{
                        .script_data_double_escaped_less_than_sign = state,
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Switch to the script data double escaped state. Emit a U+FFFD REPLACEMENT CHARACTER character token.
                    0 => {
                        self.state = .{ .script_data_double_escaped = state };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_null_character,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // Anything else
                    // Switch to the script data double escaped state. Emit the current input character as a character token.
                    else => self.state = .{
                        .script_data_double_escaped = state,
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-double-escaped-dash-dash-state
            .script_data_double_escaped_dash_dash => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-script-html-comment-like-text parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_script_html_comment_like_text,
                                .span = .{
                                    .start = state.tag_start,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Emit a U+002D HYPHEN-MINUS character token.
                    '-' => {},
                    // U+003C LESS-THAN SIGN (<)
                    // Switch to the script data double escaped less-than sign state. Emit a U+003C LESS-THAN SIGN character token.
                    '<' => self.state = .{
                        .script_data_double_escaped_less_than_sign = state,
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the script data state. Emit a U+003E GREATER-THAN SIGN character token.
                    '>' => self.state = .{ .script_data = state.data_start },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Switch to the script data double escaped state. Emit a U+FFFD REPLACEMENT CHARACTER character token.
                    0 => {
                        self.state = .{ .script_data_double_escaped = state };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_null_character,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // Anything else
                    // Switch to the script data double escaped state. Emit the current input character as a character token.
                    else => self.state = .{
                        .script_data_double_escaped = state,
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-double-escaped-less-than-sign-state
            .script_data_double_escaped_less_than_sign => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data_double_escaped = state };
                } else switch (self.current) {
                    // U+002F SOLIDUS (/)
                    // Set the temporary buffer to the empty string. Switch to the script data double escape end state. Emit a U+002F SOLIDUS character token.
                    '/' => self.state = .{
                        .script_data_double_escape_end = state,
                    },
                    // Anything else
                    // Reconsume in the script data double escaped state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data_double_escaped = state };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-double-escape-end-state
            .script_data_double_escape_end => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data_double_escaped = state };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // U+002F SOLIDUS (/)
                    // U+003E GREATER-THAN SIGN (>)
                    // If the temporary buffer is the string "script", then switch to the script data escaped state. Otherwise, switch to the script data double escaped state. Emit the current input character as a character token.
                    '\t', '\n', form_feed, ' ', '/', '>' => {
                        const name: Span = .{
                            .start = state.name_start,
                            .end = self.idx - 1,
                        };
                        const is_script = std.ascii.eqlIgnoreCase(
                            "script",
                            name.slice(src),
                        );
                        if (is_script) {
                            self.state = .{
                                .script_data_escaped = state,
                            };
                        } else {
                            self.state = .{
                                .script_data_double_escaped = state,
                            };
                        }
                    },

                    // ASCII upper alpha
                    // Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the temporary buffer. Emit the current input character as a character token.
                    // ASCII lower alpha
                    // Append the current input character to the temporary buffer. Emit the current input character as a character token.
                    'a'...'z', 'A'...'Z' => {},

                    // Anything else
                    // Reconsume in the script data double escaped state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data_double_escaped = state };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#before-attribute-name-state
            .before_attribute_name => |state| {
                // See EOF case from below
                if (!self.consume(src)) {
                    self.state = .data;
                    var tag = state;
                    tag.span.end = self.idx;
                    return .{ .token = .{ .tag = tag } };
                    // self.idx -= 1;
                    // self.state = .{
                    //     .after_attribute_name = .{
                    //         .tag = state,
                    //         .name_raw = .{
                    //             .start = self.idx,
                    //             .end = self.idx + 1,
                    //         },
                    //     },
                    // };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Ignore the character.
                    '\t', '\n', form_feed, ' ' => {},

                    // U+002F SOLIDUS (/)
                    // U+003E GREATER-THAN SIGN (>)
                    // EOF
                    // Reconsume in the after attribute name state.
                    //
                    // NOTE: handled differently
                    '/', '>' => {
                        self.state = .data;
                        var tag = state;
                        tag.span.end = self.idx;
                        return .{ .token = .{ .tag = tag } };
                        // self.idx -= 1;
                        // self.state = .{
                        //     .after_attribute_name = .{
                        //         .tag = state,
                        //         .name_raw = .{
                        //             .start = self.idx - 2,
                        //             .end = self.idx,
                        //         },
                        //     },
                        // };
                    },

                    //U+003D EQUALS SIGN (=)
                    //This is an unexpected-equals-sign-before-attribute-name parse error. Start a new attribute in the current tag token. Set that attribute's name to the current input character, and its value to the empty string. Switch to the attribute name state.
                    '=' => {
                        self.state = .{
                            .attribute_name = .{
                                .tag = state,
                                .name_start = self.idx - 1,
                            },
                        };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_equals_sign_before_attribute_name,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },

                    // Anything else
                    // Start a new attribute in the current tag token. Set that attribute name and value to the empty string. Reconsume in the attribute name state.
                    else => self.state = .{
                        .attribute_name = .{
                            .tag = state,
                            .name_start = self.idx - 1,
                        },
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#attribute-name-state
            .attribute_name => |state| {
                if (!self.consume(src)) {
                    self.state = .{
                        .after_attribute_name = .{
                            .tag = state.tag,
                            .name_raw = .{
                                .start = state.name_start,
                                .end = self.idx,
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // U+002F SOLIDUS (/)
                    // U+003E GREATER-THAN SIGN (>)
                    // EOF
                    // Reconsume in the after attribute name state.
                    '\t', '\n', form_feed, ' ', '/', '>' => {
                        self.idx -= 1;
                        self.state = .{
                            .after_attribute_name = .{
                                .tag = state.tag,
                                .name_raw = .{
                                    .start = state.name_start,
                                    .end = self.idx,
                                },
                            },
                        };
                    },

                    // U+003D EQUALS SIGN (=)
                    // Switch to the before attribute value state.
                    '=' => self.state = .{
                        .before_attribute_value = .{
                            .tag = state.tag,
                            .equal_sign = self.idx - 1,
                            .name_raw = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        },
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current attribute's name.
                    0 => return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .unexpected_null_character,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    },
                    // U+0022 QUOTATION MARK (")
                    // U+0027 APOSTROPHE (')
                    // U+003C LESS-THAN SIGN (<)
                    // This is an unexpected-character-in-attribute-name parse error. Treat it as per the "anything else" entry below.
                    '"', '\'', '<' => return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .unexpected_character_in_attribute_name,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    },
                    // ASCII upper alpha
                    // Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the current attribute's name.
                    // Anything else
                    // Append the current input character to the current attribute's name.
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-attribute-name-state
            .after_attribute_name => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-tag parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_tag,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Ignore the character.
                    '\t', '\n', form_feed, ' ' => {},
                    // U+002F SOLIDUS (/)
                    // Switch to the self-closing start tag state.
                    '/' => {
                        self.state = .{
                            .self_closing_start_tag = state.tag,
                        };

                        if (self.return_attrs) {
                            return .{
                                .token = .{
                                    .attr = .{
                                        .name_raw = state.name_raw,
                                        .value_raw = null,
                                    },
                                },
                            };
                        }
                    },
                    // U+003D EQUALS SIGN (=)
                    // Switch to the before attribute value state.
                    '=' => self.state = .{
                        .before_attribute_value = .{
                            .tag = state.tag,
                            .name_raw = state.name_raw,
                            .equal_sign = self.idx - 1,
                        },
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current tag token.
                    '>' => {
                        var tag = state.tag;
                        tag.span.end = self.idx + 1;

                        self.state = .data;
                        if (self.return_attrs) {
                            return .{
                                .token = .{
                                    .attr = .{
                                        .name_raw = state.name_raw,
                                        .value_raw = null,
                                    },
                                },
                            };
                        }

                        return .{ .token = .{ .tag = tag } };
                    },
                    // Anything else
                    // Start a new attribute in the current tag token. Set that attribute name and value to the empty string. Reconsume in the attribute name state.
                    else => {
                        self.idx -= 1;
                        self.state = .{
                            .attribute_name = .{
                                .tag = state.tag,
                                .name_start = self.idx,
                            },
                        };

                        if (self.return_attrs) {
                            return .{
                                .token = .{
                                    .attr = .{
                                        .name_raw = state.name_raw,
                                        .value_raw = null,
                                    },
                                },
                            };
                        }
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#before-attribute-value-state
            .before_attribute_value => |state| {
                if (!self.consume(src)) {
                    self.state = .{
                        .attribute_value_unquoted = .{
                            .tag = state.tag,
                            .name_raw = state.name_raw,
                            .value_start = self.idx,
                        },
                    };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Ignore the character.
                    '\t', '\n', form_feed, ' ' => {},
                    // U+0022 QUOTATION MARK (")
                    // Switch to the attribute value (double-quoted) state.
                    '"' => self.state = .{
                        .attribute_value = .{
                            .tag = state.tag,
                            .name_raw = state.name_raw,
                            .quote = .double,
                            .value_start = self.idx,
                        },
                    },
                    // U+0027 APOSTROPHE (')
                    // Switch to the attribute value (single-quoted) state.
                    '\'' => self.state = .{
                        .attribute_value = .{
                            .tag = state.tag,
                            .name_raw = state.name_raw,
                            .quote = .single,
                            .value_start = self.idx,
                        },
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // This is a missing-attribute-value parse error. Switch to the data state. Emit the current tag token.
                    '>' => {
                        var tag = state.tag;
                        tag.span.end = self.idx;

                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_attribute_value,
                                    .span = .{
                                        .start = state.equal_sign,
                                        .end = state.equal_sign + 1,
                                    },
                                },
                            },
                            .deferred = .{ .tag = tag },
                        };
                    },
                    // Anything else
                    // Reconsume in the attribute value (unquoted) state.
                    //
                    // (EOF handled above)
                    else => {
                        self.idx -= 1;
                        self.state = .{
                            .attribute_value_unquoted = .{
                                .tag = state.tag,
                                .name_raw = state.name_raw,
                                .value_start = self.idx,
                            },
                        };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#attribute-value-(double-quoted)-state
            // https://html.spec.whatwg.org/multipage/parsing.html#attribute-value-(single-quoted)-state
            .attribute_value => |state| {
                if (!self.consume(src)) {
                    self.state = .eof;

                    // EOF
                    // This is an eof-in-tag parse error. Emit an end-of-file token.
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_attribute_value,
                                .span = .{
                                    .start = state.value_start,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+0022 QUOTATION MARK (")
                    // Switch to the after attribute value (quoted) state.
                    '"' => switch (state.quote) {
                        .single => {
                            // Just a normal char in this case
                        },
                        .double => {
                            self.state = .{
                                .after_attribute_value = .{
                                    .tag = state.tag,
                                    .attr_value_end = self.idx,
                                },
                            };
                            if (self.return_attrs) {
                                return .{
                                    .token = .{
                                        .attr = .{
                                            .name_raw = state.name_raw,
                                            .value_raw = .{
                                                .quote = .double,
                                                .span = .{
                                                    .start = state.value_start,
                                                    .end = self.idx - 1,
                                                },
                                            },
                                        },
                                    },
                                };
                            }
                        },
                    },

                    // U+0027 APOSTROPHE (')
                    // Switch to the after attribute value (quoted) state.
                    '\'' => switch (state.quote) {
                        .double => {
                            // Just a normal char in this case
                        },
                        .single => {
                            self.state = .{
                                .after_attribute_value = .{
                                    .tag = state.tag,
                                    .attr_value_end = self.idx,
                                },
                            };
                            if (self.return_attrs) {
                                return .{
                                    .token = .{
                                        .attr = .{
                                            .name_raw = state.name_raw,
                                            .value_raw = .{
                                                .quote = .single,
                                                .span = .{
                                                    .start = state.value_start,
                                                    .end = self.idx - 1,
                                                },
                                            },
                                        },
                                    },
                                };
                            }
                        },
                    },
                    // U+0026 AMPERSAND (&)
                    // Set the return state to the attribute value (double-quoted) state. Switch to the character reference state.
                    //
                    // (handled downstream)
                    // '&' => {},

                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current attribute's value.
                    0 => return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .unexpected_null_character,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    },
                    // Anything else
                    // Append the current input character to the current attribute's value.
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#attribute-value-(unquoted)-state
            .attribute_value_unquoted => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-tag parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_tag,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Switch to the before attribute name state.
                    '\t', '\n', form_feed, ' ' => {
                        if (self.return_attrs) {
                            return .{
                                .token = .{
                                    .attr = .{
                                        .name_raw = state.name_raw,
                                        .value_raw = .{
                                            .quote = .single,
                                            .span = .{
                                                .start = state.value_start,
                                                .end = self.idx - 1,
                                            },
                                        },
                                    },
                                },
                            };
                        }
                        self.state = .{ .before_attribute_name = state.tag };
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current tag token.
                    '>' => {
                        var tag = state.tag;
                        tag.span.end = self.idx;

                        self.state = .data;

                        if (self.return_attrs) {
                            return .{
                                .token = .{
                                    .attr = .{
                                        .name_raw = state.name_raw,
                                        .value_raw = .{
                                            .quote = .single,
                                            .span = .{
                                                .start = state.value_start,
                                                .end = self.idx - 1,
                                            },
                                        },
                                    },
                                },
                            };
                        } else {
                            return .{ .token = .{ .tag = tag } };
                        }
                    },

                    // U+0026 AMPERSAND (&)
                    // Set the return state to the attribute value (unquoted) state. Switch to the character reference state.
                    //
                    // (handled elsewhere)
                    //'&' => {},

                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current attribute's value.
                    0 => return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .unexpected_null_character,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    },
                    // U+0022 QUOTATION MARK (")
                    // U+0027 APOSTROPHE (')
                    // U+003C LESS-THAN SIGN (<)
                    // U+003D EQUALS SIGN (=)
                    // U+0060 GRAVE ACCENT (`)
                    // This is an unexpected-character-in-unquoted-attribute-value parse error. Treat it as per the "anything else" entry below.
                    '"', '\'', '<', '=', '`' => {
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_character_in_unquoted_attribute_value,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // Anything else
                    // Append the current input character to the current attribute's value.
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-attribute-value-(quoted)-state
            .after_attribute_value => |state| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    // EOF
                    // This is an eof-in-tag parse error. Emit an end-of-file token.
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_tag,
                                .span = .{
                                    .start = state.attr_value_end,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Switch to the before attribute name state.
                    '\t', '\n', form_feed, ' ' => self.state = .{
                        .before_attribute_name = state.tag,
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current tag token.
                    '>' => {
                        var tag = state.tag;
                        tag.span.end = self.idx;

                        self.state = .data;
                        return .{ .token = .{ .tag = tag } };
                    },
                    // U+002F SOLIDUS (/)
                    // Switch to the self-closing start tag state.
                    '/' => {
                        self.state = .{
                            .self_closing_start_tag = state.tag,
                        };
                    },
                    // Anything else
                    // This is a missing-whitespace-between-attributes parse error. Reconsume in the before attribute name state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .before_attribute_name = state.tag };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_whitespace_between_attributes,
                                    .span = .{
                                        .start = state.attr_value_end,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#self-closing-start-tag-state
            .self_closing_start_tag => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-tag parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_tag,
                                .span = .{
                                    .start = state.span.start,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+003E GREATER-THAN SIGN (>)
                    // Set the self-closing flag of the current tag token. Switch to the data state. Emit the current tag token.
                    '>' => {
                        self.state = .data;

                        var tag = state;
                        tag.kind = switch (tag.kind) {
                            .start => .start_self,
                            .start_attrs => .start_attrs_self,
                            else => unreachable,
                        };

                        return .{ .token = .{ .tag = tag } };
                    },
                    // Anything else
                    // This is an unexpected-solidus-in-tag parse error. Reconsume in the before attribute name state.
                    else => {
                        self.state = .{ .before_attribute_name = state };
                        self.idx -= 1;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_solidus_in_tag,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#bogus-comment-state
            .bogus_comment => |start| {
                if (!self.consume(src)) {
                    // EOF
                    // Emit the comment. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .comment = .{
                                .start = start,
                                .end = self.idx,
                            },
                        },
                    };
                }
                switch (self.current) {
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error.
                    0 => return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .unexpected_null_character,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current comment token.
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .comment = .{
                                    .start = start,
                                    .end = self.idx,
                                },
                            },
                        };
                    },
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#markup-declaration-open-state
            .markup_declaration_open => |lbracket| {
                if (self.nextCharsAre("--", src)) {
                    // Two U+002D HYPHEN-MINUS characters (-)
                    // Consume those two characters, create a comment token whose data is the empty string, and switch to the comment start state.
                    self.idx += 2;
                    self.state = .{ .comment_start = lbracket };
                } else if (self.nextCharsAreIgnoreCase(DOCTYPE, src)) {
                    // ASCII case-insensitive match for the word "DOCTYPE"
                    // Consume those characters and switch to the DOCTYPE state.
                    self.idx += @intCast(DOCTYPE.len);
                    self.state = .{ .doctype = lbracket };
                } else if (self.nextCharsAre("[CDATA[", src)) {
                    // The string "[CDATA[" (the five uppercase letters "CDATA" with a U+005B LEFT SQUARE BRACKET character before and after)
                    // Consume those characters. If there is an adjusted current node and it is not an element in the HTML namespace, then switch to the CDATA section state. Otherwise, this is a cdata-in-html-content parse error. Create a comment token whose data is the "[CDATA[" string. Switch to the bogus comment state.
                    // NOTE: since we don't implement the AST building step
                    //       according to the HTML spec, we don't report this
                    //       error either since we don't have fully
                    //       spec-compliant knowledge about the "adjusted
                    //       current node".
                    self.idx += @intCast("[CDATA[".len);
                    self.state = .{ .cdata_section = lbracket };
                } else {
                    // Anything else
                    // This is an incorrectly-opened-comment parse error. Create a comment token whose data is the empty string. Switch to the bogus comment state (don't consume anything in the current state).
                    self.state = .{ .bogus_comment = self.idx - 1 };
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .incorrectly_opened_comment,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                }
            },
            .character_reference => {
                @panic("TODO: implement character reference");
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-start-state
            .comment_start => |comment_start| {
                if (!self.consume(src)) {
                    self.state = .{ .comment = comment_start };
                } else switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the comment start dash state.
                    '-' => self.state = .{
                        .comment_start_dash = comment_start,
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // This is an abrupt-closing-of-empty-comment parse error. Switch to the data state. Emit the current comment token.
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .abrupt_closing_of_empty_comment,
                                    .span = .{
                                        .start = comment_start,
                                        .end = self.idx,
                                    },
                                },
                            },
                            .deferred = .{
                                .comment = .{
                                    .start = comment_start,
                                    .end = self.idx,
                                },
                            },
                        };
                    },
                    // Anything else
                    // Reconsume in the comment state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .comment = comment_start };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#comment-start-dash-state
            .comment_start_dash => |comment_start| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-comment parse error. Emit the current comment token. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_comment,
                                .span = .{
                                    .start = comment_start,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{
                            .comment = .{
                                .start = comment_start,
                                .end = self.idx,
                            },
                        },
                    };
                }
                switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the comment end state.
                    '-' => self.state = .{ .comment_end = comment_start },
                    // U+003E GREATER-THAN SIGN (>)
                    // This is an abrupt-closing-of-empty-comment parse error. Switch to the data state. Emit the current comment token.
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .abrupt_closing_of_empty_comment,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                            .deferred = .{
                                .comment = .{
                                    .start = comment_start,
                                    .end = self.idx,
                                },
                            },
                        };
                    },
                    // Anything else
                    // Append a U+002D HYPHEN-MINUS character (-) to the comment token's data. Reconsume in the comment state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .comment = comment_start };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#comment-state
            .comment => |comment_start| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-comment parse error. Emit the current comment token. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_comment,
                                .span = .{
                                    .start = comment_start,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{
                            .comment = .{
                                .start = comment_start,
                                .end = self.idx,
                            },
                        },
                    };
                }
                switch (self.current) {
                    // U+003C LESS-THAN SIGN (<)
                    // Append the current input character to the comment token's data. Switch to the comment less-than sign state.
                    '<' => self.state = .{
                        .comment_less_than_sign = comment_start,
                    },
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the comment end dash state.
                    '-' => self.state = .{
                        .comment_end_dash = comment_start,
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the comment token's data.
                    0 => {
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_null_character,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // Anything else
                    // Append the current input character to the comment token's data.
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-less-than-sign-state
            .comment_less_than_sign => |comment_start| {
                if (!self.consume(src)) {
                    self.state = .{ .comment = comment_start };
                }
                switch (self.current) {
                    // U+0021 EXCLAMATION MARK (!)
                    // Append the current input character to the comment token's data. Switch to the comment less-than sign bang state.
                    '!' => self.state = .{
                        .comment_less_than_sign_bang = comment_start,
                    },
                    // U+003C LESS-THAN SIGN (<)
                    // Append the current input character to the comment token's data.
                    '<' => {},
                    // Anything else
                    // Reconsume in the comment state.
                    else => self.state = .{ .comment = comment_start },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-less-than-sign-bang-state
            .comment_less_than_sign_bang => |comment_start| {
                if (!self.consume(src)) {
                    self.state = .{ .comment = comment_start };
                }
                switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the comment less-than sign bang dash state.
                    '-' => self.state = .{
                        .comment_less_than_sign_bang_dash = comment_start,
                    },

                    // Anything else
                    // Reconsume in the comment state.
                    else => self.state = .{ .comment = comment_start },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-less-than-sign-bang-dash-state
            .comment_less_than_sign_bang_dash => |comment_start| {
                if (!self.consume(src)) {
                    self.state = .{ .comment_end_dash = comment_start };
                }
                switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the comment less-than sign bang dash dash state.
                    '-' => switch (self.state) {
                        else => unreachable,
                        .comment_less_than_sign_bang => {
                            self.state = .{
                                .comment_less_than_sign_bang_dash = comment_start,
                            };
                        },
                        .comment_less_than_sign_bang_dash => {
                            self.state = .{
                                .comment_less_than_sign_bang_dash_dash = comment_start,
                            };
                        },
                    },

                    // Anything else
                    // Reconsume in the comment end dash state.
                    else => self.state = .{ .comment_end_dash = comment_start },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#comment-less-than-sign-bang-dash-dash-state
            .comment_less_than_sign_bang_dash_dash,
            => |comment_start| {
                if (!self.consume(src)) {
                    self.state = .{ .comment_end = comment_start };
                }
                switch (self.current) {
                    // U+003E GREATER-THAN SIGN (>)
                    // EOF
                    // Reconsume in the comment end state.
                    '-' => {
                        self.idx -= 1;
                        self.state = .{ .comment_end = comment_start };
                    },

                    // Anything else
                    // This is a nested-comment parse error. Reconsume in the comment end state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .comment_end = comment_start };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .nested_comment,
                                    .span = .{
                                        .start = self.idx,
                                        .end = self.idx + 1,
                                    },
                                },
                            },
                        };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#comment-end-dash-state
            .comment_end_dash => |comment_start| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-comment parse error. Emit the current comment token. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_comment,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{
                            .comment = .{
                                .start = comment_start,
                                .end = self.idx,
                            },
                        },
                    };
                }
                switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the comment end state.
                    '-' => self.state = .{ .comment_end = comment_start },
                    // Anything else
                    // Append a U+002D HYPHEN-MINUS character (-) to the comment token's data. Reconsume in the comment state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .comment = comment_start };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#comment-end-state
            .comment_end => |comment_start| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-comment parse error. Emit the current comment token. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_comment,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{
                            .comment = .{
                                .start = comment_start,
                                .end = self.idx,
                            },
                        },
                    };
                }
                switch (self.current) {
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current comment token.
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .comment = .{
                                    .start = comment_start,
                                    .end = self.idx,
                                },
                            },
                        };
                    },
                    // U+0021 EXCLAMATION MARK (!)
                    // Switch to the comment end bang state.
                    '!' => self.state = .{ .comment_end_bang = comment_start },
                    // U+002D HYPHEN-MINUS (-)
                    // Append a U+002D HYPHEN-MINUS character (-) to the comment token's data.
                    '-' => {},
                    // Anything else
                    // Append two U+002D HYPHEN-MINUS characters (-) to the comment token's data. Reconsume in the comment state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .comment = comment_start };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-end-bang-state
            .comment_end_bang => |comment_start| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-comment parse error. Emit the current comment token. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_comment,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{
                            .comment = .{
                                .start = comment_start,
                                .end = self.idx,
                            },
                        },
                    };
                }
                switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Append two U+002D HYPHEN-MINUS characters (-) and a U+0021 EXCLAMATION MARK character (!) to the comment token's data. Switch to the comment end dash state.
                    '-' => self.state = .{ .comment_end_dash = comment_start },
                    // U+003E GREATER-THAN SIGN (>)
                    // This is an incorrectly-closed-comment parse error. Switch to the data state. Emit the current comment token.
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .incorrectly_closed_comment,
                                    .span = .{
                                        .start = comment_start,
                                        .end = self.idx,
                                    },
                                },
                            },
                            .deferred = .{
                                .comment = .{
                                    .start = comment_start,
                                    .end = self.idx,
                                },
                            },
                        };
                    },
                    // Anything else
                    // Append two U+002D HYPHEN-MINUS characters (-) and a U+0021 EXCLAMATION MARK character (!) to the comment token's data. Reconsume in the comment state.
                    else => self.state = .{ .comment = comment_start },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-state
            .doctype => |lbracket| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Create a new DOCTYPE token. Set its force-quirks flag to on. Emit the current token. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_doctype,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{
                            .doctype = .{
                                .force_quirks = true,
                                .name_raw = null,
                                .span = .{
                                    .start = lbracket,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Switch to the before DOCTYPE name state.
                    '\t', '\n', form_feed, ' ' => self.state = .{
                        .before_doctype_name = lbracket,
                    },

                    // U+003E GREATER-THAN SIGN (>)
                    // Reconsume in the before DOCTYPE name state.
                    '>' => {
                        self.idx -= 1;
                        self.state = .{ .before_doctype_name = lbracket };
                    },

                    // Anything else
                    // This is a missing-whitespace-before-doctype-name parse error. Reconsume in the before DOCTYPE name state.
                    else => {
                        self.idx -= 1;
                        self.state = .{
                            .before_doctype_name = lbracket,
                        };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_whitespace_before_doctype_name,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#before-doctype-name-state
            .before_doctype_name => |lbracket| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Create a new DOCTYPE token. Set its force-quirks flag to on. Emit the current token. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_doctype,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{
                            .doctype = .{
                                .span = .{
                                    .start = lbracket,
                                    .end = self.idx,
                                },
                                .force_quirks = true,
                                .name_raw = null,
                            },
                        },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Ignore the character.
                    '\t', '\n', form_feed, ' ' => {},
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Create a new DOCTYPE token. Set the token's name to a U+FFFD REPLACEMENT CHARACTER character. Switch to the DOCTYPE name state.
                    0 => {
                        self.state = .{
                            .doctype_name = .{
                                .lbracket = lbracket,
                                .name_start = self.idx - 1,
                            },
                        };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_null_character,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // This is a missing-doctype-name parse error. Create a new DOCTYPE token. Set its force-quirks flag to on. Switch to the data state. Emit the current token.
                    '>' => {
                        self.idx -= 1;
                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_doctype_name,
                                    .span = .{
                                        .start = lbracket,
                                        .end = self.idx + 1,
                                    },
                                },
                            },
                            .deferred = .{
                                .doctype = .{
                                    .span = .{
                                        .start = lbracket,
                                        .end = self.idx + 1,
                                    },
                                    .force_quirks = true,
                                    .name_raw = null,
                                },
                            },
                        };
                    },
                    // ASCII upper alpha
                    // Create a new DOCTYPE token. Set the token's name to the lowercase version of the current input character (add 0x0020 to the character's code point). Switch to the DOCTYPE name state.
                    // Anything else
                    // Create a new DOCTYPE token. Set the token's name to the current input character. Switch to the DOCTYPE name state.
                    else => {
                        self.state = .{
                            .doctype_name = .{
                                .lbracket = lbracket,
                                .name_start = self.idx - 1,
                            },
                        };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-name-state
            .doctype_name => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_doctype,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{
                            .doctype = .{
                                .span = .{
                                    .start = state.lbracket,
                                    .end = self.idx + 1,
                                },
                                .force_quirks = true,
                                .name_raw = null,
                            },
                        },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Switch to the after DOCTYPE name state.
                    '\t', '\n', form_feed, ' ' => {
                        self.state = .{
                            .after_doctype_name = .{
                                .lbracket = state.lbracket,
                                .name_raw = .{
                                    .start = state.name_start,
                                    .end = self.idx - 1,
                                },
                            },
                        };
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .doctype = .{
                                    .span = .{
                                        .start = state.lbracket,
                                        .end = self.idx,
                                    },
                                    .name_raw = .{
                                        .start = state.name_start,
                                        .end = self.idx - 1,
                                    },
                                    .force_quirks = false,
                                },
                            },
                        };
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current DOCTYPE token's name.
                    0 => return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .unexpected_null_character,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    },
                    // ASCII upper alpha
                    // Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the current DOCTYPE token's name.
                    // Anything else
                    // Append the current input character to the current DOCTYPE token's name.
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-name-state
            .after_doctype_name => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_doctype,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{
                            .doctype = .{
                                .span = .{
                                    .start = state.lbracket,
                                    .end = self.idx,
                                },
                                .name_raw = state.name_raw,
                                .force_quirks = true,
                            },
                        },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Ignore the character.
                    '\t', '\n', form_feed, ' ' => {},
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .doctype = .{
                                    .span = .{
                                        .start = state.lbracket,
                                        .end = self.idx,
                                    },
                                    .name_raw = state.name_raw,
                                    .force_quirks = false,
                                },
                            },
                        };
                    },

                    // Anything else
                    else => {
                        self.idx -= 1;
                        if (self.nextCharsAreIgnoreCase("PUBLIC", src)) {
                            // If the six characters starting from the current input character are an ASCII case-insensitive match for the word "PUBLIC", then consume those characters and switch to the after DOCTYPE public keyword state.
                            self.state = .{
                                .after_doctype_public_kw = .{
                                    .span = .{
                                        .start = state.lbracket,
                                        .end = 0,
                                    },
                                    .name_raw = state.name_raw,
                                    .extra = .{
                                        .start = self.idx,
                                        .end = 0,
                                    },
                                    .force_quirks = false,
                                },
                            };

                            self.idx += @intCast("PUBLIC".len);
                        } else if (self.nextCharsAreIgnoreCase("SYSTEM", src)) {
                            // Otherwise, if the six characters starting from the current input character are an ASCII case-insensitive match for the word "SYSTEM", then consume those characters and switch to the after DOCTYPE system keyword state.
                            self.state = .{
                                .after_doctype_system_kw = .{
                                    .span = .{
                                        .start = state.lbracket,
                                        .end = 0,
                                    },
                                    .name_raw = state.name_raw,
                                    .extra = .{
                                        .start = self.idx - 1,
                                        .end = 0,
                                    },
                                    .force_quirks = false,
                                },
                            };
                            self.idx += @intCast("SYSTEM".len);
                        } else {
                            // Otherwise, this is an invalid-character-sequence-after-doctype-name parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
                            self.idx -= 1;
                            self.state = .{
                                .bogus_doctype = .{
                                    .span = .{
                                        .start = state.lbracket,
                                        .end = 0,
                                    },
                                    .name_raw = state.name_raw,
                                    .extra = .{
                                        .start = self.idx - 1,
                                        .end = 0,
                                    },
                                    .force_quirks = true,
                                },
                            };
                            return .{
                                .token = .{
                                    .parse_error = .{
                                        .tag = .invalid_character_sequence_after_doctype_name,
                                        .span = .{
                                            .start = self.idx,
                                            .end = self.idx + 1,
                                        },
                                    },
                                },
                            };
                        }
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-public-keyword-state
            .after_doctype_public_kw => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
                    self.state = .eof;
                    var tag = state;
                    tag.force_quirks = true;
                    tag.span.end = self.idx;
                    tag.extra.end = self.idx;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_doctype,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{ .doctype = tag },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Switch to the before DOCTYPE public identifier state.
                    '\t', '\n', form_feed, ' ' => {
                        self.state = .{
                            .before_doctype_public_identifier = state,
                        };
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // This is a missing-doctype-public-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        self.state = .data;
                        var tag = state;
                        tag.force_quirks = true;
                        tag.span.end = self.idx;
                        tag.extra.end = self.idx - 1;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_doctype_public_identifier,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                            .deferred = .{ .doctype = tag },
                        };
                    },
                    // U+0022 QUOTATION MARK (")
                    // This is a missing-whitespace-after-doctype-public-keyword parse error. Set the current DOCTYPE token's public identifier to the empty string (not missing), then switch to the DOCTYPE public identifier (double-quoted) state.
                    '"' => {
                        self.state = .{
                            .doctype_public_identifier_double = state,
                        };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_whitespace_after_doctype_public_keyword,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // U+0027 APOSTROPHE (')
                    // This is a missing-whitespace-after-doctype-public-keyword parse error. Set the current DOCTYPE token's public identifier to the empty string (not missing), then switch to the DOCTYPE public identifier (single-quoted) state.
                    '\'' => {
                        self.state = .{
                            .doctype_public_identifier_single = state,
                        };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_whitespace_after_doctype_public_keyword,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },

                    // Anything else
                    // This is a missing-quote-before-doctype-public-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
                    else => {
                        self.idx -= 1;
                        var tag = state;
                        tag.force_quirks = true;
                        self.state = .{ .bogus_doctype = tag };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_quote_before_doctype_public_identifier,
                                    .span = .{
                                        .start = self.idx,
                                        .end = self.idx + 1,
                                    },
                                },
                            },
                        };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#before-doctype-public-identifier-state
            .before_doctype_public_identifier => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
                    var tag = state;
                    tag.force_quirks = true;
                    tag.span.end = self.idx;
                    tag.extra.end = self.idx;

                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_doctype,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{ .doctype = tag },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Ignore the character.
                    '\t', '\n', form_feed, ' ' => {},

                    // U+0022 QUOTATION MARK (")
                    // Set the current DOCTYPE token's public identifier to the empty string (not missing), then switch to the DOCTYPE public identifier (double-quoted) state.
                    '"' => {
                        self.state = .{
                            .doctype_public_identifier_double = state,
                        };
                    },
                    // U+0027 APOSTROPHE (')
                    // Set the current DOCTYPE token's public identifier to the empty string (not missing), then switch to the DOCTYPE public identifier (single-quoted) state.
                    '\'' => {
                        self.state = .{
                            .doctype_public_identifier_single = state,
                        };
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // This is a missing-doctype-public-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        var tag = state;
                        tag.force_quirks = true;
                        tag.span.end = self.idx;
                        tag.extra.end = self.idx - 1;

                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_doctype_public_identifier,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                            .deferred = .{ .doctype = tag },
                        };
                    },
                    // Anything else
                    // This is a missing-quote-before-doctype-public-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
                    else => {
                        var tag = state;
                        tag.force_quirks = true;

                        self.idx -= 1;
                        self.state = .{ .bogus_doctype = tag };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_quote_before_doctype_public_identifier,
                                    .span = .{
                                        .start = self.idx,
                                        .end = self.idx + 1,
                                    },
                                },
                            },
                        };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-public-identifier-(double-quoted)-state
            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-public-identifier-(single-quoted)-state
            .doctype_public_identifier_double,
            .doctype_public_identifier_single,
            => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
                    var tag = state;
                    tag.force_quirks = true;
                    tag.span.end = self.idx;
                    tag.extra.end = self.idx;

                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_doctype,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{ .doctype = tag },
                    };
                }
                switch (self.current) {
                    // U+0022 QUOTATION MARK (")
                    // Switch to the after DOCTYPE public identifier state.
                    // U+0027 APOSTROPHE (')
                    // Switch to the after DOCTYPE public identifier state.
                    '"', '\'' => {
                        const double = self.current == '"' and self.state == .doctype_public_identifier_double;
                        const single = self.current == '\'' and self.state == .doctype_public_identifier_single;
                        if (single or double) {
                            self.state = .{
                                .after_doctype_public_identifier = state,
                            };
                        }
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current DOCTYPE token's public identifier.
                    0 => return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .unexpected_null_character,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // This is an abrupt-doctype-public-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        var tag = state;
                        tag.force_quirks = true;
                        tag.span.end = self.idx;
                        tag.extra.end = self.idx - 1;

                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .abrupt_doctype_public_identifier,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                            .deferred = .{ .doctype = tag },
                        };
                    },

                    // Anything else
                    // Append the current input character to the current DOCTYPE token's public identifier.
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-public-identifier-state
            .after_doctype_public_identifier => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
                    var tag = state;
                    tag.force_quirks = true;
                    tag.span.end = self.idx;
                    tag.extra.end = self.idx;

                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_doctype,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{ .doctype = tag },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Switch to the between DOCTYPE public and system identifiers state.
                    '\t', '\n', form_feed, ' ' => {
                        self.state = .{
                            .beteen_doctype_public_and_system_identifiers = state,
                        };
                    },
                    // U+0022 QUOTATION MARK (")
                    // This is a missing-whitespace-between-doctype-public-and-system-identifiers parse error. Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (double-quoted) state.
                    '"' => {
                        self.state = .{
                            .doctype_system_identifier_double = state,
                        };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_whitespace_between_doctype_public_and_system_identifiers,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // U+0027 APOSTROPHE (')
                    // This is a missing-whitespace-between-doctype-public-and-system-identifiers parse error. Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (single-quoted) state.
                    '\'' => {
                        self.state = .{
                            .doctype_system_identifier_single = state,
                        };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_whitespace_between_doctype_public_and_system_identifiers,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },

                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        self.state = .data;
                        var tag = state;
                        tag.span.end = self.idx;
                        tag.extra.end = self.idx - 1;
                        return .{ .token = .{ .doctype = tag } };
                    },

                    // Anything else
                    // This is a missing-quote-before-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
                    else => {
                        var tag = state;
                        tag.force_quirks = true;

                        self.idx -= 1;
                        self.state = .{ .bogus_doctype = tag };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_quote_before_doctype_system_identifier,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#between-doctype-public-and-system-identifiers-state
            .beteen_doctype_public_and_system_identifiers => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
                    var tag = state;
                    tag.force_quirks = true;
                    tag.span.end = self.idx;
                    tag.extra.end = self.idx;

                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_doctype,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{ .doctype = tag },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Ignore the character.
                    '\t', '\n', form_feed, ' ' => {},
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        self.state = .data;
                        var tag = state;
                        tag.span.end = self.idx;
                        tag.extra.end = self.idx - 1;
                        return .{ .token = .{ .doctype = tag } };
                    },
                    // U+0022 QUOTATION MARK (")
                    // Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (double-quoted) state.
                    '"' => {
                        self.state = .{
                            .doctype_system_identifier_double = state,
                        };
                    },
                    // U+0027 APOSTROPHE (')
                    // Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (single-quoted) state.
                    '\'' => {
                        self.state = .{
                            .doctype_system_identifier_single = state,
                        };
                    },

                    // Anything else
                    // This is a missing-quote-before-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
                    else => {
                        self.idx -= 1;
                        self.state = .{
                            .bogus_doctype = state,
                        };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_quote_before_doctype_system_identifier,
                                    .span = .{
                                        .start = self.idx,
                                        .end = self.idx + 1,
                                    },
                                },
                            },
                        };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-system-keyword-state
            .after_doctype_system_kw => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
                    var tag = state;
                    tag.force_quirks = true;
                    tag.span.end = self.idx;
                    tag.extra.end = self.idx;

                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_doctype,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{ .doctype = tag },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Switch to the before DOCTYPE system identifier state.
                    '\t', '\n', form_feed, ' ' => {
                        self.state = .{
                            .before_doctype_system_identifier = state,
                        };
                    },
                    // U+0022 QUOTATION MARK (")
                    // This is a missing-whitespace-after-doctype-system-keyword parse error. Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (double-quoted) state.
                    '"' => {
                        self.state = .{
                            .doctype_system_identifier_double = state,
                        };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_whitespace_after_doctype_system_keyword,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // U+0027 APOSTROPHE (')
                    // This is a missing-whitespace-after-doctype-system-keyword parse error. Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (single-quoted) state.
                    '\'' => {
                        self.state = .{
                            .doctype_public_identifier_single = state,
                        };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_whitespace_after_doctype_system_keyword,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // This is a missing-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        var tag = state;
                        tag.force_quirks = true;
                        tag.span.end = self.idx;
                        tag.extra.end = self.idx - 1;

                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_doctype_system_identifier,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                            .deferred = .{ .doctype = tag },
                        };
                    },
                    // Anything else
                    // This is a missing-quote-before-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
                    else => {
                        var tag = state;
                        tag.force_quirks = true;

                        self.idx -= 1;
                        self.state = .{ .bogus_doctype = tag };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_quote_before_doctype_system_identifier,
                                    .span = .{
                                        .start = self.idx,
                                        .end = self.idx + 1,
                                    },
                                },
                            },
                        };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#before-doctype-system-identifier-state
            .before_doctype_system_identifier => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
                    var tag = state;
                    tag.force_quirks = true;
                    tag.span.end = self.idx;
                    tag.extra.end = self.idx;

                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_doctype,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{ .doctype = tag },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Ignore the character.
                    '\t', '\n', form_feed, ' ' => {},

                    // U+0022 QUOTATION MARK (")
                    // Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (double-quoted) state.
                    '"' => {
                        self.state = .{
                            .doctype_system_identifier_double = state,
                        };
                    },
                    // U+0027 APOSTROPHE (')
                    // Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (single-quoted) state.
                    '\'' => {
                        self.state = .{
                            .doctype_system_identifier_single = state,
                        };
                    },

                    // U+003E GREATER-THAN SIGN (>)
                    // This is a missing-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        var tag = state;
                        tag.force_quirks = true;
                        tag.span.end = self.idx;
                        tag.extra.end = self.idx - 1;

                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_doctype_system_identifier,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                            .deferred = .{ .doctype = tag },
                        };
                    },
                    // Anything else
                    // This is a missing-quote-before-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
                    else => {
                        var tag = state;
                        tag.force_quirks = true;
                        self.state = .{
                            .bogus_doctype = tag,
                        };
                        self.idx -= 1;

                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_quote_before_doctype_system_identifier,
                                    .span = .{
                                        .start = self.idx,
                                        .end = self.idx + 1,
                                    },
                                },
                            },
                        };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-system-identifier-(double-quoted)-state
            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-system-identifier-(double-quoted)-state
            .doctype_system_identifier_double,
            .doctype_system_identifier_single,
            => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
                    var tag = state;
                    tag.force_quirks = true;
                    tag.span.end = self.idx;
                    tag.extra.end = self.idx;

                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_doctype,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{ .doctype = tag },
                    };
                }
                switch (self.current) {
                    // U+0022 QUOTATION MARK (")
                    // Switch to the after DOCTYPE system identifier state.
                    // U+0027 APOSTROPHE (')
                    // Switch to the after DOCTYPE system identifier state.
                    '"', '\'' => {
                        const double = self.current == '"' and self.state == .doctype_system_identifier_double;
                        const single = self.current == '\'' and self.state == .doctype_system_identifier_single;
                        if (single or double) {
                            self.state = .{
                                .after_doctype_system_identifier = state,
                            };
                        }
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current DOCTYPE token's public identifier.
                    0 => return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .unexpected_null_character,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // This is an abrupt-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        var tag = state;
                        tag.force_quirks = true;
                        tag.span.end = self.idx;
                        tag.extra.end = self.idx - 1;

                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .abrupt_doctype_system_identifier,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                            .deferred = .{ .doctype = tag },
                        };
                    },

                    // Anything else
                    // Append the current input character to the current DOCTYPE token's system identifier.
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-system-identifier-state
            .after_doctype_system_identifier => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
                    var tag = state;
                    tag.force_quirks = true;
                    tag.span.end = self.idx;
                    tag.extra.end = self.idx;

                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_doctype,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{ .doctype = tag },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Ignore the character.
                    '\t', '\n', form_feed, ' ' => {},

                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        var tag = state;
                        tag.span.end = self.idx;
                        tag.extra.end = self.idx - 1;

                        self.state = .data;
                        return .{ .token = .{ .doctype = tag } };
                    },
                    // Anything else
                    // This is an unexpected-character-after-doctype-system-identifier parse error. Reconsume in the bogus DOCTYPE state. (This does not set the current DOCTYPE token's force-quirks flag to on.)
                    else => {
                        self.idx -= 1;
                        self.state = .{ .bogus_doctype = state };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_character_after_doctype_system_identifier,
                                    .span = .{
                                        .start = self.idx,
                                        .end = self.idx + 1,
                                    },
                                },
                            },
                        };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#bogus-doctype-state
            .bogus_doctype => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // Emit the DOCTYPE token. Emit an end-of-file token.
                    self.state = .eof;
                    var tag = state;
                    tag.span.end = self.idx;
                    tag.extra.end = self.idx;
                    return .{
                        .token = .{ .doctype = tag },
                    };
                }
                switch (self.current) {
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the DOCTYPE token.
                    '>' => {
                        self.state = .data;
                        var tag = state;
                        tag.span.end = self.idx;
                        tag.extra.end = self.idx - 1;
                        return .{
                            .token = .{ .doctype = tag },
                        };
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Ignore the character.
                    0 => {
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_null_character,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },

                    // Anything else
                    // Ignore the character.
                    else => {},
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#cdata-section-state
            .cdata_section => |lbracket| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-cdata parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_cdata,
                                .span = .{
                                    .start = lbracket,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                }
                switch (self.current) {
                    // U+005D RIGHT SQUARE BRACKET (])
                    // Switch to the CDATA section bracket state.
                    ']' => self.state = .{
                        .cdata_section_bracket = lbracket,
                    },
                    // Anything else
                    // Emit the current input character as a character token.
                    else => {},
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#cdata-section-bracket-state
            .cdata_section_bracket => |lbracket| {
                if (!self.consume(src)) {
                    self.state = .{ .cdata_section = lbracket };
                }
                switch (self.current) {
                    // U+005D RIGHT SQUARE BRACKET (])
                    // Switch to the CDATA section end state.
                    ']' => self.state = .{ .cdata_section_end = lbracket },
                    // Anything else
                    // Emit a U+005D RIGHT SQUARE BRACKET character token. Reconsume in the CDATA section state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .cdata_section = lbracket };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#cdata-section-end-state
            .cdata_section_end => |lbracket| {
                if (!self.consume(src)) {
                    self.state = .{ .cdata_section = lbracket };
                }
                switch (self.current) {
                    // U+005D RIGHT SQUARE BRACKET (])
                    // Emit a U+005D RIGHT SQUARE BRACKET character token.
                    ']' => {},
                    // U+003E GREATER-THAN SIGN character
                    // Switch to the data state.
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .comment = .{
                                    .start = lbracket,
                                    .end = self.idx,
                                },
                            },
                        };
                    },
                    // Anything else
                    // Emit two U+005D RIGHT SQUARE BRACKET character tokens. Reconsume in the CDATA section state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .cdata_section = lbracket };
                    },
                }
            },

            .eof => return null,
        }
    }
}

pub fn gotoScriptData(self: *Tokenizer) void {
    self.state = .{ .script_data = self.idx };
    self.last_start_tag_name = "script";
}

pub fn gotoRcData(self: *Tokenizer, tag_name: []const u8) void {
    self.state = .{ .rcdata = self.idx };
    self.last_start_tag_name = tag_name;
}

pub fn gotoRawText(self: *Tokenizer, tag_name: []const u8) void {
    self.state = .{ .rawtext = self.idx };
    self.last_start_tag_name = tag_name;
}

pub fn gotoPlainText(self: *Tokenizer) void {
    self.state = .{ .plaintext = self.idx };
}

fn nextCharsAre(self: Tokenizer, needle: []const u8, src: []const u8) bool {
    return std.mem.startsWith(u8, src[self.idx..], needle);
}

fn nextCharsAreIgnoreCase(self: Tokenizer, needle: []const u8, src: []const u8) bool {
    return std.ascii.startsWithIgnoreCase(src[self.idx..], needle);
}

fn isAsciiAlphaLower(c: u8) bool {
    return (c >= 'a' and c <= 'z');
}
fn isAsciiAlphaUpper(c: u8) bool {
    return (c >= 'A' and c <= 'Z');
}
fn isAsciiAlpha(c: u8) bool {
    return isAsciiAlphaLower(c) or isAsciiAlphaUpper(c);
}

const tl = std.log.scoped(.trim);

fn trimmedText(start: u32, end: u32, src: []const u8) ?Span {
    var text_span: Span = .{ .start = start, .end = end };

    tl.debug("span: {any}, txt: '{s}'", .{
        text_span,
        text_span.slice(src),
    });

    while (text_span.start < end and
        std.ascii.isWhitespace(src[text_span.start]))
    {
        text_span.start += 1;
    }

    while (text_span.end > text_span.start and
        std.ascii.isWhitespace(src[text_span.end - 1]))
    {
        text_span.end -= 1;
    }

    tl.debug("end span: {any}, txt: '{s}'", .{
        text_span,
        text_span.slice(src),
    });

    if (text_span.start == text_span.end) {
        return null;
    }

    return text_span;
}

test "script single/double escape weirdness" {
    // case from https://stackoverflow.com/questions/23727025/script-double-escaped-state
    const case =
        \\<script>
        \\<!--script data escaped-->
        \\</script>    
        \\
        \\<script>
        \\<!--<script>script data double escaped</script>-->
        \\</script>
    ;

    // TODO: fix also the expected results!

    var tokenizer: Tokenizer = .{};
    var t = tokenizer.next(case);
    errdefer std.debug.print("t = {any}\n", .{t});

    // first half
    {
        try std.testing.expect(t != null);
        try std.testing.expect(t.? == .tag);
        try std.testing.expect(t.?.tag.kind == .start);
    }
    {
        t = tokenizer.next(case);
        try std.testing.expect(t != null);
        try std.testing.expect(t.? == .text);
    }
    {
        t = tokenizer.next(case);
        try std.testing.expect(t != null);
        try std.testing.expect(t.? == .tag);
        try std.testing.expect(t.?.tag.kind == .end);
    }

    // Second half

    {
        try std.testing.expect(t != null);
        try std.testing.expect(t.? == .tag);
        try std.testing.expect(t.?.tag.kind == .start);
    }
    {
        t = tokenizer.next(case);
        try std.testing.expect(t != null);
        try std.testing.expect(t.? == .text);
    }
    {
        t = tokenizer.next(case);
        try std.testing.expect(t != null);
        try std.testing.expect(t.? == .tag);
        try std.testing.expect(t.?.tag.kind == .end);
    }

    t = tokenizer.next(case);
    try std.testing.expect(t == null);
}
