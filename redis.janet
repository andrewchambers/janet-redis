(import _janet_redis :prefix "" :export true)

(defn pipeline
  [conn & forms]
  (each f forms
    (append conn ;f))
  (def r @[])
  (each f forms
    (array/push r (get-reply conn)))
  r)

(defn multi
  [conn & forms]
  (as-> (array/concat @[@["MULTI"]] forms @[["EXEC"]]) _
        (pipeline conn ;_)
        (array/pop _)))
