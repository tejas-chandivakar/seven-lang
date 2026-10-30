// SEVEN Language — WebAssembly Runtime
// Bridges SEVEN runtime to JS via wasm imports

// JS imports
__attribute__((import_module("env"), import_name("js_print_int")))
void js_print_int(long long val);

__attribute__((import_module("env"), import_name("js_print_str")))
void js_print_str(const char *ptr, int len);

__attribute__((import_module("env"), import_name("js_print_nl")))
void js_print_nl(void);

// Bump allocator
static char heap[1048576];
static int heap_ptr = 0;

void *malloc(unsigned long size) {
    if (heap_ptr + size > sizeof(heap)) return 0;
    void *p = &heap[heap_ptr];
    heap_ptr = (heap_ptr + size + 7) & ~7;
    return p;
}

void free(void *p) { (void)p; }

int strlen(const char *s) { int n = 0; while (s[n]) n++; return n; }

void *memcpy(void *d, const void *s, unsigned long n) {
    char *dd = d; const char *ss = s; while (n--) *dd++ = *ss++; return d;
}

void *memset(void *s, int c, unsigned long n) {
    char *p = s; while (n--) *p++ = (char)c; return s;
}

int strcmp(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return (unsigned char)*a - (unsigned char)*b;
}

char *strstr(const char *h, const char *n) {
    int nl = strlen(n);
    if (!nl) return (char *)h;
    for (; *h; h++) {
        int match = 1;
        for (int i = 0; i < nl; i++) { if (h[i] != n[i]) { match = 0; break; } }
        if (match) return (char *)h;
    }
    return 0;
}

// Forward declarations
char *seven_hex(long long val);
char *seven_bin(long long val);

// libc stubs used by LLVM codegen
int puts(const char *s) {
    js_print_str(s, strlen(s));
    js_print_nl();
    return 0;
}

// Variadic printf is not possible in wasm32 (no va_list ABI).
// The codegen only calls printf with 2 args: printf(fmt, val).
// We provide specialized overloads and let wasm-ld pick the right one.
// Actually, we use a workaround: wasm calling convention passes args in registers.
// The codegen calls printf("%lld\n", int_val) or printf("%s\n", str_ptr).
// We implement printf as a 2-arg function that inspects the format string.
int printf(const char *fmt, int arg) {
    // In wasm32, pointers are i32 and ints get truncated to i32 in variadic calls
    // Check format pattern
    if (fmt[0] == '%' && fmt[1] == 'l' && fmt[2] == 'l' && fmt[3] == 'd') {
        js_print_int(arg);
        // Print remaining chars after %lld
        const char *rest = fmt + 4;
        int rl = strlen(rest);
        if (rl > 0) {
            if (rl == 1 && rest[0] == '\n') js_print_nl();
            else js_print_str(rest, rl);
        }
    } else if (fmt[0] == '%' && fmt[1] == 's') {
        const char *s = (const char *)arg;
        js_print_str(s, strlen(s));
        const char *rest = fmt + 2;
        int rl = strlen(rest);
        if (rl > 0) {
            if (rl == 1 && rest[0] == '\n') js_print_nl();
            else js_print_str(rest, rl);
        }
    } else if (fmt[0] == '%' && fmt[1] == 'l' && fmt[2] == 'l' && fmt[3] == 'x') {
        char *h = seven_hex(arg);
        js_print_str(h, strlen(h));
        const char *rest = fmt + 4;
        int rl = strlen(rest);
        if (rl > 0) js_print_str(rest, rl);
    } else {
        js_print_str(fmt, strlen(fmt));
    }
    return 0;
}

void exit(int code) { (void)code; __builtin_unreachable(); }

int snprintf(char *buf, unsigned long size, const char *fmt, ...) {
    // Minimal: just copy fmt
    int i = 0;
    while (fmt[i] && (unsigned long)i < size - 1) { buf[i] = fmt[i]; i++; }
    buf[i] = '\0';
    return i;
}

// === String functions (names match codegen declarations) ===

long long seven_str_equal(const char *a, const char *b) {
    return strcmp(a, b) == 0;
}

