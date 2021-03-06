(in-package #:3bgl-shaders)
;;; some brain-dead utils for shader-related stuff (recompiling
;;; shaders, setting uniforms by name, etc)


(defun uniform-index (program name)
  (if program
      (gl:get-uniform-location program name)
      -1))

(defun uniformi (program name value)
  (gl:uniformi (uniform-index program name) value))

(defun uniformf (program name x &optional y z w)
  (let ((u (uniform-index program name)))
    (unless (minusp u)
      (cond
      (w (%gl:uniform-4f u (float x) (float y) (float z) (float w)))
      (z (%gl:uniform-3f u (float x) (float y) (float z)))
      (y (%gl:uniform-2f u (float x) (float y)))
      (x (%gl:uniform-1f u (float x)))))))

(defun uniformfv (program name v)
  (let ((u (uniform-index program name)))
    (unless (minusp u)
      (typecase v
        ;; fast cases
        ((vector single-float 3)
         (%gl:uniform-3f u (aref v 0) (aref v 1) (aref v 2)))
        ((vector single-float 4)
         (%gl:uniform-4f u (aref v 0) (aref v 1) (aref v 2) (aref v 3)))
        ;; convenient but slower cases
        ((vector * 4)
         (%gl:uniform-3f u (float (elt v 0) 1.0) (float (elt v 1) 1.0)
                         (float (elt v 2) 1.0) (float (elt v 3) 1.0)))
        ((vector * 3)
         (%gl:uniform-3f u (float (elt v 0) 1.0) (float (elt v 1) 1.0)
                         (float (elt v 2) 1.0)))
        ((vector * 2)
         (%gl:uniform-2f u (float (elt v 0) 1.0) (float (elt v 1) 1.0)))

        ((vector * 1)
         (%gl:uniform-1f u (float (elt v 0) 1.0)))

        ))))

(defun uniform-matrix (program name m)
  (let ((u (uniform-index program name)))
    (unless (minusp u)
      (gl:uniform-matrix u 4 (vector m) nil))))



(defun reload-program (old v f &key errorp (verbose t) geometry (version 450))
  "compile program from shaders named by V and F, on success, delete
program OLD and return new program, otherwise return OLD"
  ;; intended to be used like
  ;;  (setf (program foo) (reload-program (program foo) 'vertex 'frag))
  (let ((vs (gl:create-shader :vertex-shader))
        (fs (gl:create-shader :fragment-shader))
        (gs (when geometry (gl:create-shader :geometry-shader)))
        (program (gl:create-program)))
    (unwind-protect
         (flet ((try-shader (shader source)
                  (format t "compiling shader:~% ~s~%" source)
                  (gl:shader-source shader source)
                  (gl:compile-shader shader)
                  (cond
                    ((gl:get-shader shader :compile-status)
                     (gl:attach-shader program shader))
                    (errorp
                     (error "shader compile failed: ~s" (gl:get-shader-info-log shader)))
                    (t
                     (format (or verbose t) "shader compile failed: ~s" (gl:get-shader-info-log shader))
                     (return-from reload-program old)))))
           (try-shader vs (3bgl-shaders::generate-stage :vertex v
                                                        :version version))
           (try-shader fs (3bgl-shaders::generate-stage :fragment f
                                                        :version version))
           (when gs
             (try-shader gs (3bgl-shaders::generate-stage :geometry geometry
                                                          :version version)))
           (gl:link-program program)
           (cond
             ((gl:get-program program :link-status)
              ;; if it linked, swap with old program so we delete that on uwp
              (rotatef old program))
             (errorp
              (error "program link failed ~s"
                     (gl:get-program-info-log program)))
             (t
              (format (or verbose t) "program link failed: ~s" (gl:get-program-info-log program)))))
      ;; clean up on exit
      (gl:delete-shader vs)
      (gl:delete-shader fs)
      ;; PROGRAM is either program we just tried to link, or previous one if
      ;; link succeeded
      (when program
        (gl:delete-program program)))
    old))
