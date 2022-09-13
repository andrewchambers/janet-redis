(declare-project
  :name "redis"
  :description "A Janet Redis library built with the official hiredis C library."
  :author "Andrew Chambers"
  :license "MIT"
  :url "https://github.com/andrewchambers/janet-redis"
  :repo "git+https://github.com/andrewchambers/janet-redis.git")

(defn exec-slurp
   "Read stdout of subprocess and return it trimmed in a string."
   [& args]
   (def proc (os/spawn args :px {:out :pipe}))
   (def out (get proc :out))
   (def buf @"")
   (ev/gather
     (:read out :all buf)
     (:wait proc))
   (string/trimr buf))

(defn pkg-config [& what]
  (try
    (string/split " " (exec-slurp "pkg-config" ;what))
    ([err] (error "pkg-config failed!"))))

(declare-source
  :source ["redis.janet"])

(declare-native
  :name "_janet_redis"
  :cflags (pkg-config "hiredis" "--cflags")
  :lflags (pkg-config "hiredis" "--libs")
  :source ["redis.c"])