long long seven_str_len(const char *s) {
    return strlen(s);
}

char *seven_str_concat(const char *a, const char *b) {
    int la = strlen(a), lb = strlen(b);
    char *r = malloc(la + lb + 1);
    if (!r) return "";
    memcpy(r, a, la);
    memcpy(r + la, b, lb + 1);
    return r;
}

char *seven_str_upper(const char *s) {
    int n = strlen(s);
    char *r = malloc(n + 1);
    if (!r) return "";
    for (int i = 0; i <= n; i++)
        r[i] = (s[i] >= 'a' && s[i] <= 'z') ? s[i] - 32 : s[i];
    return r;
}

char *seven_str_lower(const char *s) {
    int n = strlen(s);
    char *r = malloc(n + 1);
    if (!r) return "";
    for (int i = 0; i <= n; i++)
        r[i] = (s[i] >= 'A' && s[i] <= 'Z') ? s[i] + 32 : s[i];
    return r;
}

char *seven_str_trim(const char *s) {
    while (*s == ' ' || *s == '\t' || *s == '\n' || *s == '\r') s++;
    int n = strlen(s);
    while (n > 0 && (s[n-1] == ' ' || s[n-1] == '\t' || s[n-1] == '\n' || s[n-1] == '\r')) n--;
    char *r = malloc(n + 1);
    if (!r) return "";
    memcpy(r, s, n);
    r[n] = '\0';
    return r;
}

long long seven_str_contains(const char *haystack, const char *needle) {
    return strstr(haystack, needle) != 0;
}

char *seven_str_replace(const char *s, const char *old, const char *new_s) {
    int sl = strlen(s), ol = strlen(old), nl = strlen(new_s);
    char *found = strstr(s, old);
    if (!found) { char *r = malloc(sl + 1); if(r) memcpy(r, s, sl+1); return r ? r : ""; }
    int pos = found - s;
    char *r = malloc(sl - ol + nl + 1);
    if (!r) return "";
    memcpy(r, s, pos);
    memcpy(r + pos, new_s, nl);
    memcpy(r + pos + nl, s + pos + ol, sl - pos - ol + 1);
    return r;
}

char *seven_str_substr(const char *s, long long start, long long len) {
    int sl = strlen(s);
    if (start < 0) start = 0;
    if (start >= sl) { char *r = malloc(1); if(r) r[0]='\0'; return r ? r : ""; }
    if (start + len > sl) len = sl - start;
    char *r = malloc(len + 1);
    if (!r) return "";
    memcpy(r, s + start, len);
    r[len] = '\0';
    return r;
}

char *seven_str_char_at(const char *s, long long idx) {
    int sl = strlen(s);
    if (idx < 0 || idx >= sl) return "";
    char *r = malloc(2);
    if (!r) return "";
    r[0] = s[idx]; r[1] = '\0';
    return r;
}

char *seven_str_from_int(long long val) {
    char buf[32];
    int neg = val < 0;
    if (neg) val = -val;
    int i = 0;
    do { buf[i++] = '0' + (int)(val % 10); val /= 10; } while (val);
    if (neg) buf[i++] = '-';
    char *r = malloc(i + 1);
    if (!r) return "";
    for (int j = 0; j < i; j++) r[j] = buf[i - 1 - j];
    r[i] = '\0';
    return r;
}

long long seven_ord(const char *s) { return s[0]; }

char *seven_chr(long long code) {
    char *r = malloc(2);
    if (!r) return "";
    r[0] = (char)code; r[1] = '\0';
    return r;
}

// === Array functions ===

typedef struct { long long *data; int len; int cap; } SevenArray;

SevenArray *seven_arr_new(void) {
    SevenArray *a = malloc(sizeof(SevenArray));
    if (!a) return 0;
    a->data = malloc(16 * sizeof(long long));
    a->len = 0; a->cap = 16;
    return a;
}

long long seven_arr_len(SevenArray *a) { return a ? a->len : 0; }

