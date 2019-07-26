#lang info
(define collection "file-watchers")
(define deps '("rackunit-lib"
               "base"))
(define build-deps '("scribble-lib" "racket-doc" "rackunit-lib"))
(define scribblings '(("scribblings/file-watchers.scrbl" ())))
(define pkg-desc "Recursive file system watching threads")
(define version "0.1")
(define pkg-authors '(Sage Gerard))
(define raco-commands
  '(("file-watchers" file-watchers/cli "Monitor files using file-watchers" #f)))
