#include "../utf8.h"

#include <sys/wait.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void fail(const char *message) {
  fprintf(stderr, "utf8_tests: %s\n", message);
  exit(1);
}

static void expect_unicode(const char *name, const unsigned char *bytes, size_t len,
                           unicode expected) {
  FILE *file = tmpfile();
  if (file == NULL) {
    fail("tmpfile failed");
  }
  if (fwrite(bytes, 1, len, file) != len) {
    fail("fwrite failed");
  }
  rewind(file);
  unicode actual = fromUTF8(file);
  fclose(file);
  if (actual != expected) {
    fprintf(stderr, "utf8_tests: %s expected %#lx got %#lx\n", name, expected, actual);
    exit(1);
  }
}

static void expect_out(const char *name, unicode value, const unsigned char *expected,
                       size_t expected_len) {
  FILE *file = tmpfile();
  if (file == NULL) {
    fail("tmpfile failed");
  }
  outUTF8(value, file);
  rewind(file);

  unsigned char actual[8];
  size_t actual_len = fread(actual, 1, sizeof(actual), file);
  fclose(file);
  if (actual_len != expected_len || memcmp(actual, expected, expected_len) != 0) {
    fprintf(stderr, "utf8_tests: %s output mismatch\n", name);
    exit(1);
  }
}

static void call_from_utf8(const unsigned char *bytes, size_t len) {
  FILE *file = tmpfile();
  if (file == NULL) {
    fail("tmpfile failed");
  }
  if (fwrite(bytes, 1, len, file) != len) {
    fail("fwrite failed");
  }
  rewind(file);
  (void)fromUTF8(file);
  fclose(file);
}

static void call_out_utf8(unicode value) {
  FILE *file = tmpfile();
  if (file == NULL) {
    fail("tmpfile failed");
  }
  outUTF8(value, file);
  fclose(file);
}

static void expect_fatal(const char *name, void (*call)(const void *), const void *arg,
                         const char *expected_stderr) {
  int stderr_pipe[2];
  if (pipe(stderr_pipe) != 0) {
    fail("pipe failed");
  }

  pid_t pid = fork();
  if (pid < 0) {
    fail("fork failed");
  }
  if (pid == 0) {
    close(stderr_pipe[0]);
    dup2(stderr_pipe[1], STDERR_FILENO);
    close(stderr_pipe[1]);
    call(arg);
    _exit(0);
  }

  close(stderr_pipe[1]);
  char stderr_text[256];
  size_t used = 0;
  for (;;) {
    ssize_t count = read(stderr_pipe[0], stderr_text + used, sizeof(stderr_text) - used - 1);
    if (count < 0) {
      fail("read failed");
    }
    if (count == 0) {
      break;
    }
    used += (size_t)count;
    if (used + 1 == sizeof(stderr_text)) {
      break;
    }
  }
  close(stderr_pipe[0]);
  stderr_text[used] = '\0';

  int status = 0;
  if (waitpid(pid, &status, 0) != pid) {
    fail("waitpid failed");
  }
  if (!WIFEXITED(status) || WEXITSTATUS(status) != 1) {
    fprintf(stderr, "utf8_tests: %s expected exit 1\n", name);
    exit(1);
  }
  if (strcmp(stderr_text, expected_stderr) != 0) {
    fprintf(stderr, "utf8_tests: %s stderr mismatch\nexpected: %sactual: %s", name,
            expected_stderr, stderr_text);
    exit(1);
  }
}

struct bytes_case {
  const unsigned char *bytes;
  size_t len;
};

static void fatal_from_utf8(const void *arg) {
  const struct bytes_case *bytes = arg;
  call_from_utf8(bytes->bytes, bytes->len);
}

static void fatal_out_utf8(const void *arg) {
  const unicode *value = arg;
  call_out_utf8(*value);
}

int main(void) {
  const unsigned char ascii[] = {0x41};
  const unsigned char two_byte[] = {0xc2, 0xa3};
  const unsigned char three_byte[] = {0xe2, 0x82, 0xac};
  const unsigned char four_byte[] = {0xf0, 0x9f, 0x98, 0x80};
  const unsigned char invalid_lead[] = {0xff};
  const unsigned char incomplete_two_byte[] = {0xc2};

  expect_unicode("ascii", ascii, sizeof(ascii), 0x41);
  expect_unicode("two-byte", two_byte, sizeof(two_byte), 0x00a3);
  expect_unicode("three-byte", three_byte, sizeof(three_byte), 0x20ac);
  expect_unicode("four-byte", four_byte, sizeof(four_byte), 0x1f600);

  expect_out("ascii", 0x41, ascii, sizeof(ascii));
  expect_out("two-byte", 0x00a3, two_byte, sizeof(two_byte));
  expect_out("three-byte", 0x20ac, three_byte, sizeof(three_byte));
  expect_out("four-byte", 0x1f600, four_byte, sizeof(four_byte));

  const struct bytes_case invalid_lead_case = {invalid_lead, sizeof(invalid_lead)};
  const struct bytes_case incomplete_two_byte_case = {incomplete_two_byte,
                                                      sizeof(incomplete_two_byte)};
  const unicode out_of_range = UMAX + 1;
  expect_fatal("invalid lead byte", fatal_from_utf8, &invalid_lead_case,
               "protocol error - invalid sequence: 0xff\n");
  expect_fatal("incomplete two-byte sequence", fatal_from_utf8, &incomplete_two_byte_case,
               "protocol error - incomplete sequence: 0xc2 EOF\n");
  expect_fatal("out of range output", fatal_out_utf8, &out_of_range,
               "char 0x110000 out of unicode range\n");

  return 0;
}
