#ifndef COLLECTNSAVE_H
#define COLLECTNSAVE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint8_t cns_path_type_t;
enum {
    CNS_PATH_TYPE_NA = 0,
    CNS_PATH_TYPE_EXTERNAL = 1,
    CNS_PATH_TYPE_INTERNAL = 3,
    CNS_PATH_TYPE_ABLETON_PLUGIN_DATA = 5,
    CNS_PATH_TYPE_USER_LIBRARY = 6,
    CNS_PATH_TYPE_ABLETON_BUILTIN = 7,
};

typedef uint8_t cns_save_command_t;
enum {
    CNS_SAVE_COMMAND_CHECK = 0,
    CNS_SAVE_COMMAND_SAVE = 1,
    CNS_SAVE_COMMAND_SAFE = 2,
    CNS_SAVE_COMMAND_INFO = 3,
    CNS_SAVE_COMMAND_XML = 4,
};

typedef uint8_t cns_file_state_t;
enum {
    CNS_FILE_STATE_MISSING = 0,
    CNS_FILE_STATE_FOUND = 1,
    CNS_FILE_STATE_COLLECTED = 2,
};

typedef uint8_t cns_collect_res_t;
enum {
    CNS_COLLECT_RES_OK = 0,
    CNS_COLLECT_RES_BAD_FILE = 1,
    CNS_COLLECT_RES_FAIL_COLLECT = 2,
    CNS_COLLECT_RES_IS_BACKUP = 3,
};

typedef struct CAbletonFile {
    const char *file_name;
    const char *file_path;
    uint64_t file_size;
    cns_path_type_t path_type;
} CAbletonFile;

typedef struct AbletonFiles {
    const CAbletonFile *files;
    size_t len;
} AbletonFiles;

typedef struct CollectSetRes {
    cns_collect_res_t err;
    size_t count;
} CollectSetRes;

void cns_free_files(AbletonFiles files);
AbletonFiles cns_collect_files(const char *ableton_set_path);
cns_collect_res_t cns_save_file(CAbletonFile file, bool dry_run);
bool cns_is_backup(const char *filepath);
CollectSetRes cns_collect_set(const char *filepath, cns_save_command_t cmd);

#ifdef __cplusplus
}
#endif

#endif
