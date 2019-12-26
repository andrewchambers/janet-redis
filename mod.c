#include <hiredis.h>
#include <janet.h>

typedef struct {
  redisContext *ctx;
} Context;

static void context_close(Context *ctx) {
  if (ctx->ctx) {
    redisFree(ctx->ctx);
    ctx->ctx = NULL;
  }
}

/* Called to garbage collect a sqlite3 connection */
static int context_gc(void *p, size_t s) {
  (void)s;
  Context *ctx = (Context *)p;
  context_close(ctx);
  return 0;
}

static const JanetAbstractType redis_context_type = {
    "redis.context", context_gc, NULL, NULL, NULL, NULL, NULL, NULL};

static Janet jredis_connect(int32_t argc, Janet *argv) {
  janet_arity(argc, 1, 2);
  const char *u = janet_getcstring(argv, 0);

  int32_t port = 6379;

  if (argc >= 2) {
    port = janet_getinteger(argv, 1);
  }

  Context *ctx =
      (Context *)janet_abstract(&redis_context_type, sizeof(Context));

  ctx->ctx = redisConnect(u, port);
  if (!ctx->ctx)
    janet_panic("redis connection failed");

  if (ctx->ctx->err)
    janet_panicf("error connecting to redis server: %s", ctx->ctx->errstr);

  return janet_wrap_abstract(ctx);
}

static Janet jredis_connect_unix(int32_t argc, Janet *argv) {
  janet_fixarity(argc, 1);
  const char *u = janet_getcstring(argv, 0);

  Context *ctx =
      (Context *)janet_abstract(&redis_context_type, sizeof(Context));

  ctx->ctx = redisConnectUnix(u);
  if (!ctx->ctx)
    janet_panic("redis connection failed");

  if (ctx->ctx->err)
    janet_panicf("error connecting to redis server: %s", ctx->ctx->errstr);

  return janet_wrap_abstract(ctx);
}

static Janet jredis_close(int32_t argc, Janet *argv) {
  janet_fixarity(argc, 1);
  Context *ctx = (Context *)janet_getabstract(argv, 0, &redis_context_type);
  context_close(ctx);
  return janet_wrap_nil();
}

static void __ensure_ctx_ok(Context *ctx) {
  if (ctx->ctx == NULL)
    janet_panic("redis context is disconnected");
  if (ctx->ctx->err)
    janet_panicf("context has previously encountered an error: '%s'",
                 ctx->ctx->errstr);
}

typedef enum {
  DO_ACTION_SEND,
  DO_ACTION_APPEND,
} do_action;

static void *__do_x_command(do_action action, Context *ctx, int32_t argc,
                            Janet *argv) {
#define N_FAST_PATH 8

  const char *args[N_FAST_PATH];
  size_t argl[N_FAST_PATH];

  const char **args_p;
  size_t *argl_p;

  if (argc <= N_FAST_PATH) {
    args_p = &args[0];
    argl_p = &argl[0];
  } else {
    args_p = janet_smalloc(sizeof(char *) * argc);
    argl_p = janet_smalloc(sizeof(size_t) * argc);
  }

  for (int i = 0; i < argc; i++) {
    JanetByteView bv = janet_getbytes(argv, i);
    args_p[i] = bv.bytes;
    argl_p[i] = bv.len;
  }

  int had_error = 0;
  void *reply = NULL;

  switch (action) {
  case DO_ACTION_SEND:
    reply = redisCommandArgv(ctx->ctx, argc, args_p, argl_p);
    if (!reply)
      had_error = 1;
    break;
  case DO_ACTION_APPEND:
    if (redisAppendCommandArgv(ctx->ctx, argc, args_p, argl_p) != REDIS_OK)
      had_error = 1;
    break;
  }

  if (argc > N_FAST_PATH) {
    janet_sfree(args_p);
    janet_sfree(argl_p);
  }

  if (had_error)
    janet_panicf("%s", ctx->ctx->errstr);

  return reply;

#undef N_FAST_PATH
}

static Janet reply_to_janet(redisReply *reply) {
  Janet v;
  switch (reply->type) {
  case REDIS_REPLY_STATUS:
    v = janet_stringv(reply->str, reply->len);
    break;
  case REDIS_REPLY_ERROR:
    v = janet_stringv(reply->str, reply->len);
    break;
  case REDIS_REPLY_INTEGER:
    v = janet_wrap_s64(reply->integer);
    break;
  case REDIS_REPLY_NIL:
    v = janet_wrap_nil();
    break;
  case REDIS_REPLY_STRING:
    v = janet_stringv(reply->str, reply->len);
    break;
  case REDIS_REPLY_ARRAY: {
    JanetArray *a = janet_array(reply->elements);
    for (int i = 0; i < reply->elements; i++)
      janet_array_push(a, reply_to_janet(reply->element[i]));
    v = janet_wrap_array(a);
    break;
  }
  default:
    v = janet_wrap_nil();
    break;
  }
  return v;
}

