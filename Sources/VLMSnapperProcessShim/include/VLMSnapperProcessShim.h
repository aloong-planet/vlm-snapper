#ifndef VLMSNAPPER_PROCESS_SHIM_H
#define VLMSNAPPER_PROCESS_SHIM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Swift cannot reliably disambiguate the Darwin flock function from the
// flock structure. These wrappers keep the synchronous kernel lease behind a
// two-function C seam instead of weakening process ownership semantics.
bool VLMSnapperTryLockFileDescriptor(int descriptor, int *error_code);
void VLMSnapperUnlockFileDescriptor(int descriptor);
bool VLMSnapperGzipCompress(
    const uint8_t *input,
    size_t input_length,
    uint8_t **output,
    size_t *output_length,
    int *error_code
);
void VLMSnapperFreeBuffer(void *buffer);

#endif
