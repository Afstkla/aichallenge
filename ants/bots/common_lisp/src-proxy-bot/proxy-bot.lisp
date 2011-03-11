;;;; proxy-bot.lisp
;;;;
;;;; Possible problem: once the proxy bot has send the end turn to the real
;;;; bot it doesn't send the bot response back to the game engine.

(in-package :ants-proxy-bot)


;;; Parameters

(defparameter *verbose* nil)  ; bot seems to work well, turning logging off

(defparameter *input* *standard-input*)
(defparameter *output* *standard-output*)


;;; Utility Functions

(let ((log nil))
  (defun close-log ()
    (when log
      (force-output log)
      (close log)))

  (defun logmsg (&rest args)
    (when log
      (format log (with-output-to-string (s) (dolist (a args) (princ a s))))
      (force-output log)))

  (defun open-log (&optional (file "proxy-bot.log"))
    (when *verbose*
      (setf log (open file :direction :output :if-exists :append
                           :if-does-not-exist :create)))))


;;; Handlers

(defun error-handler (&optional arg)
  (logmsg "~&" arg " Aborting...~%")
  (cl-user::quit :unix-status 1))


(defun interrupted-by-user (arg)
  (declare (ignore arg))
  (logmsg "~&Interrupted by user. Aborting...~%")
  (cl-user::quit))


;;; Main Program

(defun main ()
  (open-log)
  (let (socket)
    (logmsg "~&~%=== ProxyBot started: " (current-date-time-string) " ===~%")
    (logmsg "Connecting to real bot at 127.0.0.1:41807...~%")
    (handler-bind (#+sbcl (sb-sys:interactive-interrupt #'interrupted-by-user)
                   (error #'error-handler))
      (setf socket (socket-connect #-allegro #(127 0 0 1) #+allegro "localhost"
                                   41807))
      (loop with end-of-game-p = nil
            with stream = (socket-stream socket)
            while (peek-char nil *input* nil)  ; run until we receive EOF
            for turn from 0
            do (logmsg "--- turn: " turn " ---~%")
               (logmsg "Sending game state... ")
               (loop with checksum = (list 0 0)
                     for line = (read-line *input* nil)
                     until (or (starts-with line "go")
                               (starts-with line "ready"))
                     do (when line
                          (when (starts-with line "end")
                            (setf end-of-game-p t))
                          (incf (first checksum) (length line))
                          (incf (second checksum))
                          (write-line line stream)
                          (force-output stream))
                     finally (logmsg "checksum = " checksum ".~%")
                             (when line
                               (write-line line stream)
                               (force-output stream)))
               (logmsg "Receiving bot response... ")
               (loop with checksum = (list 0 0)
                     for line = (read-line stream nil)
                     until (or (starts-with line "go")
                               end-of-game-p)
                     do (when line
                          (incf (first checksum) (length line))
                          (incf (second checksum))
                          (write-line line *output*)
                          (force-output *output*))
                     finally (logmsg "checksum = " checksum ".~%")
                             (when line
                               (write-line line *output*)
                               (force-output *output*)))
               (when end-of-game-p
                 (loop-finish)))
      (ignore-errors (socket-close socket))))
  (close-log))
