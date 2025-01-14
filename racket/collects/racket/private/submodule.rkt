(module submodule '#%kernel
  (#%require (for-syntax '#%kernel
                         "stxcase-scheme.rkt"
                         "more-scheme.rkt"
                         "letstx-scheme.rkt"
                         "qqstx.rkt"))

  (#%provide module+)

  (define-syntaxes (module+)
    (lambda (stx)
      (case (syntax-local-context)
        [(module-begin)
         (quasisyntax/loc stx (begin #,stx))]
        [(module)
         (syntax-case stx ()
           [(_ the-submodule e ...)
            (begin
              (unless (symbol? (syntax-e #'the-submodule))
                (raise-syntax-error #f
                                    "expected an identifier for a submodule, found something else"
                                    stx
                                    #'the-submodule))
              ;; This looks it up the first time and is allowed to create a
              ;; list and lift a module-end declaration if necessary:
              (let ([stxs-box (get-stxs-box stx #'the-submodule #t)])
                (set-box! stxs-box
                          (cons (append (reverse (syntax->list (syntax-local-introduce #'(e ...))))
                                        (car (unbox stxs-box)))
                                (cons (syntax-local-introduce stx) (cdr (unbox stxs-box))))))
              (syntax/loc stx (begin)))])]
        [else
         (raise-syntax-error #f
                             "allowed only in a module body"
                             stx)])))

  (begin-for-syntax
   ;; The following table is newly instantiated for each module
   ;; expansion that uses `module+', so it is effectively
   ;; module-local:
   (define-values (submodule->stxs-box) (make-weak-hash))
   (define-values (get-stxs-box)
     (lambda (form-stx the-submodule-stx lift?)
       (hash-ref! submodule->stxs-box (syntax-e the-submodule-stx)
                  (lambda ()
                    (when lift?
                      (syntax-local-lift-module-end-declaration
                       ;; Use the lexical context of the first `module+'
                       ;; form as the context of the implicit `#%module-begin':
                       (datum->syntax
                        form-stx
                        (list #'define-module the-submodule-stx)
                        form-stx)))
                    (box (cons null null)))))))

  ;; A use of this form is lifted to the end of the enclosing module
  ;; for each submodule created by `module+':
  (define-syntaxes (define-module)
    (lambda (stx)
      (syntax-case stx ()
        [(_ the-submodule)
         (let* ([stxs-box (get-stxs-box #f #'the-submodule #f)]
                ;; Propagate the lexical context of the first `module+'
                ;; for the implicit `#%module-begin':
                [module-decl
                 (datum->syntax
                  stx
                  (list*
                   #'module* 
                   #'the-submodule 
                   #f ; namespace context is the original context
                   (map syntax-local-introduce (reverse (car (unbox stxs-box)))))
                  stx)])
           ;; Add 'origin and copy properties for every original declaration
           (let loop ([stx module-decl]
                      [origs (cdr (unbox stxs-box))])
             (if (null? origs) stx
                 (let* ([orig (car origs)]
                        [id-stx (if (symbol? (syntax-e orig)) orig
                                    (car (syntax-e orig)))])
                   (loop (syntax-track-origin stx orig id-stx)
                         (cdr origs))))))]))))
