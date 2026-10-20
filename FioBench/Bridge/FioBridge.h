#ifndef FioBridge_h
#define FioBridge_h

#include <stdint.h>

/// Returns the size of an opened block device in bytes, or 0 when unknown.
uint64_t fb_disk_size(int fd);

/// Applies Darwin's F_NOCACHE to an open descriptor.
int fb_set_nocache(int fd);

/// Best-effort jailbreak/root probe. TrollStore alone is not a jailbreak.
int fb_is_jailbroken(void);

#endif /* FioBridge_h */
