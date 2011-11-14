;;; Copyright (c) 2011, Peter Seibel.  All rights reserved.

;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions
;;; are met:
;;;
;;;   * Redistributions of source code must retain the above copyright
;;;     notice, this list of conditions and the following disclaimer.
;;;
;;;   * Redistributions in binary form must reproduce the above
;;;     copyright notice, this list of conditions and the following
;;;     disclaimer in the documentation and/or other materials
;;;     provided with the distribution.
;;;
;;; THIS SOFTWARE IS PROVIDED BY THE AUTHOR 'AS IS' AND ANY EXPRESSED
;;; OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
;;; WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;; ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
;;; DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
;;; DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
;;; GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
;;; WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
;;; NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
;;; SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

(in-package :toot)

(defvar *test-acceptor* nil)

(defun test-document-directory (&optional sub-directory)
  (asdf:system-relative-pathname :toot (format nil "www/~@[~A~]" sub-directory)))

(defun start-test-server (port)
  (setf *test-acceptor* (start-server :port port :handler (test-handler))))

(defun reset-test-handler ()
  (setf (handler *test-acceptor*) (test-handler)))

;;; FIXME: this is perhaps not as correct as it should be. For
;;; instance, it may not work on windows beacuse of \ vs /. See the
;;; old create-folder-dispatcher-and-handler to see if there's any
;;; goodness that needs to be brought over.
(defun make-static-file-handler (document-root &optional uri-prefix)
  "Make a handler that maps the requested URI to a file under
DOCUMENT-ROOT and serves it if it exists. Does a basic sanity check to
dissalow requests for things like ../../../etc/passwd. Also maps
directory names to index.html in that directory. If URI-PREFIX is
supplied, it will strip that from the URI before mapping it to a
file."
  (lambda (request)
    (let ((path (uri-path (request-uri request))))
      (unless (safe-filename-p path)
        (abort-request-handler request +http-forbidden+))
      (let ((file (resolve-file (enough-url path uri-prefix) document-root)))
        (serve-file request file)))))

(defun enough-url (url url-prefix)
  "Returns the relative portion of URL relative to URL-PREFIX, similar
to what ENOUGH-NAMESTRING does for pathnames."
  (let ((prefix-length (length url-prefix)))
    (if (string= url url-prefix :end1 prefix-length)
        (subseq url prefix-length)
        url)))

(defun safe-filename-p (path)
  "Verify that a path, translated to a file doesn't contain any tricky
bits such as '..'"
  (let ((directory (pathname-directory (subseq path 1))))
    (or (stringp directory)
        (null directory)
        (and (consp directory)
             (eql (first directory) :relative)
             (every #'stringp (rest directory))))))

(defun resolve-file (path document-root)
  (merge-pathnames (subseq (add-index path) 1) document-root))

(defun add-index (filename &key (extension "html"))
  (format nil "~a~@[index~*~@[.~a~]~]" filename (ends-with #\/ filename) extension))

;;; Simple composite handler that searches a list of sub-handlers for
;;; one that can handle the request.

(defclass search-handler ()
  ((handlers :initarg :handlers :initform () :accessor handlers)))

(defun make-search-handler (&rest sub-handlers)
  (make-instance 'search-handler :handlers sub-handlers))

(defun add-handler (search-handler sub-handler)
  (push sub-handler (handlers search-handler)))

(defmethod handle-request ((handler search-handler) request)
  (loop for sub in (handlers handler)
     for result = (handle-request sub request)
     when (not (eql result 'not-handled)) return result
     finally (return 'not-handled)))

(defun make-exact-path-handler (path sub-handler)
  "Make a handler that handles the request with SUB-HANDLER if the
file name of the request is exactly the given PATH."
  (lambda (request)
    (maybe-handle (string= path (uri-path (request-uri request)))
      (handle-request sub-handler request))))

(defun test-handler ()
  (make-search-handler
   (make-exact-path-handler "/form-test-params" 'form-test-params)
   (make-exact-path-handler "/form-test-octets" 'form-test-octets)
   (make-exact-path-handler "/form-test-stream" 'form-test-stream)
   (make-static-file-handler (test-document-directory))))

(defun form-test-params (request)
  (with-output-to-string (s)
    (format s "~&<html><head><title>Form test params</title></head><body>")
    (format s "~&<h1>Form results via <code>post-parameters</code></h1>")
    (loop for (k . v) in (post-parameters request)
       do
         (cond
           ((listp v)
            (format s "~&<p>~a: ~a</p><p><pre>" k v)
            (with-open-file (in (first v))
              (loop for char = (read-char in nil nil)
                 while char do (write-string (escape-for-html (string char)) s)))
            (format s "</pre></p>"))
           (t (format s "~&<p>~a: ~a</p>" k v))))
    (format s "~&</body></html>")))

(defun form-test-octets (request)
  (with-output-to-string (s)
    (format s "~&<html><head><title>Form test octets</title></head><body>")
    (format s "~&<h1>Form results via <code>body-octets</code></h1>")
    (format s "~&<p><pre>~a</pre></p>" (escape-for-html (octets-to-string (body-octets request))))
    (format s "~&</body></html>")))

(defun form-test-stream (request)
  (with-output-to-string (s)
    (format s "~&<html><head><title>Form test stream</title></head><body>")
    (format s "~&<h1>Form results via <code>body-stream</code></h1>")
    (format s "~&<p><pre>")
    (loop with in = (body-stream request)
       for char = (read-char in nil nil)
       while char do (write-string (escape-for-html (string char)) s))
    (format s "</pre></p>")
    (format s "~&</body></html>")))



