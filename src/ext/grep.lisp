(defpackage :lem/grep
  (:use :cl
        :lem
        :lem/peek-source)
  (:export :grep)
  #+sbcl
  (:lock t))
(in-package :lem/grep)

(defun run-grep (string directory)
  (with-output-to-string (output)
    (uiop:run-program string
                      :directory directory
                      :output output
                      :error-output output)))

(defun parse-grep-result (text)
  (let* ((text (string-right-trim '(#\newline) text))
         (lines (uiop:split-string text :separator '(#\newline)))
         (file-line-content-tuples
           (mapcar (lambda (line)
                     (destructuring-bind (file line-number content)
                         (ppcre:split ":" line :limit 3)
                       (list file
                             (parse-integer line-number)
                             content)))
                   lines)))
    file-line-content-tuples))

(defun move (directory file line-number)
  (let ((buffer (find-file-buffer (merge-pathnames file directory))))
    (move-to-line (buffer-point buffer) line-number)))

(defun make-move-function (directory file line-number)
  (lambda ()
    (move directory file line-number)))

(defun get-content-string (start)
  (with-point ((start start)
               (end start))
    (line-start start)
    (next-single-property-change start :content-start)
    (character-offset start 1)
    (line-end end)
    (points-to-string start end)))

(defun change-grep-buffer (start end old-len)
  (declare (ignore end old-len))
  (let ((string (get-content-string start))
        (move (get-move-function start)))
    (with-point ((point (funcall move)))
      (with-point ((start point)
                   (end point))
        (line-start start)
        (line-end end)
        (buffer-undo-boundary (point-buffer start))
        (delete-between-points start end)
        (insert-string start string)
        (buffer-undo-boundary (point-buffer start)))))
  (show-matched-line))

(define-command grep (string &optional (directory (buffer-directory)))
    ((prompt-for-string ": " :initial-value "grep -nH "))
  (let ((result (parse-grep-result (run-grep string directory))))
    (if (null result)
        (editor-error "No match")
        (with-collecting-sources (collector)
          (loop :for (file line-number content) :in result
                :do (with-appending-source (point :move-function (make-move-function directory file line-number))
                      (insert-string point file :attribute 'lem/peek-source:filename-attribute :read-only t)
                      (insert-string point ":" :read-only t)
                      (insert-string point (princ-to-string line-number)
                                     :attribute 'lem/peek-source:position-attribute
                                     :read-only t)
                      (insert-string point ":" :read-only t :content-start t)
                      (insert-string point content)))
          (add-hook (variable-value 'after-change-functions :buffer (collector-buffer collector))
                    'change-grep-buffer)))))
