#include <cassert>
#include <cstdio>
#include <cstdint>
#include <unistd.h>

extern "C" {
#include "convert.h"
#include "output.h"
#include "parse.h"

// The following are variables that need to be defined for unrtf to work (see
// their declarations in main.h).

int lineno = 0;
int debug_mode = 0;
int simple_mode = 0;
int inline_mode = 0;
int no_remap_mode = 0;
int nopict_mode = 0;
int verbose_mode = 0;

static OutputPersonality default_output_personality = {
    .comment_begin = (char *)"<!--",
    .comment_end = (char *)"-->",
    .document_begin = (char *)"<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 "
                              "Transitional//EN\">\n<html>",
    .document_end = (char *)"</html>",
    .header_begin = (char *)"<head>",
    .header_end = (char *)"</head>",
    .document_title_begin = (char *)"<title>",
    .document_title_end = (char *)"</title>",
    .document_author_begin = (char *)"<meta name=\"author\" content=\"",
    .document_author_end = (char *)"\">",
    .document_changedate_begin = (char *)"<!-- changed:",
    .document_changedate_end = (char *)"-->",
    .body_begin = (char *)"<body>",
    .body_end = (char *)"</body>",
    .paragraph_begin = (char *)"<p>",
    .paragraph_end = (char *)"</p>",
    .center_begin = (char *)"<center>",
    .center_end = (char *)"</center>",
    .justify_begin = (char *)"<div align=\"justify\">",
    .justify_end = (char *)"</div>",
    .align_left_begin = (char *)"<div align=\"left\">",
    .align_left_end = (char *)"</div>",
    .align_right_begin = (char *)"<div align=\"right\">",
    .align_right_end = (char *)"</div>",
    .forced_space = (char *)"&nbsp;",
    .line_break = (char *)"<br>",
    .page_break = (char *)"<p><hr><p>",
    .hyperlink_begin = (char *)"<a href=\"",
    .hyperlink_end = (char *)"\">hyperlink</a>",
    .imagelink_begin = (char *)"<img src=\"",
    .imagelink_end = (char *)"\">",
    .table_begin = (char *)"<table border=\"2\">",
    .table_end = (char *)"</table>",
    .table_row_begin = (char *)"<tr>",
    .table_row_end = (char *)"</tr>",
    .table_cell_begin = (char *)"<td>",
    .table_cell_end = (char *)"</td>",
    .font_begin = (char *)"<font face=\"%\">",
    .font_end = (char *)"</font>",
    .fontsize_begin = (char *)"<span style=\"font-size:%pt\">",
    .fontsize_end = (char *)"</span>",
    .fontsize8_begin = (char *)"<font size=\"1\">",
    .fontsize8_end = (char *)"</font>",
    .fontsize10_begin = (char *)"<font size=\"2\">",
    .fontsize10_end = (char *)"</font>",
    .fontsize12_begin = (char *)"<font size=\"3\">",
    .fontsize12_end = (char *)"</font>",
    .fontsize14_begin = (char *)"<font size=\"4\">",
    .fontsize14_end = (char *)"</font>",
    .fontsize18_begin = (char *)"<font size=\"5\">",
    .fontsize18_end = (char *)"</font>",
    .fontsize24_begin = (char *)"<font size=\"6\">",
    .fontsize24_end = (char *)"</font>",
    .smaller_begin = (char *)"<small>",
    .smaller_end = (char *)"</small>",
    .bigger_begin = (char *)"<big>",
    .bigger_end = (char *)"</big>",
    .foreground_begin = (char *)"<font color=\"%\">",
    .foreground_end = (char *)"</font>",
    .background_begin = (char *)"<span style=\"background:%\">",
    .background_end = (char *)"</span>",
    .bold_begin = (char *)"<b>",
    .bold_end = (char *)"</b>",
    .italic_begin = (char *)"<i>",
    .italic_end = (char *)"</i>",
    .underline_begin = (char *)"<u>",
    .underline_end = (char *)"</u>",
    .dbl_underline_begin = (char *)"<u>",
    .dbl_underline_end = (char *)"</u>",
    .superscript_begin = (char *)"<sup>",
    .superscript_end = (char *)"</sup>",
    .subscript_begin = (char *)"<sub>",
    .subscript_end = (char *)"</sub>",
    .strikethru_begin = (char *)"<s>",
    .strikethru_end = (char *)"</s>",
    .dbl_strikethru_begin = (char *)"<s>",
    .dbl_strikethru_end = (char *)"</s>",
    .emboss_begin =
        (char *)"<span style=\"background:gray\"><font color=\"black\">",
    .emboss_end = (char *)"</font></span>",
    .engrave_begin =
        (char *)"<span style=\"background:gray\"><font color=\"navyblue\">",
    .engrave_end = (char *)"</font></span>",
    .shadow_begin = (char *)"<span style=\"background:gray\">",
    .shadow_end = (char *)"</span>",
    .outline_begin = (char *)"<span style=\"background:gray\">",
    .outline_end = (char *)"</span>",
    .expand_begin = (char *)"<span style=\"letter-spacing: %\">",
    .expand_end = (char *)"</span>",
    .pointlist_begin = (char *)"<ol>",
    .pointlist_end = (char *)"</ol>",
    .pointlist_item_begin = (char *)"<li>",
    .pointlist_item_end = (char *)"</li>",
    .numericlist_begin = (char *)"<ul>",
    .numericlist_end = (char *)"</ul>",
    .numericlist_item_begin = (char *)"<li>",
    .numericlist_item_end = (char *)"</li>",
    .unisymbol_print = (char *)"&#%;",
    .utf8_encoding =
        (char *)"<meta http-equiv=\"content-type\" content=\"text/html; "
                "charset=utf-8\">\n",
    .chars = {.right_quote = (char *)"&rsquo;",
              .left_quote = (char *)"&lsquo;",
              .right_dbl_quote = (char *)"&rdquo;",
              .left_dbl_quote = (char *)"&ldquo;",
              .endash = (char *)"&ndash;",
              .emdash = (char *)"&mdash;",
              .bullet = (char *)"&bull;",
              .lessthan = (char *)"&lt;",
              .greaterthan = (char *)"&gt;",
              .amp = (char *)"&amp;",
              .copyright = (char *)"&copy;",
              .trademark = (char *)"&trade;",
              .nonbreaking_space = (char *)"&nbsp;"}};

OutputPersonality *op = &default_output_personality;

// Redirect stdout, because we don't want to see any output from word_print.
// Code from http://c-faq.com/stdio/rd.kirby.c
int copy_of_stdout = -1;
fpos_t pos_of_stdout;

void RedirectStdoutToDevNull() {
  assert(copy_of_stdout == -1 && "Duplicate calls to RedirectStdoutToDevNull?");

  fflush(stdout);
  fgetpos(stdout, &pos_of_stdout);
  copy_of_stdout = dup(fileno(stdout));
  freopen("/dev/null", "w", stdout);
}

void RestoreStdout() {
  fflush(stdout);
  dup2(copy_of_stdout, fileno(stdout));
  close(copy_of_stdout);
  copy_of_stdout = -1;
  clearerr(stdout);
  fsetpos(stdout, &pos_of_stdout);
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  FILE *f;
  Word *word;

  if (size) {
    f = fmemopen((void *)data, size, "r");
  } else {
    // Prevent empty data from leading to zero coverage.
    f = fmemopen((void *)"\n", 1, "r");
  }
  assert(f && "fmemopen failed?");

  word = word_read(f);
  if (!word) return 0;
  word = optimize_word(word, 1);
  if (!word) return 0;

  RedirectStdoutToDevNull();
  word_print(word);
  RestoreStdout();

  word_free(word);
  fclose(f);

  return 0;
}
}
