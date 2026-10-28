// ============================================================
// SEVEN Language — C Lexer Implementation
// ============================================================

#include "llvm_lexer.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

static void lexer_add(Lexer *lex, TokenType type, const char *val, int line, int col) {
    if (lex->count >= lex->capacity) {
        lex->capacity *= 2;
        lex->tokens = realloc(lex->tokens, sizeof(Token) * lex->capacity);
    }
    Token *t = &lex->tokens[lex->count++];
    t->type = type;
    t->value = val ? strdup(val) : NULL;
    t->line = line;
    t->col = col;
}

typedef struct { const char *word; TokenType type; } Keyword;

static const Keyword keywords[] = {
    {"show", TOK_SHOW}, {"set", TOK_SET}, {"to", TOK_TO},
    {"if", TOK_IF}, {"elif", TOK_ELIF}, {"else", TOK_ELSE}, {"end", TOK_END},
    {"while", TOK_WHILE}, {"done", TOK_DONE},
    {"each", TOK_EACH}, {"as", TOK_AS}, {"in", TOK_IN},
    {"repeat", TOK_REPEAT},
    {"func", TOK_FUNC}, {"result", TOK_RESULT}, {"return", TOK_RETURN},
    {"use", TOK_USE},
    {"try", TOK_TRY}, {"catch", TOK_CATCH},
    {"ask", TOK_ASK}, {"assert", TOK_ASSERT},
    {"is", TOK_IS}, {"isnt", TOK_ISNT},
    {"above", TOK_ABOVE}, {"below", TOK_BELOW},
    {"atleast", TOK_ATLEAST}, {"atmost", TOK_ATMOST},
    {"and", TOK_AND}, {"or", TOK_OR}, {"not", TOK_NOT},
    {"band", TOK_BAND}, {"bor", TOK_BOR}, {"bxor", TOK_BXOR},
    {"bnot", TOK_BNOT}, {"shl", TOK_SHL}, {"shr", TOK_SHR},
    {"true", TOK_TRUE}, {"false", TOK_FALSE},
    {"many", TOK_MANY},
    {"push", TOK_PUSH}, {"pop", TOK_POP},
    {"write", TOK_WRITE}, {"read", TOK_READ},
    {"delete", TOK_DELETE}, {"append", TOK_APPEND},
    {NULL, 0}
};

static TokenType lookup_keyword(const char *word) {
    for (int i = 0; keywords[i].word; i++) {
        if (strcmp(word, keywords[i].word) == 0)
            return keywords[i].type;
    }
    return TOK_IDENT;
}

void lexer_init(Lexer *lex, const char *source, const char *filename) {
    lex->tokens = malloc(sizeof(Token) * 256);
    lex->count = 0;
    lex->capacity = 256;
    lex->pos = 0;
    lex->filename = filename;

    // Store source pointer for tokenize
    lex->tokens[0].value = (char *)source;  // temp hack, overwritten in tokenize
}

void lexer_tokenize(Lexer *lex) {
    const char *src = lex->tokens[0].value;  // retrieve source
    lex->count = 0;

    int i = 0;
    int line = 1, col = 1;

    while (src[i]) {
        // Skip spaces and tabs
        if (src[i] == ' ' || src[i] == '\t') {
            i++; col++;
            continue;
        }

        // Skip carriage return
        if (src[i] == '\r') {
            i++;
            continue;
        }

        // Newline
        if (src[i] == '\n') {
            // Only add if last token wasn't a newline
            if (lex->count == 0 || lex->tokens[lex->count - 1].type != TOK_NEWLINE) {
                lexer_add(lex, TOK_NEWLINE, NULL, line, col);
            }
            line++; col = 1; i++;
            continue;
        }

        // Comment: !! to end of line
        if (src[i] == '!' && src[i + 1] == '!') {
            while (src[i] && src[i] != '\n') i++;
            continue;
        }

        // String literal
        if (src[i] == '"') {
            i++; col++;
            int start = i;
            char buf[4096];
            int bi = 0;
            while (src[i] && src[i] != '"' && src[i] != '\n') {
                if (src[i] == '\\' && src[i + 1]) {
                    i++;
                    switch (src[i]) {
                        case 'n': buf[bi++] = '\n'; break;
                        case 't': buf[bi++] = '\t'; break;
                        case '\\': buf[bi++] = '\\'; break;
                        case '"': buf[bi++] = '"'; break;
                        default: buf[bi++] = src[i]; break;
                    }
                } else {
                    buf[bi++] = src[i];
                }
                i++; col++;
            }
            buf[bi] = '\0';
            if (src[i] == '"') { i++; col++; }
            lexer_add(lex, TOK_STRING, buf, line, col);
            continue;
        }

        // Number
        if (isdigit(src[i])) {
            int start = i;
            while (isdigit(src[i])) { i++; col++; }
            char num[64];
            int len = i - start;
            if (len > 63) len = 63;
            memcpy(num, &src[start], len);
            num[len] = '\0';
            lexer_add(lex, TOK_INT, num, line, col);
            continue;
        }

        // Identifier / keyword
        if (isalpha(src[i]) || src[i] == '_') {
            int start = i;
            while (isalnum(src[i]) || src[i] == '_') { i++; col++; }
            char word[256];
            int len = i - start;
            if (len > 255) len = 255;
            memcpy(word, &src[start], len);
            word[len] = '\0';
            TokenType tt = lookup_keyword(word);
            lexer_add(lex, tt, word, line, col);
            continue;
        }

        // Operators
        int ocol = col;
        switch (src[i]) {
            case '+': lexer_add(lex, TOK_PLUS, "+", line, col); break;
            case '-': lexer_add(lex, TOK_MINUS, "-", line, col); break;
            case '*': lexer_add(lex, TOK_STAR, "*", line, col); break;
            case '/': lexer_add(lex, TOK_SLASH, "/", line, col); break;
            case '%': lexer_add(lex, TOK_PERCENT, "%", line, col); break;
            case '(': lexer_add(lex, TOK_LPAREN, "(", line, col); break;
            case ')': lexer_add(lex, TOK_RPAREN, ")", line, col); break;
            case '[': lexer_add(lex, TOK_LBRACKET, "[", line, col); break;
            case ']': lexer_add(lex, TOK_RBRACKET, "]", line, col); break;
            case ',': lexer_add(lex, TOK_COMMA, ",", line, col); break;
            case '.': lexer_add(lex, TOK_DOT, ".", line, col); break;
            case ':': lexer_add(lex, TOK_COLON, ":", line, col); break;
            case '=': lexer_add(lex, TOK_ASSIGN, "=", line, col); break;
            default:
                fprintf(stderr, "%s:%d:%d: warning: unexpected character '%c'\n",
                        lex->filename, line, col, src[i]);
                break;
        }
        i++; col++;
    }

    lexer_add(lex, TOK_EOF, NULL, line, col);
}

