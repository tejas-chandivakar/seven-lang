// ============================================================
// SEVEN Language — C Runtime Library Implementation
// ============================================================

#include "llvm_runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <time.h>
#include <unistd.h>
#include <sys/stat.h>

// ---- String functions ----

char *seven_str_new(const char *s) {
    return strdup(s ? s : "");
}

char *seven_str_concat(const char *a, const char *b) {
    if (!a) a = "";
    if (!b) b = "";
    size_t la = strlen(a), lb = strlen(b);
    char *r = malloc(la + lb + 1);
    memcpy(r, a, la);
    memcpy(r + la, b, lb);
    r[la + lb] = '\0';
    return r;
}

int64_t seven_str_len(const char *s) {
    return s ? (int64_t)strlen(s) : 0;
}

int64_t seven_str_equal(const char *a, const char *b) {
    if (!a || !b) return a == b;
    return strcmp(a, b) == 0 ? 1 : 0;
}

char *seven_str_from_int(int64_t n) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%lld", (long long)n);
    return strdup(buf);
}

int64_t seven_str_to_int(const char *s) {
    return s ? atoll(s) : 0;
}

char *seven_str_upper(const char *s) {
    if (!s) return strdup("");
    char *r = strdup(s);
    for (int i = 0; r[i]; i++) r[i] = toupper(r[i]);
    return r;
}

char *seven_str_lower(const char *s) {
    if (!s) return strdup("");
    char *r = strdup(s);
    for (int i = 0; r[i]; i++) r[i] = tolower(r[i]);
    return r;
}

char *seven_str_trim(const char *s) {
    if (!s) return strdup("");
    while (*s && isspace(*s)) s++;
    size_t len = strlen(s);
    while (len > 0 && isspace(s[len - 1])) len--;
    char *r = malloc(len + 1);
    memcpy(r, s, len);
    r[len] = '\0';
    return r;
}

int64_t seven_str_contains(const char *haystack, const char *needle) {
    if (!haystack || !needle) return 0;
    return strstr(haystack, needle) ? 1 : 0;
}

char *seven_str_replace(const char *s, const char *old, const char *new_s) {
    if (!s || !old || !new_s) return strdup(s ? s : "");
    size_t slen = strlen(s), olen = strlen(old), nlen = strlen(new_s);
    if (olen == 0) return strdup(s);

    // Count occurrences
    int count = 0;
    const char *p = s;
    while ((p = strstr(p, old))) { count++; p += olen; }

    char *result = malloc(slen + count * (nlen - olen) + 1);
    char *dst = result;
    p = s;
    while (*p) {
        if (strncmp(p, old, olen) == 0) {
            memcpy(dst, new_s, nlen);
            dst += nlen;
            p += olen;
        } else {
            *dst++ = *p++;
        }
    }
    *dst = '\0';
    return result;
}

char *seven_str_substr(const char *s, int64_t start, int64_t len) {
    if (!s) return strdup("");
    int64_t slen = strlen(s);
    if (start < 0) start = slen + start;
    if (start < 0) start = 0;
    if (start >= slen) return strdup("");
    if (len < 0 || start + len > slen) len = slen - start;
    char *r = malloc(len + 1);
    memcpy(r, s + start, len);
    r[len] = '\0';
    return r;
}

int64_t seven_str_find(const char *s, const char *sub) {
    if (!s || !sub) return -1;
    const char *p = strstr(s, sub);
    return p ? (int64_t)(p - s) : -1;
}

int64_t seven_str_count(const char *s, const char *sub) {
    if (!s || !sub || !*sub) return 0;
    int64_t count = 0;
    size_t sublen = strlen(sub);
    const char *p = s;
    while ((p = strstr(p, sub))) { count++; p += sublen; }
    return count;
}

char *seven_str_pad(const char *s, int64_t width, const char *ch) {
    if (!s) s = "";
    if (!ch || !*ch) ch = " ";
    int64_t slen = strlen(s);
    if (slen >= width) return strdup(s);
    int64_t pad = width - slen;
    char *r = malloc(width + 1);
    for (int64_t i = 0; i < pad; i++) r[i] = ch[0];
    memcpy(r + pad, s, slen);
    r[width] = '\0';
    return r;
}

int64_t seven_ord(const char *s) {
    return (s && *s) ? (int64_t)(unsigned char)s[0] : 0;
}

char *seven_chr(int64_t code) {
    char *r = malloc(2);
    r[0] = (char)code;
    r[1] = '\0';
    return r;
}

