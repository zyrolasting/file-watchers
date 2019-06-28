#lang racket/base

(require
  "./threads.rkt"
  racket/contract)

(module+ main
  (require
    racket/format
    racket/string
    racket/cmdline
    racket/match
    racket/list)

  (define method-string (make-parameter "robust"))
  (define paths (command-line
    #:program "file-watchers"
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

  (thread-wait (watch-directories paths displayln displayln method)))


(provide
  file-activity-channel
  file-watcher-status-channel
  file-watcher-channel-try-get
  file-watcher-channel-get
  (all-from-out "./robust-watch.rkt")
  (all-from-out "./intensive-watch.rkt")
  (all-from-out "./apathetic-watch.rkt")
  (contract-out
    [suggest-approach   (->* (#:apathetic boolean?) () procedure?)]
    [watch-directories  (->* ()
                             ((listof directory-exists?)
                              (-> list? any)
                              (-> list? any)
                              (-> path? thread?))
                             void?)]))

;; ------------------------------------------------------------------ 
;; Implementation

(require
  racket/async-channel
  "./intensive-watch.rkt"
  "./apathetic-watch.rkt"
  "./robust-watch.rkt"
  "./filesystem.rkt")


(define (suggest-approach #:apathetic apathetic)
  (define spec (system-type 'fs-change))
  (define (check-support index sym) (equal? (vector-ref spec index) sym))
  (define supported (check-support 0 'supported))
  (define file-level (check-support 3 'file-level))
  (if (and supported file-level)
      (if apathetic apathetic-watch intensive-watch)
      robust-watch))

(define (watch-directories
          [directories (list (current-directory))]
          [on-activity displayln]
          [on-status displayln]
          [thread-maker (suggest-approach #:apathetic #f)])
  (define watchers (map thread-maker directories))
  (thread (lambda () (let loop ()
    (define activity (async-channel-try-get (file-activity-channel)))
    (define status (async-channel-try-get (file-watcher-status-channel)))
    (when status (on-status status))
    (when activity (on-activity activity))
    (when (ormap thread-running? watchers) (loop))))))
