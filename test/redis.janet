(import sh)
(import process)
(import build/redis :as r)

(defn assert [t] (when (not t) (error "assertion failed")))

(defn tmp-redis
  []
  (def port 35543)
  (def d (string (sh/$$_ ["mktemp" "-d" "/tmp/janet-redis-test.tmp.XXXXX"])))
  (def sock (string d "/redis.sock"))
  (def r (process/spawn 
           ["redis-server"
            # We can't use unix sockets because the SIGPIPE aborts our tests.
            "--port" (string port)]
           :redirects [[stderr :discard] [stdout :discard]]
           :start-dir d))
  (os/sleep 0.5)
  @{
   :port port
   :d d
   :r r
   :sock sock
   :connect
     (fn [self]
       (r/connect "localhost" (self :port)))
   :close
     (fn [self]
       (print "closing down server...")
       (:close (self :r))
       (sh/$ ["rm" "-rf" (self :d)]))})

(with [tmp-redis-server (tmp-redis)]
  
  (print "test redis at " (tmp-redis-server :sock))
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
    (def conn (:connect tmp-redis-server))
    (r/close conn)
    (def [ok v] (protect (r/command conn "PING")))
    (assert (false? ok)))

  # test gc
  (do
    (var conn (:connect tmp-redis-server))
    (set conn nil)
    (gccollect))
)