(import (scheme base)
        (scheme case-lambda)
        (scheme write)
        (srfi 1)
        (srfi 128)
        (srfi 158)
        (srfi 225))

(cond-expand
  ((library (srfi 69))
   (import (prefix (srfi 69) t69-)))
  (else))

(cond-expand
  ((library (srfi 125))
   (import (prefix (srfi 125) t125-)))
  (else))

(cond-expand
  ((library (srfi 126))
   (import (prefix (srfi 126) t126-)))
  (else))

(cond-expand
  ((and (library (srfi 146))
        (library (srfi 146 hash)))
   (import (srfi 146)
           (srfi 146 hash)))
  (else))

(cond-expand
  (chibi
   (import (rename (except (chibi test) test-equal)
                   (test test-equal)
                   (test-group test-group*)))
   (define test-skip-count 0)
   (define (test-skip n)
     (set! test-skip-count n))
   (define-syntax test-group
     (syntax-rules ()
       ((_ name body ...)
        (test-group*
          name
          (if (> test-skip-count 0)
              (set! test-skip-count (- test-skip-count 1))
              (let ()
               body ...)))))))
  (else
   (import (srfi 64))))

;; returns new wrapper dto
;; which counts how often each dto's method was called
;; verify that all functions were tested
(define (wrap-dto dto)
  (define proc-count (+ 1 dict-adjoin-accumulator-id))
  (define counter (make-vector proc-count 0))
  (define wrapper-dto-args
    (let loop ((indexes (iota proc-count))
               (args '()))
      (if (null? indexes)
          args
          (let* ((index (car indexes))
                 (real-proc (dto-ref dto index))
                 (wrapper-proc (lambda args
                                 (vector-set! counter index (+ 1 (vector-ref counter index)))
                                 (apply real-proc args))))
            (loop (cdr indexes)
                  (append (list index wrapper-proc)
                          args))))))
  (values
   (apply make-dto wrapper-dto-args)
   counter))

(define (test-for-each expect-success for-each-proc expected-keys)
  (call/cc (lambda (cont)
             (with-exception-handler
               (lambda (err)
                 (unless expect-success
                   (cont #t)))
               (lambda ()
                 (define lst '())
                 (for-each-proc
                   (lambda (key value)
                     (set! lst (append lst (list key)))))
                 (test-equal (length lst) (length expected-keys))
                 (for-each
                   (lambda (key)
                     (test-assert (find (lambda (key*) (equal? key key*))
                                        expected-keys)))
                   lst))))))

(define (do-test real-dto alist->dict comparator mutable?)

  (define-values
      (dto counter)
    (wrap-dto real-dto))

  (test-group
   "dictionary?"
   (test-assert (not (dictionary? dto 'foo)))
   (test-assert (dictionary? dto (alist->dict '())))
   (test-assert (dictionary? dto (alist->dict '((a . b))))))

  (test-group
   "dict-empty?"
   (test-assert (dict-empty? dto (alist->dict '())))
   (test-assert (not (dict-empty? dto (alist->dict '((a . b)))))))

  (test-group
   "dict-contains?"
   (test-assert (not (dict-contains? dto (alist->dict '()) 'a)))
   (test-assert (not (dict-contains? dto (alist->dict '((b . c))) 'a)))
   (test-assert (dict-contains? dto (alist->dict '((a . b))) 'a)))

  (test-group
    "dict=?"
    (define dict1 (alist->dict '((a . 1) (b . 2))))
    (define dict2 (alist->dict '((b . 2) (a . 1))))
    (define dict3 (alist->dict '((a . 1))))
    (define dict4 (alist->dict '((a . 2) (b . 2))))

    (test-assert (dict=? dto = dict1 dict2))
    (test-assert (not (dict=? dto = dict1 dict3)))
    (test-assert (not (dict=? dto = dict3 dict1)))
    (test-assert (not (dict=? dto = dict1 dict4)))
    (test-assert (not (dict=? dto = dict4 dict1))))

  (test-group
   "dict-ref"
   (test-assert (dict-ref dto (alist->dict '((a . b))) 'a (lambda () #f) (lambda (x) #t)))
   (test-assert (dict-ref dto (alist->dict '((a . b))) 'b (lambda () #t) (lambda (x) #f))))

  (test-group
   "dict-ref/default"
   (test-equal (dict-ref/default dto (alist->dict '((a . b))) 'a 'c) 'b)
   (test-equal (dict-ref/default dto (alist->dict '((a* . b))) 'a 'c) 'c))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-set"
   (define dict-original (alist->dict '((a . b))))
   (define d (dict-set dto dict-original 'a 'c 'a2 'b2))
   (test-equal 'c (dict-ref dto d 'a ))
   (test-equal 'b2 (dict-ref dto d 'a2))
   (test-equal 'b (dict-ref dto dict-original' a))
   (test-equal #f (dict-ref/default dto dict-original 'a2 #f)))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-set!"
   (define d (dict-set! dto (alist->dict '((a . b))) 'a 'c 'a2 'b2))
   (test-equal 'c (dict-ref dto d 'a ))
   (test-equal 'b2 (dict-ref dto d 'a2)))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-adjoin"
   (define dict-original (alist->dict '((a . b))))
   (define d (dict-adjoin dto dict-original 'a 'c 'a2 'b2))
   (test-equal 'b (dict-ref dto d 'a))
   (test-equal 'b2 (dict-ref dto d 'a2))
   (test-equal #f (dict-ref/default dto dict-original 'a2 #f)))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-adjoin!"
   (define d (dict-adjoin! dto (alist->dict '((a . b))) 'a 'c 'a2 'b2))
   (test-equal 'b (dict-ref dto d 'a))
   (test-equal 'b2 (dict-ref dto d 'a2)))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-delete"
   (define dict-original (alist->dict '((a . b) (c . d))))
   (define d (dict-delete dto dict-original 'a 'b))
   (test-equal (dict->alist dto d) '((c . d)))
   (test-equal 'b (dict-ref dto dict-original 'a)))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-delete!"
   (define d (dict-delete! dto (alist->dict '((a . b) (c . d))) 'a 'b))
   (test-equal (dict->alist dto d) '((c . d))))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-delete-all"
   (define dict-original (alist->dict '((a . b) (c . d))))
   (define d (dict-delete-all dto dict-original '(a b)))
   (test-equal (dict->alist dto d) '((c . d)))
   (test-equal 'b (dict-ref dto dict-original 'a)))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-delete-all!"
   (define d (dict-delete-all! dto (alist->dict '((a . b) (c . d))) '(a b)))
   (test-equal (dict->alist dto d) '((c . d))))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-replace"
   (define dict-original (alist->dict '((a . b) (c . d))))
   (define d (dict-replace dto dict-original 'a 'b2))
   (test-equal 'b2 (dict-ref dto d 'a))
   (test-equal 'd (dict-ref dto d 'c))
   (test-equal 'b (dict-ref dto dict-original 'a)))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-replace!"
   (define d (dict-replace! dto (alist->dict '((a . b) (c . d))) 'a 'b2))
   (test-equal 'b2 (dict-ref dto d 'a))
   (test-equal 'd (dict-ref dto d 'c)))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-intern"
   ;; intern existing
   (let ()
     (define-values
         (d value)
       (dict-intern dto (alist->dict '((a . b))) 'a (lambda () 'd)))
     (test-equal 'b (dict-ref dto d 'a))
     (test-equal 'b value))
   ;; intern missing
   (let ()
     (define dict-original (alist->dict '((a . b))))
     (define-values
         (d value)
       (dict-intern dto dict-original 'c (lambda () 'd)))
     (test-equal 'b (dict-ref dto d 'a))
     (test-equal 'd (dict-ref dto d 'c))
     (test-equal 'd value)
     (test-equal #f (dict-ref/default dto dict-original 'c #f))))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-intern!"
   ;; intern existing
   (let ()
     (define-values
         (d value)
       (dict-intern! dto (alist->dict '((a . b))) 'a (lambda () 'd)))
     (test-equal 'b (dict-ref dto d 'a))
     (test-equal 'b value))
   ;; intern missing
   (let ()
     (define-values
         (d value)
       (dict-intern! dto (alist->dict '((a . b))) 'c (lambda () 'd)))
     (test-equal 'b (dict-ref dto d 'a))
     (test-equal 'd (dict-ref dto d 'c))
     (test-equal 'd value)))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-update"
   ;; update existing
   (define dict-original (alist->dict '((a . "b"))))
   (let ()
     (define d (dict-update dto dict-original 'a
                            (lambda (value)
                              (string-append value "2"))
                            error
                            (lambda (x) (string-append x "1"))))
     (test-equal "b12" (dict-ref dto d 'a))
     (test-equal "b" (dict-ref dto dict-original 'a)))
   ;; update missing
   (let ()
     (define d (dict-update dto dict-original 'c
                            (lambda (value)
                              (string-append value "2"))
                            (lambda () "d1")
                            (lambda (x) (string-append x "1"))))
     (test-equal "d12" (dict-ref dto d 'c))
     (test-equal #f (dict-ref/default dto dict-original 'c #f))))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-update!"
   ;; update existing
   (let ()
     (define d (dict-update! dto (alist->dict '((a . "b"))) 'a
                             (lambda (value)
                               (string-append value "2"))
                             error
                             (lambda (x) (string-append x "1"))))
     (test-equal "b12" (dict-ref dto d 'a)))
   ;; update missing
   (let ()
     (define d (dict-update! dto (alist->dict '((a . "b"))) 'c
                             (lambda (value)
                               (string-append value "2"))
                             (lambda () "d1")
                             (lambda (x) (string-append x "1"))))
     (test-equal "d12" (dict-ref dto d 'c))))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-update/default"
   ;; update existing
   (define dict-original (alist->dict '((a . "b"))))
   (let ()
     (define d (dict-update/default dto dict-original 'a
                                    (lambda (value)
                                      (string-append value "2"))
                                    "d1"))
     (test-equal "b2" (dict-ref dto d 'a))
     (test-equal "b" (dict-ref dto dict-original 'a)))

   ;; update missing
   (let ()
     (define d (dict-update/default dto dict-original 'c
                                    (lambda (value)
                                      (string-append value "2"))
                                    "d1"))
     (test-equal "d12" (dict-ref dto d 'c))
     (test-equal #f (dict-ref/default dto dict-original 'c #f))))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-update/default!"
   ;; update existing
   (let ()
     (define d (dict-update/default! dto (alist->dict '((a . "b"))) 'a
                                     (lambda (value)
                                       (string-append value "2"))
                                     "d1"))
     (test-equal "b2" (dict-ref dto d 'a)))

   ;; update missing
   (let ()
     (define d (dict-update/default! dto (alist->dict '((a . "b"))) 'c
                                     (lambda (value)
                                       (string-append value "2"))
                                     "d1"))
     (test-equal "d12" (dict-ref dto d 'c))))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-pop"
   (define dict-original (alist->dict '((a . b) (c . d))))
   (define-values
       (new-dict key value)
     (dict-pop dto dict-original))
   (test-assert
       (or
        (and (equal? (dict->alist dto new-dict) '((c . d)))
             (equal? key 'a)
             (equal? value 'b))

        (and (equal? (dict->alist dto new-dict) '((a . b)))
             (equal? key 'c)
             (equal? value 'd))))
   (test-assert 'b (dict-ref dto dict-original 'a))
   (test-assert 'd (dict-ref dto dict-original 'c)))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-pop!"
   (define-values
       (new-dict key value)
     (dict-pop! dto (alist->dict '((a . b) (c . d)))))
   (test-assert
       (or
        (and (equal? (dict->alist dto new-dict) '((c . d)))
             (equal? key 'a)
             (equal? value 'b))

        (and (equal? (dict->alist dto new-dict) '((a . b)))
             (equal? key 'c)
             (equal? value 'd)))))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-map"
   (define dict-original (alist->dict '((a . "a") (b . "b"))))
   (define d (dict-map dto
                       (lambda (key value)
                         (string-append value "2"))
                       dict-original))
   (test-equal "a2" (dict-ref dto d 'a))
   (test-equal "b2" (dict-ref dto d 'b))
   (test-equal "a" (dict-ref dto dict-original 'a))
   (test-equal "b" (dict-ref dto dict-original 'b)))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-map!"
   (define d (dict-map! dto
                        (lambda (key value)
                          (string-append value "2"))
                        (alist->dict '((a . "a") (b . "b")))))
   (test-equal "a2" (dict-ref dto d 'a))
   (test-equal "b2" (dict-ref dto d 'b)))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-filter"
   (define dict-original (alist->dict '((a . b) (c . d))))

   (define d (dict-filter dto
                          (lambda (key value)
                            (equal? value 'b))
                          dict-original))
   (test-equal '((a . b)) (dict->alist dto d))
   (test-equal 'd (dict-ref dto dict-original 'c)))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-filter!"
   (define d (dict-filter! dto
                           (lambda (key value)
                             (equal? value 'b))
                           (alist->dict '((a . b) (c . d)))))
   (test-equal '((a . b)) (dict->alist dto d)))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-remove"
   (define dict-original (alist->dict '((a . b) (c . d))))
   (define d (dict-remove dto
                          (lambda (key value)
                            (equal? value 'b))
                          dict-original))
   (test-equal '((c . d)) (dict->alist dto d))
   (test-equal 'b (dict-ref dto dict-original 'a)))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-remove!"
   (define d (dict-remove! dto
                           (lambda (key value)
                             (equal? value 'b))
                           (alist->dict '((a . b) (c . d)))))
   (test-equal '((c . d)) (dict->alist dto d)))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-find-update"
   ;; ignore
   (let ()
     (define dict (dict-find-update dto (alist->dict '((a . b))) 'c
                              (lambda (insert ignore)
                                (ignore))
                              (lambda args
                                (error "shouldn't happen"))))
     (test-equal '((a . b)) (dict->alist dto dict)))

   ;; insert
   (let ()
     (define dict-original (alist->dict '((a . b))))
     (define dict (dict-find-update dto dict-original 'c
                    (lambda (insert ignore)
                      (insert 'd))
                    (lambda args
                      (error "shouldn't happen"))))
     (test-equal 'b (dict-ref dto dict 'a))
     (test-equal 'd (dict-ref dto dict 'c))
     (test-equal #f (dict-ref/default dto dict-original 'c #f)))

   ;; update
   (let ()
     (define dict-original (alist->dict '((a . b))))
     (define dict (dict-find-update dto dict-original 'a
                              (lambda args
                                (error "shouldn't happen"))
                              (lambda (key value update delete)
                                (update 'a2 'b2))))
     (test-equal '((a2 . b2)) (dict->alist dto dict))
     (test-equal #f (dict-ref/default dto dict-original 'a2 #f))
     (test-equal 'b (dict-ref dto dict-original 'a)))

   ;; delete
   (let ()
     (define dict-original (alist->dict '((a . b) (c . d))))
     (define dict (dict-find-update dto dict-original 'a
                              (lambda args
                                (error "shouldn't happen"))
                              (lambda (key value update delete)
                                (delete))))
     (test-equal '((c . d)) (dict->alist dto dict))
     (test-equal 'b (dict-ref dto dict-original 'a))))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-find-update!"
   ;; ignore
   (let ()
    (define dict (dict-find-update! dto (alist->dict '((a . b))) 'c
                              (lambda (insert ignore)
                                (ignore))
                              (lambda args
                                (error "shouldn't happen"))))
     (test-equal '((a . b)) (dict->alist dto dict)))

   ;; insert
   (let ()
     (define dict (dict-find-update! dto (alist->dict '((a . b))) 'c
                               (lambda (insert ignore)
                                 (insert 'd))
                               (lambda args
                                 (error "shouldn't happen"))))
     (test-equal 'b (dict-ref dto dict 'a))
     (test-equal 'd (dict-ref dto dict 'c)))

   ;; update
   (let ()
     (define dict (dict-find-update! dto (alist->dict '((a . b))) 'a
                               (lambda args
                                 (error "shouldn't happen"))
                               (lambda (key value update delete)
                                 (update 'a2 'b2))))
     (test-equal '((a2 . b2)) (dict->alist dto dict)))

   ;; delete
   (let ()
     (define dict (dict-find-update! dto (alist->dict '((a . b) (c . d))) 'a
                               (lambda args
                                 (error "shouldn't happen"))
                               (lambda (key value update delete)
                                 (delete))))
     (test-equal '((c . d)) (dict->alist dto dict))))

  (test-group
   "dict-size"
   (test-equal 2 (dict-size dto (alist->dict '((a . b) (c . d)))))
   (test-equal 0 (dict-size dto (alist->dict '()))))

  (test-group
   "dict-count"
   (define count (dict-count dto
                             (lambda (key value)
                               (equal? value 'b))
                             (alist->dict '((a . b) (c . d)))))
   (test-equal count 1))

  (test-group
   "dict-any"

   (let ()
     (define value
       (dict-any dto
                 (lambda (key value)
                   (if (equal? 'b value) 'foo #f))
                 (alist->dict '((a . b) (c . d)))))
     (test-equal value 'foo))

   (let ()
     (define value
       (dict-any dto
                 (lambda (key value)
                   (if (equal? 'e value) 'foo #f))
                 (alist->dict '((a . b) (c . d)))))
     (test-equal value #f)))

  (test-group
   "dict-every"
   (let ()
     (define value
       (dict-every dto
                   (lambda (key value)
                     (if (equal? 'b value) 'foo #f))
                   (alist->dict '((a . b) (c . b)))))
     (test-equal value 'foo))

   (let ()
     (define value
       (dict-every dto
                   (lambda (key value)
                     (if (equal? 'b value) 'foo #f))
                   (alist->dict '())))
     (test-equal value #t))

   (let ()
     (define value
       (dict-every dto
                   (lambda (key value)
                     (if (equal? 'b value) 'foo #f))
                   (alist->dict '((a . b) (c . d)))))
     (test-equal value #f)))

  (test-group
   "dict-keys"
   (define keys
     (dict-keys dto (alist->dict '((a . b) (c . d)))))
   (test-assert
       (or (equal? '(a c) keys)
           (equal? '(c a) keys))))

  (test-group
   "dict-values"
   (define vals
     (dict-values dto (alist->dict '((a . b) (c . d)))))
   (test-assert
       (or (equal? '(b d) vals)
           (equal? '(d b) vals))))

  (test-group
   "dict-entries"
   (define-values
       (keys vals)
     (dict-entries dto (alist->dict '((a . b) (c . d)))))
   (test-assert
       (or (and (equal? '(a c) keys)
                (equal? '(b d) vals))
           (and (equal? '(c a) keys)
                (equal? '(d b) vals)))))

  (test-group
   "dict-fold"
   (define value
     (dict-fold dto
                (lambda (key value acc)
                  (append acc (list key value)))
                '()
                (alist->dict '((a . b) (c . d)))))
   (test-assert
       (or (equal? '(a b c d) value)
           (equal? '(c d a b) value))))

  (test-group
   "dict-map->list"
   (define lst
     (dict-map->list dto
                     (lambda (key value)
                       (string-append (symbol->string key)
                                      value))
                     (alist->dict '((a . "b") (c . "d")))))
   (test-assert
       (or (equal? '("ab" "cd") lst)
           (equal? '("cd" "ab") lst))))

  (test-group
   "dict->alist"
   (define alist
     (dict->alist dto (alist->dict '((a . b) (c . d)))))
   (test-assert
       (or (equal? '((a . b) (c . d)) alist)
           (equal? '((c . d) (a . b)) alist))))

  (test-group
   "dict-comparator"
   ;; extremelly basic generic test; more useful specific tests defined separately
   ;; for each dto
   (let ((cmp (dict-comparator dto (alist->dict '((a . b))))))
     (test-assert (or (not cmp)
                      (comparator? cmp)))))

  (test-group
    "dict-for-each"
    (test-for-each #t
      (lambda (proc)
        (dict-for-each dto
                       proc
                       (alist->dict '((1 . a)
                                      (2 . b)
                                      (3 . c)
                                      (4 . d)))))
      '(1 2 3 4)))

  (test-group
    "dict-for-each<"
    (test-for-each (let* ((cmp (dict-comparator dto (alist->dict '())))
                          (ordering (and cmp (comparator-ordered? cmp))))
                     ordering)
      (lambda (proc)
        (dict-for-each< dto
                        proc
                        (alist->dict '((1 . a)
                                       (2 . b)
                                       (3 . c)
                                       (4 . d)))
                        3))
      '(1 2)))

  (test-group
    "dict-for-each<="
    (test-for-each (let* ((cmp (dict-comparator dto (alist->dict '())))
                          (ordering (and cmp (comparator-ordered? cmp))))
                     ordering)
      (lambda (proc)
        (dict-for-each<= dto
                        proc
                        (alist->dict '((1 . a)
                                       (2 . b)
                                       (3 . c)
                                       (4 . d)))
                        3))
      '(1 2 3)))

  (test-group
    "dict-for-each>"
    (test-for-each (let* ((cmp (dict-comparator dto (alist->dict '())))
                          (ordering (and cmp (comparator-ordered? cmp))))
                     ordering)
      (lambda (proc)
        (dict-for-each> dto
                        proc
                        (alist->dict '((1 . a)
                                       (2 . b)
                                       (3 . c)
                                       (4 . d)))
                        2))
      '(3 4)))

  (test-group
    "dict-for-each>="
    (test-for-each (let* ((cmp (dict-comparator dto (alist->dict '())))
                          (ordering (and cmp (comparator-ordered? cmp))))
                     ordering)
      (lambda (proc)
        (dict-for-each>= dto
                        proc
                        (alist->dict '((1 . a)
                                       (2 . b)
                                       (3 . c)
                                       (4 . d)))
                        2))
      '(2 3 4)))

  (test-group
    "dict-for-each-in-open-interval"
    (test-for-each (let* ((cmp (dict-comparator dto (alist->dict '())))
                          (ordering (and cmp (comparator-ordered? cmp))))
                     ordering)
      (lambda (proc)
        (dict-for-each-in-open-interval dto
                                        proc
                                        (alist->dict '((1 . a)
                                                       (2 . b)
                                                       (3 . c)
                                                       (4 . d)))
                                        1 4))
      '(2 3)))

  (test-group
    "dict-for-each-in-closed-interval"
    (test-for-each (let* ((cmp (dict-comparator dto (alist->dict '())))
                          (ordering (and cmp (comparator-ordered? cmp))))
                     ordering)
      (lambda (proc)
        (dict-for-each-in-closed-interval dto
                                        proc
                                        (alist->dict '((1 . a)
                                                       (2 . b)
                                                       (3 . c)
                                                       (4 . d)))
                                        1 4))
      '(1 2 3 4)))

  (test-group
    "dict-for-each-in-open-closed-interval"
    (test-for-each (let* ((cmp (dict-comparator dto (alist->dict '())))
                          (ordering (and cmp (comparator-ordered? cmp))))
                     ordering)
      (lambda (proc)
        (dict-for-each-in-open-closed-interval dto
                                               proc
                                               (alist->dict '((1 . a)
                                                              (2 . b)
                                                              (3 . c)
                                                              (4 . d)))
                                               1 4))
      '(2 3 4)))

  (test-group
    "dict-for-each-in-closed-open-interval"
    (test-for-each (let* ((cmp (dict-comparator dto (alist->dict '())))
                          (ordering (and cmp (comparator-ordered? cmp))))
                     ordering)
      (lambda (proc)
        (dict-for-each-in-closed-open-interval dto
                                               proc
                                               (alist->dict '((1 . a)
                                                              (2 . b)
                                                              (3 . c)
                                                              (4 . d)))
                                               1 4))
      '(1 2 3)))

  (test-group
    "make-dict-generator"
    (test-for-each #t
      (lambda (proc)
        (generator-for-each
          (lambda (entry)
            (proc (car entry) (cdr entry)))
          (make-dict-generator dto (alist->dict '((1 . a)
                                                  (2 . b)
                                                  (3 . c))))))
      '(1 2 3)))

  (test-group
    "dict-set-accumulator"
    (define acc (dict-set-accumulator dto (alist->dict '())))
    (acc (cons 1 'a))
    (acc (cons 2 'b))
    (acc (cons 2 'c))
    (test-assert (dict=? dto equal? (acc (eof-object)) (alist->dict '((1 . a) (2 . c))))))

  (test-group
    "dict-adjoin-accumulator"
    (define acc (dict-adjoin-accumulator dto (alist->dict '())))
    (acc (cons 1 'a))
    (acc (cons 2 'b))
    (acc (cons 2 'c))
    (test-assert (dict=? dto equal? (acc (eof-object)) (alist->dict '((1 . a) (2 . b))))))

  ;; check all procs were called
  (for-each
   (lambda (index)
     (when (> 0 (vector-ref counter index))
       (error "Untested procedure" index)))
   (iota (vector-length counter))))

(test-begin "Dictionaries")

(test-group
 "default"
 ;; test defaults by overring only procedures that raise error otherwise
 (define alist-dto (make-alist-dto equal?))
 (define minimal-alist-dto
   (make-dto
    dictionary?-id (dto-ref alist-dto dictionary?-id)
    dict-mutable?-id (dto-ref alist-dto dict-mutable?-id)
    dict-size-id (dto-ref alist-dto dict-size-id)
    dict-find-update-id (dto-ref alist-dto dict-find-update-id)
    dict-for-each-id (dto-ref alist-dto dict-for-each-id)
    dict-comparator-id (dto-ref alist-dto dict-comparator-id)))
 (do-test
  minimal-alist-dto
  alist-copy
  #f
  #f))

(test-group
 "alist"
 (do-test
  (make-alist-dto equal?)
  ;; copy to a mutable list instead of using identity function
  ;; so that mutating procedures don't fail
  alist-copy
  #f
  #f)

 (test-group
  "alist dict-comparator"
  (test-assert (not (dict-comparator alist-equal-dto '())))))

(cond-expand
  ((and (library (srfi 69))
        (not gauche) ;; gauche has bug with comparator retrieval from srfi 69 table
        )
   (test-group
     "srfi-69"
     (do-test
       srfi-69-dto
       (lambda (alist)
         (define table (t69-make-hash-table equal?))
         (for-each
           (lambda (pair)
             (t69-hash-table-set! table (car pair) (cdr pair)))
           alist)
         table)
       (make-default-comparator)
       #t)))
  (else))

(cond-expand
  ((library (srf 125))
   (test-group
     "srfi-125 mutable"
     (do-test
       hash-table-dto
       (lambda (alist)
         (define table (t125-hash-table-empty-copy (t125-make-hash-table equal?)))
         (for-each
           (lambda (pair)
             (t125-hash-table-set! table (car pair) (cdr pair)))
           alist)
         table)
       (make-default-comparator)
       #t))
   (test-group
     "srfi-125 immutable"
     (do-test
       hash-table-dto
       (lambda (alist)
         (define table (t125-hash-table-empty-copy (t125-make-hash-table equal?)))
         (for-each
           (lambda (pair)
             (t125-hash-table-set! table (car pair) (cdr pair)))
           alist)
         (t125-hash-table-copy table #f))
       (make-default-comparator)
       #f)))
  (else))

(cond-expand
  ((library (srfi 126))
   (test-group
     "srfi-126 (r6rs) mutable"
     (do-test
       srfi-126-dto
       (lambda (alist)
         (define table (t126-make-eqv-hashtable))
         (for-each
           (lambda (pair)
             (t126-hashtable-set! table (car pair) (cdr pair)))
           alist)
         table)
       (make-default-comparator)
       #t))
   (test-group
     "srfi-126 (r6rs) immutable"
     (do-test
       srfi-126-dto
       (lambda (alist)
         (define table (t126-make-eqv-hashtable))
         (for-each
           (lambda (pair)
             (t126-hashtable-set! table (car pair) (cdr pair)))
           alist)
         (t126-hashtable-copy table #f))
       (make-default-comparator)
       #f)))
  (else))

(cond-expand
  ((and (library (srfi 146))
        (library (srfi 146 hash)))
   (test-group
     "srfi-146"
     (define cmp (make-default-comparator))
     (do-test
       mapping-dto
       (lambda (alist)
         (let loop ((table (mapping cmp))
                    (entries alist))
           (if (null? entries)
               table
               (loop (mapping-set! table (caar entries) (cdar entries))
                     (cdr entries)))))
       cmp
       #f)
     (test-group
       "srfi-146 dict-comparator"
       (test-equal cmp (dict-comparator mapping-dto (mapping cmp)))))

   (test-group
     "srfi-146 hash"
     (define cmp (make-default-comparator))
     (do-test
       hash-mapping-dto
       (lambda (alist)
         (let loop ((table (hashmap cmp))
                    (entries alist))
           (if (null? entries)
               table
               (loop (hashmap-set! table (caar entries) (cdar entries))
                     (cdr entries)))))
       cmp
       #f)
     (test-group
       "srfi-146 hash dict-comparator"
       (test-equal cmp (dict-comparator hash-mapping-dto (hashmap cmp))))))
  (else))

(test-end)
