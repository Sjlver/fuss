/* Adapted from the FILE command's checks/test.c file, for ASAP.
 *
 * Below is that file's original copyright notice. */

/*
 * Copyright (c) Christos Zoulas 2003.
 * All Rights Reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice immediately at the beginning of the file, without modification,
 *    this list of conditions, and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include <cassert>
#if ASAP_DEBUG
#include <cstdio>
#endif
#include <cstdint>
#include <cstdlib>
#include "magic.h"

namespace {
struct magic_set *ms = NULL;

void Uninitialize() {
  if (ms) {
    magic_close(ms);
    ms = NULL;
  }
}

int Initialize() {
  assert(ms == NULL && "Initialize called twice?");

  ms = magic_open(MAGIC_NONE);
  assert(ms && "ERROR opening MAGIC_NONE: out of memory");
  assert(magic_load(ms, ASAP_MAGIC_FILE_PATH) != -1 &&
         "ERROR loading magic file \"" ASAP_MAGIC_FILE_PATH "\".");

  atexit(Uninitialize);

  return 1;
}
} // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  static int initialized = Initialize();
  const char *result;
  const char *error;

  (void)initialized; // suppress "unused variable" warning

  result = magic_buffer(ms, data, size);
  if (!result) {
    error = magic_error(ms);
    // Sometimes, error is NULL too. Not sure when this happens and whether
    // it's a bug. Anyway...
    (void) error;
  }

#if ASAP_DEBUG
  if (result) {
    printf("magic result: %s\n", result);
  } else if (magic_error(ms)) {
    printf("magic error: %s\n", magic_error(ms));
  } else {
    printf("libmagic returned an unknown error.");
  }
#endif

  return 0;
}
