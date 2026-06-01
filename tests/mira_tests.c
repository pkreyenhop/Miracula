#include <criterion/criterion.h>

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

struct test_env {
  char root[PATH_MAX];
  char home[PATH_MAX];
  char work[PATH_MAX];
};

struct run_result {
  int status;
  char *stdout_text;
  char *stderr_text;
};

static void checked_snprintf(char *buffer, size_t size, const char *format, ...) {
  va_list args;
  va_start(args, format);
  int written = vsnprintf(buffer, size, format, args);
  va_end(args);

  cr_assert(written >= 0 && (size_t)written < size, "buffer too small for %s", format);
}

static char *format_alloc(const char *format, ...) {
  va_list args;
  va_start(args, format);
  va_list copy;
  va_copy(copy, args);
  int written = vsnprintf(NULL, 0, format, copy);
  va_end(copy);
  cr_assert(written >= 0, "failed to format string");

  char *buffer = malloc((size_t)written + 1);
  cr_assert_not_null(buffer, "failed to allocate formatted string");
  int written_again = vsnprintf(buffer, (size_t)written + 1, format, args);
  va_end(args);
  cr_assert_eq(written_again, written, "formatted string size changed");
  return buffer;
}

static char *read_file(const char *path) {
  FILE *file = fopen(path, "rb");
  cr_assert_not_null(file, "failed to open %s: %s", path, strerror(errno));

  cr_assert_eq(fseek(file, 0, SEEK_END), 0, "failed to seek %s", path);
  long size = ftell(file);
  cr_assert_geq(size, 0, "failed to tell %s", path);
  rewind(file);

  char *buffer = malloc((size_t)size + 1);
  cr_assert_not_null(buffer, "failed to allocate file buffer");
  size_t read_count = fread(buffer, 1, (size_t)size, file);
  cr_assert_eq(read_count, (size_t)size, "short read from %s", path);
  buffer[size] = '\0';
  fclose(file);
  return buffer;
}

static void write_file(const char *path, const char *contents) {
  FILE *file = fopen(path, "wb");
  cr_assert_not_null(file, "failed to open %s: %s", path, strerror(errno));
  size_t length = strlen(contents);
  cr_assert_eq(fwrite(contents, 1, length, file), length, "short write to %s", path);
  cr_assert_eq(fclose(file), 0, "failed to close %s", path);
}

static void remove_tree(const char *path) {
  pid_t pid = fork();
  cr_assert_neq(pid, -1, "fork failed: %s", strerror(errno));
  if (pid == 0) {
    execlp("rm", "rm", "-rf", path, (char *)NULL);
    _exit(127);
  }

  int status = 0;
  cr_assert_eq(waitpid(pid, &status, 0), pid, "waitpid failed");
  cr_assert(WIFEXITED(status) && WEXITSTATUS(status) == 0, "rm -rf failed for %s", path);
}

static void init_env(struct test_env *env) {
  cr_assert_not_null(getcwd(env->root, sizeof(env->root)), "getcwd failed: %s", strerror(errno));

  checked_snprintf(env->home, sizeof(env->home), "%s", "/tmp/mira-test.XXXXXX");
  checked_snprintf(env->work, sizeof(env->work), "%s", "/tmp/mira-work.XXXXXX");
  cr_assert_not_null(mkdtemp(env->home), "mkdtemp failed for home: %s", strerror(errno));
  cr_assert_not_null(mkdtemp(env->work), "mkdtemp failed for work: %s", strerror(errno));
}

static void cleanup_env(struct test_env *env) {
  remove_tree(env->home);
  remove_tree(env->work);
}

static void chomp_stdout(char *text) {
  size_t length = strlen(text);
  while (length > 0 && text[length - 1] == '\n') {
    text[--length] = '\0';
  }
}

