(declare-project
  :name "redis"
  :author "Andrew Chambers"
  :license "MIT"
  :url "https://github.com/andrewchambers/janet-redis"
  :repo "git+https://github.com/andrewchambers/janet-redis.git")

(declare-native
    :name "redis"
    :cflags ["-lhiredis" "-I/nix/store/6blfjdkah4r5mf0yrb2snq68hqmxwcf3-hiredis-0.14.0/include/hiredis"]
    :source ["mod.c"])
