;;; test-triode.el --- Casual Suite Tests      -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Charles Y. Choi

;; Author: Charles Choi <kickingvegas@gmail.com>
;; Keywords: tools

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:

(require 'ert)
(require 'triode-test-utils)
(require 'triode)

(ert-deftest test-triode-group ()
  "Test `triode' group."
  (should (and (symbolp 'triode)
               (get 'triode 'custom-group))))

(ert-deftest test-triode-dismiss-menu-for-actions ()
  "Test `triode-dismiss-menu-for-actions' variable."
  (should (and (symbolp 'triode-dismiss-menu-for-actions)
               (custom-variable-p 'triode-dismiss-menu-for-actions))))

(ert-deftest test-triode-poll-status-interval ()
  "Test `triode-poll-status-interval' variable."
  (should (and (symbolp 'triode-poll-status-interval)
               (custom-variable-p 'triode-poll-status-interval))))


(ert-deftest test-triode-tmenu ()
  "Test for `triode-tmenu'."

  (let ()
    (cl-letf ((triodet-mock #'triode-station-gui)
              (triodet-mock #'triode-toggle-play)
              (triodet-mock #'triode-mute)
              (triodet-mock #'triode-refresh-state)
              (triodet-mock #'triode-kill-as-copy-current)
              (triodet-mock #'shazam)
              (triodet-mock #'triode-launch)
              (triodet-mock #'triode-customize-group)
              (triodet-mock #'triode-quit-all))

      (let ((test-vectors
             '((:binding "s" :command triode-station-gui)
               (:binding "SPC" :command triode-toggle-play)
               (:binding "m" :command triode-mute)
               (:binding "r" :command triode-refresh-state)
               (:binding "w" :command triode-kill-as-copy-current)
               (:binding "z" :command shazam)
               (:binding "o" :command triode-launch)
               (:binding "," :command triode-customize-group)
               (:binding "RET" :command transient-quit-all))))

        (triodet-suffix-testcase-runner test-vectors
                                        #'triode-tmenu
                                        '(lambda () (random 5000)))))))

(provide 'test-triode)
;;; test-triode.el ends here
