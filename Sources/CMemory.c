#include "CMemory.h"
#include <errno.h>
#include <libproc.h>
#include <mach/mach.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/proc_info.h>
#include <sys/proc.h>
#include <sys/resource.h>
#include <sys/sysctl.h>
#include <unistd.h>

int cm_read_global(CMGlobalMemory *result) {
    memset(result, 0, sizeof(*result));
    size_t size = sizeof(result->total_bytes);
    if (sysctlbyname("hw.memsize", &result->total_bytes, &size, NULL, 0) != 0) return errno;
    vm_statistics64_data_t vm = {0};
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    mach_port_t host = mach_host_self();
    vm_size_t page_size = 0;
    kern_return_t status = host_page_size(host, &page_size);
    if (status == KERN_SUCCESS) {
        status = host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &count);
    }
    mach_port_deallocate(mach_task_self(), host);
    if (status != KERN_SUCCESS || page_size == 0) return EIO;
    result->page_size = page_size;
    result->internal_pages = vm.internal_page_count;
    result->purgeable_pages = vm.purgeable_count;
    result->wired_pages = vm.wire_count;
    result->compressed_pages = vm.compressor_page_count;
    result->external_pages = vm.external_page_count;
    /* The SDK explicitly says free_count already includes speculative_count. */
    result->free_pages = vm.free_count;
    size = sizeof(result->pressure_level);
    result->pressure_available = sysctlbyname("kern.memorystatus_vm_pressure_level", &result->pressure_level, &size, NULL, 0) == 0;
    struct xsw_usage swap = {0};
    size = sizeof(swap);
    result->swap_available = sysctlbyname("vm.swapusage", &swap, &size, NULL, 0) == 0;
    if (result->swap_available) {
        result->swap_used_bytes = swap.xsu_used;
        result->swap_total_bytes = swap.xsu_total;
    }
    return 0;
}

CMProcess *cm_copy_processes(size_t *count, int *error_code) {
    *count = 0;
    *error_code = 0;
    int estimate = proc_listallpids(NULL, 0);
    if (estimate <= 0) { *error_code = errno ? errno : EIO; return NULL; }
    int capacity = estimate + 256;
    pid_t *pids = NULL;
    int returned = 0;
    for (int attempt = 0; attempt < 3; attempt++) {
        free(pids);
        pids = calloc((size_t)capacity, sizeof(pid_t));
        if (!pids) { *error_code = ENOMEM; return NULL; }
        returned = proc_listallpids(pids, capacity * (int)sizeof(pid_t));
        if (returned < 0) { *error_code = errno ? errno : EIO; free(pids); return NULL; }
        if (returned < capacity) break;
        if (attempt == 2) { *error_code = EOVERFLOW; free(pids); return NULL; }
        capacity *= 2;
    }
    CMProcess *results = calloc((size_t)(returned > 0 ? returned : 1), sizeof(CMProcess));
    if (!results) { *error_code = ENOMEM; free(pids); return NULL; }
    for (int i = 0; i < returned; i++) {
        pid_t pid = pids[i];
        if (pid <= 0) continue;
        CMProcess item = {0};
        item.pid = pid;
        struct proc_bsdinfo bsd = {0};
        int bsd_size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd));
        if (bsd_size == sizeof(bsd)) {
            item.parent_pid = (int32_t)bsd.pbi_ppid;
            item.start_seconds = bsd.pbi_start_tvsec;
            item.start_microseconds = bsd.pbi_start_tvusec;
            item.identity_available = bsd.pbi_start_tvsec > 0;
            item.is_system = (bsd.pbi_flags & PROC_FLAG_SYSTEM) != 0;
            if (bsd.pbi_name[0]) {
                memcpy(item.name, bsd.pbi_name, sizeof(bsd.pbi_name));
            } else {
                memcpy(item.name, bsd.pbi_comm, sizeof(bsd.pbi_comm));
            }
        } else {
            proc_name(pid, item.name, sizeof(item.name));
        }
        proc_pidpath(pid, item.path, sizeof(item.path));
        struct rusage_info_v2 usage = {0};
        if (proc_pid_rusage(pid, RUSAGE_INFO_V2, (rusage_info_t *)&usage) == 0) {
            item.memory_bytes = usage.ri_phys_footprint;
            item.metric = 1;
        } else {
            struct proc_taskinfo task = {0};
            if (proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, sizeof(task)) == sizeof(task)) {
                item.memory_bytes = task.pti_resident_size;
                item.metric = 2;
            }
        }
        /* Omit only a process that demonstrably exited, never an access denial. */
        if (bsd_size != sizeof(bsd) && !item.path[0] && !item.name[0] && item.metric == 0) {
            if (kill(pid, 0) == -1 && errno == ESRCH) continue;
        }
        results[(*count)++] = item;
    }
    free(pids);
    return results;
}

