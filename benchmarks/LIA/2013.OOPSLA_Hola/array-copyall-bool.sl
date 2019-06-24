(set-logic ALIA)

(synth-inv inv_fun ((a1 (Array Int Bool)) (a2 (Array Int Bool)) (n Int) (i Int)))

(declare-primed-var a1 (Array Int Bool))
(declare-primed-var a2 (Array Int Bool))
(declare-primed-var i Int)
(declare-primed-var n Int)

(define-fun pre_fun ((a1 (Array Int Bool)) (a2 (Array Int Bool)) (n Int) (i Int)) Bool
  (and (>= n 0) (and (= i 0) (< i n))))

(define-fun trans_fun ((a1 (Array Int Bool)) (a2 (Array Int Bool)) (n Int) (i Int) (a1! (Array Int Bool)) (a2! (Array Int Bool)) (n! Int) (i! Int)) Bool
  (and (= i! (+ i 1)) (and (= n! n) (and (= a2! a2) (= a1! (store a1 i (select a2 i)))))))

(define-fun post_fun ((a1 (Array Int Bool)) (a2 (Array Int Bool)) (n Int) (i Int)) Bool
  (or (< i n) (= a1 a2)))

(inv-constraint inv_fun pre_fun trans_fun post_fun)

(check-synth)