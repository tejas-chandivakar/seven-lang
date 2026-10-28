// ============================================================
// SEVEN Language — C Runtime Library (for LLVM backend)
// Handles strings, arrays, and stdlib functions
// ============================================================
#ifndef SEVEN_RUNTIME_H
#define SEVEN_RUNTIME_H

#include <stdint.h>

// Tagged value: bit 0 = 1 means pointer (string/array), 0 means integer
// We use a simpler approach: all values are int64_t
// Strings are heap-allocated, tracked separately

// ---- String functions ----
char *seven_str_new(const char *s);
char *seven_str_concat(const char *a, const char *b);
int64_t seven_str_len(const char *s);
int64_t seven_str_equal(const char *a, const char *b);
char *seven_str_from_int(int64_t n);
int64_t seven_str_to_int(const char *s);
char *seven_str_upper(const char *s);
char *seven_str_lower(const char *s);
char *seven_str_trim(const char *s);
int64_t seven_str_contains(const char *haystack, const char *needle);
char *seven_str_replace(const char *s, const char *old, const char *new_s);
char *seven_str_substr(const char *s, int64_t start, int64_t len);
int64_t seven_str_find(const char *s, const char *sub);
int64_t seven_str_count(const char *s, const char *sub);
char *seven_str_pad(const char *s, int64_t width, const char *ch);
int64_t seven_ord(const char *s);
char *seven_chr(int64_t code);
char *seven_str_char_at(const char *s, int64_t idx);

// ---- Array functions ----
// Arrays: [count, capacity, elem0, elem1, ...]
// Stored as int64_t* on heap
int64_t *seven_arr_new(void);
int64_t seven_arr_len(int64_t *arr);
void seven_arr_push(int64_t *arr, int64_t val);
int64_t seven_arr_pop(int64_t *arr);
int64_t seven_arr_get(int64_t *arr, int64_t idx);
void seven_arr_set(int64_t *arr, int64_t idx, int64_t val);
int64_t *seven_arr_slice(int64_t *arr, int64_t start, int64_t end);
int64_t *seven_arr_concat(int64_t *a, int64_t *b);
void seven_arr_sort(int64_t *arr);
void seven_arr_reverse(int64_t *arr);
char *seven_arr_join(int64_t *arr, const char *sep);
int64_t *seven_arr_range(int64_t start, int64_t end, int64_t step);
int64_t seven_arr_find(int64_t *arr, int64_t val);
int64_t *seven_arr_unique(int64_t *arr);
int64_t *seven_arr_fill(int64_t count, int64_t val);
void seven_arr_insert(int64_t *arr, int64_t idx, int64_t val);
void seven_arr_remove(int64_t *arr, int64_t idx);

// ---- Math functions ----
int64_t seven_pow(int64_t base, int64_t exp);
int64_t seven_clamp(int64_t val, int64_t lo, int64_t hi);
int64_t seven_sign(int64_t n);
int64_t seven_gcd(int64_t a, int64_t b);
int64_t seven_sum(int64_t *arr);
int64_t seven_avg(int64_t *arr);
int64_t seven_abs_val(int64_t n);

// ---- Conversion ----
char *seven_hex(int64_t n);
char *seven_bin(int64_t n);
int64_t seven_bool(int64_t val);
int64_t seven_number(const char *s);

// ---- File I/O ----
int64_t seven_file_exists(const char *path);
void seven_file_write(const char *path, const char *data);
char *seven_file_read(const char *path);
void seven_file_append(const char *path, const char *data);
void seven_file_delete(const char *path);

// ---- OS/System ----
int64_t seven_time(void);
int64_t seven_clock_ns(void);
void seven_sleep(int64_t seconds);
char *seven_env(const char *name);
int64_t seven_system(const char *cmd);

// ---- I/O ----
char *seven_ask(const char *prompt);
void seven_show_int(int64_t val);
void seven_show_str(const char *s);

#endif
