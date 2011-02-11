;;; Copyright (c) 2011 Cyrus Harmon, All rights reserved.
;;; See COPYRIGHT file for details.

(in-package :opticl)

(deftype integer-image (&optional channels bits-per-channel)
  `(simple-array ,(if (numberp bits-per-channel)
                      `(unsigned-byte ,bits-per-channel)
                      bits-per-channel)
                 ,(if (numberp channels)
                      (if (= channels 1)
                          `(* *)
                          `(* * ,channels))
                      channels)))

(deftype single-float-image (&optional channels)
  `(simple-array single-float
                 ,(if (numberp channels)
                      (if (= channels 1)
                          `(* *)
                          `(* * ,channels))
                      channels)))

(deftype double-float-image (&optional channels)
  `(simple-array double-float
                 ,(if (numberp channels)
                      (if (= channels 1)
                          `(* *)
                          `(* * ,channels))
                      channels)))

(defmacro check-bounds ((img y x) &body body)
  (let ((ymax (gensym)) (xmax (gensym)))
    `(let ((,ymax (1- (array-dimension ,img 0)))
           (,xmax (1- (array-dimension ,img 1))))
       (if (and (<= 0 ,y ,ymax)
                (<= 0 ,x ,xmax))
           ,@body))))


(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *image-types*
    '((1-bit-gray-image '(integer-image 1 1) '(unsigned-byte 1) 1)
      (2-bit-gray-image '(integer-image 1 2) '(unsigned-byte 2) 1)
      (4-bit-gray-image '(integer-image 1 4) '(unsigned-byte 4) 1)
      (8-bit-gray-image '(integer-image 1 8) '(unsigned-byte 8) 1)
      (16-bit-gray-image '(integer-image 1 16) '(unsigned-byte 16) 1)
      (32-bit-gray-image '(integer-image 1 32) '(unsigned-byte 32) 1)
      (single-float-gray-image '(single-float-image 1) 'single-float 1)
      (double-float-gray-image '(double-float-image 1) 'double-float 1)

      (4-bit-rgb-image '(integer-image 3 4) '(unsigned-byte 4) 3)
      (8-bit-rgb-image '(integer-image 3 8) '(unsigned-byte 8) 3)
      (16-bit-rgb-image '(integer-image 3 16) '(unsigned-byte 16) 3)
      (single-float-rgb-image '(single-float-image 3) 'single-float 3)
      (double-float-rgb-image '(double-float-image 3) 'double-float 3)

      (4-bit-rgba-image '(integer-image 4 4) '(unsigned-byte 4) 4)
      (8-bit-rgba-image '(integer-image 4 8) '(unsigned-byte 8) 4)
      (16-bit-rgba-image '(integer-image 4 16) '(unsigned-byte 16) 4)
      (single-float-rgba-image '(single-float-image 4) 'single-float 4)
      (double-float-rgba-image '(double-float-image 4) 'double-float 4)
      )))

(macrolet
    ((frob-image (name image-type element-type num-channels)
       (let ((type
              (read-from-string (format nil "~A" name))))
         (let ((ctor-function
                (read-from-string (format nil "make-~A" type))))
           `(progn
              (deftype ,type () ,image-type)
              (defun ,ctor-function (height width &key
                                     (initial-element nil initial-element-p)
                                     (initial-contents nil initial-contents-p))
                (apply #'make-array (append (list height width)
                                            (when (> ,num-channels 1)
                                              (list ,num-channels)))
                       :element-type ,element-type
                       (append
                        (when initial-element-p
                          `(:initial-element ,initial-element))
                        (when initial-contents-p
                          `(:initial-contents ,initial-contents)))))))))
     (frobber ()
       `(progn
          ,@(loop for (name image-type element-type num-channels) in *image-types*
               collect 
               `(frob-image ,name ,image-type ,element-type ,num-channels)))))
  (frobber))


(defun get-image-dimensions (image-var env)
  #+(or sbcl ccl)
  (multiple-value-bind (binding-type localp declarations)
      (opticl-cltl2:variable-information image-var env)
    (declare (ignore binding-type localp))
    (let ((type-decl (find 'type declarations :key #'car)))
      (and type-decl
           (listp type-decl)
           (= (length type-decl) 4)
           (fourth type-decl)))))

(defconstant +max-image-channels+ 4)

