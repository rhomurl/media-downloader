#include "ProcessSupervision.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/proc.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>

// Fixed memory bound. A larger group fails closed instead of truncating a list.
#define MD_MAX_GROUP_MEMBERS 4096

static int pid_order(const void *a, const void *b) {
    pid_t lhs = *(const pid_t *)a;
    pid_t rhs = *(const pid_t *)b;
    return (lhs > rhs) - (lhs < rhs);
}

static int group_snapshot(pid_t pgid, pid_t *pids) {
    errno = 0;
    int capacity = MD_MAX_GROUP_MEMBERS * (int)sizeof(pid_t);
    // Unlike proc_listpids, this convenience API returns a PID COUNT.
    int count = proc_listpgrppids(pgid, pids, capacity);
    if (count < 0 || (count == 0 && errno != 0)) return -1;
    if (count >= MD_MAX_GROUP_MEMBERS) { errno = ENOBUFS; return -1; }
    qsort(pids, count, sizeof(pid_t), pid_order);
    return count;
}

int md_group_is_quiescent(pid_t pgid) {
    pid_t first[MD_MAX_GROUP_MEMBERS];
    pid_t second[MD_MAX_GROUP_MEMBERS];
    int count = group_snapshot(pgid, first);
    if (count < 0) return -1;
    for (int index = 0; index < count; index++) {
        struct proc_bsdinfo info;
        errno = 0;
        int bytes = proc_pidinfo(first[index], PROC_PIDTBSDINFO, 0, &info, sizeof(info));
        if (bytes == 0 && errno == ESRCH) continue;
        if (bytes != sizeof(info)) { if (errno == 0) errno = EIO; return -1; }
        // A listed process can disappear and its PID be reused in another group.
        if (info.pbi_pgid != (uint32_t)pgid) continue;
        if (info.pbi_status != SZOMB) return 0;
    }
    // A live member might have forked between enumeration and being observed
    // dead. Require stable membership after observing every member quiescent.
    int second_count = group_snapshot(pgid, second);
    if (second_count < 0) return -1;
    if (second_count != count) return 0;
    return memcmp(first, second, count * sizeof(pid_t)) == 0;
}
