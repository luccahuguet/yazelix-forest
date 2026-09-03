(require "#%private/steel/ports")

(provide forest-confined-create-path
         forest-confined-rename-path
         forest-entry-visible?
         forest-git-status-symbol
         forest-path-entry-symlink?
         forest-parse-git-status-z
         forest-read-directory
         forest-read-preview
         forest-scan-files-bounded)

(define (forest-string-has-char? value ch)
  (not (not (member ch (string->list value)))))

(define (forest-all? predicate values)
  (or (null? values)
      (and (predicate (car values)) (forest-all? predicate (cdr values)))))

(define (forest-path-component-valid? component)
  (and (> (string-length component) 0)
       (not (string=? component "."))
       (not (string=? component ".."))))

(define (forest-drive-absolute? path)
  (and (> (string-length path) 2)
       (char=? (string-ref path 1) #\:)
       (or (char=? (string-ref path 2) #\/)
           (char=? (string-ref path 2) #\\))))

(define (forest-relative-path-components input allow-separators?)
  (when (or (not (string? input))
            (= (string-length input) 0)
            (starts-with? input "/")
            (starts-with? input "\\")
            (forest-drive-absolute? input)
            (forest-string-has-char? input (integer->char 0))
            (forest-string-has-char? input #\\))
    (error "path must be a non-empty workspace-relative path"))
  (define parts (split-many input (path-separator)))
  (unless (and (not (null? parts))
               (or allow-separators? (= (length parts) 1))
               (forest-all? forest-path-component-valid? parts))
    (error "path contains an empty, current, parent, or prohibited component"))
  parts)

(define (forest-canonical-root root)
  (unless (and (string? root) (is-dir? root))
    (error "workspace root does not exist"))
  (canonicalize-path root))

(define (forest-path-contained? root path)
  (or (string=? root path)
      (starts-with? path (string-append root (path-separator)))))

(define (forest-existing-ancestor path)
  (if (path-exists? path)
      path
      (let ([parent (parent-name path)])
        (if (string=? parent path)
            (error "path has no existing ancestor")
            (forest-existing-ancestor parent)))))

(define (forest-directory-entry<? left right)
  (define left-directory? (list-ref left 2))
  (define right-directory? (list-ref right 2))
  (if (equal? left-directory? right-directory?)
      (string<? (cadr left) (cadr right))
      left-directory?))

;; Returns sorted (path name real-directory?) entries. DirEntry's file type does
;; not follow links, so callers can render links without traversing them.
;; Unreadable directories behave as empty ones.
(define (forest-read-directory path)
  (with-handler
    (lambda (_) '())
    (let ([iter (read-dir-iter path)])
      (let loop ([entry (read-dir-iter-next! iter)] [result '()])
        (if (not entry)
            (sort result forest-directory-entry<?)
            (let ([entry-path (read-dir-entry-path entry)]
                  [name (read-dir-entry-file-name entry)])
              (loop (read-dir-iter-next! iter)
                    (if (and entry-path name)
                        (cons (list entry-path
                                    name
                                    (read-dir-entry-is-dir? entry))
                              result)
                        result))))))))

(define (forest-path-entry-symlink? path)
  (with-handler
    (lambda (_) #f)
    (let ([iter (read-dir-iter (parent-name path))]
          [name (file-name path)])
      (let loop ([entry (read-dir-iter-next! iter)])
        (cond
          [(not entry) #f]
          [(string=? (read-dir-entry-file-name entry) name)
           (read-dir-entry-is-symlink? entry)]
          [else (loop (read-dir-iter-next! iter))])))))

(define (forest-reject-symlink-components! root components)
  (let loop ([current root] [parts components])
    (unless (null? parts)
      (define next (string-append current (path-separator) (car parts)))
      (when (forest-path-entry-symlink? next)
        (error "path crosses a symbolic link"))
      (when (path-exists? next)
        (loop next (cdr parts))))))

;; Returns (absolute-path . directory?). Creation may name nested descendants,
;; but every component must be lexical and every existing ancestor must remain
;; beneath the canonical workspace without crossing a symlink.
(define (forest-confined-create-path workspace input)
  (define directory? (and (string? input) (ends-with? input (path-separator))))
  (define body (if directory? (trim-end-matches input (path-separator)) input))
  (define components (forest-relative-path-components body #t))
  (define root (forest-canonical-root workspace))
  (forest-reject-symlink-components! root components)
  (define target (string-append root (path-separator) body))
  (when (or (path-exists? target) (forest-path-entry-symlink? target))
    (error "target already exists"))
  (define ancestor (canonicalize-path (forest-existing-ancestor target)))
  (unless (forest-path-contained? root ancestor)
    (error "target escapes the workspace"))
  (cons target directory?))

;; Returns an absolute destination. Rename accepts exactly one basename and
;; keeps it in the selected entry's canonical parent.
(define (forest-confined-rename-path workspace source new-name)
  (forest-relative-path-components new-name #f)
  (unless (or (path-exists? source) (forest-path-entry-symlink? source))
    (error "source does not exist"))
  (define lexical-root (canonicalize-path workspace))
  (define lexical-prefix (string-append workspace (path-separator)))
  (unless (starts-with? source lexical-prefix)
    (error "source is outside the workspace"))
  (define source-parent (parent-name source))
  (unless (string=? source-parent workspace)
    (define relative-parent
      (substring source-parent (string-length lexical-prefix) (string-length source-parent)))
    (forest-reject-symlink-components! workspace (split-many relative-parent (path-separator))))
  (define parent (canonicalize-path source-parent))
  (unless (forest-path-contained? lexical-root parent)
    (error "source parent escapes the workspace"))
  (define target (string-append parent (path-separator) new-name))
  (when (or (path-exists? target) (forest-path-entry-symlink? target))
    (error "target already exists"))
  target)

;; This predicate is shared by the trees and both search modes. Explicit
;; ignores always win; hidden and Git-ignored entries follow their toggles.
(define (forest-entry-visible? name ignore-set show-hidden? show-git-ignored? git-ignored?)
  (not (or (hashset-contains? ignore-set name)
           (and (not show-hidden?)
                (> (string-length name) 0)
                (char=? (string-ref name 0) #\.))
           (and (not show-git-ignored?) git-ignored?))))

(define (forest-git-status-symbol code)
  (if (< (string-length code) 2)
      #f
      (let ([x (string-ref code 0)] [y (string-ref code 1)])
        (cond
          ;; glyph.hx has no dedicated conflict or type-change category.
          [(member code '("DD" "AU" "UD" "UA" "DU" "AA" "UU")) 'modified]
          [(and (char=? x #\?) (char=? y #\?)) 'untracked]
          [(or (char=? x #\A) (char=? y #\A) (char=? x #\C) (char=? y #\C)) 'added]
          [(or (char=? x #\D) (char=? y #\D)) 'deleted]
          [(or (char=? x #\R) (char=? y #\R)) 'renamed]
          [(or (char=? x #\M) (char=? y #\M) (char=? x #\T) (char=? y #\T)) 'modified]
          [else #f]))))

;; Parses `git status --porcelain=v1 -z`. In -z mode rename/copy destinations
;; come first and their source is the following NUL record.
(define (forest-parse-git-status-z output)
  (let loop ([records (split-many output "\0")] [ignored (hashset)] [statuses (hash)])
    (if (null? records)
        (cons ignored statuses)
        (let ([record (car records)])
          (if (< (string-length record) 3)
              (loop (cdr records) ignored statuses)
              (let* ([code (substring record 0 2)]
                     [raw-path (substring record 3 (string-length record))]
                     [path (if (string=? code "!!")
                               (trim-end-matches raw-path (path-separator))
                               raw-path)]
                     [remaining (if (and (or (forest-string-has-char? code #\R)
                                             (forest-string-has-char? code #\C))
                                         (pair? (cdr records)))
                                    (cddr records)
                                    (cdr records))])
                (if (string=? code "!!")
                    (loop remaining (hashset-insert ignored path) statuses)
                    (let ([status (forest-git-status-symbol code)])
                      (loop remaining ignored
                            (if status (hash-insert statuses path status) statuses))))))))))

;; Bounded depth-first iteration. The budget counts directory entries, and
;; read-dir-iter avoids materializing an unbounded single directory. Symlinked
;; directories are never followed.
(define (forest-scan-files-bounded root visible? max-entries)
  (unless (and (int? max-entries) (> max-entries 0))
    (error "scan budget must be positive"))
  (define files '())
  (define visited 0)
  (define truncated? #f)
  (define (walk dir)
    (define iter (with-handler (lambda (_) #f) (read-dir-iter dir)))
    (when iter
      (let loop ([entry (read-dir-iter-next! iter)])
        (cond
          [(not entry) void]
          [(>= visited max-entries) (set! truncated? #t)]
          [else
           (set! visited (+ visited 1))
           (define path (read-dir-entry-path entry))
           (define name (read-dir-entry-file-name entry))
           (when (and path name (visible? path name))
             (cond
               [(read-dir-entry-is-dir? entry) (walk path)]
               [(read-dir-entry-is-file? entry) (set! files (cons path files))]))
           (loop (read-dir-iter-next! iter))]))))
  (walk root)
  (list (sort files string<?) truncated? visited))

(define (forest-bytes-have-zero? bytes length)
  (let loop ([index 0])
    (and (< index length)
         (or (= (bytes-ref bytes index) 0)
             (loop (+ index 1))))))

(define (forest-decode-utf8-prefix bytes length retries)
  (with-handler
    (lambda (_)
      (if (and (> retries 0) (> length 0))
          (forest-decode-utf8-prefix bytes (- length 1) (- retries 1))
          #f))
    (bytes->string/utf8 bytes 0 length)))

;; Returns (lines truncated? kind bytes-read). One sentinel byte beyond the
;; declared budget detects truncation without reading the complete file.
(define (forest-read-preview path max-lines max-bytes)
  (unless (and (int? max-lines) (> max-lines 0) (int? max-bytes) (> max-bytes 0))
    (error "preview budgets must be positive"))
  (with-handler
    (lambda (_) (list '("(unable to preview)") #f 'unreadable 0))
    (let* ([port (open-input-file path)]
           [result (with-handler
                     (lambda (_) (begin (close-input-port port) #f))
                     (read-bytes (+ max-bytes 1) port))])
      (if (not result)
          (list '("(unable to preview)") #f 'unreadable 0)
          (begin
            (close-input-port port)
            (define bytes (if (eof-object? result) (bytevector) result))
            (define bytes-read (bytes-length bytes))
            (define visible-bytes (min bytes-read max-bytes))
            (if (forest-bytes-have-zero? bytes visible-bytes)
                (list '("(binary file)") #f 'binary bytes-read)
                (let ([content (forest-decode-utf8-prefix bytes visible-bytes 3)])
                  (if (not content)
                      (list '("(unable to preview)") #f 'unreadable bytes-read)
                      (let* ([all-lines (split-many content "\n")]
                             [line-truncated? (> (length all-lines) max-lines)]
                             [byte-truncated? (> bytes-read max-bytes)])
                        (list (take all-lines max-lines)
                              (or line-truncated? byte-truncated?)
                              'text
                              bytes-read))))))))))