void seven_arr_push(SevenArray *a, long long val) {
    if (!a) return;
    if (a->len >= a->cap) {
        int nc = a->cap * 2;
        long long *nd = malloc(nc * sizeof(long long));
        if (!nd) return;
        memcpy(nd, a->data, a->len * sizeof(long long));
        a->data = nd; a->cap = nc;
    }
    a->data[a->len++] = val;
}

long long seven_arr_get(SevenArray *a, long long idx) {
    if (!a || idx < 0 || idx >= a->len) return 0;
    return a->data[idx];
}

void seven_arr_set(SevenArray *a, long long idx, long long val) {
    if (!a || idx < 0 || idx >= a->len) return;
    a->data[idx] = val;
}

long long seven_arr_pop(SevenArray *a) {
    if (!a || a->len <= 0) return 0;
    return a->data[--a->len];
}

SevenArray *seven_arr_range(long long start, long long end, long long step) {
    SevenArray *a = seven_arr_new();
    if (!a || step == 0) return a;
    if (step > 0) { for (long long i = start; i < end; i += step) seven_arr_push(a, i); }
    else { for (long long i = start; i > end; i += step) seven_arr_push(a, i); }
    return a;
}

// === Math functions ===

long long seven_pow(long long b, long long e) {
    long long r = 1;
    while (e > 0) { if (e & 1) r *= b; b *= b; e >>= 1; }
    return r;
}

long long seven_abs_val(long long v) { return v < 0 ? -v : v; }
long long seven_clamp(long long v, long long lo, long long hi) { return v<lo?lo:v>hi?hi:v; }
long long seven_sign(long long v) { return v > 0 ? 1 : v < 0 ? -1 : 0; }

long long seven_gcd(long long a, long long b) {
    if (a < 0) a = -a; if (b < 0) b = -b;
    while (b) { long long t = b; b = a % b; a = t; } return a;
}

// === Conversion functions ===

char *seven_hex(long long val) {
    char buf[20]; int i = 0;
    if (val == 0) { buf[i++] = '0'; }
    else { unsigned long long v = val < 0 ? -val : val;
        while (v) { int d = v & 0xf; buf[i++] = d < 10 ? '0'+d : 'a'+d-10; v >>= 4; } }
    char *r = malloc(i + 1); if (!r) return "";
    for (int j = 0; j < i; j++) r[j] = buf[i-1-j]; r[i] = '\0';
    return r;
}

char *seven_bin(long long val) {
    char buf[68]; int i = 0;
    if (val == 0) { buf[i++] = '0'; }
    else { unsigned long long v = val < 0 ? -val : val;
        while (v) { buf[i++] = '0' + (v & 1); v >>= 1; } }
    char *r = malloc(i + 1); if (!r) return "";
    for (int j = 0; j < i; j++) r[j] = buf[i-1-j]; r[i] = '\0';
    return r;
}

long long seven_bool(long long v) { return v != 0; }

// === Print functions ===

void seven_print_int(long long val) { js_print_int(val); }
void seven_print_str(const char *s) { js_print_str(s, strlen(s)); }
void seven_print_nl(void) { js_print_nl(); }

void seven_show_int(long long val) { js_print_int(val); js_print_nl(); }
void seven_show_str(const char *s) { js_print_str(s, strlen(s)); js_print_nl(); }

// === Stubs for unavailable features ===
long long seven_time(void) { return 0; }
long long seven_clock_ns(void) { return 0; }
void seven_sleep(long long s) { (void)s; }
char *seven_env(const char *n) { (void)n; return ""; }
long long seven_system(const char *c) { (void)c; return -1; }
char *seven_ask(const char *prompt) { seven_print_str(prompt); return ""; }
int seven_file_exists(const char *p) { (void)p; return 0; }
char *seven_file_read(const char *p) { (void)p; return ""; }
void seven_file_write(const char *p, const char *d) { (void)p; (void)d; }
void seven_file_delete(const char *p) { (void)p; }
void seven_file_append(const char *p, const char *d) { (void)p; (void)d; }

void seven_assert(long long cond, const char *msg) {
    if (!cond) {
        js_print_str("Assertion failed: ", 18);
        js_print_str(msg, strlen(msg));
        js_print_nl();
    }
}
