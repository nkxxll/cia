#ifndef CIA_CORE_H
#define CIA_CORE_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct cia_core_result cia_core_result;
typedef int cia_core_status;
enum {
    CIA_CORE_OK = 0,
    CIA_CORE_INVALID_ARGUMENT = 1,
    CIA_CORE_OUT_OF_MEMORY = 2,
    CIA_CORE_SCAN_FAILED = 3
};

typedef struct cia_core_file {
    /* Borrowed relative path bytes, NOT NUL-terminated. Valid until result destruction. */
    const unsigned char *path;
    size_t path_length;
    size_t lines;
} cia_core_file;

/* Synchronous scan of a NUL-terminated filesystem path. Run on a UI worker thread.
 * On success the caller owns *out_result; on failure it is NULL.
 * Currently scans .zig files only. Per-file failures increment warning_count.
 * This C adapter does not yet expose cancellation; Zig clients use scanCancelable. */
cia_core_status cia_core_scan(const char *path, cia_core_result **out_result);
/* Accepts NULL. Never destroy while another thread reads this result. */
void cia_core_result_destroy(cia_core_result *result);
/* Accessors require a valid, live result. Immutable results may be read concurrently. */
size_t cia_core_result_file_count(const cia_core_result *result);
size_t cia_core_result_total_lines(const cia_core_result *result);
size_t cia_core_result_warning_count(const cia_core_result *result);
/* Returns INVALID_ARGUMENT for an invalid index or NULL out_file. */
cia_core_status cia_core_result_file(const cia_core_result *result, size_t index,
                                     cia_core_file *out_file);
#ifdef __cplusplus
}
#endif
#endif
