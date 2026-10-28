// ============================================================
// SEVEN Language — C Lexer (for LLVM backend)
// Tokenizes .seven source into a token array
// ============================================================
#ifndef SEVEN_LEXER_H
#define SEVEN_LEXER_H

#include <stddef.h>

typedef enum {
    // Literals
    TOK_INT,          // 42
    TOK_STRING,       // "hello"
    TOK_IDENT,        // variable/function name
    TOK_TRUE,         // true
    TOK_FALSE,        // false

    // Keywords
    TOK_SHOW,         // show
    TOK_SET,          // set
    TOK_TO,           // to
    TOK_IF,           // if
    TOK_ELIF,         // elif
    TOK_ELSE,         // else
    TOK_END,          // end
    TOK_WHILE,        // while
    TOK_DONE,         // done
    TOK_EACH,         // each
    TOK_AS,           // as
    TOK_IN,           // in
    TOK_REPEAT,       // repeat
    TOK_FUNC,         // func
    TOK_RESULT,       // result
    TOK_RETURN,       // return
    TOK_USE,          // use
    TOK_TRY,          // try
    TOK_CATCH,        // catch
    TOK_ASK,          // ask
    TOK_ASSERT,       // assert

    // Operators
    TOK_PLUS,         // +
    TOK_MINUS,        // -
    TOK_STAR,         // *
    TOK_SLASH,        // /
    TOK_PERCENT,      // %
    TOK_LPAREN,       // (
    TOK_RPAREN,       // )
    TOK_LBRACKET,     // [
    TOK_RBRACKET,     // ]
    TOK_COMMA,        // ,
    TOK_DOT,          // .
    TOK_COLON,        // :
    TOK_ASSIGN,       // =

    // Comparison (word-based)
    TOK_IS,           // is
    TOK_ISNT,         // isnt
    TOK_ABOVE,        // above
    TOK_BELOW,        // below
    TOK_ATLEAST,      // atleast
    TOK_ATMOST,       // atmost

    // Logical
    TOK_AND,          // and
    TOK_OR,           // or
    TOK_NOT,          // not

    // Bitwise
    TOK_BAND,         // band
    TOK_BOR,          // bor
    TOK_BXOR,         // bxor
    TOK_BNOT,         // bnot
    TOK_SHL,          // shl
    TOK_SHR,          // shr

    // Special
    TOK_MANY,         // many (variadic)
    TOK_PUSH,         // push
    TOK_POP,          // pop
    TOK_WRITE,        // write (file)
    TOK_READ,         // read (file)
    TOK_DELETE,       // delete (file)
    TOK_APPEND,       // append (file)

    TOK_NEWLINE,      // end of statement
    TOK_EOF,          // end of input
} TokenType;

typedef struct {
    TokenType type;
    char *value;       // heap-allocated string value
    int line;
    int col;
} Token;

typedef struct {
    Token *tokens;
    int count;
    int capacity;
    int pos;           // current read position
    const char *filename;
} Lexer;

// Initialize lexer with source code
void lexer_init(Lexer *lex, const char *source, const char *filename);

// Tokenize the source
void lexer_tokenize(Lexer *lex);

// Free lexer resources
void lexer_free(Lexer *lex);

// Token access
Token *lexer_peek(Lexer *lex);
Token *lexer_next(Lexer *lex);
int lexer_match(Lexer *lex, TokenType type);
Token *lexer_expect(Lexer *lex, TokenType type);

// Debug
const char *token_type_name(TokenType t);

#endif
