#include "VLMSnapperProcessShim.h"

#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <sys/file.h>
#include <zlib.h>

bool VLMSnapperTryLockFileDescriptor(int descriptor, int *error_code) {
    if (flock(descriptor, LOCK_EX | LOCK_NB) == 0) {
        if (error_code != NULL) {
            *error_code = 0;
        }
        return true;
    }
    if (error_code != NULL) {
        *error_code = errno;
    }
    return false;
}

void VLMSnapperUnlockFileDescriptor(int descriptor) {
    flock(descriptor, LOCK_UN);
}

bool VLMSnapperGzipCompress(
    const uint8_t *input,
    size_t input_length,
    uint8_t **output,
    size_t *output_length,
    int *error_code
) {
    if (input_length > UINT_MAX) {
        if (error_code != NULL) *error_code = Z_BUF_ERROR;
        return false;
    }

    z_stream stream = {0};
    int result = deflateInit2(
        &stream,
        Z_DEFAULT_COMPRESSION,
        Z_DEFLATED,
        15 + 16,
        8,
        Z_DEFAULT_STRATEGY
    );
    if (result != Z_OK) {
        if (error_code != NULL) *error_code = result;
        return false;
    }

    uLong bound = deflateBound(&stream, (uLong)input_length);
    if (bound > UINT_MAX) {
        deflateEnd(&stream);
        if (error_code != NULL) *error_code = Z_BUF_ERROR;
        return false;
    }
    uint8_t *buffer = malloc(bound);
    if (buffer == NULL) {
        deflateEnd(&stream);
        if (error_code != NULL) *error_code = Z_MEM_ERROR;
        return false;
    }

    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_length;
    stream.next_out = buffer;
    stream.avail_out = (uInt)bound;
    result = deflate(&stream, Z_FINISH);
    if (result != Z_STREAM_END) {
        free(buffer);
        deflateEnd(&stream);
        if (error_code != NULL) *error_code = result;
        return false;
    }

    *output = buffer;
    *output_length = stream.total_out;
    deflateEnd(&stream);
    if (error_code != NULL) *error_code = Z_OK;
    return true;
}

void VLMSnapperFreeBuffer(void *buffer) {
    free(buffer);
}
