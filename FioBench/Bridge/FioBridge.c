#include "FioBridge.h"

#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <unistd.h>

#if __has_include(<sys/disk.h>)
#include <sys/disk.h>
#define FB_HAS_SYS_DISK 1
#else
#define FB_HAS_SYS_DISK 0
#endif

uint64_t fb_disk_size(int fd) {
    uint64_t count = 0;
    uint32_t sector = 0;

#if FB_HAS_SYS_DISK && defined(DKIOCGETBLOCKCOUNT)
    if (ioctl(fd, DKIOCGETBLOCKCOUNT, &count) == 0 && count > 0) {
#ifdef DKIOCGETBLOCKSIZE
        if (ioctl(fd, DKIOCGETBLOCKSIZE, &sector) == 0 && sector > 0) {
            return count * (uint64_t)sector;
        }
#endif
        return count * 512ULL;
    }
#endif

    struct stat st;
    if (fstat(fd, &st) == 0 && st.st_size > 0) {
        return (uint64_t)st.st_size;
    }

    off_t end = lseek(fd, 0, SEEK_END);
    if (end > 0) {
        (void)lseek(fd, 0, SEEK_SET);
        return (uint64_t)end;
    }
    return 0;
}

int fb_set_nocache(int fd) {
    return fcntl(fd, F_NOCACHE, 1);
}

int fb_is_jailbroken(void) {
    if (getuid() == 0 || geteuid() == 0) {
        return 1;
    }

    const char *paths[] = {
        "/var/jb/usr/bin/su",
        "/var/jb/usr/sbin/sshd",
        "/usr/sbin/sshd",
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/etc/apt",
        "/private/var/lib/dpkg",
        NULL
    };

    for (int i = 0; paths[i] != NULL; i++) {
        if (access(paths[i], F_OK) == 0) {
            return 1;
        }
    }
    return 0;
}