static Janet jredis_command(int32_t argc, Janet *argv) {
  if (argc < 1)
    janet_panic("expected at least a redis context");

  Context *ctx = (Context *)janet_getabstract(argv, 0, &redis_context_type);
  __ensure_ctx_ok(ctx);
  argc--;
  argv++;
  redisReply *reply =
      (redisReply *)__do_x_command(DO_ACTION_SEND, ctx, argc, argv);

  Janet v = reply_to_janet(reply);
  int err_occured = reply->type == REDIS_REPLY_ERROR;
  freeReplyObject(reply);
  if (err_occured)
    janet_panicv(v);

  return v;
}

static Janet jredis_append(int32_t argc, Janet *argv) {
  if (argc < 1)
    janet_panic("expected at least a redis context");

  Context *ctx = (Context *)janet_getabstract(argv, 0, &redis_context_type);
  __ensure_ctx_ok(ctx);
  argc--;
  argv++;
  __do_x_command(DO_ACTION_APPEND, ctx, argc, argv);
  return janet_wrap_nil();
}

static Janet jredis_get_reply(int32_t argc, Janet *argv) {
  janet_fixarity(argc, 1);

  Context *ctx = (Context *)janet_getabstract(argv, 0, &redis_context_type);
  __ensure_ctx_ok(ctx);

  redisReply *reply;
  if (redisGetReply(ctx->ctx, (void **)&reply) != REDIS_OK)
    janet_panicf("error getting reply: %s", ctx->ctx->errstr);

  Janet v = reply_to_janet(reply);
  int err_occured = reply->type == REDIS_REPLY_ERROR;
  freeReplyObject(reply);
  if (err_occured)
    janet_panicv(v);

  return v;
}

static Janet jredis_error_message(int32_t argc, Janet *argv) {
  janet_fixarity(argc, 1);
  Context *ctx = (Context *)janet_getabstract(argv, 0, &redis_context_type);
  if (!ctx->ctx)
    janet_panic("connection closed");
  if (ctx->ctx->err)
    return janet_cstringv(ctx->ctx->errstr);
  return janet_wrap_nil();
}

static Janet jredis_error_code(int32_t argc, Janet *argv) {
  janet_fixarity(argc, 1);
  Context *ctx = (Context *)janet_getabstract(argv, 0, &redis_context_type);
  if (!ctx->ctx)
    janet_panic("connection closed");
  switch (ctx->ctx->err) {
  case 0:
    return janet_wrap_nil();
  case REDIS_ERR_IO:
    return janet_ckeywordv("REDIS_ERR_IO");
  case REDIS_ERR_EOF:
    return janet_ckeywordv("REDIS_ERR_EOF");
  case REDIS_ERR_PROTOCOL:
    return janet_ckeywordv("REDIS_ERR_PROTOCOL");
  case REDIS_ERR_OTHER:
  default:
    return janet_ckeywordv("REDIS_ERR_OTHER");
  }
}

static const JanetReg cfuns[] = {
    {"connect", jredis_connect,
     "(redis/connect host & port)\n\n"
     "Connect to a redis server or raise an error."},
    {"connect-unix", jredis_connect_unix,
     "(redis/connect-unix socket-path)\n\n"
     "Connect to a redis server or raise an error."},
    {"close", jredis_close,
     "(redis/close ctx)\n\n"
     "Close a redis context."},
    {"command", jredis_command,
     "(redis/command ctx & params])\n\n"
     "Send a command and get the reply, raises an error on redis errors."},
    {"append", jredis_append,
     "(redis/append ctx & params])\n\n"
     "Add a command to the pipline, raises an error on redis errors."},
    {"get-reply", jredis_get_reply,
     "(redis/get-reply ctx & params])\n\n"
     "Get the result of a redis command, raises an error on redis errors."},
    {"error-message", jredis_error_message,
     "(redis/error-message ctx)\n\n"
     "Returns the last redis error or nil."},
    {"error-code", jredis_error_code, "(redis/error-code ctx)\n\n"},
    {NULL, NULL, NULL}};

JANET_MODULE_ENTRY(JanetTable *env) { janet_cfuns(env, "redis", cfuns); }