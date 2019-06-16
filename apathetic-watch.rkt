#lang racket/base

(require
  racket/contract)

(provide
  (contract-out
    [apathetic-watch  (->* () (directory-exists?) thread?)]))

;; ------------------------------------------------------------------ 
;; Implementation

(require
  racket/file
  racket/async-channel
  "./filesystem.rkt"
  "./threads.rkt")

(define-values (report-activity report-status) (report-iface 'apathetic))

(define (apathetic-watch [path (current-directory)])
  (thread (lambda ()
    (let loop ()
      (when (directory-exists? path)
        (with-handlers ([exn:fail:filesystem? (lambda (e) (void))])
          (sync/enable-break
            (guard-evt (lambda () (report-status 'watching path) never-evt))
            (bulk-filesystem-change-evt (append (list path) (recursive-file-list path))))
          (report-activity 'change path)
          (loop)))))))

(module+ test
  (require
    rackunit
    (submod "./filesystem.rkt" test-lib)
    (submod "./threads.rkt" test-lib))

  (parameterize ([current-directory (create-temp-directory)])
    (define th (apathetic-watch))
    (define wd (current-directory))
    (define (lifecycle thunk)
      (expect-status (list 'apathetic 'watching wd))
      (thunk)
      (expect-activity (list 'apathetic 'change wd)))

    (lifecycle (lambda () (create-file "a")))
    (lifecycle (lambda () (make-directory "dir")))
    (lifecycle (lambda () (create-file "dir/b")))
    (lifecycle (lambda () (delete-directory/files wd)))
    (expect-silence)
    (check-true (thread-dead? th))))
