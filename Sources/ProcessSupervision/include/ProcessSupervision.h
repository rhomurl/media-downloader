#include <sys/types.h>
// 1: quiescent; 0: live/changing membership; -1: inspection failed (errno).
int md_group_is_quiescent(pid_t pgid);
