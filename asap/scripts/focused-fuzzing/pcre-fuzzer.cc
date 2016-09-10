#include <string.h>
#include <stdint.h>
#include "pcre2posix.h"
extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  if (size < 1) return 0;
  char *str = new char[size+1];
  memcpy(str, data, size);
  str[size] = 0;
  regex_t preg;
  if (0 == regcomp(&preg, str, 0)) {
    regexec(&preg, str, 0, 0, 0);
    regfree(&preg);
  }
  delete [] str;
  return 0;
}
