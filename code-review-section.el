;;; code-review-section.el --- Helpers for the UI -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2021 Wanderson Ferreira
;;
;; Author: Wanderson Ferreira <https://github.com/wandersoncferreira>
;; Maintainer: Wanderson Ferreira <wand@hey.com>
;; Created: October 14, 2021
;; Modified: October 14, 2021
;; Version: 0.0.1
;; Keywords: tools
;; Homepage: https://github.com/wandersoncferreira/code-review-section
;; Package-Requires: ((emacs "25.1"))
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;;
;;
;;; Code:

(require 'magit-utils)
(require 'magit-section)
(require 'magit-diff)
(require 'code-review-github)

(defvar code-review-section-first-hunk-header-pos nil
  "A-LIST to hold the first hunk header position for each path.
For internal usage only.")

(defvar code-review-section-written-comments-count nil
  "A-LIST to hold how many lines of comments written for each path.
For internal usage only.")

(defvar code-review-section-written-comments-ident nil
  "LIST to hold the identifiers comments written.
For internal usage only.")

(defvar code-review-section-grouped-comments nil
  "Hold the grouped comments info.
Used by the overwritten version of `magit-diff-wash-hunk'.
For internal usage only.")

(defvar code-review-section-file nil
  "For internal usage only.")

(defun code-review-section-diff-pos ()
  "Compute the true diff position by discounting additional lines in the buffer."
  (let ((curr-pos (line-number-at-pos))
        (hunk-pos (or (alist-get code-review-section-file
                                 code-review-section-first-hunk-header-pos
                                 nil nil 'equal)
                      0))
        (comments-written-pos (or (alist-get code-review-section-file
                                             code-review-section-written-comments-count
                                             nil nil 'equal)
                                  0)))
    (- curr-pos
       hunk-pos
       comments-written-pos)))

(defun code-review-section-insert-outdated-comment (comments)
  "Insert outdated COMMENTS in the buffer."

  ;;; hunk groups are necessary because we usually have multiple reviews about
  ;;; the same original position accross different commits snapshots.
  ;;; as github UI we will add those hunks and its comments
  (let* ((hunk-groups (-group-by (lambda (el) (a-get el 'diffHunk)) comments))
         (hunks (a-keys hunk-groups)))
    (dolist (hunk hunks)
      (let* ((diff-hunk-lines (split-string hunk "\n"))
             (first-hunk-commit (-first-item (alist-get hunk hunk-groups nil nil 'equal))))

        (setq code-review-section-written-comments-count
              (code-review-utils-update-count-comments-written
               code-review-section-written-comments-count
               code-review-section-file
               (+ 1 (length diff-hunk-lines))))

        (magit-insert-section (comment first-hunk-commit)
          (let ((heading (format "Reviewed by %s [%s] - [OUTDATED]"
                                 (a-get first-hunk-commit 'author)
                                 (a-get first-hunk-commit 'state))))
            (add-face-text-property 0 (length heading)
                                    'code-review-outdated-comment-heading
                                    t heading)
            (magit-insert-heading heading))
          (magit-insert-section (hunk hunk)
            (dolist (l diff-hunk-lines)
              (insert l)
              (insert "\n"))

            (dolist (c (alist-get hunk hunk-groups nil nil 'equal))
              (let ((body-lines (split-string (a-get c 'bodyText) "\n")))

                (setq code-review-section-written-comments-count
                      (code-review-utils-update-count-comments-written
                       code-review-section-written-comments-count
                       code-review-section-file
                       (+ 1 (length body-lines))))

                (magit-insert-section (comment c)
                  (insert (format "Reviewed by %s[%s]:"
                                  (a-get c 'author)
                                  (a-get c 'state)))
                  (put-text-property
                   (line-beginning-position)
                   (1+ (line-end-position))
                   'font-lock-face
                   'magit-diff-hunk-heading)
                  (magit-insert-heading)
                  (magit-insert-section (comment c)
                    (dolist (l body-lines)
                      (insert l)
                      (insert "\n"))))))))))))

(defun code-review-section-insert-comment (comments)
  "Insert COMMENTS in the buffer.
A quite good assumption: every comment in an outdated hunk will be outdated."
  (if (a-get (-first-item comments) 'outdated)
      (code-review-section-insert-outdated-comment comments)
    (dolist (c comments)
      (let ((body-lines (split-string (a-get c 'bodyText) "\n")))

        (setq code-review-section-written-comments-count
              (code-review-utils-update-count-comments-written
               code-review-section-written-comments-count
               code-review-section-file
               (+ 2 (length body-lines))))

        (magit-insert-section (comment c)
          (let ((heading (format "Reviewed by @%s [%s]: "
                                 (a-get c 'author)
                                 (a-get c 'state))))
            (add-face-text-property 0 (length heading)
                                    'code-review-section-recent-comment t heading)
            (magit-insert-heading heading))
          (magit-insert-section (comment c)
            (dolist (l body-lines)
              (insert l)
              (insert "\n"))
            (insert ?\n)))))))

(defun magit-diff-insert-file-section
    (file orig status modes rename header &optional long-status)
  "Overwrite the original Magit function on `magit-diff.el' file."

  ;;; code-review specific code.
  ;;; I need to set a reference point for the first hunk header
  ;;; so the positioning of comments is done correctly.
  (setq code-review-section-file (substring-no-properties file))

  (magit-insert-section section
    (file file (or (equal status "deleted")
                   (derived-mode-p 'magit-status-mode)))
    (insert (propertize (format "%-10s %s" status
                                (if (or (not orig) (equal orig file))
                                    file
                                  (format "%s -> %s" orig file)))
                        'font-lock-face 'magit-diff-file-heading))
    (when long-status
      (insert (format " (%s)" long-status)))
    (magit-insert-heading)
    (unless (equal orig file)
      (oset section source orig))
    (oset section header header)
    (when modes
      (magit-insert-section (hunk '(chmod))
        (insert modes)
        (magit-insert-heading)))
    (when rename
      (magit-insert-section (hunk '(rename))
        (insert rename)
        (magit-insert-heading)))
    (magit-wash-sequence #'magit-diff-wash-hunk)))

(defun magit-diff-wash-hunk ()
  "Overwrite the original Magit function on `magit-diff.el' file.
Code Review inserts PR comments sections in the diff buffer."
  (when (looking-at "^@\\{2,\\} \\(.+?\\) @\\{2,\\}\\(?: \\(.*\\)\\)?")

    ;;; code-review specific code.
    ;;; I need to set a reference point for the first hunk header
    ;;; so the positioning of comments is done correctly.
    (setf code-review-section-first-hunk-header-pos
          (code-review-utils-update-first-hunk-pos
           code-review-section-first-hunk-header-pos
           code-review-section-file
           (+ 1 (line-number-at-pos))))

    (let* ((heading  (match-string 0))
           (ranges   (mapcar (lambda (str)
                               (mapcar #'string-to-number
                                       (split-string (substring str 1) ",")))
                             (split-string (match-string 1))))
           (about    (match-string 2))
           (combined (= (length ranges) 3))
           (value    (cons about ranges)))
      (magit-delete-line)
      (magit-insert-section section (hunk value)
        (insert (propertize (concat heading "\n")
                            'font-lock-face 'magit-diff-hunk-heading))
        (magit-insert-heading)
        (while (not (or (eobp) (looking-at "^[^-+\s\\]")))
          ;;; code-review specific code.
          ;;; add code comments
          (let ((path-pos (code-review-utils-path-pos-key code-review-section-file (code-review-section-diff-pos))))
            (if-let (grouped-comments (and
                                       (not (code-review-utils-already-written?
                                             code-review-section-written-comments-ident
                                             path-pos))
                                       (code-review-utils-get-comments
                                        code-review-section-grouped-comments
                                        path-pos)))
                (progn
                  (add-to-list 'code-review-section-written-comments-ident path-pos)
                  (code-review-section-insert-comment grouped-comments))
              (forward-line))))
        (oset section end (point))
        (oset section washer 'magit-diff-paint-hunk)
        (oset section combined combined)
        (if combined
            (oset section from-ranges (butlast ranges))
          (oset section from-range (car ranges)))
        (oset section to-range (car (last ranges)))
        (oset section about about)))
    t))

(defun code-review-section-insert-headers (pull-request)
  "Insert header with PULL-REQUEST data."
  (let-alist pull-request
    (let* ((assignee-names (-map
                            (lambda (a)
                              (format "%s (@%s)"
                                      (a-get a 'name)
                                      (a-get a 'login)))
                            .assignees.nodes))
           (assignees (string-join assignee-names ", "))
           (project-names (-map
                           (lambda (p)
                             (a-get-in p (list 'project 'name)))
                           .projectCards.nodes))
           (projects (string-join project-names ", "))
           (reviewers (string-join .suggestedReviewers ", "))
           (suggested-reviewers (if (string-empty-p reviewers)
                                    (propertize "No reviews" 'font-lock-face 'magit-dimmed)
                                  reviewers)))
      (magit-insert-section (_)
        (insert (format "%-17s" "Title: ") .title)
        (magit-insert-heading)
        (magit-insert-section (_)
          (insert (format "%-17s" "State: ") (or (format "%s" .state) "none"))
          (insert ?\n))
        (magit-insert-section (_)
          (insert (format "%-17s" "Refs: "))
          (insert .baseRefName)
          (insert (propertize " ... " 'font-lock-face 'magit-dimmed))
          (insert .headRefName)
          (insert ?\n))
        (magit-insert-section (_)
          (insert (format "%-17s" "Milestone: ") (format "%s (%s%%)"
                                                         .milestone.title
                                                         .milestone.progressPercentage))
          (insert ?\n))
        (magit-insert-section (_)
          (insert (format "%-17s" "Labels: "))
          (dolist (label .labels.nodes)
            (insert (a-get label 'name))
            (let* ((color (concat "#" (a-get label 'color)))
                   (background (code-review-utils--sanitize-color color))
                   (foreground (code-review-utils--contrast-color color))
                   (o (make-overlay (- (point) (length (a-get label 'name))) (point))))
              (overlay-put o 'priority 2)
              (overlay-put o 'evaporate t)
              (overlay-put o 'font-lock-face
                           `((:background ,background)
                             (:foreground ,foreground)
                             code-review-label)))
            (insert " "))
          (insert ?\n))
        (magit-insert-section (_)
          (insert (format "%-17s" "Assignees: ") assignees)
          (insert ?\n))
        (magit-insert-section (_)
          (insert (format "%-17s" "Projects: ") projects)
          (insert ?\n))
        (magit-insert-section (_)
          (insert (format "%-17s" "Suggested-Reviewers: ") suggested-reviewers)
          (insert ?\n)))))
  (insert ?\n))

;;; faces used from magit:
;; magit-section-heading
;; magit-dimmed
;; magit-hash

(defun code-review-section-insert-commits (pull-request)
  "Insert commits from PULL-REQUEST."
  (let-alist pull-request
    (magit-insert-section (commits-header)
      (insert (propertize "Commits" 'font-lock-face 'magit-section-heading))
      (magit-insert-heading)
      (magit-insert-section (commits)
        (dolist (c .commits.nodes)
          (insert (propertize
                   (format "%-6s " (a-get-in c (list 'commit 'abbreviatedOid)))
                   'font-lock-face 'magit-hash)
                  (a-get-in c (list 'commit 'message)))
          (insert ?\n)))))
  (insert ?\n))

(defun code-review-section-insert-pr-description (pull-request)
  "Insert PULL-REQUEST description."
  (magit-insert-section (_)
    (insert (propertize "Description" 'font-lock-face 'magit-section-heading))
    (magit-insert-heading)
    (magit-insert-section (_)
      (let-alist pull-request
        (if (string-empty-p .bodyText)
            (insert (propertize "No description provided." 'font-lock-face 'magit-dimmed))
          (insert .bodyText))
        (insert ?\n)
        (insert ?\n)
        (insert ?\n)))))

(defun code-review-section-insert-feedback-heading ()
  "Insert feedback heading."
  (magit-insert-section (feedback)
    (insert (propertize "Your Review Feedback" 'font-lock-face 'magit-section-heading))
    (magit-insert-heading)
    (magit-insert-section (feedback-text)
      (insert (propertize "Leave a comment here." 'font-lock-face 'magit-dimmed))
      (insert ?\n)
      (insert ?\n))))

(defun code-review-section-insert-feedback (feedback)
  "Add review FEEDBACK."
  (with-current-buffer (get-buffer "*Code Review*")
    (save-excursion
      (goto-char (point-min))
      (magit-wash-sequence
       (lambda ()
         (with-slots (type value) (magit-current-section)
           (if (string-equal type 'feedback-text)
               (let ((inhibit-read-only t))
                 ;;; improve this to abort going over the whole buffer after we add the text
                 (delete-region (line-beginning-position) (line-end-position))
                 (insert feedback))
             (forward-line))))))))

(defun code-review-section-insert-local-comment (local-comment metadata)
  "Insert a LOCAL-COMMENT and attach section METADATA."
  (with-current-buffer (get-buffer "*Code Review*")
    (let ((inhibit-read-only t))
      (goto-char (a-get metadata 'cursor-pos))
      (forward-line)
      (magit-insert-section (local-comment-header metadata)
        (insert (format "[local comment] - @%s:" (code-review-utils-get-user)))
        (put-text-property
         (line-beginning-position)
         (1+ (line-end-position))
         'font-lock-face
         'magit-diff-hunk-heading)
        (magit-insert-heading)
        (magit-insert-section (local-comment metadata)
          (dolist (l (split-string local-comment "\n"))
            (insert l)
            (insert "\n")))))))

(defun code-review-section-wash (grouped-comments)
  "Format buffer text with PULL-REQUEST and GROUPED-COMMENTS info."

  ;;; unfortunately, this data needs to be passed to a magit function
  ;;; deep in the call stack.
  (setq code-review-section-grouped-comments grouped-comments)
  (magit-diff-wash-diff ()))

(provide 'code-review-section)
;;; code-review-section.el ends here
