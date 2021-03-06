(import sh)
(import shlex)
(import posix-spawn)
(import ../redis :as r)

(defn tmp-redis
  []
  (def port 35543)

  (def d (sh/$<_ mktemp -d /tmp/janet-redis-test.tmp.XXXXX))

  (def r (posix-spawn/spawn ["sh" "-c"
                             (string
                               "cd " (shlex/quote d) " ;"
                               "exec redis-server --port " port " > /dev/null 2>&1")]))
  (os/sleep 0.5)

  @{:port port
    :d d
    :r r
    :connect
    (fn [self]
      (r/connect "localhost" (self :port)))
    :close
    (fn [self]
      (print "closing down server...")
      (:close (self :r))
      (sh/$ rm -rf (self :d)))})

(with [tmp-redis-server (tmp-redis)]

  (var conn (:connect tmp-redis-server))

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

  # Test multi.
  (assert
    (=
      (tuple ;(r/multi conn ["PING"] ["PING"]))
      ["PONG" "PONG"]))

  # Test errors
  (do
    (def [ok v] (protect (r/command conn "FOOCOMMAND")))
    (assert (false? ok)))

  # Test server disconnect error
  (do
    (def conn (:connect tmp-redis-server))
    (r/command conn "QUIT")
    (protect (r/command conn "PING"))
    (assert (= (r/error-code conn) :REDIS_ERR_EOF)))

  # test close.
  (do
    (def conn1 (:connect tmp-redis-server))
    (def conn2 (:connect tmp-redis-server))
    (r/close conn1)
    (:close conn2)
    (def [ok1 v] (protect (r/command conn1 "PING")))
    (def [ok2 v] (protect (r/command conn2 "PING")))
    (assert (false? ok1))
    (assert (false? ok2)))

  # test get timeout and reconnect
  (do
    (def c (:connect tmp-redis-server))
    (assert (= [0 0] (r/get-timeout c)))
    (r/set-timeout c 10 0)
    (assert (= [10 0] (r/get-timeout c)))
    (r/reconnect c)
    (assert (= [0 0] (r/get-timeout c))))

  # test gc
  (do
    (var conn (:connect tmp-redis-server))
    (set conn nil)
    (gccollect)))
