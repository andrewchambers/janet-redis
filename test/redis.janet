(import build/redis :as r)

(defn assert [t] (when (not t) (error "assertion failed")))

(var conn (r/connect "localhost"))

# Simple commands.
(assert (= (r/command conn "PING") "PONG"))
# Simple pipeline
(assert (= (r/append conn "PING") nil))
(assert (= (r/get-reply conn) "PONG"))

# Test slow path of many args command
(var args @[])
(loop [i :range [0 64]]
  (array/push args (string "K" i) (string "V" i)))
(r/command conn "HSET" "H" ;args)
(assert (= (r/command conn "HGET" "H" "K1") "V1"))
(assert (= (r/command conn "HGET" "H" "K60") "V60"))

# Test slow path of many args append
(set args @[])
(loop [i :range [0 64]]
  (array/push args (string "K" i) (string "V" i)))
(r/append conn "HSET" "H2" ;args)
(r/get-reply conn)
(assert (= (r/command conn "HGET" "H2" "K1") "V1"))
(assert (= (r/command conn "HGET" "H2" "K60") "V60"))

# Test large pipeline.
(loop [i :range [0 64]]
  (r/append conn "SET" (string "K" i) (string "V" i)))

(loop [i :range [0 64]]
  (r/append conn "GET" (string "K" i)))

(loop [i :range [0 64]]
  (assert (= (r/get-reply conn) "OK")))

(loop [i :range [0 64]]
  (assert (= (r/get-reply conn) (string "V" i))))

# Test errors
(do
  (def [ok v] (protect (r/command conn "FOOCOMMAND")))
  (assert (false? ok)))

(r/command conn "QUIT")
(protect (r/command conn "PING"))
(assert (= (r/error-code conn) :REDIS_ERR_EOF))

(do
  (def [ok v] (protect (r/command conn "PING")))
  (assert (false? ok)))

(do
  (def conn (r/connect "localhost"))
  (r/close conn)
  (def [ok v] (protect (r/command conn "PING")))
  (assert (false? ok)))

(set conn nil)
(gccollect)