char *seven_str_char_at(const char *s, int64_t idx) {
    if (!s) return strdup("");
    int64_t len = strlen(s);
    if (idx < 0) idx = len + idx;
    if (idx < 0 || idx >= len) return strdup("");
    char *r = malloc(2);
    r[0] = s[idx];
    r[1] = '\0';
    return r;
}

// ---- Array functions ----
// Layout: [count, capacity, elem0, elem1, ...]

int64_t *seven_arr_new(void) {
    int64_t *arr = malloc(sizeof(int64_t) * 18);
    arr[0] = 0;   // count
    arr[1] = 16;  // capacity
    return arr;
}

int64_t seven_arr_len(int64_t *arr) {
    return arr ? arr[0] : 0;
}

void seven_arr_push(int64_t *arr, int64_t val) {
    if (!arr) return;
    int64_t count = arr[0];
    int64_t cap = arr[1];
    if (count >= cap) {
        // Can't realloc in-place with this design, so just use large initial
        // For now, cap at capacity
        return;
    }
    arr[2 + count] = val;
    arr[0] = count + 1;
}

int64_t seven_arr_pop(int64_t *arr) {
    if (!arr || arr[0] == 0) return 0;
    arr[0]--;
    return arr[2 + arr[0]];
}

int64_t seven_arr_get(int64_t *arr, int64_t idx) {
    if (!arr) return 0;
    int64_t count = arr[0];
    if (idx < 0) idx = count + idx;
    if (idx < 0 || idx >= count) return 0;
    return arr[2 + idx];
}

void seven_arr_set(int64_t *arr, int64_t idx, int64_t val) {
    if (!arr) return;
    int64_t count = arr[0];
    if (idx < 0) idx = count + idx;
    if (idx < 0 || idx >= count) return;
    arr[2 + idx] = val;
}

int64_t *seven_arr_slice(int64_t *arr, int64_t start, int64_t end) {
    int64_t *r = seven_arr_new();
    if (!arr) return r;
    int64_t count = arr[0];
    if (start < 0) start = count + start;
    if (end < 0) end = count + end;
    if (start < 0) start = 0;
    if (end > count) end = count;
    for (int64_t i = start; i < end; i++)
        seven_arr_push(r, arr[2 + i]);
    return r;
}

int64_t *seven_arr_concat(int64_t *a, int64_t *b) {
    int64_t *r = seven_arr_new();
    if (a) for (int64_t i = 0; i < a[0]; i++) seven_arr_push(r, a[2 + i]);
    if (b) for (int64_t i = 0; i < b[0]; i++) seven_arr_push(r, b[2 + i]);
    return r;
}

static int cmp_int64(const void *a, const void *b) {
    int64_t x = *(const int64_t *)a, y = *(const int64_t *)b;
    return (x > y) - (x < y);
}

void seven_arr_sort(int64_t *arr) {
    if (!arr || arr[0] < 2) return;
    qsort(&arr[2], arr[0], sizeof(int64_t), cmp_int64);
}

void seven_arr_reverse(int64_t *arr) {
    if (!arr || arr[0] < 2) return;
    int64_t n = arr[0];
    for (int64_t i = 0; i < n / 2; i++) {
        int64_t tmp = arr[2 + i];
        arr[2 + i] = arr[2 + n - 1 - i];
        arr[2 + n - 1 - i] = tmp;
    }
}

char *seven_arr_join(int64_t *arr, const char *sep) {
    if (!arr || arr[0] == 0) return strdup("");
    if (!sep) sep = "";
    size_t seplen = strlen(sep);
    char buf[65536];
    int pos = 0;
    for (int64_t i = 0; i < arr[0]; i++) {
        if (i > 0 && seplen > 0) {
            memcpy(buf + pos, sep, seplen);
            pos += seplen;
        }
        pos += snprintf(buf + pos, sizeof(buf) - pos, "%lld", (long long)arr[2 + i]);
    }
    buf[pos] = '\0';
    return strdup(buf);
}

int64_t *seven_arr_range(int64_t start, int64_t end, int64_t step) {
    int64_t *r = seven_arr_new();
    if (step == 0) step = 1;
    if (step > 0) {
        for (int64_t i = start; i < end; i += step) seven_arr_push(r, i);
    } else {
        for (int64_t i = start; i > end; i += step) seven_arr_push(r, i);
    }
    return r;
}

int64_t seven_arr_find(int64_t *arr, int64_t val) {
    if (!arr) return -1;
    for (int64_t i = 0; i < arr[0]; i++)
        if (arr[2 + i] == val) return i;
    return -1;
}

int64_t *seven_arr_unique(int64_t *arr) {
    int64_t *r = seven_arr_new();
    if (!arr) return r;
    for (int64_t i = 0; i < arr[0]; i++) {
        if (seven_arr_find(r, arr[2 + i]) == -1)
            seven_arr_push(r, arr[2 + i]);
    }
    return r;
}

