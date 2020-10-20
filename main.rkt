#lang racket/base

; A cross-platform filesystem monitor.

(require racket/contract)

(define fs-kind/c (or/c 'dne 'link 'directory 'file))

(provide
 (contract-out
  [fs-kind/c flat-contract?]

  [make-watcher (-> (-> hash? hash? any)
                    (>=/c 0)
                    (listof (or/c regexp? pregexp?))
                    (listof path-string?)
                    (-> path? fs-kind/c any/c)
                    thread?)]

  [capture-file-info
   (-> (listof path-string?)
       (listof (or/c regexp? pregexp?))
       (-> path? fs-kind/c any/c)
       hash?)]

  [diff-file-info
   (-> hash? hash? hash?)]

  [default-path->info
    (-> path? fs-kind/c (list/c fs-kind/c exact-positive-integer?))]))


(require racket/file
         racket/function
         racket/hash
         racket/path
         racket/sequence)


(define (make-watcher on-activity delay/milliseconds patterns start-paths path->info)
  (let ([capture (λ () (capture-file-info start-paths patterns path->info))])
    (thread
     (λ ()
       (with-handlers ([exn:break? void])
         (let loop ([pre (capture)])
           (sync/enable-break
            (handle-evt (poll-evt delay/milliseconds)
                        (λ (e)
                          (let ([post (capture)])
                            (on-activity pre post)
                            (loop post)))))))))))


(define (fs-kind path)
  (cond [(file-exists? path) 'file]
        [(directory-exists? path) 'directory]
        [(link-exists? path) 'link]
        [else 'dne]))


(define (default-path->info path kind)
  (list kind
        (file-or-directory-modify-seconds path #f (const #f))))


(define (diff-file-info before now)
  (for/fold ([diff (hash)])
            ([k (sequence-append (in-hash-keys before) (in-hash-keys now))])
    (define exists-before? (hash-has-key? before k))
    (define exists-now? (hash-has-key? now k))
    (cond [(and exists-before? exists-now?)
           (if (equal? (hash-ref before k) (hash-ref now k))
               diff
               (hash-set diff k '*))]

          [(and exists-before? (not exists-now?))
           (hash-set diff k '-)]

          [(and (not exists-before?) exists-now?)
           (hash-set diff k '+)]

          [else (hash-set diff k #f)])))


(define (poll-evt delay/milliseconds)
  (alarm-evt (+ (current-inexact-milliseconds)
                delay/milliseconds)))


(define (path-matches-any-pattern? patterns path)
  (ormap (λ (patt) (regexp-match? patt path))
         patterns))


(define (find-file-infos path->info patterns unnormalized-path)
  (define path (normalize-path (path->complete-path unnormalized-path)))
  (if (path-matches-any-pattern? patterns path)
      (let ([kind (fs-kind path)])
        (case kind
          [(file)
           (hash path (path->info path kind))]
          [(directory)
           (hash-set (capture-file-info (directory-list #:build? #t path) patterns path->info)
                     path
                     (path->info path kind))]
          [(dne)
           (hash)]))
      (hash)))


(define (capture-file-info start-paths patterns path->info)
  (foldl (λ (p res)
           (with-handlers ([exn:break? (const res)])
             (hash-union #:combine/key (λ (k v1 v2) v2)
                         res
                         (find-file-infos path->info patterns p))))
         (hash)
         start-paths))


(module+ main
  (require racket/cmdline)

  (define user-delay 1000)
  (define user-patterns null)

  (command-line
   #:multi
   [("+p" "++pattern")
    pregexp-pattern
    "A Perl regular expression to match against paths. Can be set multiple times."
    (with-handlers
      ([exn:fail? (λ (e)
                    (eprintf "~s does not appear to be a valid pattern.~a"
                             pregexp-pattern)
                    (exit 1))])
      (set! user-patterns
            (cons (pregexp pregexp-pattern)
                  user-patterns)))]

   #:once-each
   [("-d" "--delay-ms")
    milliseconds
    "How long to wait before polling the filesystem"
    (define maybe-num (string->number milliseconds))
    (unless maybe-num
      (eprintf "~s does not appear to be a number.~n"
               maybe-num)
      (exit 1))
    (set! user-delay maybe-num)]

   #:args start-paths
   (set! user-patterns (if (null? user-patterns) (list (pregexp "")) user-patterns))
   (set! start-paths (if (null? start-paths) (list (current-directory)) start-paths))

   (define (on-activity before now)
     (for ([(path status) (diff-file-info before now)])
       (printf "~a ~a~n" status path)))

   (thread-wait (make-watcher on-activity
                              user-delay
                              user-patterns
                              start-paths
                              default-path->info))))
