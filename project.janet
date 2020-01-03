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

(declare-native
    :name "redis"
    :cflags (array/push (pkg-config "hiredis --cflags") "-g")
    :lflags (pkg-config "hiredis --libs")
    :source ["mod.c"])
