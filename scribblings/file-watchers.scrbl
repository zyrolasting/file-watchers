#lang scribble/manual
@require[@for-label[file-watchers
                    racket/base]]

@title{Monitoring file system activity with file-watchers}
@author{Sage Gerard}

@defmodule[file-watchers]

Use file-watchers to audit and react to file activity in a system.

@section{Quick Start}

For command-line use, use the @racket[file-watchers] raco command.

@verbatim[#:indent 2]|{
  $ raco file-watchers -h # For help
  $ raco file-watchers dir # Watch given directory

  # Watch directories with a given method (methods documented below).
  $ raco file-watchers -m apathetic dir
  $ raco file-watchers -m robust dir
  $ raco file-watchers -m intensive dir
}|


For programmatic use, you can apply @racket[watch-directories] to
a list of target directories.

@racketblock[
(require file-watchers)

(define watcher (watch-directories '("/path/to/dir")))
]

By default, lists describing file activity from the watched directory
will appear via @racket[displayln].

@defproc[(watch-directories
  [directories (listof directory-exists?) (list (current-directory))]
  [on-activity (-> list? any) displayln]
  [on-status (-> list? any) displayln]
  [thread-maker (-> path? thread?) (suggest-approach #:apathetic #f)])
  thread?]{

Starts threads using @racket[thread-maker] to watch each given directory.
Meant for use with file-watcher procedures, namely
@racket[apathetic-watch], @racket[intensive-watch], or @racket[robust-watch].

The thread returned by @racket[watch-directories] will wait all threads created with @racket[thread-maker] terminate.}

@defproc[(suggest-approach [#:apathetic apathetic boolean?])
         procedure?]{

Returns a file watcher procedure depending on the output of @racket[(system-type 'fs-change)].
If @racket[apathetic] is true, @racket[apathetic-watch] will be returned instead of
@racket[intensive-watch] in the event that file-level monitoring is supported.

If file change events are not supported on the operating system or if file-level monitoring is unavailable,
then @racket[robust-watch] is returned.}

@section{Synchronization}

All file monitoring occurs in at least one thread. Activity
and status information are each conveyed on a dedicated
asynchronous channel. For more, see @secref["async-channel" #:doc '(lib "scribblings/reference/reference.scrbl")].

Each channel message is a @racket[list] that starts with
a symbol for the associated file monitoring method,
followed by a symbol indicating the kind of activity
or status reported. For example, an @racket[apathetic-watch]
will convey that it is watching a directory and a change
was detected somewhere inside it.

@racketblock[
'(apathetic watching /path/to/dir)
]

A @racket['watching] status comes from @racket[file-watcher-status-channel],
while detected file activity comes from @racket[file-activity-channel].


@defthing[file-activity-channel (parameter/c async-channel?)]{
A @racket[parameter] for a @racket[channel] that reports file
system activity depending on the monitoring approach.
}

@defthing[file-watcher-status-channel (parameter/c async-channel?)]{
A @racket[parameter] for a @racket[channel] that reports a specific
watchers status. The meaning of a status depends on how a watcher
carries out its task.
}

@defproc[(file-watcher-channel-try-get) (or/c boolean? list?)]{

Returns the next available message from @racket[file-watcher-status-channel],
or @racket[file-activity-channel], in that order. Returns @racket[#f] if no
message is available.}

@defproc[(file-watcher-channel-get) (or/c boolean? list?)]{

Waits for and returns the next available message from @racket[file-watcher-status-channel], or @racket[file-activity-channel].}

@section{Detecting changes without concern for root cause}

@defproc[#:kind "file-watcher"
(apathetic-watch [path directory-exists?])
                 thread?]{

An @italic{apathetic} thread recursively scans the given
directory and waits for the first to trigger a
@racket[filesystem-change-evt].}

An apathetic thread reports a @racket[(list 'apathetic 'watching path)] status on
@racket[file-watcher-status-channel] each time it starts waiting for a change.
There are no other status messages and the thread will terminate
when it can no longer access the directory located at the given @racket[path].

@racket[file-activity-channel] will only report
@racket[(list 'apathetic 'change path)] when any change
is detected.

The below example starts an apathetic watch thread,
waits for the thread to report that it is watching
@racket["dir"], then deletes @racket["dir"].
The apathetic watcher thread will report that the change occurred
on @racket[file-activity-channel] before terminating,
since @racket["dir"] was the root path for the
watching thread.

@racketblock[
(define apathetic-watcher (apathetic-watch "dir"))

(sync/enable-break (file-watcher-status-channel))
(delete-directory "dir")
(displayln (sync/enable-break (file-activity-channel)))

(thread-wait apathetic-watcher)
(displayln (thread-dead? apathetic-watcher))
]


@section{Poll-based file monitoring}

@defproc[#:kind "file-watcher"
(robust-watch [path directory-exists?])
              thread?]{

A @racket[robust] watch operates on a polling mechanism that compares
recursive listings of the given directory @racket[path] to report changes.
This approach is cross-platform, but cannot detect any activity between
filesystem polls.

Furthermore, @racket[robust-watch] only detects changes in file permissions and access time.

@racket[robust-watch] only reports @racket['add], @racket['change], and @racket['remove]
events on @racket[file-activity-channel]. It does not report status information
on @racket[file-watcher-status-channel].}

@defthing[robust-poll-milliseconds (parameter/c exact-positive-integer?)]{
A @racket[parameter] for the number of milliseconds a robust watch poll
should wait before comparing directory listings. This defaults to @racket[250].
}

@section{Verbose file-level monitoring}

@defproc[#:kind "file-watcher"
(intensive-watch [path directory-exists?])
                 thread?]{

An @italic{intensive} watch dedicates a thread to each
file in the directory to monitor with a separate @racket[filesystem-change-evt].
Due to the resource-hungry nature of the model, an intensive watch may
warrant a dedicated custodian.

If a link file is accessed in a way that impacts the link's target, both
the link file and the target file will be marked as changed.

Status information appears on @racket[file-watcher-status-channel] under the following rules:

@itemlist[@item{@racket[(list 'intensive 'new-thread detected-path)] appears when a new thread is created to monitor a created file.}
          @item{@racket[(list 'intensive 'thread-done path)] appears when a thread dies, meaning it is no longer monitoring the given path.}]

Activity information appears on @racket[file-activity-channel] under the following rules:

@itemlist[@item{@racket[(list 'intensive 'add detected-path)] appears when a new file is detected.}
          @item{@racket[(list 'intensive 'remove path)] appears when a file or directory is found to no longer exist.}
          @item{@racket[(list 'intensive 'change path)] appears when a file or directory at the given path triggers a @racket[filesystem-change-evt].}]
}
