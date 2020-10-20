#lang scribble/manual

@require[@for-label["main.rkt"
                    racket/base
                    racket/contract
                    racket/file
                    racket/path]
         racket/runtime-path]

@(define-runtime-path main.rkt "main.rkt")

@title{Filesystem Monitoring}

@(declare-exporting ,(path->complete-path main.rkt))

file-watchers monitors at least one file or directory with the same
level of precision across platforms. It uses memory proportional to
the number of paths watched, and the number of paths it watches may
change over time as files are added to--or removed from--monitored
directories.

You can use file-watchers as a command line application, or as
a Racket library.


@section{Command Line Interface}

For the command line app, launch main.rkt using Racket

@verbatim[#:indent 2]|{
$ racket main.rkt
}|

This command handles the simplest case: watch everything inside the
current directory. Whenever you change something in the directory, the
process will write a hash table to STDOUT. Hit Control-C to stop the
application.

Alternatively, you can name the current directory explicitly. This
command does the same thing.

@verbatim[#:indent 2]|{
$ racket main.rkt .
}|

Keep adding paths as you please. Each argument is a path to a file or
directory to watch.

@verbatim[#:indent 2]|{
$ racket main.rkt ./posts/ ./README.md
}|

The application polls the filesystem every so often. By default, it
polls every second. You can change the delay using
@litchar{-d/--delay-ms}, which adjusts the delay using milliseconds.

Long form:
@verbatim[#:indent 2]|{
$ racket main.rkt --delay-ms 2000 ./posts/ README.md
}|

Short form:
@verbatim[#:indent 2]|{
$ racket main.rkt -d 2000 ./posts/ README.md
}|

Note that this only controls the length of time between polls, not how
long it takes for the process to collect information about all
monitored files.

Finally, you can add Perl-style regular expressions using
@litchar{++pattern/+p}.  Each pattern filters out files to watch.  You
can leverage this to abbreviate your commands.

Long form:
@verbatim[#:indent 2]|{
$ racket main.rkt --delay-ms 2000 ++pattern '\.md$' ++pattern '\.txt$' ./posts/ ./README.md
}|

Short form:
@verbatim[#:indent 2]|{
$ racket main.rkt -d 2000 +p '\.(md|txt)$' .
}|


@section{API}

@defthing[fs-kind/c flat-contract? #:value (or/c 'dne 'link 'directory 'file)]{
A contract used by the @racket[get-info] argument in the
@racket[make-watcher] and @racket[capture-file-info] procedures. A
compliant symbol describes the kind of filesystem entry referenced by
a path.
}


@defproc[(make-watcher [after-poll (-> hash? hash? any)]
                       [delay-ms (>=/c 0)]
                       [patterns (listof (or/c regexp? pregexp?))]
                       [start-paths (listof path-string?)]
                       [get-info (-> path? fs-kind/c any/c)])
                       thread?]{
Returns a thread used watch file information from a list of given
paths.  Specifically, it reports the value of
@racket[(capture-file-info start-paths patterns get-info)] over time.

The thread applies @racket[(after-poll before now)], with @italic{at
least} @racketid[delay-ms] milliseconds between
calls. @racketid[before] and @racketid[now] are both values returned
from @racket[(capture-file-info start-paths patterns get-info)].  The
difference being that @racketid[now] was computed after
@racketid[before].

This process will continue until the thread terminates.  If any (or
every) path in @racket[start-paths] is removed, then the thread will
note this and continue. If new files or directories are added that are
reachable from @racket[start-paths], then the thread will monitor them
too.
}

@defproc[(capture-file-info [start-paths (listof path-string?)]
                            [patterns (listof (or/c regexp? pregexp?))]
                            [get-info (-> path? fs-kind/c any/c)])
                            hash?]{
Returns a hash table that maps a path @racketid[P] to
@racket[(get-info P kind)], @racket[P] matches at least one of the
@racket[patterns], and @racketid[kind] is one of the following:

@itemlist[
@item{@racket['dne]: @racketid[P] does not point to an existing file, directory, or link.}
@item{@racket['link]: @racketid[P] points to a link}
@item{@racket['directory]: @racketid[P] points to a directory.}
@item{@racket['file]: @racketid[P] points to a file.}
]

@racket[capture-file-info] will visit every file or directory from
@racket[start-paths], including all directory contents.
}

@defproc[(diff-file-info [before hash?] [now hash?]) (hash/c path? (or/c '+ '- '* #f))]{
Returns a hash table that maps a path @racketid[P] to one of the following symbols:

@margin-note{The @racket[get-info] procedure used in
@racket[capture-file-info] can change when @racket[diff-file-info]
uses @racket['*].}

@itemlist[
@item{@racket['+]: @racketid[P] appeared on disk.}

@item{@racket['-]: @racketid[P] appeared on disk.}

@item{@racket['*]: The file, directory, or link referenced by @racketid[P] has changed,
      because @racket[(not (equal? (hash-ref before P) (hash-ref now P)))].}

@item{@racket[#f]: @racketid[P] was removed as a key from
@racket[before] or @racket[now] before a determination could be
made. @racket[#f] would only appear as a consequence of a
synchronization bug that unsafely modifies @racket[before] or
@racket[now]. It is not expected, and is mentioned here only for
completeness reasons.}

]


}

@defthing[default-path->info (-> path? fs-kind/c (list/c fs-kind/c exact-positive-integer?))]{
A procedure suitable for use in the @racket[get-info] argument for
@racket[make-watcher] or @racket[capture-file-info]. It merely returns
a list with the given @racket[fs-kind/c] symbol and the output of
@racket[file-or-directory-modify-seconds].
}
