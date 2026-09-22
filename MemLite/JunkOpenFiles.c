#include <libproc.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

char *MemLiteCopyOpenFilePaths(void) {
    int listed = proc_listallpids(NULL, 0);
    if (listed <= 0) {
        return strdup("");
    }

    pid_t *pids = calloc((size_t)listed, sizeof(pid_t));
    if (pids == NULL) {
        return strdup("");
    }

    int count = proc_listallpids(pids, listed * (int)sizeof(pid_t));
    if (count < 0) {
        count = 0;
    }

    size_t capacity = 4096;
    size_t used = 0;
    char *output = malloc(capacity);
    if (output == NULL) {
        free(pids);
        return NULL;
    }
    output[0] = '\0';

    pid_t self = getpid();
    for (int index = 0; index < count; index++) {
        pid_t pid = pids[index];
        if (pid == 0 || pid == self) {
            continue;
        }

        int bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
        if (bufferSize <= 0) {
            continue;
        }

        struct proc_fdinfo *descriptors = malloc((size_t)bufferSize);
        if (descriptors == NULL) {
            continue;
        }

        int received = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, descriptors, bufferSize);
        int descriptorCount = received / (int)sizeof(struct proc_fdinfo);
        for (int descriptorIndex = 0; descriptorIndex < descriptorCount; descriptorIndex++) {
            if (descriptors[descriptorIndex].proc_fdtype != PROX_FDTYPE_VNODE) {
                continue;
            }

            struct vnode_fdinfowithpath info;
            memset(&info, 0, sizeof(info));
            int infoSize = proc_pidfdinfo(
                pid,
                descriptors[descriptorIndex].proc_fd,
                PROC_PIDFDVNODEPATHINFO,
                &info,
                sizeof(info)
            );
            if (infoSize <= 0 || info.pvip.vip_path[0] == '\0') {
                continue;
            }

            size_t length = strnlen(info.pvip.vip_path, sizeof(info.pvip.vip_path));
            if (used + length + 2 > capacity) {
                size_t grownCapacity = (used + length + 2) * 2;
                char *grown = realloc(output, grownCapacity);
                if (grown == NULL) {
                    continue;
                }
                output = grown;
                capacity = grownCapacity;
            }
            memcpy(output + used, info.pvip.vip_path, length);
            used += length;
            output[used++] = '\n';
            output[used] = '\0';
        }
        free(descriptors);
    }

    free(pids);
    return output;
}
