#include "cia_core.h"
#include <stdio.h>
#include <string.h>
#define CHECK(expr) do { if (!(expr)) { fprintf(stderr, "failed: %s\n", #expr); return 1; } } while (0)

int main(int argc, char **argv) {
    CHECK(argc == 2);
    cia_core_result *result = NULL;
    CHECK(cia_core_scan(NULL, &result) == CIA_CORE_INVALID_ARGUMENT);
    CHECK(result == NULL);
    CHECK(cia_core_scan(argv[1], NULL) == CIA_CORE_INVALID_ARGUMENT);
    /* The running executable is a file, not a scan directory. */
    CHECK(cia_core_scan(argv[0], &result) == CIA_CORE_SCAN_FAILED);
    CHECK(result == NULL);
    cia_core_result_destroy(NULL);
    for (int i = 0; i < 2; ++i) {
        CHECK(cia_core_scan(argv[1], &result) == CIA_CORE_OK);
        CHECK(result != NULL);
        CHECK(cia_core_result_file_count(result) == 2);
        CHECK(cia_core_result_total_lines(result) == 2);
        CHECK(cia_core_result_warning_count(result) == 0);
        cia_core_file file;
        CHECK(cia_core_result_file(result, 0, &file) == CIA_CORE_OK);
        CHECK(file.path_length == 5 && memcmp(file.path, "a.zig", 5) == 0);
        CHECK(file.lines == 2);
        CHECK(cia_core_result_file(result, 1, &file) == CIA_CORE_OK);
        CHECK(file.path_length == 9 && memcmp(file.path, "empty.zig", 9) == 0);
        CHECK(file.lines == 0);
        CHECK(cia_core_result_file(result, 2, &file) == CIA_CORE_INVALID_ARGUMENT);
        CHECK(file.path == NULL && file.path_length == 0);
        CHECK(cia_core_result_file(result, 0, NULL) == CIA_CORE_INVALID_ARGUMENT);
        cia_core_result_destroy(result);
        result = NULL;
    }
    return 0;
}
