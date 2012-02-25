;;;; -*- Mode: Lisp; indent-with-tabs: nil -*-

(in-package :hemlock-internals)

;;;; Editor input from a tty.

(defclass tty-editor-input (editor-input)
  ((fd :initarg :fd
       :accessor tty-editor-input-fd)))

(defun make-tty-editor-input (&rest args)
  (apply #'make-instance 'tty-editor-input args))

(defmethod get-key-event
    ((stream tty-editor-input) &optional ignore-abort-attempts-p)
  (%editor-input-method stream ignore-abort-attempts-p))

(defmethod unget-key-event (key-event (stream tty-editor-input))
  (un-event key-event stream))

(defmethod clear-editor-input ((stream tty-editor-input))
  (hemlock-ext:without-interrupts
   (let* ((head (editor-input-head stream))
          (next (input-event-next head)))
     (when next
       (setf (input-event-next head) nil)
       (shiftf (input-event-next (editor-input-tail stream))
               *free-input-events* next)
       (setf (editor-input-tail stream) head)))))

;;; Note that we never return NIL as long as there are events to be served with
;;; SERVE-EVENT.  Thus non-keyboard input (i.e. process output)
;;; effectively causes LISTEN to block until either all the non-keyboard input
;;; has happened, or there is some real keyboard input.
;;;
(defmethod listen-editor-input ((stream tty-editor-input))
  (process-editor-tty-input)
  nil)

(defvar *tty-translations* (make-hash-table :test #'equal))

(defun register-tty-translations ()
  (assert hemlock.terminfo:*terminfo*)
  (flet ((reg (string keysym)
           (let ((string (etypecase string
                           (character (string string))
                           (list (coerce string 'simple-string))
                           (string string))))
              (setf (gethash string *tty-translations*) keysym))))
    ;; KLUDGE: There seems to be no way get F1-F4 reliably transmit
    ;; things in the terminfo db, since some terminals transmit them
    ;; as if they were vt100 PF1-PF4, so, register these aliases here.
    ;; If they double as something else, that will override these.
    (reg '(#\Esc #\O #\P) #k"F1")
    (reg '(#\Esc #\O #\Q) #k"F2")
    (reg '(#\Esc #\O #\R) #k"F3")
    (reg '(#\Esc #\O #\S) #k"F4")
    ;; Terminfo definitions for F1-F12
    (reg hemlock.terminfo:key-f1 #k"F1")
    (reg hemlock.terminfo:key-f2 #k"F2")
    (reg hemlock.terminfo:key-f3 #k"F3")
    (reg hemlock.terminfo:key-f4 #k"F4")
    (reg hemlock.terminfo:key-f5 #k"F5")
    (reg hemlock.terminfo:key-f6 #k"F6")
    (reg hemlock.terminfo:key-f7 #k"F7")
    (reg hemlock.terminfo:key-f8 #k"F8")
    (reg hemlock.terminfo:key-f9 #k"F9")
    (reg hemlock.terminfo:key-f10 #k"F10")
    (reg hemlock.terminfo:key-f11 #k"F11")
    (reg hemlock.terminfo:key-f12 #k"F12")
    ;; Terminfo definitions for movement keys
    (reg hemlock.terminfo:key-left #k"Leftarrow")
    (reg hemlock.terminfo:key-up #k"Uparrow")
    (reg hemlock.terminfo:key-down #k"Downarrow")
    (reg hemlock.terminfo:key-right #k"Rightarrow")
    (reg hemlock.terminfo:key-ppage #k"Pageup")
    (reg hemlock.terminfo:key-npage #k"Pagedown")
    ;; Best-effort to tell C-h and backspace apart: we have set VERASE to
    ;; #\Rubout so we can _sometimes_ do this: C-h is always send as
    ;; backspace.
    ;;
    ;; FIXME: This is less elegant than we'd like, however, since
    ;; #k"Delete" and #k"Rubout" are currently the same keysym in Hemlock:
    ;; so we can't use
    ;;   User-Backspace -> #k"Backspace"
    ;;   User-Delete    -> #k"Delete"
    ;;   User-C-h       -> #k"Rubout"
    ;; which wold degrade gracefully by collapsing User-Backspace
    ;; and User-C-h into #k"Rubout" -- now they collapse into #k"Control-h".
    (reg #\Rubout #k"Backspace")
    (reg hemlock.terminfo:key-backspace #k"Control-h")
    (reg hemlock.terminfo:key-dc #k"Delete")
    
    (reg hemlock.terminfo:key-home #k"Home")
    
    ;; Misc.
    ;;
    ;; Not #\return, because then C-j turns into return aka C-m.
    ;; Is this translation needed at all?
    (reg #\newline #k"Linefeed")
    ;;
    (reg #\tab #k"Tab")
    (reg #\escape #k"Escape")
    ;; Kludge: This shouldn't be needed, but otherwise C-c M-i doesn't work.
    (reg '(#\Esc #\i) #k"meta-i")))

(defun translate-tty-event (data)
  (let ((string (coerce data 'string)))
    (or (gethash string *tty-translations*)
        (when (= 1 (length string))
          (hemlock-ext:char-key-event (char string 0))))))

(defun tty-key-event (data)
  (loop with start = 0
        with length = (length data)
        while (< start length)
        do (loop for end from length downto (1+ start)
                 do (let ((event (translate-tty-event (subseq data start end))))
                      (when event
                        (q-event *real-editor-input* event)
                        (setf start end)
                        (return))))))