(define-setf-expander pixel (image-var y x &environment env)
  (let ((image-dimensions (get-image-dimensions image-var env)))
    (if image-dimensions
        (let ((arity (or (and (= (length image-dimensions) 3)
                              (third image-dimensions))
                         1))
              (temp-y (gensym))
              (temp-x (gensym)))
          (if (= arity 1)
              (let ((store (gensym)))
                (values `(,temp-y ,temp-x)
                        `(,y ,x)
                        `(,store)
                        `(setf (aref ,image-var ,temp-y ,temp-x) ,store)
                        `(aref ,image-var ,temp-y ,temp-x)))
              (let ((stores (map-into (make-list arity) #'gensym)))
                (values `(,temp-y ,temp-x)
                        `(,y ,x)
                        stores
                        `(progn (setf ,@(loop for i from 0
                                           for store in stores
                                           collect `(aref ,image-var ,temp-y ,temp-x ,i)
                                           collect store))
                                (values ,@stores))
                        `(values ,@(loop for i from 0 below (length stores)
                                      collect `(aref ,image-var ,temp-y ,temp-x ,i)))))))
        (let ((syms (map-into (make-list +max-image-channels+) #'gensym)))
          (let ((temp-y (gensym))
                (temp-x (gensym)))
            (values `(,temp-y ,temp-x)
                    `(,y ,x)
                    syms
                    `(case (array-rank ,image-var)
                       (3 (let ((d (array-dimension ,image-var 2)))
                            (case d
                              (1
                               (values
                                (setf (aref ,image-var ,temp-y ,temp-x 0) ,(elt syms 0))))
                              (2
                               (values
                                (setf (aref ,image-var ,temp-y ,temp-x 0) ,(elt syms 0))
                                (setf (aref ,image-var ,temp-y ,temp-x 1) ,(elt syms 1))))
                              (3
                               (values
                                (setf (aref ,image-var ,temp-y ,temp-x 0) ,(elt syms 0))
                                (setf (aref ,image-var ,temp-y ,temp-x 1) ,(elt syms 1))
                                (setf (aref ,image-var ,temp-y ,temp-x 2) ,(elt syms 2))))
                              (4
                               (values
                                (setf (aref ,image-var ,temp-y ,temp-x 0) ,(elt syms 0))
                                (setf (aref ,image-var ,temp-y ,temp-x 1) ,(elt syms 1))
                                (setf (aref ,image-var ,temp-y ,temp-x 2) ,(elt syms 2))
                                (setf (aref ,image-var ,temp-y ,temp-x 3) ,(elt syms 3))))
                              (t (loop for i below d
                                    collect (setf (aref ,image-var ,temp-y ,temp-x i) (elt (list ,@syms) i)))))))
                       (2 (setf (aref ,image-var ,temp-y ,temp-x) ,(elt syms 0))))
                    `(case (array-rank ,image-var)
                       (3
                        (let ((d (array-dimension ,image-var 2)))
                          (case d
                            (1
                             (values
                              (aref ,image-var ,temp-y ,temp-x 0)))
                            (2
                             (values
                              (aref ,image-var ,temp-y ,temp-x 0)
                              (aref ,image-var ,temp-y ,temp-x 1)))
                            (3
                             (values
                              (aref ,image-var ,temp-y ,temp-x 0)
                              (aref ,image-var ,temp-y ,temp-x 1)
                              (aref ,image-var ,temp-y ,temp-x 2)))
                            (4
                             (values
                              (aref ,image-var ,temp-y ,temp-x 0)
                              (aref ,image-var ,temp-y ,temp-x 1)
                              (aref ,image-var ,temp-y ,temp-x 2)
                              (aref ,image-var ,temp-y ,temp-x 3)))
                            (t (values-list
                                (loop for i below d
                                   collect (aref ,image-var ,temp-y ,temp-x i)))))))
                       (2 (aref ,image-var ,temp-y ,temp-x)))))))))



(defmacro pixel (image-var y x &environment env)
  (let ((image-dimensions (get-image-dimensions image-var env)))
    (if image-dimensions
        (progn
          (case (length image-dimensions)
            (2 `(aref ,image-var ,y ,x))
            (3 `(values ,@(loop for i below (third image-dimensions)
                             collect `(aref ,image-var ,y ,x ,i))))))
        `(case (array-rank ,image-var)
           (2 (aref ,image-var ,y ,x))
           (3 (case (array-dimension ,image-var 2)
                (2 (values
                    (aref ,image-var ,y ,x 0)
                    (aref ,image-var ,y ,x 1)))
                (3 (values
                    (aref ,image-var ,y ,x 0)
                    (aref ,image-var ,y ,x 1)
                    (aref ,image-var ,y ,x 2)))
                (4 (values
                    (aref ,image-var ,y ,x 0)
                    (aref ,image-var ,y ,x 1)
                    (aref ,image-var ,y ,x 2)
                    (aref ,image-var ,y ,x 3)))))))))


(defun constrain (val min max)
  (let ((val (if (< val min) min val)))
    (if (> val max)
        max
        val)))

(defmacro with-image-bounds ((ymax-var xmax-var &optional (channels (gensym))) img &body body)
  `(let ((,ymax-var (array-dimension ,img 0))
         (,xmax-var (array-dimension ,img 1))
         (,channels (when (= (array-rank ,img) 3)
                      (array-dimension ,img 2))))
     (declare (ignorable ,channels))
     ,@body))


(defun pixel-in-bounds (img y x)
  (with-image-bounds (ymax xmax)
      img
    (and (>= y 0)
         (< y ymax)
         (>= x 0)
         (< x xmax))))
