#!/usr/bin/env racket
#lang racket
(require racket/gui/base)
(require file/glob)
(require openssl/sha1)
(require net/sendurl)

(struct sort-set (dst sortme wname use-wname?))

(define (load-dirs dirs) (void))

(define (update-sort-sets) (void))

(define (sort-img dst) (void))

(define (existing-path? path) (and (path? path) (directory-exists? path)))

(define (my/fmt-number n)
  (cond
    [(< n 10) (format "00~v" n)]
    [(< n 100) (format "0~v" n)]
    [#t (format "~v" n)]))

(define (rem-idx lst idx) (append (take lst idx) (cdr (list-tail lst idx))))

(define program-name "HyperSorter")

(define program-name-lower (string-downcase program-name))

(define program-version "v1.0.0")

(define program-homepage "https://github.com/japanoise/HyperSorter")

;; --- OH NOES! GLOBAL STATE!!!!! ---
;; Paths
(define dst-dir "")
(define sort-dir "")
(define config-dir
  (if (eq? (system-type 'os) 'windows)
      (build-path (getenv "userprofile") program-name-lower)
      (if (getenv "XDG_CONFIG_HOME")
          (build-path (getenv "XDG_CONFIG_HOME") program-name-lower)
          (build-path (expand-user-path "~/.config/") program-name-lower))))
(unless (directory-exists? config-dir) (make-directory config-dir #o755))

;; Lists of files/dirs
(define to-sort '())
(define dst-subdirs '())

;; Counters for status bar
(define sorted 0)
(define skipped 0)
(define remaining 0)

;; Misc. global state
(define waifu-name "")
(define use-waifu-name? #f)

;; All sort sets
(define loaded-sort-sets '())
;; --- END TEH EVIL STATE!!!!!!!! ---

(define frame (new frame%
                   [label program-name]
                   [width 1280]
                   [height 800]))

(define (about) (message-box
               (format "About ~a" program-name)
               (format "~a version ~a~n~a~n~a"
                       program-name
                       program-version
                       "Unleashed on an unsuspecting world by japanoise"
                       "Copyright (C) 2024 japanoise")
               frame (list 'ok)))

(application-about-handler about)

(define (error-message msg) (message-box
                             program-name msg frame (list 'ok 'stop)))

(define vsplit (new vertical-pane% [parent frame]))

(define hsplit (new horizontal-pane%	 
   	 	[parent vsplit]))

(define status-bar (new horizontal-pane%
                        [parent vsplit]
                        [min-height 10]
                        [stretchable-height #f]))

(define status (new message% [label "No files to sort."] [parent status-bar]))
(new message% [label ""] [parent status-bar] [stretchable-width #t])

(define (update-status)
  (send status set-label (cond
                           [(<= remaining 0)
                            (cond
                              [(and
                                (eq? skipped 0)
                                (eq? sorted 0))
                               "No files to sort."]
                              [(> skipped 0)
                               (format "Done - Sorted ~a; Skipped ~a"
                                       sorted skipped)]
                              [(> sorted 0)
                               (format "Done - Sorted ~a"
                                       sorted)]
                              ; Shouldn't occur - egg.
                              [#t "Donezo, cap'n!"])]
                           [(> skipped 0)
                            (format "Sorted ~a | Skipped ~a | Remaining ~a"
                                    sorted skipped remaining)]
                           [(> sorted 0)
                            (format "Sorted ~a | Remaining ~a"
                                    sorted remaining)]
                           [#t
                            (format "~a files to sort"
                                    remaining)])))

(define buttons (new vertical-panel%
                     [parent hsplit]
                     [style '(vscroll)]
                     [stretchable-width #f]
                     [min-width 200]))

;; A canvas that loads and displays the given image
(define img-view%
  (class canvas%
    (define outside-canvas
      (let ([shade 100]) (make-object color% shade shade shade)))
    (define pale-text
      (let ([shade 200]) (make-object color% shade shade shade)))
    (define text-color
      (let ([shade 0]) (make-object color% shade shade shade)))
    (define text-background
      (let ([shade 255]) (make-object color% shade shade shade)))
    (define worker-delay 0.2)
    (define bmp 'none)
    (define scale 100)
    (define offset-x 0)
    (define offset-y 0)
    (define step 32)
    (define last-scroll (current-inexact-milliseconds))
    (define last-mouse (current-inexact-milliseconds))
    (define last-mouse-x 0)
    (define last-mouse-y 0)
    (define search-term "")
    (define candidates '())
    (define candidates-string "")
    (define term-changed #f)
    (define scale-mode #f)

    (define (update-scale-args height width)
      (unless (eq? 'none bmp)
        (let ([this-height height]
              [this-width width]
              [bmp-height (send bmp get-height)]
              [bmp-width (send bmp get-width)])
          (let loop ([desired-height bmp-height]
                     [desired-width bmp-width]
                     [desired-scale 100])
            (if (or (> desired-height this-height)
                    (> desired-width this-width))
                (loop (/ desired-height 2)
                      (/ desired-width 2)
                      (/ desired-scale 2))
                (begin
                  (set! scale desired-scale)
                  (set! offset-y
                        (* (/ (- this-height desired-height) 2) (/ 100 scale)))
                  (set! offset-x
                        (* (/ (- this-width desired-width) 2) (/ 100 scale)))))))))

    (define (update-scale)
      (update-scale-args (send this get-height)
                         (send this get-width)))

    (define/public (reset-view)
      (if scale-mode (update-scale)
          (begin
            (set! scale 100)
            (set! offset-x 0)
            (set! offset-y 0)))
      (send this refresh))

    (define/public (toggle-scale)
      (set! scale-mode (not scale-mode))
      (when scale-mode
        (update-scale)
        (send this refresh)))

    (define/override (on-size width height)
      (when scale-mode (update-scale-args height width)))

    (define (update-candidates-string)
      (set! candidates-string (format "~v" candidates)))

    (define worker
      (thread
       (lambda ()
         (let loop ()
           (cond
             [(not term-changed)
              (sleep worker-delay)]
             [(equal? "" search-term)
              (set! candidates-string "")
              (set! candidates '())
              (set! term-changed #f)
              (send this refresh)
              (sleep worker-delay)]
             [#t
              (begin
                (set! term-changed #f)
                (set! candidates
                      (filter
                       (lambda (dir)
                          (string-prefix?
                           (string-downcase dir)
                           search-term))
                       (map
                        (lambda (dir) (path->string dir)) dst-subdirs)))
                 (update-candidates-string)
                 (send this refresh))])
           (loop)))))

    (define (update-search-term st)
      (set! search-term st)
      (if (eq? st "")
         (begin
           (set! candidates '())
           (set! candidates-string "")
           (set! term-changed #f))
         (set! term-changed #t)))

    (define (do-scroll up? event)
      (when (> (current-inexact-milliseconds) (+ last-scroll 10))
             (begin
               (set! last-scroll (current-inexact-milliseconds))
               (cond
                 [(send event get-control-down) (if up?
                                                  (set! scale (* scale 2))
                                                  (set! scale (/ scale 2)))]
                 [(send event get-shift-down) (if up?
                                                  (set! offset-x
                                                        (+ offset-x step))
                                                  (set! offset-x
                                                        (- offset-x step)))]
                 [#t (if up?
                         (set! offset-y
                               (+ offset-y step))
                         (set! offset-y
                               (- offset-y step)))])
               (send this refresh))))

    ; Keyboard event
    (define/override (on-char event)
      (cond
        [(eq? (send event get-key-code) 'wheel-up)
         (do-scroll #t event)]
        [(eq? (send event get-key-code) 'wheel-down)
         (do-scroll #f event)]
        [(not (eq? 'press (send event get-key-release-code)))
         (let ([keycode (send event get-key-release-code)]
               [zoom-in (lambda () (set! scale (* scale 2)))]
               [zoom-out (lambda () (set! scale (/ scale 2)))]
               [key-up (lambda () (set! offset-y (+ offset-y step step)))]
               [key-down (lambda () (set! offset-y (- offset-y step step)))]
               [key-right (lambda () (set! offset-x (- offset-x step step)))]
               [key-left (lambda () (set! offset-x (+ offset-x step step)))])
           (cond
             [(char? keycode)
              (begin
                (cond
                  [(and (eq? keycode #\backspace)
                        (> (string-length search-term) 0))
                   (update-search-term
                         (substring search-term 0
                                    (- (string-length search-term) 1)))]
                  [(send event get-control-down)
                   (cond
                     [(or (eq? keycode #\u) (eq? keycode #\g))
                      (update-search-term "")]
                     [(eq? keycode #\-) (zoom-out)]
                     [(eq? keycode #\+) (zoom-in)]
                     [(eq? keycode #\=) (zoom-in)]
                     [(eq? keycode #\,) (zoom-out)]
                     [(eq? keycode #\.) (zoom-in)]
                     [(eq? keycode #\s) (begin
                                          (set! candidates
                                                (append (cdr candidates)
                                                        (list (car
                                                               candidates))))
                                          (update-candidates-string))]
                     [(eq? keycode #\c) (begin
                                          (set! offset-x 0)
                                          (set! offset-y 0)
                                          (set! scale 100))]
                     [(eq? keycode #\p) (key-up)]
                     [(eq? keycode #\n) (key-down)]
                     [(eq? keycode #\b) (key-left)]
                     [(eq? keycode #\f) (key-right)])]
                  [(eq? keycode #\return)
                   (when term-changed (sleep (* 2 worker-delay)))
                   (unless (empty? candidates) (sort-img (car candidates)))]
                  [(eq? keycode #\tab)
                   (set! candidates
                         (append (cdr candidates) (list (car candidates))))
                   (update-candidates-string)]
                  [(< (char->integer keycode) 32) ; other ascii escapes
                   (void)]
                  [#t
                   (update-search-term
                    (string-append search-term
                                   (string (char-downcase keycode))))]))]
             [(eq? keycode 'escape)
              (update-search-term "")]
             [(eq? keycode 'up)
              (key-up)]
             [(eq? keycode 'down)
              (key-down)]
             [(eq? keycode 'left)
              (key-left)]
             [(eq? keycode 'right)
              (key-right)])
           (send this refresh))]))

    ; Mouse event
    (define/override (on-event event)
      (when (> (current-inexact-milliseconds) (+ last-mouse 1))
        (let ([x (send event get-x)]
              [y (send event get-y)])
          (begin
            (set! last-mouse (current-inexact-milliseconds))
            (when (send event get-left-down)
              (begin
                (set! offset-x
                      (+ offset-x
                         (* (/ (- x last-mouse-x) scale) 100)))
                (set! offset-y
                      (+ offset-y
                         (* (/ (- y last-mouse-y) scale) 100)))
                (send this refresh)))
            (set! last-mouse-x x)
            (set! last-mouse-y y)))))

    (define/override (on-focus on?) (send this refresh))
    
    (define/override (on-paint)
      (let ([dc (send this get-dc)])
        (begin
          (send dc set-background outside-canvas)
          (send dc clear)
          (if (eq? 'none bmp)
              (begin
                (send dc set-text-background text-background)
                (send dc set-text-mode 'solid)
                (send dc draw-text "<No image loaded>" 1 1))
              (begin
                (send dc set-scale (/ scale 100) (/ scale 100))
                (send dc draw-bitmap bmp offset-x offset-y)
                (send dc set-scale 1 1)))
          (let-values ([(width height) (send dc get-size)])
            (send dc set-text-background text-background)
            (send dc set-text-mode 'solid)
            (send dc set-text-foreground pale-text)
            (send dc draw-text
                  (if (empty? candidates) "" (car candidates))
                  10 (- height 30))
            (send dc set-text-foreground text-color)
            (send dc draw-text candidates-string 10 (- height 60))
            (send dc set-text-mode 'transparent)
            (send dc draw-text
                  (if (send this has-focus?)
                      (string-append search-term "_")
                      search-term)
                  10 (- height 30))))))

    (define/public (reload-img)
      (begin
        (begin-busy-cursor)
        (update-search-term "")
        (set! scale 100)
        (set! offset-x 0)
        (set! offset-y 0)
        (set! bmp
              (with-handlers ([exn:fail? (lambda (e) 'none)])
                (make-object bitmap% (car to-sort) 'unknown/alpha #f #t)))
        (when scale-mode (update-scale))
        (send this focus)
        (send this refresh)
        (end-busy-cursor)))

    (define/public (get-search-term) search-term)

    (super-new [min-height 400] [min-width 400])))

;; A button that sorts the current image into the directory
;; which the button is responsible for
(define sort-btn%
  (class button%
    (init subdir)
    (define this-subdir subdir)
    (super-new
     [stretchable-width #t]
     [callback (lambda (btn ev) (sort-img this-subdir))]
     [label (path->string this-subdir)])))

(define img-view (new img-view% [parent hsplit]))

(define (next-img)
  (set! to-sort (cdr to-sort))
  (send img-view reload-img))

(define (generate-waifuname-filename dst ff)
  (let ([fhash (let ([in (open-input-file ff)])
                (let ([ret (sha1 in)]) (close-input-port in) ret))]
        [num 0])
    (let loop ()
      (if (empty? (glob (build-path
                         dst (format "~a-~a*"
                                     waifu-name (my/fmt-number num)))))
          (build-path dst (format "~a-~a-nameme-~a~a"
                  waifu-name (my/fmt-number num) (substring fhash 0 10)
                  (if (path-get-extension ff) (path-get-extension ff) "")))
          (begin (set! num (add1 num)) (loop))))))
  
(set! sort-img
      (lambda (dst)
        (with-handlers
          ([exn:fail? (lambda (e)
                        ((error-display-handler) (exn-message e) e)
                        (error-message (format "An error occured:~n~a~"
                                               (exn-message e))))])
          (let ([sort-full-path (car to-sort)]
                [dst-full-path (build-path dst-dir dst)])
            (let-values ([(sortme-dir sort-file-base-name mbd?)
                          (split-path sort-full-path)])
              (if (directory-exists? dst-full-path)
                  (let ([destination
                         (if use-waifu-name?
                             (generate-waifuname-filename
                              dst-full-path sort-full-path)
                             (build-path dst-full-path sort-file-base-name))])
                    (printf "sorting ~v to ~v\n" sort-full-path destination)
                    (rename-file-or-directory sort-full-path destination)
                    (set! sorted (+ sorted 1))
                    (set! remaining (- remaining 1))
                    (update-status)
                    (next-img))
                  (error-message (format
                                  "~v not found~nCowardly refusing to sort."
                                  dst-full-path))))))))

(define (update-buttons)
  (send buttons change-children (lambda (lst) (take lst 3)))
  (set! dst-subdirs
        (map
         (lambda (dir)
           (begin (new sort-btn% [subdir dir] [parent buttons]) dir))
         (sort
          (filter
           (lambda (dir)
             (and
              (not (string-prefix? (path->string dir) "."))
              (directory-exists? (build-path dst-dir dir))
              (not (equal? (build-path dst-dir dir) (string->path sort-dir)))))
           (directory-list dst-dir))
          (lambda (x y)
            (string-ci<? (path->string x) (path->string y)))))))

(define skip-button-action (lambda (b e) (unless (<= remaining 0)
                          (set! skipped (add1 skipped))
                          (set! remaining (sub1 remaining))
                          (update-status)
                          (next-img))))

(define skip-btn (new button%
     [parent buttons]
     [label "Skip this one"]
     [stretchable-width #t]
     [callback skip-button-action]))

(define new-subdirectory (lambda (b e)
                 (unless (eq? dst-dir "")
                   (let ([new-dir-name
                          (get-text-from-user "New directory"
                                              "Name of the new directory?"
                                              frame)])
                     (unless
                         (or (not (string? new-dir-name))
                             (equal? "" new-dir-name))
                       (directory-exists? (build-path dst-dir new-dir-name))
                       (make-directory
                        (build-path dst-dir new-dir-name) #o755)
                       (update-buttons))))))

(define newdir-btn (new button%
     [parent buttons]
     [label "New subdirectory"]
     [stretchable-width #t]
     [callback new-subdirectory]))

(new pane% [parent buttons] [stretchable-height #f] [min-height 10])

(set! load-dirs
      (lambda (dirs)
        (begin
          (set! waifu-name (sort-set-wname dirs))
          (set! use-waifu-name? (sort-set-use-wname? dirs))
          (set! dst-dir (sort-set-dst dirs))
          (set! sort-dir (sort-set-sortme dirs))
          (set! sorted 0)
          (set! skipped 0)
          (set! to-sort
                (map
                 (lambda (dir) (build-path sort-dir dir))
                 (filter
                  (lambda (dir)
                    (and
                     (not (string-prefix? (path->string dir) "."))
                     (not (directory-exists? (build-path dst-dir dir)))))
                  (directory-list sort-dir))))
          (update-buttons)
          (set! remaining (length to-sort))
          (update-status)
          (send img-view reload-img))))

(define version-byte 0)

(define (save-dirfile)
  (define out
    (open-output-file
     (build-path config-dir "sort-sets")
     #:mode 'binary
     #:exists 'truncate/replace
     #:permissions #o644))
  (write-byte version-byte out)
  (for-each
   (lambda (set)
     (display (sort-set-dst set) out)
     (write-byte 0 out)
     (display (sort-set-sortme set) out)
     (write-byte 0 out)
     (display (sort-set-wname set) out)
     (write-byte 0 out)
     (display (sort-set-use-wname? set) out)
     (write-byte 0 out))
   loaded-sort-sets)
  (close-output-port out))

(define (read-nulterm in)
  (let ([ret (open-output-string)])
    (for ([byte in])
      #:break (equal? byte 0)
      (write-byte byte ret))
    (get-output-string ret)))

(define (read-dirfile)
  (with-handlers ([exn:fail? (lambda (e) 'error)])
    (let ([ret '()])
      (define in (open-input-file
                  (build-path config-dir "sort-sets")
                  #:mode 'binary))
      (case (read-byte in)
        [(0)
         (let loop ()
           (let ([dst (read-nulterm in)]
                 [sortme (read-nulterm in)]
                 [wname (read-nulterm in)]
                 [use-wname? (read-nulterm in)])
             (unless
                 (member "" (list dst sortme wname use-wname?))
               (set! ret (append ret (list
                                      (sort-set dst sortme wname
                                                (equal? use-wname? "#t")))))
               (unless (eof-object? (peek-byte in)) (loop)))))]
        [(eof) (error-message "Savefile empty")]
        [else (error-message
               "This version of the program is too old to load the savefile")])
      (close-input-port in)
      ret)))

(define dir-dialog (new dialog%
                        [label "Manage Directories"]
                        [parent frame]
                        [min-width 200]
                        [min-height 300]))
(define dir-list (new list-box%
                      [label #f]
                      [choices
                       (map (lambda (s) (sort-set-wname s)) loaded-sort-sets)]
                      [parent dir-dialog]))

(define new-dir-dialog (new dialog%
                        [label "New Directory"]
                        [parent frame]
                        [min-width 500]
                        [min-height 200]
                        [stretchable-height #f]))

(let ([vpane (new vertical-pane% [parent new-dir-dialog])])
  (new message% [label "Target Directory"] [parent new-dir-dialog])
  (let ([dir-row
         (new horizontal-pane%
              [parent new-dir-dialog] [stretchable-height #f] [min-height 10])]
        [sortme-label
         (new message% [label "Unsorted Directory"] [parent new-dir-dialog])]
        [sortme-row
         (new horizontal-pane%
              [parent new-dir-dialog] [stretchable-height #f] [min-height 10])]
        [bottom-controls-row
         (new vertical-pane%
              [parent new-dir-dialog] [stretchable-height #f] [min-height 10])]
        [button-row
         (new horizontal-pane%
              [parent new-dir-dialog] [stretchable-height #t] [min-height 10])]
        [dir-value 'unset]
        [sortme-value 'unset])
    (let ([dir-label
           (new message% [label ""] [parent dir-row] [stretchable-width #t])]
          [sortme-label
           (new message% [label ""] [parent sortme-row] [stretchable-width #t])]
          [wname-field
           (new text-field% [label "Name:"] [parent bottom-controls-row])]
          [use-wname-box
           (new check-box% [label "Rename files?"]
                [parent bottom-controls-row])])
      (new button% [label "Update"] [parent dir-row]
           [callback
            (lambda (b e)
              (let ([sel (get-directory
                          "Target directory"
                          new-dir-dialog
                          (if (path? dir-value) dir-value #f))])
                (when (existing-path? sel)
                  (set! dir-value sel)
                  (send dir-label set-label (path->string sel)))))])
      (new button% [label "Update"] [parent sortme-row]
           [callback
            (lambda (b e)
              (let ([sel (get-directory
                          "Unsorted directory"
                          new-dir-dialog
                          (cond
                            [(path? sortme-value) sortme-value]
                            [(path? dir-value) dir-value]
                            [#t #f]))])
                (when (existing-path? sel)
                  (set! sortme-value sel)
                  (send sortme-label set-label (path->string sel)))))])
      (new button% [label "OK"] [parent button-row]
           [callback
            (lambda (b e)
              (let ([wname-value
                     (string-replace
                      (send wname-field get-value)
                      (pregexp "\\P{L}+") "_")])
                (if (and (existing-path? dir-value)
                         (existing-path? sortme-value)
                         (string? wname-value)
                         (< 0 (string-length wname-value)))
                    ;; Fields entered correctly - check for duplicates
                    (if (member wname-value (map sort-set-wname loaded-sort-sets))
                        (error-message "Names must be unique")
                        (begin
                          (set! loaded-sort-sets (append
                           loaded-sort-sets
                           (list
                            (sort-set dir-value sortme-value wname-value
                                      (send use-wname-box get-value)))))
                          (update-sort-sets)
                          (send new-dir-dialog show #f)))
                    (error-message "All fields are required"))))])
      (new button% [label "Cancel"] [parent button-row]
           [callback (lambda (b e) (send new-dir-dialog show #f))]))))

(define dir-buttons
  (new horizontal-pane%
       [parent dir-dialog] [stretchable-height #f] [min-height 10]))
(new button%
     [label "Select"]
     [parent dir-buttons]
     [callback (lambda (b ev)
                 (let ([selection (send dir-list get-selection)])
                   (when selection (let ([seldir (list-ref loaded-sort-sets selection)])
                                     (load-dirs seldir)
                                     (send dir-dialog show #f)))))])
(new button%
     [label "New"]
     [parent dir-buttons]
     [callback (lambda (b ev) (send new-dir-dialog show #t))])
(new button%
     [label "Delete"]
     [parent dir-buttons]
     [callback (lambda (b ev)
                 (let ([selection (send dir-list get-selection)])
                   (when (and selection
                              (< 1 (length loaded-sort-sets))
                              (eq? 'ok
                                   (message-box
                                    "Are you sure?"
                                    "Are you sure you want to delete this directory?\nIt will be removed from the save file. There is no undo."
                                    frame (list 'ok-cancel 'caution))))
                     (begin
                       (set! loaded-sort-sets (rem-idx loaded-sort-sets selection))
                       (update-sort-sets)
                       ))))])

(define menubar (new menu-bar% [parent frame]))

(define file-menu (new menu% [parent menubar] [label "&File"]))
(new menu-item%
     [label "&New Directory"]
     [parent file-menu]
     [callback (lambda (m c) (send new-dir-dialog show #t))])
(new menu-item%
     [label "New &Subirectory"]
     [parent file-menu]
     [callback new-subdirectory])
(new menu-item%
     [label "S&kip this one"]
     [parent file-menu]
     [callback skip-button-action])
(new menu-item%
     [label "&Quit"]
     [parent file-menu]
     [shortcut #\q]
     [callback (lambda (m c) (send frame on-exit))])

(define view-menu (new menu% [parent menubar] [label "&View"]))
(new menu-item%
     [label "&Reset View"]
     [parent view-menu]
     [shortcut #\0]
     [callback (lambda (m c) (send img-view reset-view))])
(new checkable-menu-item%
     [label "&Scaling Mode"]
     [parent view-menu]
     [callback (lambda (m c) (send img-view toggle-scale))])

(define dir-menu (new menu% [parent menubar] [label "&Directory"]))
(new menu-item%
     [label "&Manage Directories"]
     [parent dir-menu]
     [shortcut #\d]
     [callback (lambda (m c) (send dir-dialog show #t))])
(new separator-menu-item% [parent dir-menu])

(define help-menu (new menu% [parent menubar] [label "&Help"]))
(new menu-item%
     [label (format "&About ~a" program-name)]
     [parent help-menu]
     [callback (lambda (m c) (about))])
(new menu-item%
     [label "&Webpage"]
     [parent help-menu]
     [callback (lambda (m c) (send-url program-homepage))])

;; A menu item that switches to a given directory
(define dir-menu-item%
  (class menu-item%
    (init dirs)
    (define this-dirs dirs)
    (super-new
     [callback (lambda (m c) (load-dirs dirs))]
     [label (sort-set-wname dirs)])))

(set! update-sort-sets
      (lambda ()
        (begin-busy-cursor)
        (let ([dir-menu-items
               (cdr (map (lambda (item) (send item get-plain-label))
                         (filter (lambda (item) (is-a? item menu-item%))
                                 (send dir-menu get-items))))])
          (send dir-list clear)
          (for-each
           (lambda (d)
             (send dir-list append (sort-set-wname d))
             (unless (member (sort-set-wname d) dir-menu-items)
               (new dir-menu-item% [dirs d] [parent dir-menu])))
           loaded-sort-sets)
          (unless (member waifu-name (map sort-set-wname loaded-sort-sets))
            (load-dirs (car loaded-sort-sets)))
          (save-dirfile))
        (end-busy-cursor)))

(let ([loaded (read-dirfile)])
  (unless (or (equal? loaded 'error) (empty? loaded))
    (set! loaded-sort-sets loaded)
    (let ([dirs (car loaded)])
      (load-dirs dirs))
    (update-sort-sets)))

;; Show the frame by calling its show method
(send frame show #t)
