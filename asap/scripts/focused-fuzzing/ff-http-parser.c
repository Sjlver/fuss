#include "http_parser.h"

#include <assert.h>
#include <stddef.h>
#include <malloc.h>
#include <string.h>

// Callbacks for the various events

int request_url_cb(http_parser *p, const char *buf, size_t len) {
  assert(p);
  assert(buf);
  return 0;
}

int header_field_cb(http_parser *p, const char *buf, size_t len) {
  assert(p);
  assert(buf);
  return 0;
}

int header_value_cb(http_parser *p, const char *buf, size_t len) {
  assert(p);
  assert(buf);
  return 0;
}

int body_cb(http_parser *p, const char *buf, size_t len) {
  assert(p);
  assert(buf);
  return 0;
}

int count_body_cb(http_parser *p, const char *buf, size_t len) {
  assert(p);
  assert(buf);
  return 0;
}

int message_begin_cb(http_parser *p) {
  assert(p);
  return 0;
}

int headers_complete_cb(http_parser *p) {
  assert(p);
  return 0;
}

int message_complete_cb(http_parser *p) {
  assert(p);
  return 0;
}

int response_status_cb(http_parser *p, const char *buf, size_t len) {
  assert(p);
  assert(buf);
  return 0;
}

int chunk_header_cb(http_parser *p) {
  assert(p);
  return 0;
}

int chunk_complete_cb(http_parser *p) {
  assert(p);
  return 0;
}

static http_parser_settings settings = {
    .on_message_begin = message_begin_cb,
    .on_header_field = header_field_cb,
    .on_header_value = header_value_cb,
    .on_url = request_url_cb,
    .on_status = response_status_cb,
    .on_body = body_cb,
    .on_headers_complete = headers_complete_cb,
    .on_message_complete = message_complete_cb,
    .on_chunk_header = chunk_header_cb,
    .on_chunk_complete = chunk_complete_cb};

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  http_parser parser;
  http_parser_init(&parser, HTTP_REQUEST);
  http_parser_execute(&parser, &settings, (const char *)data, size);
  http_parser_execute(&parser, &settings, NULL, 0);
  return 0;
}
