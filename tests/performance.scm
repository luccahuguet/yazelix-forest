(require "../forest/core.scm")
(require-builtin steel/time)

(unless (= (length std::env::args) 2)
  (error "usage: steel tests/performance.scm <large-tree> <large-file>"))

(define tree-root (car std::env::args))
(define large-file (cadr std::env::args))

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
(displayln "bounded preview: " preview-ms " ms, read " (list-ref preview 3) " bytes")
