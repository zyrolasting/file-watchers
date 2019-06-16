#lang racket/base

;; This module provides a cross-platform, polling based file watch.

(require
  racket/contract)

(provide
  (contract-out
    [robust-poll-milliseconds (parameter/c exact-positive-integer?)]
    [robust-watch  (->* () (directory-exists?) thread?)]))


;; ------------------------------------------------------------------ 
;; Implementation

(require
  racket/hash
  "./filesystem.rkt"
  "./threads.rkt")

(define-values (report-activity report-status) (report-iface 'robust))

(define robust-poll-milliseconds (make-parameter 250))

(define (get-file-attributes path)
  (with-handlers ([exn:fail? (lambda () #f)])
                 (cons (file-or-directory-modify-seconds path)
                       (file-or-directory-permissions path 'bits))))

(define (get-listing-numbers listing)
  (foldl
    (lambda (p res)
      (define attrs (get-file-attributes p))
      (append res (list
                    (if (not attrs)
                        -1
                        (+ (car attrs) (cdr attrs))))))
    '()
    listing))

(define (get-robust-state path)
    (define listing (recursive-file-list path))
    (make-immutable-hash (map cons
                              listing
                              (get-listing-numbers listing))))

(define (mark-changes prev next)
  (hash-union prev next
              #:combine/key (lambda (k a b)
                              (if (= a b) 'same 'change))))

(define (mark-status prev next)
  (make-immutable-hash
    (map
      (lambda (pair)
        (if (symbol? (cdr pair))
          pair
          (cons (car pair)
                (if (path-on-disk? (car pair)) 'add 'remove))))
      (hash->list (mark-changes prev next)))))

(define (robust-watch [path (current-directory)])
  (thread (lambda ()
    (define initial (get-robust-state path))
    (let loop ([state initial])
      (sync/enable-break (alarm-evt (+ (current-inexact-milliseconds)
                                       (robust-poll-milliseconds))))
      (if (directory-exists? path)
        (let ([next (get-robust-state path)])
          (hash-for-each
            (mark-status state next)
            (lambda (path op)
              (unless (equal? op 'same)
                (report-activity op path))))
          (loop next))
        (report-activity 'remove path))))))
