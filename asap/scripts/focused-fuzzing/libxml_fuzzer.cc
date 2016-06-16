#include "stdint.h"
#include "stdlib.h"
#include "libxml/parser.h"
#include "libxml/xmlmemory.h"
#include "libxml/parser.h"
#include "libxml/parserInternals.h"
#include "libxml/HTMLparser.h"
#include "libxml/HTMLtree.h"
#include "libxml/tree.h"
#include "libxml/xpath.h"
#include "libxml/debugXML.h"
#include "libxml/xmlerror.h"

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>



//extern "C" int LLVMFuzzerInitialize(int *argc, char ***argv) {
////  int devNull = open("/dev/null", O_WRONLY);
////  dup2(devNull, 2);
////  return 0;
////}
//
extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
	if (auto doc = xmlReadMemory(reinterpret_cast<const char *>(data), size, "noname.xml", NULL, 0)) {
		xmlReadFile("noname.xml", NULL, 0);
		xmlFreeDoc(doc);
	}
	return 0;
}


