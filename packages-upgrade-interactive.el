;;; packages-upgrade-interactive.el --- Simple tools for upgrading Emacs packages interactively
;; -*- lexical-binding: t -*-

;; Author: Tegar Syahputra <i8iho23kh@protonmail.com>
;; Version: 0.0.1
;; Keywords: package tools
;; Package-Requires: ((emacs "28"))
;; URL: https://github.com/qxxt/packages-upgrade-interactive.el

;;; Commentary:

;; Simple tools for upgrading Emacs packages interactively

;;; Usage:
;;
;; M-x pui--package-upgrade-all
;; Upgrade all packages without prompting. If package-vc is supported,
;; upgrade those as well.
;;
;; (pui--package-upgrade-all 'vc)
;; If called uninteractively, you need to pass non-nil to VC
;; parameters to upgrade vc packages.
;;
;; To make with work with both vc and non-vc supported Emacs.
;; (pui--package-upgrade-all (functionp 'package-vc-p))
;; This will check if package-vc is supported, and pass those value as VC paramenter.
;;
;;
;; M-x package-refresh-contents-maybe
;; refreshes package archives, package archives are only refreshed IF
;; the number of days from `package-refresh-interval' has passed.
;;
;; (package-refresh-contents-maybe ’no-strict)
;; If the no-strict parameter is non-nil, it will tolerate 1 day lapse
;; from `package-refresh-interval’.  This is only practical for if you
;; want to refresh package archive at specified time of day using
;; `pui--scheduler’.
;;
;;
;; M-x package-upgrade-interactively
;; Upgrade package interactively. If package-vc is supported, those
;; packages will be included for selection as well.
;;
;; (package-upgrade-interactively 'vc)
;; If called uninteractively, you need to pass non-nil to VC
;; parameters to upgrade vc packages.
;;
;; To make with work with both vc and non-vc supported Emacs:
;; (package-upgrade-interactively (functionp 'package-vc-p))
;; Or:
;; (call-interactively 'package-upgrade-interactively)
;;
;;
;; (pui--scheduler "07:00pm")
;; Schedules a call to `package-refresh-contents-maybe' and
;; `package-upgrade-interactively' at 7:00 PM.
;; The format must be either HH:MM or HH:MMam
;;
;;
;;
;; Typical setup for running at startup:
;;
;; (setq package-refresh-interval 2) ; Set to 2 days period
;; (package-refresh-contents-maybe) ; Refresh package archives
;; (call-interactively 'package-upgrade-interactively) ; Upgrade package
;; (pui--scheduler "07:00am") ; Run at 07:00am

;;; Customization:
;;
;; The number of days that must pass before package archives are
;; refreshed can be customized with the package-refresh-interval
;; variable. The default value is 2 days. To change it, set the
;; variable to the desired number of days:
;; (setq package-refresh-interval 1)

;;; Code:

(require 'package)
(require 'package-vc nil t)
(require 'time-date)
(require 'diary-lib)

(defgroup packages-upgrade-interactive nil
  "packages-upgrade-interactive Group."
  :group 'package)

(defcustom package-refresh-interval 2
  "Number of DAYS until `package-refresh-contents-maybe’."
  :type 'number
  :group 'packages-upgrade-interactive)

(defvar pui--is-package-vc (featurep 'package-vc)
  "Check Wether or not `package-vc' is supported.

`package-vc' is a new feature of Emacs 29.")

(defvar pui--archive-contents-file (expand-file-name
				    (concat "archives/"
					    (caar package-archives)
					    "/archive-contents")
				    package-user-dir)
  "Path to package-archive file for checking freshness of `package-archive-contents'.")

(defun pui--selected-p ()
  "Check if current line is selected."
  (equal ?S (char-after (line-beginning-position))))

;; (defun pui--currently-vc ()
;;   "Check if current line is a vc package."
;;   (goto-char (- (line-end-position) 4))
;;   (looking-at "\(vc\)"))

(defun pui--select ()
  "Select package in current line."
  (if (null (pui--selected-p))
      (let ((inhibit-read-only t))
	(save-excursion
	  (goto-char (line-beginning-position))
	  (delete-char 1)
	  (insert-char ?S)))))

(defun pui--unselect ()
  "Unselect package in current line."
  (if (pui--selected-p)
      (let ((inhibit-read-only t))
	(save-excursion
	  (goto-char (line-beginning-position))
	  (delete-char 1)
	  (insert ?\ )))))

(defun pui--upgradeable-packages (&optional vc)
  "Get list of upgradable packages.

If VC is non-nil, upgradable vc package will also be included.
If `package-vc' is not supported and VC is non-nil, it will throw error.

Return the list of:
 (old-package-desc new-package-desc)"
  (if (and vc (null pui--is-package-vc))
      (error "Trying to run `pui--upgradeable-packages' with vc but `package-vc' is not supported"))

  (remq nil (mapcar
	     (lambda (elem)
	       (let ((installed (cadr elem))
		     (available (cadr (assq (car elem) package-archive-contents))))
		 (if (and vc (package-vc-p installed))
		     (list installed nil)
		   (if (and available
			    (version-list-<
			     (package-desc-version installed)
			     (package-desc-version available)))
		       (list installed available)))))
	     package-alist)))

(defun pui--package-upgrade (old-pkg-desc new-pkg-desc)
  "Install NEW-PKG-DESC and delete OLD-PKG-DESC.

If OLD-PKG-DESC is a vc package, NEW-PKG-DESC is ignored."
  (if (and pui--is-package-vc
	   (package-vc-p old-pkg-desc))
      (package-vc-upgrade old-pkg-desc)
    (unwind-protect
	(package-install new-pkg-desc 'dont-select)
      (if (package-installed-p (package-desc-name new-pkg-desc)
			       (package-desc-version new-pkg-desc))
	  (package-delete old-pkg-desc 'force 'dont-unselect)))))

(defun pui--format-package-desc (old-pkg-desc new-pkg-desc)
  "Format OLD-PKG-DESC and NEW-PKG-DESC.

This format are used:
package-name (current-version) => (new-version)

If OLD-PKG-DESC is a vc package, NEW-PKG-DESC is ignored.
And, the following format will be used instead:
package-name (current-version) (vc)"
  (format "%s (%s) %s"
	  (package-desc-name old-pkg-desc)
	  (package-version-join (package-desc-version old-pkg-desc))
	  (if (and pui--is-package-vc (package-vc-p old-pkg-desc))
	      "(vc)"
	    (format "=> (%s)" (package-version-join (package-desc-version new-pkg-desc))))))

;;;###autoload
(defun pui--package-upgrade-all (&optional vc)
  "Upgrade all packages without prompt.

If VC is non-nil, upgrade vc package also.
If called interactively, VC will automatically be true if `package-vc' is
exist."
  (interactive `(,pui--is-package-vc))

  (if (and vc (null pui--is-package-vc))
      (error "Trying to upgrade all packages with vc but package-vc doesn’t exist"))

  (when-let ((upgradable-packages (pui--upgradeable-packages vc)))
    (message "Packages to upgrade: %s" (mapconcat (lambda (x) (symbol-name (package-desc-name (car x)))) upgradable-packages " "))
    (mapcar (lambda (l) (apply #'pui--package-upgrade l)) upgradable-packages)))

;;;###autoload
(defun package-refresh-contents-maybe (&optional nostrict)
  "Refresh package only if `package-refresh-interval' days has passed.

If NOSTRICT is non-nil, ignore 1 day lapse, this to allows running
at specified TIME even if `package-refresh-interval' hasn’t passed
since last updated."
  (interactive)
  (if (null package-archives)
      (error "Null `package-archives'"))

  (if (and (cond ((null package-archive-contents)
		  (message "`package-archive-contents' does not exist."))

		 ((<= (if nostrict
			  (1- package-refresh-interval)
			package-refresh-interval)
		      (time-to-number-of-days
		       (time-since
			(file-attribute-modification-time
			 (file-attributes pui--archive-contents-file)))))
		  t))
	   (y-or-n-p "Refresh package contents now?"))
      (package-refresh-contents)))

;;;###autoload
(defun package-upgrade-interactively (&optional vc)
  "Upgrade packages interractively.

if VC is non-nil, vc package will also be included.
If called-interactively, VC will depend wheter or not there is `package-vc'."
  (interactive (list pui--is-package-vc))

  (if (and vc (not pui--is-package-vc))
      (error "Trying to run `package-upgrade-interactively' with vc but `package-vc' doesn’t exist"))

  (package-refresh-contents-maybe)

  (let ((upgradable-packages (pui--upgradeable-packages vc)))
    (if (null upgradable-packages)
	(message "All package are up-to-date")
      (if (equal (length upgradable-packages) 1)
	  (if (y-or-n-p (format "Upgrade %s now?" (pui--format-package-desc (caar upgradable-packages) (cadar upgradable-packages))))
	      (apply #'pui--package-upgrade (car upgradable-packages)))

	(with-current-buffer (get-buffer-create "*upgrade-package-interactively*")
	  (let ((inhibit-read-only t))
	    (setq buffer-read-only t)
	    (erase-buffer)
	    (switch-to-buffer-other-window (current-buffer))
	    (set-window-dedicated-p (selected-window) t)

	    (insert "Package to Update:
s Select       C-S-s Select All       [RET] Confirm
u Unselect     C-S-u Unselect All     q     Quit\n\n")

	    (save-excursion
	      (insert
	       (mapconcat
		(lambda (elem)
		  (format "   %s"
			  (pui--format-package-desc (car elem) (cadr elem))))
		upgradable-packages "\n")))

	    (local-set-key
	     (kbd "s")
	     (lambda ()
	       "Select current line."
	       (interactive)
	       (if (> (line-number-at-pos) 4)
		   (pui--select))))

	    (local-set-key
	     (kbd "u")
	     (lambda ()
	       "Unselect current line."
	       (interactive)
	       (if (> (line-number-at-pos) 4)
		   (pui--unselect))))

	    (local-set-key
	     (kbd "C-S-s")
	     (lambda ()
	       "Select all."
	       (interactive)
	       (save-excursion
		 (save-restriction
		   (forward-line (- 5 (line-number-at-pos)))
		   (narrow-to-region (point) (point-max))
		   (while (not (eobp))
		     (pui--select)
		     (forward-line))))))

	    (local-set-key
	     (kbd "C-S-u")
	     (lambda ()
	       "Unselect all."
	       (interactive)
	       (save-excursion
		 (save-restriction
		   (forward-line (- 5 (line-number-at-pos)))
		   (narrow-to-region (point) (point-max))
		   (while (not (eobp))
		     (pui--unselect)
		     (forward-line))))))

	    (local-set-key
	     (kbd "RET")
	     `(lambda ()
		"Upgrade all selected packages"
		(interactive)
		(save-excursion
		  (save-restriction
		    (forward-line (- 5 (line-number-at-pos)))
		    (narrow-to-region (point) (point-max))

		    (let (selected-indexes)
		      (while (not (eobp))
			(if (pui--selected-p)
			    (add-to-list 'selected-indexes (- (line-number-at-pos) 1) t))
			(forward-line))

		      (if (null selected-indexes)
			  (message "Empty selection, press q to quit")

			(unwind-protect
			    (mapcar
			     (lambda (i)
			       (apply #'pui--package-upgrade
				      (nth i ',upgradable-packages)))
			     selected-indexes)
			  (kill-buffer-and-window))))))))

	    (local-set-key (kbd "q") 'kill-buffer-and-window)))))))

;;;###autoload
(defun pui--scheduler (time)
  "Run every TIME.

TIME MUST be in this format:
- 13:00
- 01:00pm"
  (if (equal (diary-entry-time time) diary-unknown-time)
      (error "Unrecognized time %s" time))

  (run-at-time time (* 60 60 24)
	       (lambda ()
		 (package-refresh-contents-maybe 'no-strict)
		 (package-upgrade-interactively pui--is-package-vc))))

(provide 'packages-upgrade-interactive)
;;; packages-upgrade-interactive.el ends here