static struct run_result run_mira(const struct test_env *env, const char *script,
                                  const char *input, const char *const extra_args[]) {
  char input_path[PATH_MAX];
  char stderr_path[PATH_MAX];
  char mira_path[PATH_MAX];
  char lib_path[PATH_MAX];

  checked_snprintf(input_path, sizeof(input_path), "%s/input.txt", env->work);
  checked_snprintf(stderr_path, sizeof(stderr_path), "%s/stderr.txt", env->work);
  checked_snprintf(mira_path, sizeof(mira_path), "%s/mira", env->root);
  checked_snprintf(lib_path, sizeof(lib_path), "%s/miralib", env->root);
  write_file(input_path, input);

  int stdout_pipe[2];
  cr_assert_eq(pipe(stdout_pipe), 0, "pipe failed: %s", strerror(errno));

  pid_t pid = fork();
  cr_assert_neq(pid, -1, "fork failed: %s", strerror(errno));
  if (pid == 0) {
    int input_fd = open(input_path, O_RDONLY);
    int stderr_fd = open(stderr_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (input_fd == -1 || stderr_fd == -1) {
      _exit(126);
    }

    dup2(input_fd, STDIN_FILENO);
    dup2(stdout_pipe[1], STDOUT_FILENO);
    dup2(stderr_fd, STDERR_FILENO);
    close(stdout_pipe[0]);
    close(stdout_pipe[1]);
    close(input_fd);
    close(stderr_fd);
    setenv("HOME", env->home, 1);

    const char *argv[32];
    size_t argc = 0;
    argv[argc++] = mira_path;
    if (extra_args != NULL) {
      for (size_t i = 0; extra_args[i] != NULL; i++) {
        argv[argc++] = extra_args[i];
      }
    }
    argv[argc++] = "-lib";
    argv[argc++] = lib_path;
    argv[argc++] = "-hush";
    if (script != NULL && script[0] != '\0') {
      argv[argc++] = script;
    }
    argv[argc] = NULL;

    execv(mira_path, (char *const *)argv);
    _exit(127);
  }

  close(stdout_pipe[1]);
  char *stdout_text = NULL;
  FILE *stdout_file = fdopen(stdout_pipe[0], "rb");
  cr_assert_not_null(stdout_file, "fdopen failed");
  char buffer[4096];
  size_t used = 0;
  while (!feof(stdout_file)) {
    size_t count = fread(buffer, 1, sizeof(buffer), stdout_file);
    if (count > 0) {
      char *next = realloc(stdout_text, used + count + 1);
      cr_assert_not_null(next, "failed to grow stdout buffer");
      stdout_text = next;
      memcpy(stdout_text + used, buffer, count);
      used += count;
      stdout_text[used] = '\0';
    }
  }
  fclose(stdout_file);
  if (stdout_text == NULL) {
    stdout_text = calloc(1, 1);
    cr_assert_not_null(stdout_text, "failed to allocate empty stdout");
  }

  int status = 0;
  cr_assert_eq(waitpid(pid, &status, 0), pid, "waitpid failed");
  char *stderr_text = read_file(stderr_path);
  chomp_stdout(stdout_text);
  return (struct run_result){.status = status, .stdout_text = stdout_text, .stderr_text = stderr_text};
}

static void free_result(struct run_result *result) {
  free(result->stdout_text);
  free(result->stderr_text);
}

static void assert_success_output(const char *name, const struct run_result *result,
                                  const char *expected) {
  cr_assert(WIFEXITED(result->status), "%s did not exit normally", name);
  cr_assert_eq(WEXITSTATUS(result->status), 0, "%s exited with %d\nstderr:\n%s", name,
               WEXITSTATUS(result->status), result->stderr_text);
  cr_assert_str_eq(result->stdout_text, expected, "%s output mismatch", name);
}

static void assert_success_status(const char *name, const struct run_result *result) {
  cr_assert(WIFEXITED(result->status), "%s did not exit normally", name);
  cr_assert_eq(WEXITSTATUS(result->status), 0, "%s exited with %d\nstdout:\n%s\nstderr:\n%s", name,
               WEXITSTATUS(result->status), result->stdout_text, result->stderr_text);
}

static char *repeat_char(size_t count, char value) {
  char *buffer = malloc(count + 1);
  cr_assert_not_null(buffer, "failed to allocate repeated char buffer");
  memset(buffer, value, count);
  buffer[count] = '\0';
  return buffer;
}

static void write_compile_stress_script(const char *path, size_t items) {
  FILE *file = fopen(path, "wb");
  cr_assert_not_null(file, "failed to open %s: %s", path, strerror(errno));
  fprintf(file, "stress_list\n=[\n");
  for (size_t i = 0; i < items; i++) {
    fprintf(file, "  \"compile-time-stress-%04zu\",\n", i);
  }
  fprintf(file, "  \"compile-time-stress-end\"]\nstress_len = # stress_list\n");
  cr_assert_eq(fclose(file), 0, "failed to close stress script");
}

Test(mira, standard_arithmetic_and_lists) {
  struct test_env env;
  init_env(&env);
  struct run_result result = run_mira(&env, "", "1+2\nproduct [1..10]\nmap (2*) [1..5]\n/q\n", NULL);
  assert_success_output("standard arithmetic and lists", &result, "3\n3628800\n[2,4,6,8,10]");
  free_result(&result);
  cleanup_env(&env);
}

Test(mira, big_integers) {
  struct test_env env;
  init_env(&env);
  struct run_result result = run_mira(&env, "", "12345678901234567890 + 10\n2^80\n/q\n", NULL);
  assert_success_output("big integers", &result, "12345678901234567900\n1208925819614629174706176");
  free_result(&result);
  cleanup_env(&env);
}

Test(mira, lazy_lists_and_strings) {
  struct test_env env;
  init_env(&env);
  struct run_result result =
      run_mira(&env, "", "take 5 [1..]\nreverse [1,2,3]\nzip2 [1,2,3] [4,5,6]\n\"abc\" ++ \"def\"\n/q\n", NULL);
  assert_success_output("lazy lists and strings", &result,
                        "[1,2,3,4,5]\n[3,2,1]\n[(1,4),(2,5),(3,6)]\nabcdef");
  free_result(&result);
  cleanup_env(&env);
}

Test(mira, example_script_fib) {
  struct test_env env;
  init_env(&env);
  char script[PATH_MAX];
  checked_snprintf(script, sizeof(script), "%s/miralib/ex/fib", env.root);
  struct run_result result = run_mira(&env, script, "fib 10\n/q\n", NULL);
  assert_success_output("example script fib", &result, "55");
  free_result(&result);
  cleanup_env(&env);
}

Test(mira, user_script_definitions) {
  struct test_env env;
  init_env(&env);
  char script[PATH_MAX];
  checked_snprintf(script, sizeof(script), "%s/user-defs.m", env.work);
  write_file(script, "square x = x*x\ntwice f x = f (f x)\npairup x y = (x,y)\n");
  struct run_result result =
      run_mira(&env, script, "square 12\ntwice square 2\npairup \"a\" [1,2]\n/q\n", NULL);
  assert_success_output("user script definitions", &result, "144\n16\n(\"a\",[1,2])");
  free_result(&result);
  cleanup_env(&env);
}

Test(mira, type_error_reporting) {
  struct test_env env;
  init_env(&env);
  struct run_result result = run_mira(&env, "", "1 + \"x\"\n/q\n", NULL);
  assert_success_output("type error reporting", &result,
                        "type error in expression\ncannot unify [char] with num");
  free_result(&result);
  cleanup_env(&env);
}

Test(mira, syntax_error_reporting) {
  struct test_env env;
  init_env(&env);
  struct run_result result = run_mira(&env, "", "1 +\n/q\n", NULL);
  assert_success_output("syntax error reporting", &result, "syntax error - unexpected newline");
  free_result(&result);
  cleanup_env(&env);
}

Test(mira, very_long_literals) {
  struct test_env env;
  init_env(&env);
  char *long_string = repeat_char(4096, 'a');
  char *long_integer = repeat_char(512, '9');
  char *zeroes = repeat_char(512, '0');
  char *input = format_alloc("# \"%s\"\n%s + 1\n/q\n", long_string, long_integer);
  char *expected = format_alloc("4096\n1%s", zeroes);

  struct run_result result = run_mira(&env, "", input, NULL);
  assert_success_output("very long literals", &result, expected);

  free_result(&result);
  free(input);
  free(expected);
  free(long_string);
  free(long_integer);
  free(zeroes);
  cleanup_env(&env);
}

Test(mira, compile_time_stress_guard, .timeout = 20) {
  struct test_env env;
  init_env(&env);
  char script[PATH_MAX];
  checked_snprintf(script, sizeof(script), "%s/compile-stress.m", env.work);
  write_compile_stress_script(script, 1500);
  const char *args[] = {"-make", NULL};
  struct run_result result = run_mira(&env, script, "", args);
  assert_success_status("compile time stress guard", &result);
  free_result(&result);
  cleanup_env(&env);
}

Test(mira, standard_lib_load_speed_guard, .timeout = 15) {
  struct test_env env;
  init_env(&env);
  struct run_result result =
      run_mira(&env, "", "product [1..10]\nreverse [1,2,3]\n\"abc\" ++ \"def\"\n/q\n", NULL);
  assert_success_output("standard lib load speed guard", &result, "3628800\n[3,2,1]\nabcdef");
  free_result(&result);
  cleanup_env(&env);
}

Test(mira, compile_gc_stress) {
  struct test_env env;
  init_env(&env);
  char script[PATH_MAX];
  checked_snprintf(script, sizeof(script), "%s/compile-gc-stress.m", env.work);
  write_compile_stress_script(script, 600);
  const char *args[] = {"-heap", "25000", "-gc", NULL};
  struct run_result result = run_mira(&env, script, "stress_len\n/q\n", args);
  assert_success_output("compile-gc-stress", &result, "601");
  cr_assert(strstr(result.stderr_text, "<<gc after") != NULL, "expected GC stderr, got:\n%s",
            result.stderr_text);
  free_result(&result);
  cleanup_env(&env);
}

Test(mira, runtime_gc_stress) {
  struct test_env env;
  init_env(&env);
  const char *args[] = {"-heap", "12000", "-gc", NULL};
  struct run_result result = run_mira(&env, "", "sum [1..4000]\n/q\n", args);
  assert_success_output("runtime-gc-stress", &result, "8002000");
  cr_assert(strstr(result.stderr_text, "<<gc after") != NULL, "expected GC stderr, got:\n%s",
            result.stderr_text);
  free_result(&result);
  cleanup_env(&env);
}