void lexer_free(Lexer *lex) {
    for (int i = 0; i < lex->count; i++) {
        free(lex->tokens[i].value);
    }
    free(lex->tokens);
    lex->tokens = NULL;
    lex->count = 0;
}

Token *lexer_peek(Lexer *lex) {
    if (lex->pos >= lex->count) return &lex->tokens[lex->count - 1]; // EOF
    return &lex->tokens[lex->pos];
}

Token *lexer_next(Lexer *lex) {
    Token *t = lexer_peek(lex);
    if (t->type != TOK_EOF) lex->pos++;
    return t;
}

int lexer_match(Lexer *lex, TokenType type) {
    if (lexer_peek(lex)->type == type) {
        lexer_next(lex);
        return 1;
    }
    return 0;
}

Token *lexer_expect(Lexer *lex, TokenType type) {
    Token *t = lexer_next(lex);
    if (t->type != type) {
        fprintf(stderr, "%s:%d: error: expected %s, got %s",
                lex->filename, t->line, token_type_name(type), token_type_name(t->type));
        if (t->value) fprintf(stderr, " '%s'", t->value);
        fprintf(stderr, "\n");
        exit(1);
    }
    return t;
}

const char *token_type_name(TokenType t) {
    switch (t) {
        case TOK_INT: return "integer";
        case TOK_STRING: return "string";
        case TOK_IDENT: return "identifier";
        case TOK_SHOW: return "show";
        case TOK_SET: return "set";
        case TOK_TO: return "to";
        case TOK_IF: return "if";
        case TOK_ELIF: return "elif";
        case TOK_ELSE: return "else";
        case TOK_END: return "end";
        case TOK_WHILE: return "while";
        case TOK_DONE: return "done";
        case TOK_EACH: return "each";
        case TOK_AS: return "as";
        case TOK_IN: return "in";
        case TOK_REPEAT: return "repeat";
        case TOK_FUNC: return "func";
        case TOK_RESULT: return "result";
        case TOK_RETURN: return "return";
        case TOK_USE: return "use";
        case TOK_TRY: return "try";
        case TOK_CATCH: return "catch";
        case TOK_ASK: return "ask";
        case TOK_ASSERT: return "assert";
        case TOK_PLUS: return "+";
        case TOK_MINUS: return "-";
        case TOK_STAR: return "*";
        case TOK_SLASH: return "/";
        case TOK_PERCENT: return "%";
        case TOK_LPAREN: return "(";
        case TOK_RPAREN: return ")";
        case TOK_LBRACKET: return "[";
        case TOK_RBRACKET: return "]";
        case TOK_COMMA: return ",";
        case TOK_DOT: return ".";
        case TOK_COLON: return ":";
        case TOK_ASSIGN: return "=";
        case TOK_IS: return "is";
        case TOK_ISNT: return "isnt";
        case TOK_ABOVE: return "above";
        case TOK_BELOW: return "below";
        case TOK_ATLEAST: return "atleast";
        case TOK_ATMOST: return "atmost";
        case TOK_AND: return "and";
        case TOK_OR: return "or";
        case TOK_NOT: return "not";
        case TOK_NEWLINE: return "newline";
        case TOK_EOF: return "EOF";
        default: return "?";
    }
}
