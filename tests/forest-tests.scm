(require "../forest/core.scm")
(require "#%private/steel/ports")

(define test-root
  (if (null? std::env::args)
      (error "tests require an isolated temporary root")
      (car std::env::args)))

(define checks 0)

(define (check-equal! name actual expected)
  (set! checks (+ checks 1))
  (unless (equal? actual expected)
    (error (string-append name ": expected " (to-string expected) ", got " (to-string actual)))))

(define (check! name actual)
  (check-equal! name (not (not actual)) #t))

(define (raises? thunk)
  (with-handler (lambda (_) #t) (begin (thunk) #f)))

(define (run! program args)
  (define spawned (~> (command program args) spawn-process))
  (unless (Ok? spawned) (error (string-append "could not run " program)))
  (define status (wait (Ok->value spawned)))
  (unless (and (Ok? status) (= (Ok->value status) 0))
    (error (string-append program " failed"))))

(define (run-output! program args)
  (define spawned (~> (command program args)
                      with-stdout-piped
                      with-stderr-piped
                      spawn-process))
  (unless (Ok? spawned) (error (string-append "could not run " program)))
  (define child (Ok->value spawned))
  (define output (read-port-to-string (child-stdout child)))
  (define stderr (read-port-to-string (child-stderr child)))
  (define status (wait child))
  (unless (and (Ok? status) (= (Ok->value status) 0))
    (error (string-append program " failed: " stderr)))
  output)

(define (mkdir! path)
  (run! "mkdir" (list "-p" path)))

(define (write-text! path content)
  (call-with-output-file path (lambda (port) (write-string content port))))

(define (write-binary! path)
  (call-with-output-file path (lambda (port) (write-bytes (bytes 0 1 2 3) port))))

(define workspace (string-append test-root (path-separator) "workspace"))
(define outside (string-append test-root (path-separator) "outside"))
(mkdir! (string-append workspace (path-separator) "sub"))
(mkdir! outside)
(run! "ln" (list "-s" outside (string-append workspace (path-separator) "escape")))

;; Create is workspace-relative and may name nested descendants. Rename is one
;; basename in the selected entry's canonical parent.
(define created (forest-confined-create-path workspace "sub/new file.txt"))
(check-equal! "create path" (car created)
              (string-append (canonicalize-path workspace) (path-separator) "sub/new file.txt"))
(check-equal! "create kind" (cdr created) #f)
(check-equal! "directory suffix" (cdr (forest-confined-create-path workspace "new-dir/")) #t)
(check-equal! "create permits zero digits"
              (car (forest-confined-create-path workspace "sub/file-01.txt"))
              (string-append (canonicalize-path workspace) (path-separator) "sub/file-01.txt"))
(check-equal! "create permits Unix colon names"
              (car (forest-confined-create-path workspace "sub/a:b.txt"))
              (string-append (canonicalize-path workspace) (path-separator) "sub/a:b.txt"))
(define exclusive-target (string-append workspace (path-separator) "exclusive.txt"))
(write-text! exclusive-target "preserve")
(check! "output-file creation refuses an existing target"
        (raises? (lambda () (call-with-output-file exclusive-target (lambda (_) void)))))
(check-equal! "exclusive creation preserves existing content"
              (call-with-input-file exclusive-target (lambda (port) (read-port-to-string port)))
              "preserve")
(check! "create rejects NUL"
        (raises? (lambda ()
                   (forest-confined-create-path
                    workspace
                    (string-append "bad" (string (integer->char 0)) "name")))))
(for-each
 (lambda (name)
   (check! (string-append "reject create " name)
           (raises? (lambda () (forest-confined-create-path workspace name)))))
 (list "" "." ".." "../outside" "/tmp/outside" "C:/tmp/outside" "sub//file" "sub/./file" "sub/../file"
       "sub\\file" "escape/pwned"))

(define source (string-append workspace (path-separator) "sub" (path-separator) "old.txt"))
(write-text! source "old")
(check-equal! "rename path" (forest-confined-rename-path workspace source "new name.txt")
              (string-append (canonicalize-path workspace) (path-separator) "sub/new name.txt"))
(define root-source (string-append workspace (path-separator) "root.txt"))
(write-text! root-source "root")
(check-equal! "rename root entry" (forest-confined-rename-path workspace root-source "renamed.txt")
              (string-append (canonicalize-path workspace) (path-separator) "renamed.txt"))
(check-equal! "rename permits zero digits"
              (forest-confined-rename-path workspace source "new-01.txt")
              (string-append (canonicalize-path workspace) (path-separator) "sub/new-01.txt"))
(define repeated-parent
  (string-append workspace (path-separator) "same" (path-separator) "same"))
(check-equal! "native parent keeps repeated component"
              (parent-name repeated-parent)
              (string-append workspace (path-separator) "same"))

;; The native rename primitive treats its destination as the exact entry. It
;; neither moves a source inside a real directory nor follows a directory link.
(define directory-source (string-append workspace (path-separator) "sub/directory-source.txt"))
(define directory-target (string-append workspace (path-separator) "sub/directory-target"))
(write-text! directory-source "source")
(mkdir! directory-target)
(check! "exact rename rejects a directory destination"
        (raises? (lambda () (rename-file-or-directory! directory-source directory-target))))
(check! "failed exact rename retains its source" (path-exists? directory-source))
(check-equal! "exact rename does not move inside a directory"
              (path-exists? (string-append directory-target (path-separator) "directory-source.txt"))
              #f)

(define link-source (string-append workspace (path-separator) "sub/link-source.txt"))
(define link-target (string-append workspace (path-separator) "sub/link-target"))
(write-text! link-source "source")
(run! "ln" (list "-s" outside link-target))
(check! "directory link is classified as a link" (forest-path-entry-symlink? link-target))
(rename-file-or-directory! link-source link-target)
(check-equal! "exact rename does not follow a directory link"
              (path-exists? (string-append outside (path-separator) "link-source.txt"))
              #f)
(check-equal! "exact rename replaces the destination link"
              (call-with-input-file link-target (lambda (port) (read-port-to-string port)))
              "source")
(check-equal! "renamed destination is no longer a link"
              (forest-path-entry-symlink? link-target)
              #f)
(for-each
 (lambda (name)
   (check! (string-append "reject rename " name)
           (raises? (lambda () (forest-confined-rename-path workspace source name)))))
 (list "" "." ".." "../new" "dir/new" "dir\\new"))

(define escaped-source (string-append workspace (path-separator) "escape" (path-separator) "old.txt"))
(write-text! (string-append outside (path-separator) "old.txt") "outside")
(check! "rename rejects symlinked parent"
        (raises? (lambda () (forest-confined-rename-path workspace escaped-source "new.txt"))))

;; Porcelain v1 -z preserves every filename byte except NUL. Rename records put
;; the destination first and the source in the following record.
(define git-state
  (forest-parse-git-status-z
   (string-append " M ordinary.txt\0"
                  "?? space name.txt\0"
                  "R  new\nname.txt\0old -> literal.txt\0"
                  "!! ignored dir/\0"
                  " M \"quoted\".txt\0")))
(define ignored (car git-state))
(define statuses (cdr git-state))
(check-equal! "ordinary status" (hash-try-get statuses "ordinary.txt") 'modified)
(check-equal! "space status" (hash-try-get statuses "space name.txt") 'untracked)
(check-equal! "newline rename" (hash-try-get statuses "new\nname.txt") 'renamed)
(check-equal! "rename source skipped" (hash-try-get statuses "old -> literal.txt") #f)
(check-equal! "literal quotes" (hash-try-get statuses "\"quoted\".txt") 'modified)
(check! "ignored directory normalized" (hashset-contains? ignored "ignored dir"))

(define git-root (string-append test-root (path-separator) "git-workspace"))
(mkdir! git-root)
(run! "git" (list "-C" git-root "init" "-q"))
(run! "git" (list "-C" git-root "config" "user.email" "forest-tests@example.invalid"))
(run! "git" (list "-C" git-root "config" "user.name" "Forest Tests"))
(write-text! (string-append git-root (path-separator) ".gitignore") "ignored-dir/\n")
(write-text! (string-append git-root (path-separator) "old.txt") "tracked")
(run! "git" (list "-C" git-root "add" ".gitignore" "old.txt"))
(run! "git" (list "-C" git-root "commit" "-qm" "fixture"))
(run! "mv" (list (string-append git-root (path-separator) "old.txt")
                  (string-append git-root (path-separator) "renamed\nfile.txt")))
(run! "git" (list "-C" git-root "add" "-A"))
(write-text! (string-append git-root (path-separator) "space name.txt") "space")
(write-text! (string-append git-root (path-separator) "\"quoted\".txt") "quote")
(mkdir! (string-append git-root (path-separator) "ignored-dir"))
(write-text! (string-append git-root (path-separator) "ignored-dir/skip.txt") "ignored")
(define actual-git-state
  (forest-parse-git-status-z
   (run-output! "git" (list "-C" git-root
                            "status"
                            "--porcelain=v1"
                            "-z"
                            "--ignored=matching"
                            "--untracked-files=all"))))
(check-equal! "actual Git newline rename"
              (hash-try-get (cdr actual-git-state) "renamed\nfile.txt") 'renamed)
(check-equal! "actual Git whitespace filename"
              (hash-try-get (cdr actual-git-state) "space name.txt") 'untracked)
(check-equal! "actual Git quote filename"
              (hash-try-get (cdr actual-git-state) "\"quoted\".txt") 'untracked)
(check! "actual Git ignored directory"
        (hashset-contains? (car actual-git-state) "ignored-dir"))

;; One visibility predicate owns tree and search semantics.
(define explicit-ignore (hashset "ignored-dir"))
(check! "visible ordinary entry"
        (forest-entry-visible? "file.txt" explicit-ignore #f #f #f))
(check-equal! "hide dotfile"
              (forest-entry-visible? ".secret" explicit-ignore #f #f #f) #f)
(check! "show dotfile"
        (forest-entry-visible? ".secret" explicit-ignore #t #f #f))
(check-equal! "hide git ignored"
              (forest-entry-visible? "generated" explicit-ignore #t #f #t) #f)
(check! "show git ignored"
        (forest-entry-visible? "generated" explicit-ignore #t #t #t))
(check-equal! "explicit ignore always wins"
              (forest-entry-visible? "ignored-dir" explicit-ignore #t #t #f) #f)

(write-text! (string-append workspace (path-separator) "visible.txt") "visible")
(write-text! (string-append workspace (path-separator) ".hidden.txt") "hidden")
(mkdir! (string-append workspace (path-separator) "ignored-dir"))
(write-text! (string-append workspace (path-separator) "ignored-dir/skip.txt") "skip")
(write-text! (string-append outside (path-separator) "outside.txt") "outside")

(define scan
  (forest-scan-files-bounded
   workspace
   (lambda (path name)
     (forest-entry-visible? name explicit-ignore #f #f #f))
   100))
(define scan-files (list-ref scan 0))
(check! "scan includes visible file"
        (member (string-append workspace (path-separator) "visible.txt") scan-files))
(check-equal! "scan hides dotfile"
              (member (string-append workspace (path-separator) ".hidden.txt") scan-files) #f)
(check-equal! "scan skips explicit ignored subtree"
              (member (string-append workspace (path-separator) "ignored-dir/skip.txt") scan-files) #f)
(check-equal! "scan does not follow directory symlinks"
              (member (string-append workspace (path-separator) "escape/outside.txt") scan-files) #f)

(define limited-scan (forest-scan-files-bounded workspace (lambda (_path _name) #t) 2))
(check! "scan work is bounded" (<= (list-ref limited-scan 2) 2))
(check! "scan reports its bound" (list-ref limited-scan 1))

;; Preview reads at most byte-budget + one sentinel byte and retains at most the
;; line budget. Binary data is classified without attempting to render it.
(define preview-path (string-append workspace (path-separator) "preview.txt"))
(write-text! preview-path "one\nsecond\nthird\n")
(define line-preview (forest-read-preview preview-path 2 1024))
(check-equal! "preview line bound" (list-ref line-preview 0) '("one" "second"))
(check! "preview reports omitted lines" (list-ref line-preview 1))

(define large-path (string-append workspace (path-separator) "large.txt"))
(write-text! large-path "abcdefghijklmnop")
(define byte-preview (forest-read-preview large-path 200 8))
(check-equal! "preview byte bound" (car (list-ref byte-preview 0)) "abcdefgh")
(check! "preview reports omitted bytes" (list-ref byte-preview 1))
(check! "preview reads only one sentinel beyond budget" (<= (list-ref byte-preview 3) 9))

(define utf8-path (string-append workspace (path-separator) "utf8.txt"))
(write-text! utf8-path "aaaaaaaé")
(define utf8-preview (forest-read-preview utf8-path 200 8))
(check-equal! "preview trims a split UTF-8 code point" (car (list-ref utf8-preview 0)) "aaaaaaa")
(check-equal! "split UTF-8 remains text" (list-ref utf8-preview 2) 'text)

(define binary-path (string-append workspace (path-separator) "binary.dat"))
(write-binary! binary-path)
(define binary-preview (forest-read-preview binary-path 200 1024))
(check-equal! "binary classification" (list-ref binary-preview 2) 'binary)

(define unreadable-path (string-append workspace (path-separator) "unreadable.txt"))
(write-text! unreadable-path "secret")
(run! "chmod" (list "000" unreadable-path))
(define unreadable-preview (forest-read-preview unreadable-path 200 1024))
(check-equal! "unreadable classification" (list-ref unreadable-preview 2) 'unreadable)

(displayln "forest native checks passed: " checks)
