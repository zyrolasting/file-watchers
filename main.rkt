#lang racket/base

(require racket/async-channel
         racket/file
         (only-in racket/function curry const))

(define file-activity-channel (make-async-channel))

(define (path->file-info path)
  (define kind
    (cond [(file-exists? path) 'file]
          [(directory-exists? path) 'directory]
          [(link-exists? path) 'link]
          [else 'dne]))
  (hasheq 'path (simplify-path (path->complete-path path))
          'kind kind
          'mtime (file-or-directory-modify-seconds path #f (const #f))))


(define (make-make-evt [delay/seconds 1000])
  (let* ([spec (system-type 'fs-change)]
         [check-support (λ (index sym) (equal? (vector-ref spec index) sym))]
         [make-poll-evt (make-make-poll-evt delay/seconds)]
         [make-fs-evt (make-make-fs-evt make-poll-evt)])
    (if (and (check-support 0 'supported) (check-support 3 'file-level))
        make-fs-evt
        make-poll-evt)))


(define (make-make-poll-evt delay/seconds)
  (λ (path) (alarm-evt (+ (current-inexact-milliseconds) (/ delay/seconds 1000)))))


(define (make-make-fs-evt make-poll-evt)
  (λ (path) (filesystem-change-evt path (λ () (make-poll-evt path)))))


(define (path-matches-any-pattern? patterns path)
  (ormap (λ (patt) (regexp-match? patt path)) patterns))


(define (find-file-infos patterns path)
  (and (path-matches-any-pattern? patterns path)
       (let ([info (path->file-info path)])
         (case (hash-ref info 'kind)
           [(file) (list info)]
           [(directory)
            (cons info
                  (map (λ (p) (find-file-infos patterns p))
                       (find-files (λ (p) (not (equal? p path))) path)))]
           [(dne) null]))))

(define (accumulate-info start-paths patterns)
  (foldl (λ (p res)
           (with-handlers ([exn:break? (λ (e) res)])
             (append res (find-file-infos patterns p))))
         null
         start-paths))


(define (watch delay/seconds make-evt patterns start-paths)
  (apply sync/enable-break
         (map (λ (path)
                (handle-evt
                 (begin (eprintf "Watching ~a~n" path)
                        (make-evt path))
                 (λ (e)
                   (async-channel-put file-activity-channel path))))
              (accumulate-info start-paths patterns))))

(define (make-watcher delay/seconds patterns start-paths)
  (define make-evt (make-make-evt delay/seconds))
  (thread
   (λ ()
     (let loop ()
       (watch delay/seconds make-evt patterns start-paths)
       (loop)))))


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
   [("-d" "--delay")
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
   (define watcher (make-watcher user-delay user-patterns start-paths))
   (with-handlers ([exn:break?
                    (λ (e)
                      (kill-thread watcher)
                      (thread-wait watcher)
                      (displayln "bye"))])
     (let loop ()
       (writeln (sync/enable-break file-activity-channel))
       (loop)))))
