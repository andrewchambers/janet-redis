# janet-redis
A janet redis library built with the official hiredis C library.

Quick Example:
```
(import redis)

(def r (redis/connect "localhost" 1337))

# Simple commands
(redis/command r "SET" "FOOBAR" "BAZ")
(redis/command r "GET" "FOOBAR")
# "BAZ"

# Command pipelining
(redis/append r "PING")
(redis/append r "PING")
(redis/get-reply r)
# "PONG"
(redis/get-reply r)
# "PONG"

(redis/close r)
```