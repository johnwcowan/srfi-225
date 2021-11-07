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

;; returns new wrapper dtd
;; which counts how often each dtd's method was called
;; verify that all functions were tested
(define (wrap-dtd dtd)
  (define proc-count (+ 1 dict-adjoin-accumulator-id))
  (define counter (make-vector proc-count 0))
  (define wrapper-dtd-args
    (let loop ((indexes (iota proc-count))
               (args '()))
      (if (null? indexes)
          args
          (let* ((index (car indexes))
                 (real-proc (dtd-ref dtd index))
                 (wrapper-proc (lambda args
                                 (vector-set! counter index (+ 1 (vector-ref counter index)))
                                 (apply real-proc args))))
            (loop (cdr indexes)
                  (append (list index wrapper-proc)
                          args))))))
  (values
   (apply make-dtd wrapper-dtd-args)
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

(define (do-test real-dtd alist->dict comparator mutable?)

  (define-values
      (dtd counter)
    (wrap-dtd real-dtd))

  (test-group
   "dictionary?"
   (test-assert (not (dictionary? dtd 'foo)))
   (test-assert (dictionary? dtd (alist->dict '())))
   (test-assert (dictionary? dtd (alist->dict '((a . b))))))

  (test-group
   "dict-empty?"
   (test-assert (dict-empty? dtd (alist->dict '())))
   (test-assert (not (dict-empty? dtd (alist->dict '((a . b)))))))

  (test-group
   "dict-contains?"
   (test-assert (not (dict-contains? dtd (alist->dict '()) 'a)))
   (test-assert (not (dict-contains? dtd (alist->dict '((b . c))) 'a)))
   (test-assert (dict-contains? dtd (alist->dict '((a . b))) 'a)))
  
  (test-group
    "dict=?"
    (define dict1 (alist->dict '((a . 1) (b . 2))))
    (define dict2 (alist->dict '((b . 2) (a . 1))))
    (define dict3 (alist->dict '((a . 1))))
    (define dict4 (alist->dict '((a . 2) (b . 2))))
    
    (test-assert (dict=? dtd = dict1 dict2))
    (test-assert (not (dict=? dtd = dict1 dict3)))
    (test-assert (not (dict=? dtd = dict3 dict1)))
    (test-assert (not (dict=? dtd = dict1 dict4)))
    (test-assert (not (dict=? dtd = dict4 dict1))))

  (test-group
   "dict-ref"
   (test-assert (dict-ref dtd (alist->dict '((a . b))) 'a (lambda () #f) (lambda (x) #t)))
   (test-assert (dict-ref dtd (alist->dict '((a . b))) 'b (lambda () #t) (lambda (x) #f))))

  (test-group
   "dict-ref/default"
   (test-equal (dict-ref/default dtd (alist->dict '((a . b))) 'a 'c) 'b)
   (test-equal (dict-ref/default dtd (alist->dict '((a* . b))) 'a 'c) 'c))
  
  (test-group
    "dict-min-key"
    (define dict (alist->dict '((2 . a) (1 . b) (3 . c))))
    (call/cc (lambda (cont)
               (with-exception-handler
                 (lambda (err)
                   (unless (let* ((cmp (dict-comparator dtd (alist->dict '())))
                                  (ordering (and cmp (comparator-ordering-predicate cmp))))
                             ordering)
                     (cont #t)))
                 (lambda ()
                   (define key (dict-min-key dtd dict))
                   (test-equal 1 key))))))
  
  (test-group
    "dict-max-key"
    (define dict (alist->dict '((2 . a) (3 . b) (1 . c))))
    (call/cc (lambda (cont)
               (with-exception-handler
                 (lambda (err)
                   (unless (let* ((cmp (dict-comparator dtd (alist->dict '())))
                                  (ordering (and cmp (comparator-ordering-predicate cmp))))
                             ordering)
                     (cont #t)))
                 (lambda ()
                   (define key (dict-max-key dtd dict))
                   (test-equal 3 key))))))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-set"
   (define dict-original (alist->dict '((a . b))))
   (define d (dict-set dtd dict-original 'a 'c 'a2 'b2))
   (test-equal 'c (dict-ref dtd d 'a ))
   (test-equal 'b2 (dict-ref dtd d 'a2))
   (test-equal 'b (dict-ref dtd dict-original' a))
   (test-equal #f (dict-ref/default dtd dict-original 'a2 #f)))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-set!"
   (define d (dict-set! dtd (alist->dict '((a . b))) 'a 'c 'a2 'b2))
   (test-equal 'c (dict-ref dtd d 'a ))
   (test-equal 'b2 (dict-ref dtd d 'a2)))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-adjoin"
   (define dict-original (alist->dict '((a . b))))
   (define d (dict-adjoin dtd dict-original 'a 'c 'a2 'b2))
   (test-equal 'b (dict-ref dtd d 'a))
   (test-equal 'b2 (dict-ref dtd d 'a2))
   (test-equal #f (dict-ref/default dtd dict-original 'a2 #f)))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-adjoin!"
   (define d (dict-adjoin! dtd (alist->dict '((a . b))) 'a 'c 'a2 'b2))
   (test-equal 'b (dict-ref dtd d 'a))
   (test-equal 'b2 (dict-ref dtd d 'a2)))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-delete"
   (define dict-original (alist->dict '((a . b) (c . d))))
   (define d (dict-delete dtd dict-original 'a 'b))
   (test-equal (dict->alist dtd d) '((c . d)))
   (test-equal 'b (dict-ref dtd dict-original 'a)))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-delete!"
   (define d (dict-delete! dtd (alist->dict '((a . b) (c . d))) 'a 'b))
   (test-equal (dict->alist dtd d) '((c . d))))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-delete-all"
   (define dict-original (alist->dict '((a . b) (c . d))))
   (define d (dict-delete-all dtd dict-original '(a b)))
   (test-equal (dict->alist dtd d) '((c . d)))
   (test-equal 'b (dict-ref dtd dict-original 'a)))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-delete-all!"
   (define d (dict-delete-all! dtd (alist->dict '((a . b) (c . d))) '(a b)))
   (test-equal (dict->alist dtd d) '((c . d))))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-replace"
   (define dict-original (alist->dict '((a . b) (c . d))))
   (define d (dict-replace dtd dict-original 'a 'b2))
   (test-equal 'b2 (dict-ref dtd d 'a))
   (test-equal 'd (dict-ref dtd d 'c))
   (test-equal 'b (dict-ref dtd dict-original 'a)))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-replace!"
   (define d (dict-replace! dtd (alist->dict '((a . b) (c . d))) 'a 'b2))
   (test-equal 'b2 (dict-ref dtd d 'a))
   (test-equal 'd (dict-ref dtd d 'c)))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-intern"
   ;; intern existing
   (let ()
     (define-values
         (d value)
       (dict-intern dtd (alist->dict '((a . b))) 'a (lambda () 'd)))
     (test-equal 'b (dict-ref dtd d 'a))
     (test-equal 'b value))
   ;; intern missing
   (let ()
     (define dict-original (alist->dict '((a . b))))
     (define-values
         (d value)
       (dict-intern dtd dict-original 'c (lambda () 'd)))
     (test-equal 'b (dict-ref dtd d 'a))
     (test-equal 'd (dict-ref dtd d 'c))
     (test-equal 'd value)
     (test-equal #f (dict-ref/default dtd dict-original 'c #f))))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-intern!"
   ;; intern existing
   (let ()
     (define-values
         (d value)
       (dict-intern! dtd (alist->dict '((a . b))) 'a (lambda () 'd)))
     (test-equal 'b (dict-ref dtd d 'a))
     (test-equal 'b value))
   ;; intern missing
   (let ()
     (define-values
         (d value)
       (dict-intern! dtd (alist->dict '((a . b))) 'c (lambda () 'd)))
     (test-equal 'b (dict-ref dtd d 'a))
     (test-equal 'd (dict-ref dtd d 'c))
     (test-equal 'd value)))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-update"
   ;; update existing
   (define dict-original (alist->dict '((a . "b"))))
   (let ()
     (define d (dict-update dtd dict-original 'a
                            (lambda (value)
                              (string-append value "2"))
                            error
                            (lambda (x) (string-append x "1"))))
     (test-equal "b12" (dict-ref dtd d 'a))
     (test-equal "b" (dict-ref dtd dict-original 'a)))
   ;; update missing
   (let ()
     (define d (dict-update dtd dict-original 'c
                            (lambda (value)
                              (string-append value "2"))
                            (lambda () "d1")
                            (lambda (x) (string-append x "1"))))
     (test-equal "d12" (dict-ref dtd d 'c))
     (test-equal #f (dict-ref/default dtd dict-original 'c #f))))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-update!"
   ;; update existing
   (let ()
     (define d (dict-update! dtd (alist->dict '((a . "b"))) 'a
                             (lambda (value)
                               (string-append value "2"))
                             error
                             (lambda (x) (string-append x "1"))))
     (test-equal "b12" (dict-ref dtd d 'a)))
   ;; update missing
   (let ()
     (define d (dict-update! dtd (alist->dict '((a . "b"))) 'c
                             (lambda (value)
                               (string-append value "2"))
                             (lambda () "d1")
                             (lambda (x) (string-append x "1"))))
     (test-equal "d12" (dict-ref dtd d 'c))))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-update/default"
   ;; update existing
   (define dict-original (alist->dict '((a . "b"))))
   (let ()
     (define d (dict-update/default dtd dict-original 'a
                                    (lambda (value)
                                      (string-append value "2"))
                                    "d1"))
     (test-equal "b2" (dict-ref dtd d 'a))
     (test-equal "b" (dict-ref dtd dict-original 'a)))

   ;; update missing
   (let ()
     (define d (dict-update/default dtd dict-original 'c
                                    (lambda (value)
                                      (string-append value "2"))
                                    "d1"))
     (test-equal "d12" (dict-ref dtd d 'c))
     (test-equal #f (dict-ref/default dtd dict-original 'c #f))))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-update/default!"
   ;; update existing
   (let ()
     (define d (dict-update/default! dtd (alist->dict '((a . "b"))) 'a
                                     (lambda (value)
                                       (string-append value "2"))
                                     "d1"))
     (test-equal "b2" (dict-ref dtd d 'a)))

   ;; update missing
   (let ()
     (define d (dict-update/default! dtd (alist->dict '((a . "b"))) 'c
                                     (lambda (value)
                                       (string-append value "2"))
                                     "d1"))
     (test-equal "d12" (dict-ref dtd d 'c))))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-pop"
   (define dict-original (alist->dict '((a . b) (c . d))))
   (define-values
       (new-dict key value)
     (dict-pop dtd dict-original))
   (test-assert
       (or
        (and (equal? (dict->alist dtd new-dict) '((c . d)))
             (equal? key 'a)
             (equal? value 'b))

        (and (equal? (dict->alist dtd new-dict) '((a . b)))
             (equal? key 'c)
             (equal? value 'd))))
   (test-assert 'b (dict-ref dtd dict-original 'a))
   (test-assert 'd (dict-ref dtd dict-original 'c)))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-pop!"
   (define-values
       (new-dict key value)
     (dict-pop! dtd (alist->dict '((a . b) (c . d)))))
   (test-assert
       (or
        (and (equal? (dict->alist dtd new-dict) '((c . d)))
             (equal? key 'a)
             (equal? value 'b))

        (and (equal? (dict->alist dtd new-dict) '((a . b)))
             (equal? key 'c)
             (equal? value 'd)))))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-map"
   (define dict-original (alist->dict '((a . "a") (b . "b"))))
   (define d (dict-map dtd
                       (lambda (key value)
                         (string-append value "2"))
                       dict-original))
   (test-equal "a2" (dict-ref dtd d 'a))
   (test-equal "b2" (dict-ref dtd d 'b))
   (test-equal "a" (dict-ref dtd dict-original 'a))
   (test-equal "b" (dict-ref dtd dict-original 'b)))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-map!"
   (define d (dict-map! dtd
                        (lambda (key value)
                          (string-append value "2"))
                        (alist->dict '((a . "a") (b . "b")))))
   (test-equal "a2" (dict-ref dtd d 'a))
   (test-equal "b2" (dict-ref dtd d 'b)))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-filter"
   (define dict-original (alist->dict '((a . b) (c . d))))

   (define d (dict-filter dtd
                          (lambda (key value)
                            (equal? value 'b))
                          dict-original))
   (test-equal '((a . b)) (dict->alist dtd d))
   (test-equal 'd (dict-ref dtd dict-original 'c)))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-filter!"
   (define d (dict-filter! dtd
                           (lambda (key value)
                             (equal? value 'b))
                           (alist->dict '((a . b) (c . d)))))
   (test-equal '((a . b)) (dict->alist dtd d)))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-remove"
   (define dict-original (alist->dict '((a . b) (c . d))))
   (define d (dict-remove dtd
                          (lambda (key value)
                            (equal? value 'b))
                          dict-original))
   (test-equal '((c . d)) (dict->alist dtd d))
   (test-equal 'b (dict-ref dtd dict-original 'a)))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-remove!"
   (define d (dict-remove! dtd
                           (lambda (key value)
                             (equal? value 'b))
                           (alist->dict '((a . b) (c . d)))))
   (test-equal '((c . d)) (dict->alist dtd d)))

  (when mutable?
    (test-skip 1))
  (test-group
   "dict-alter"
   ;; ignore
   (let ()
     (define dict (dict-alter dtd (alist->dict '((a . b))) 'c
                              (lambda (insert ignore)
                                (ignore))
                              (lambda args
                                (error "shouldn't happen"))))
     (test-equal '((a . b)) (dict->alist dtd dict)))

   ;; insert
   (let ()
     (define dict-original (alist->dict '((a . b))))
     (define dict (dict-alter dtd dict-original 'c
                    (lambda (insert ignore)
                      (insert 'd))
                    (lambda args
                      (error "shouldn't happen"))))
     (test-equal 'b (dict-ref dtd dict 'a))
     (test-equal 'd (dict-ref dtd dict 'c))
     (test-equal #f (dict-ref/default dtd dict-original 'c #f)))

   ;; update
   (let ()
     (define dict-original (alist->dict '((a . b))))
     (define dict (dict-alter dtd dict-original 'a
                              (lambda args
                                (error "shouldn't happen"))
                              (lambda (key value update delete)
                                (update 'a2 'b2))))
     (test-equal '((a2 . b2)) (dict->alist dtd dict))
     (test-equal #f (dict-ref/default dtd dict-original 'a2 #f))
     (test-equal 'b (dict-ref dtd dict-original 'a)))

   ;; delete
   (let ()
     (define dict-original (alist->dict '((a . b) (c . d))))
     (define dict (dict-alter dtd dict-original 'a
                              (lambda args
                                (error "shouldn't happen"))
                              (lambda (key value update delete)
                                (delete))))
     (test-equal '((c . d)) (dict->alist dtd dict))
     (test-equal 'b (dict-ref dtd dict-original 'a))))

  (unless mutable?
    (test-skip 1))
  (test-group
   "dict-alter!"
   ;; ignore
   (let ()
    (define dict (dict-alter! dtd (alist->dict '((a . b))) 'c
                              (lambda (insert ignore)
                                (ignore))
                              (lambda args
                                (error "shouldn't happen"))))
     (test-equal '((a . b)) (dict->alist dtd dict)))

   ;; insert
   (let ()
     (define dict (dict-alter! dtd (alist->dict '((a . b))) 'c
                               (lambda (insert ignore)
                                 (insert 'd))
                               (lambda args
                                 (error "shouldn't happen"))))
     (test-equal 'b (dict-ref dtd dict 'a))
     (test-equal 'd (dict-ref dtd dict 'c)))

   ;; update
   (let ()
     (define dict (dict-alter! dtd (alist->dict '((a . b))) 'a
                               (lambda args
                                 (error "shouldn't happen"))
                               (lambda (key value update delete)
                                 (update 'a2 'b2))))
     (test-equal '((a2 . b2)) (dict->alist dtd dict)))

   ;; delete
   (let ()
     (define dict (dict-alter! dtd (alist->dict '((a . b) (c . d))) 'a
                               (lambda args
                                 (error "shouldn't happen"))
                               (lambda (key value update delete)
                                 (delete))))
     (test-equal '((c . d)) (dict->alist dtd dict))))

  (test-group
   "dict-size"
   (test-equal 2 (dict-size dtd (alist->dict '((a . b) (c . d)))))
   (test-equal 0 (dict-size dtd (alist->dict '()))))

  (test-group
   "dict-count"
   (define count (dict-count dtd
                             (lambda (key value)
                               (equal? value 'b))
                             (alist->dict '((a . b) (c . d)))))
   (test-equal count 1))

  (test-group
   "dict-any"

   (let ()
     (define value
       (dict-any dtd
                 (lambda (key value)
                   (if (equal? 'b value) 'foo #f))
                 (alist->dict '((a . b) (c . d)))))
     (test-equal value 'foo))

   (let ()
     (define value
       (dict-any dtd
                 (lambda (key value)
                   (if (equal? 'e value) 'foo #f))
                 (alist->dict '((a . b) (c . d)))))
     (test-equal value #f)))

  (test-group
   "dict-every"
   (let ()
     (define value
       (dict-every dtd
                   (lambda (key value)
                     (if (equal? 'b value) 'foo #f))
                   (alist->dict '((a . b) (c . b)))))
     (test-equal value 'foo))

   (let ()
     (define value
       (dict-every dtd
                   (lambda (key value)
                     (if (equal? 'b value) 'foo #f))
                   (alist->dict '())))
     (test-equal value #t))

   (let ()
     (define value
       (dict-every dtd
                   (lambda (key value)
                     (if (equal? 'b value) 'foo #f))
                   (alist->dict '((a . b) (c . d)))))
     (test-equal value #f)))

  (test-group
   "dict-keys"
   (define keys
     (dict-keys dtd (alist->dict '((a . b) (c . d)))))
   (test-assert
       (or (equal? '(a c) keys)
           (equal? '(c a) keys))))

  (test-group
   "dict-values"
   (define vals
     (dict-values dtd (alist->dict '((a . b) (c . d)))))
   (test-assert
       (or (equal? '(b d) vals)
           (equal? '(d b) vals))))

  (test-group
   "dict-entries"
   (define-values
       (keys vals)
     (dict-entries dtd (alist->dict '((a . b) (c . d)))))
   (test-assert
       (or (and (equal? '(a c) keys)
                (equal? '(b d) vals))
           (and (equal? '(c a) keys)
                (equal? '(d b) vals)))))

  (test-group
   "dict-fold"
   (define value
     (dict-fold dtd
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
     (dict-map->list dtd
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
     (dict->alist dtd (alist->dict '((a . b) (c . d)))))
   (test-assert
       (or (equal? '((a . b) (c . d)) alist)
           (equal? '((c . d) (a . b)) alist))))

  (test-group
   "dict-comparator"
   ;; extremelly basic generic test; more useful specific tests defined separately
   ;; for each dtd
   (let ((cmp (dict-comparator dtd (alist->dict '((a . b))))))
     (test-assert (or (not cmp)
                      (comparator? cmp)))))
  
  (test-group
    "dict-for-each"
    (test-for-each #t
      (lambda (proc)
        (dict-for-each dtd 
                       proc 
                       (alist->dict '((1 . a)
                                      (2 . b)
                                      (3 . c)
                                      (4 . d)))))
      '(1 2 3 4)))

  (test-group
    "dict-for-each<"
    (test-for-each (let* ((cmp (dict-comparator dtd (alist->dict '())))
                          (ordering (and cmp (comparator-ordering-predicate cmp))))
                     ordering)
      (lambda (proc)
        (dict-for-each< dtd 
                        proc 
                        (alist->dict '((1 . a)
                                       (2 . b)
                                       (3 . c)
                                       (4 . d)))
                        3))
      '(1 2)))

  (test-group
    "dict-for-each<="
    (test-for-each (let* ((cmp (dict-comparator dtd (alist->dict '())))
                          (ordering (and cmp (comparator-ordering-predicate cmp))))
                     ordering)
      (lambda (proc)
        (dict-for-each<= dtd 
                        proc 
                        (alist->dict '((1 . a)
                                       (2 . b)
                                       (3 . c)
                                       (4 . d)))
                        3))
      '(1 2 3)))
  
  (test-group
    "dict-for-each>"
    (test-for-each (let* ((cmp (dict-comparator dtd (alist->dict '())))
                          (ordering (and cmp (comparator-ordering-predicate cmp))))
                     ordering)
      (lambda (proc)
        (dict-for-each> dtd 
                        proc 
                        (alist->dict '((1 . a)
                                       (2 . b)
                                       (3 . c)
                                       (4 . d)))
                        2))
      '(3 4)))
  
  (test-group
    "dict-for-each>="
    (test-for-each (let* ((cmp (dict-comparator dtd (alist->dict '())))
                          (ordering (and cmp (comparator-ordering-predicate cmp))))
                     ordering)
      (lambda (proc)
        (dict-for-each>= dtd 
                        proc 
                        (alist->dict '((1 . a)
                                       (2 . b)
                                       (3 . c)
                                       (4 . d)))
                        2))
      '(2 3 4)))
  
  (test-group
    "dict-for-each-in-open-interval"
    (test-for-each (let* ((cmp (dict-comparator dtd (alist->dict '())))
                          (ordering (and cmp (comparator-ordering-predicate cmp))))
                     ordering)
      (lambda (proc)
        (dict-for-each-in-open-interval dtd 
                                        proc 
                                        (alist->dict '((1 . a)
                                                       (2 . b)
                                                       (3 . c)
                                                       (4 . d)))
                                        1 4))
      '(2 3)))
  
  (test-group
    "dict-for-each-in-closed-interval"
    (test-for-each (let* ((cmp (dict-comparator dtd (alist->dict '())))
                          (ordering (and cmp (comparator-ordering-predicate cmp))))
                     ordering)
      (lambda (proc)
        (dict-for-each-in-closed-interval dtd 
                                        proc 
                                        (alist->dict '((1 . a)
                                                       (2 . b)
                                                       (3 . c)
                                                       (4 . d)))
                                        1 4))
      '(1 2 3 4)))
  
  (test-group
    "dict-for-each-in-open-closed-interval"
    (test-for-each (let* ((cmp (dict-comparator dtd (alist->dict '())))
                          (ordering (and cmp (comparator-ordering-predicate cmp))))
                     ordering)
      (lambda (proc)
        (dict-for-each-in-open-closed-interval dtd 
                                               proc 
                                               (alist->dict '((1 . a)
                                                              (2 . b)
                                                              (3 . c)
                                                              (4 . d)))
                                               1 4))
      '(2 3 4)))
  
  (test-group
    "dict-for-each-in-closed-open-interval"
    (test-for-each (let* ((cmp (dict-comparator dtd (alist->dict '())))
                          (ordering (and cmp (comparator-ordering-predicate cmp))))
                     ordering)
      (lambda (proc)
        (dict-for-each-in-closed-open-interval dtd 
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
          (make-dict-generator dtd (alist->dict '((1 . a) 
                                                  (2 . b)
                                                  (3 . c))))))
      '(1 2 3)))
  
  (test-group
    "dict-set-accumulator"
    (define acc (dict-set-accumulator dtd (alist->dict '())))
    (acc (cons 1 'a))
    (acc (cons 2 'b))
    (acc (cons 2 'c))
    (test-assert (dict=? dtd equal? (acc (eof-object)) (alist->dict '((1 . a) (2 . c))))))
  
  (test-group
    "dict-adjoin-accumulator"
    (define acc (dict-adjoin-accumulator dtd (alist->dict '())))
    (acc (cons 1 'a))
    (acc (cons 2 'b))
    (acc (cons 2 'c))
    (test-assert (dict=? dtd equal? (acc (eof-object)) (alist->dict '((1 . a) (2 . b))))))

  ;; check all procs were called
  (for-each
   (lambda (index)
     (when (= 0 (vector-ref counter index))
       (error "Untested procedure" index)))
   (iota (vector-length counter))))

(test-begin "Dictionaries")

(test-group
 "default"
 ;; test defaults by overring only procedures that raise error otherwise
 (define alist-dtd (make-alist-dtd equal?))
 (define minimal-alist-dtd
   (make-dtd
    dictionary?-id (dtd-ref alist-dtd dictionary?-id)
    dict-mutable?-id (dtd-ref alist-dtd dict-mutable?-id)
    dict-size-id (dtd-ref alist-dtd dict-size-id)
    dict-alter-id (dtd-ref alist-dtd dict-alter-id)
    dict-for-each-id (dtd-ref alist-dtd dict-for-each-id)
    dict-comparator-id (dtd-ref alist-dtd dict-comparator-id)))
 (do-test
  minimal-alist-dtd
  alist-copy
  #f
  #f
  ))

(test-group
 "alist"
 (do-test
  (make-alist-dtd equal?)
  ;; copy to a mutable list instead of using identity function
  ;; so that mutating procedures don't fail
  alist-copy
  #f
  #f) 

 (test-group
  "alist dict-comparator"
  (test-assert (not (dict-comparator alist-equal-dtd '())))))

(test-group
 "plist"
 (do-test
  plist-dtd
  (lambda (alist)
    (apply append
           (map (lambda (pair)
                  (list (car pair) (cdr pair)))
                alist)))
  #f
  #f)
 (test-group
  "plist dict-comparator"
  (test-assert (not (dict-comparator plist-dtd '())))))

(cond-expand
  ((and (library (srfi 69))
        (not gauche)) ;; gauche has bug with comparator retrieval from srfi 69 table
   (test-group
     "srfi-69"
     (do-test
       srfi-69-dtd
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
       hash-table-dtd
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
       hash-table-dtd
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
       srfi-126-dtd
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
       srfi-126-dtd
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
       mapping-dtd
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
       (test-equal cmp (dict-comparator mapping-dtd (mapping cmp)))))

   (test-group
     "srfi-146 hash"
     (define cmp (make-default-comparator))
     (do-test
       hash-mapping-dtd
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
       (test-equal cmp (dict-comparator hash-mapping-dtd (hashmap cmp))))))
  (else))

(test-end)
