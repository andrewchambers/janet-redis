(declare-project
  :name "redis"
  :author "Andrew Chambers"
  :license "MIT"
  :url "https://github.com/andrewchambers/janet-redis"
  :repo "git+https://github.com/andrewchambers/janet-redis.git")

(defn pkg-config [what]
  (def f (file/popen (string "pkg-config " what)))
  (def v (->>
           (file/read f :all)
           (string/trim)
           (string/split " ")))
  (unless (zero? (file/close f))
    (error "pkg-config failed!"))
  v)

(declare-source
    :source ["redis.janet"])

(declare-native
    :name "_janet-redis"
    :cflags (pkg-config "hiredis --cflags")
    :lflags (pkg-config "hiredis --libs")
    :source ["redis.c"])