static int cm_read_bsd(int32_t pid, struct proc_bsdinfo *bsd) {
    if (pid <= 0) return EINVAL;
    memset(bsd, 0, sizeof(*bsd));
    errno = 0;
    int received = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, bsd, sizeof(*bsd));
    if (received != sizeof(*bsd)) {
        int saved_error = errno;
        /* Access denial is not proof of exit. Only ESRCH establishes absence. */
        if (kill(pid, 0) == -1 && errno == ESRCH) return ESRCH;
        return saved_error ? saved_error : EIO;
    }
    return 0;
}

int cm_read_process_state(int32_t pid, CMProcessState *result) {
    if (!result) return EINVAL;
    memset(result, 0, sizeof(*result));
    struct proc_bsdinfo bsd;
    int error = cm_read_bsd(pid, &bsd);
    if (error) return error;
    result->start_seconds = bsd.pbi_start_tvsec;
    result->start_microseconds = bsd.pbi_start_tvusec;
    result->is_zombie = bsd.pbi_status == SZOMB;
    result->is_system = (bsd.pbi_flags & PROC_FLAG_SYSTEM) != 0;
    if (bsd.pbi_name[0]) memcpy(result->name, bsd.pbi_name, sizeof(bsd.pbi_name));
    else memcpy(result->name, bsd.pbi_comm, sizeof(bsd.pbi_comm));
    proc_pidpath(pid, result->path, sizeof(result->path));
    return 0;
}

static int cm_critical_name(const char *name) {
    return strcasecmp(name, "loginwindow") == 0 || strcasecmp(name, "WindowServer") == 0
        || strcasecmp(name, "kernel_task") == 0 || strcasecmp(name, "launchd") == 0;
}

int cm_force_quit(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds) {
    if (pid <= 1 || pid == getpid()) return CM_TERMINATION_PROTECTED;
    if (start_seconds == 0 || start_microseconds >= 1000000) return CM_TERMINATION_IDENTITY_CHANGED;
    struct proc_bsdinfo bsd;
    int error = cm_read_bsd(pid, &bsd);
    if (error) return error;
    if (bsd.pbi_start_tvsec != start_seconds || bsd.pbi_start_tvusec != start_microseconds)
        return CM_TERMINATION_IDENTITY_CHANGED;
    if ((bsd.pbi_flags & PROC_FLAG_SYSTEM) || cm_critical_name(bsd.pbi_name) || cm_critical_name(bsd.pbi_comm))
        return CM_TERMINATION_PROTECTED;
    if (bsd.pbi_status == SZOMB) return ESRCH;
    /* Public kill(2) has no atomic start-time argument. Keep the final identity
       check next to the signal; never retry a failed signal against another PID. */
    return kill(pid, SIGKILL) == 0 ? 0 : errno;
}

void cm_free_processes(CMProcess *processes) { free(processes); }
int cm_read_string(const char *key, char *buffer, size_t capacity) {
    if (capacity == 0) return EINVAL;
    memset(buffer, 0, capacity);
    size_t size = capacity - 1;
    return sysctlbyname(key, buffer, &size, NULL, 0) == 0 ? 0 : errno;
}
