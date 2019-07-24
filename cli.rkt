#lang racket/base

(require
  "./main.rkt"
  "./threads.rkt"
  racket/format
  racket/string
  racket/cmdline
  racket/list
  raco/command-name)

(define method-string (make-parameter "robust"))
(define paths (command-line
  #:program (short-program+command-name)
  #:once-each
  [("-m" "--method")  user-method
                      ("Use method: apathetic, intensive, robust (Default: robust)."
                       "Be warned that only 'robust' is cross-platform.")
                      (method-string user-method)]
  #:args user-path-strings
  (if (empty? user-path-strings)
      (list (current-directory))
      (map string->path user-path-strings))))

(define normalized-method-string
  (case (method-string)
     [("robust" "intensive" "apathetic") (method-string)]
     [else "robust"]))

(define method (case normalized-method-string
   [("robust")    robust-watch]
   [("intensive") intensive-watch]
   [("apathetic") apathetic-watch]
   [else          robust-watch]))

(when (not (equal? normalized-method-string (method-string)))
  (printf "Unrecognized method: ~a. Falling back to robust watch.~n" method-string))

(printf "Starting ~a watch over paths:~n~a~n~n"
      normalized-method-string
      (string-join
        (map (lambda (p) (~a "-->  " p)) paths)
        (~a "~n")))

(thread-wait (watch-directories paths displayln displayln method))
