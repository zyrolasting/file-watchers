# `file-watchers`

This is the out-of-the-box way to watch files you have been looking for in Racket.

Use this to understand I/O behavior in a system and to increase iteration speed for local development.

* `raco test *.rkt` to run tests
* `racket main.rkt [-m apathetic, robust, or intensive] DIRECTORY ...` to watch the given directories with one of the methods in the project. See the documentation for more.
* `raco setup -l file-watchers` to build the package and documentation.
