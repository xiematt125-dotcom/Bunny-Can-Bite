#ifndef C_MEMORY_H
#define C_MEMORY_H
#include <stdint.h>
#include <stddef.h>

typedef struct {
    uint64_t total_bytes;
    uint64_t page_size;
    uint64_t internal_pages;
    uint64_t purgeable_pages;
    uint64_t wired_pages;
    uint64_t compressed_pages;
    uint64_t external_pages;
    uint64_t free_pages;
    uint64_t swap_used_bytes;
    uint64_t swap_total_bytes;
    int pressure_level;
    int pressure_available;
    int swap_available;
} CMGlobalMemory;

typedef struct {
    int32_t pid;
    int32_t parent_pid;
    uint64_t memory_bytes;
    int metric; /* 1 = physical footprint, 2 = resident size, 0 = unavailable */
    uint64_t start_seconds;
    uint64_t start_microseconds;
    int identity_available;
    int is_system;
    char name[256];
    char path[4096];
} CMProcess;

typedef struct {
    uint64_t start_seconds;
    uint64_t start_microseconds;
    int is_zombie;
    int is_system;
    char name[256];
    char path[4096];
} CMProcessState;

#define CM_TERMINATION_IDENTITY_CHANGED -1
#define CM_TERMINATION_PROTECTED -2

/* Return 0 or a positive errno. These functions never launch subprocesses. */
int cm_read_process_state(int32_t pid, CMProcessState *result);
/* Revalidate identity immediately before SIGKILL. Negative codes above are app policy results. */
int cm_force_quit(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds);

/* Return 0 on success; caller owns the copied process buffer. */
int cm_read_global(CMGlobalMemory *result);
CMProcess *cm_copy_processes(size_t *count, int *error_code);
void cm_free_processes(CMProcess *processes);
int cm_read_string(const char *key, char *buffer, size_t capacity);
#endif