int64_t *seven_arr_fill(int64_t count, int64_t val) {
    int64_t *r = seven_arr_new();
    for (int64_t i = 0; i < count; i++) seven_arr_push(r, val);
    return r;
}

void seven_arr_insert(int64_t *arr, int64_t idx, int64_t val) {
    if (!arr) return;
    int64_t count = arr[0];
    if (idx < 0 || idx > count || count >= arr[1]) return;
    for (int64_t i = count; i > idx; i--)
        arr[2 + i] = arr[2 + i - 1];
    arr[2 + idx] = val;
    arr[0]++;
}

void seven_arr_remove(int64_t *arr, int64_t idx) {
    if (!arr) return;
    int64_t count = arr[0];
    if (idx < 0) idx = count + idx;
    if (idx < 0 || idx >= count) return;
    for (int64_t i = idx; i < count - 1; i++)
        arr[2 + i] = arr[2 + i + 1];
    arr[0]--;
}

// ---- Math functions ----

int64_t seven_pow(int64_t base, int64_t exp) {
    if (exp < 0) return 0;
    int64_t result = 1;
    while (exp > 0) {
        if (exp & 1) result *= base;
        base *= base;
        exp >>= 1;
    }
    return result;
}

int64_t seven_clamp(int64_t val, int64_t lo, int64_t hi) {
    if (val < lo) return lo;
    if (val > hi) return hi;
    return val;
}

int64_t seven_sign(int64_t n) {
    if (n > 0) return 1;
    if (n < 0) return -1;
    return 0;
}

int64_t seven_gcd(int64_t a, int64_t b) {
    if (a < 0) a = -a;
    if (b < 0) b = -b;
    while (b) { int64_t t = b; b = a % b; a = t; }
    return a;
}

int64_t seven_sum(int64_t *arr) {
    if (!arr) return 0;
    int64_t s = 0;
    for (int64_t i = 0; i < arr[0]; i++) s += arr[2 + i];
    return s;
}

int64_t seven_avg(int64_t *arr) {
    if (!arr || arr[0] == 0) return 0;
    return seven_sum(arr) / arr[0];
}

int64_t seven_abs_val(int64_t n) {
    return n < 0 ? -n : n;
}

// ---- Conversion ----

char *seven_hex(int64_t n) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%llx", (long long)n);
    return strdup(buf);
}

char *seven_bin(int64_t n) {
    if (n == 0) return strdup("0");
    char buf[65];
    int pos = 64;
    buf[pos] = '\0';
    uint64_t u = (uint64_t)n;
    while (u > 0) {
        buf[--pos] = '0' + (u & 1);
        u >>= 1;
    }
    return strdup(&buf[pos]);
}

int64_t seven_bool(int64_t val) {
    return val ? 1 : 0;
}

int64_t seven_number(const char *s) {
    return s ? atoll(s) : 0;
}

// ---- File I/O ----

int64_t seven_file_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 ? 1 : 0;
}

void seven_file_write(const char *path, const char *data) {
    FILE *f = fopen(path, "w");
    if (f) { fputs(data ? data : "", f); fclose(f); }
}

char *seven_file_read(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return strdup("");
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc(len + 1);
    size_t read = fread(buf, 1, len, f);
    buf[read] = '\0';
    fclose(f);
    return buf;
}

void seven_file_append(const char *path, const char *data) {
    FILE *f = fopen(path, "a");
    if (f) { fputs(data ? data : "", f); fclose(f); }
}

void seven_file_delete(const char *path) {
    remove(path);
}

// ---- OS/System ----

int64_t seven_time(void) {
    return (int64_t)time(NULL);
}

int64_t seven_clock_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

void seven_sleep(int64_t seconds) {
    sleep((unsigned)seconds);
}

char *seven_env(const char *name) {
    const char *val = getenv(name);
    return strdup(val ? val : "");
}

int64_t seven_system(const char *cmd) {
    return (int64_t)system(cmd);
}

// ---- I/O ----

char *seven_ask(const char *prompt) {
    if (prompt) printf("%s", prompt);
    fflush(stdout);
    char buf[4096];
    if (!fgets(buf, sizeof(buf), stdin)) return strdup("");
    size_t len = strlen(buf);
    if (len > 0 && buf[len - 1] == '\n') buf[len - 1] = '\0';
    return strdup(buf);
}

void seven_show_int(int64_t val) {
    printf("%lld\n", (long long)val);
}

void seven_show_str(const char *s) {
    printf("%s\n", s ? s : "");
}
