(require "../forest/core.scm")
(require-builtin steel/time)

(unless (= (length std::env::args) 2)
  (error "usage: steel tests/performance.scm <large-tree> <large-file>"))

(define tree-root (car std::env::args))
(define large-file (cadr std::env::args))

(define listing-start (instant/now))
(define listing (forest-read-directory tree-root))
(define listing-ms (duration->millis (instant/elapsed listing-start)))
(displayln "directory listing: " listing-ms " ms, returned " (length listing) " entries")
(unless (and (>= (length listing) 5000) (< listing-ms 1500))
  (error "large-directory listing exceeded its work contract"))

(define lookup-start (instant/now))
(define missing-link?
  (forest-path-entry-symlink? (string-append tree-root (path-separator) "missing-link")))
(define lookup-ms (duration->millis (instant/elapsed lookup-start)))
(unless (and (not missing-link?) (< lookup-ms 250))
  (error "directory-entry lookup exceeded its work contract"))

(define scan-start (instant/now))
(define scan (forest-scan-files-bounded tree-root (lambda (_path _name) #t) 5000))
(define scan-ms (duration->millis (instant/elapsed scan-start)))
(unless (and (<= (list-ref scan 2) 5000) (list-ref scan 1) (< scan-ms 500))
  (error "large-tree scan exceeded its work contract"))

(define preview-start (instant/now))
(define preview (forest-read-preview large-file 200 65536))
(define preview-ms (duration->millis (instant/elapsed preview-start)))
(unless (and (<= (length (list-ref preview 0)) 200)
             (<= (list-ref preview 3) 65537)
             (< preview-ms 100))
  (error "large-file preview exceeded its read contract"))

(displayln "bounded scan: " scan-ms " ms, visited " (list-ref scan 2) " entries")
(displayln "directory-entry lookup: " lookup-ms " ms")
(displayln "bounded preview: " preview-ms " ms, read " (list-ref preview 3) " bytes")
