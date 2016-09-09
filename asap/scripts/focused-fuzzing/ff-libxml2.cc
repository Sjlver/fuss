#include <stdint.h>

#include "libxml/parser.h"
#include "libxml/tree.h"

static void nopErrorHandlerFunction(void *ctx, const char *msg, ...) {}
static xmlGenericErrorFunc nopErrorHandler = nopErrorHandlerFunction;

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    // Please, libxml, don't print errors.
    initGenericErrorDefaultFunc(&nopErrorHandler);

    if (auto doc = xmlReadMemory(reinterpret_cast<const char *>(data), size, "noname.xml", NULL,
                XML_PARSE_NOERROR | XML_PARSE_NOWARNING | XML_PARSE_NONET)) {
        xmlFreeDoc(doc);
    }

    return 0;
}
