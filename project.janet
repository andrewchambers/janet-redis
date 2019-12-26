(declare-project
  :name "redis"
  :author "Andrew Chambers"
  :license "MIT"
  :url "https://github.com/andrewchambers/janet-redis"
  :repo "git+https://github.com/andrewchambers/janet-redis.git")

(declare-native
    :name "redis"
    :cflags ["-lhiredis"]
    :source ["mod.c"])
