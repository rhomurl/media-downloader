#include "ProcessFixtureSupport.h"
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <stdio.h>

void fixture_fork_hold(int orphan) {
    int ready[2];
    if (pipe(ready) != 0) _exit(91);
    pid_t child = fork();
    if (child == 0) {
        close(ready[0]);
        signal(SIGTERM, SIG_IGN);
        char marker = 1;
        while (write(ready[1], &marker, 1) < 0 && errno == EINTR) {}
        close(ready[1]);
        for (;;) pause();
    }
    if (child < 0) _exit(92);
    close(ready[1]);
    char marker;
    while (read(ready[0], &marker, 1) < 0 && errno == EINTR) {}
    close(ready[0]);
    char output[32];
    int length = snprintf(output, sizeof(output), "%d\n", child);
    int offset = 0;
    while (offset < length) {
        ssize_t count = write(STDOUT_FILENO, output + offset, length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) _exit(94);
        offset += (int)count;
    }
    if (orphan) _exit(0);
    for (;;) pause();
}

#include <libproc.h>
#include <sys/proc_info.h>

void fixture_closed_output_group(int hold) {
    for (int index = 0; index < 32; index++) {
        int ready[2];
        if (pipe(ready) != 0) _exit(96);
        pid_t child = fork();
        if (child == 0) {
            close(ready[0]);
            close(STDIN_FILENO);
            close(STDOUT_FILENO);
            close(STDERR_FILENO);
            signal(SIGTERM, SIG_IGN);
            char marker = 1;
            while (write(ready[1], &marker, 1) < 0 && errno == EINTR) {}
            close(ready[1]);
            for (;;) {}
        }
        if (child < 0) _exit(97);
        close(ready[1]);
        char marker;
        while (read(ready[0], &marker, 1) < 0 && errno == EINTR) {}
        close(ready[0]);
        char output[32];
        int length = snprintf(output, sizeof(output), "%d\n", child);
        int offset = 0;
        while (offset < length) {
            ssize_t count = write(STDOUT_FILENO, output + offset, length - offset);
            if (count < 0 && errno == EINTR) continue;
            if (count <= 0) _exit(98);
            offset += (int)count;
        }
    }
    if (hold) { for (;;) pause(); }
    _exit(0);
}

int fixture_process_status(int pid) {
    struct proc_bsdinfo info;
    errno = 0;
    int bytes = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info));
    if (bytes == sizeof(info)) return (int)info.pbi_status;
    if (bytes == 0 && errno == ESRCH) return 0;
    return -(errno ? errno : EIO);
}
