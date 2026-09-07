;;; triode.el --- Triode Interface                   -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Charles Y. Choi

;; Author: Charles Y. Choi <kickingvegas@gmail.com>
;; URL: https://github.com/kickingvegas/triode
;; Keywords: tools
;; Package-Version: 0.0.2-rc.1
;; Package-Requires: ((emacs "30.1"))

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

;; Emacs interface to Triode app (https://triode.app/) via Shortcuts.

;;

;;; Code:
(require 'map)
(require 'transient)
(require 'restlib)
(require 'shazam)


;;; Variables

(defgroup triode nil
  "Group for Triode settings."
  :group 'convenience)

(defcustom triode-dismiss-menu-for-actions
  nil
  "If non-nil then dismiss `triode-tmenu' for action commands."
  :type 'boolean
  :group 'triode)

(defvar triode-is-muting nil
  "If non-nil, then muting is on.

This value is local only as there is no muting state to be synchronized
with the Triode app.")

(defvar triode-play-state :stopped
  "Playback state.

This variable is populated with pseudo-Enum values:
:playing
:stopped
:refresh")

(defvar triode-current-station ""
  "Current station.")

(defvar triode--last-description nil
  "Last description.")

(defvar triode--current-state-timestamp nil
  "Current state timestamp.")

(defvar triode--current-state nil
  "Current state.")

(defvar triode-station-db (make-hash-table :test #'equal)
  "Station database.")

(defvar triode--shortcut-cancelled-exit nil
  "State variable to track if Shortcut was cancelled.")

(defvar triode--process-filter-hash (make-hash-table :test 'eq :weakness 'key)
  "Process filter hash table.")

(defvar triode--process-sentinel-hash (make-hash-table :test 'eq :weakness 'key)
  "Process sentinel hash table.")

(defvar triode--status-poll-timer nil
  "Timer for polling Triode status.")

;;; Utilities

(defun triode--dismiss-menu-for-actions ()
  "Transient state function based on `triode-dismiss-menu-for-actions'."
  (if triode-dismiss-menu-for-actions
      (transient--do-return)
    (transient--do-stay)))

(defun triode--tmenu-displayed-p ()
  "Predicate if Triode Transient menu is being displayed."
  (let* ((tmenu (transient-active-prefix))
         (tinst (if tmenu
                    (oref tmenu command))))

    (and tmenu (eq tinst #'triode-tmenu))))

(defun triode--refresh-tmenu ()
  "Refresh Transient menu if displayed."

  (if (triode--tmenu-displayed-p)
      (transient--refresh-transient)))

(defun triode--process-sentinel (process signal)
  "Process sentinel for PROCESS and SIGNAL."
  (when (string-match-p "finished\\|exited" signal)
    (let* ((exit-code (process-exit-status process))
           (fn (map-elt triode--process-sentinel-hash process)))
      (cond
       ((= exit-code 0)
        (if fn
          (funcall fn process signal))
        (triode--refresh-tmenu))

       (t
        (if triode--shortcut-cancelled-exit
            (setq triode--shortcut-cancelled-exit nil)
          (error "Error: exit code: %s" exit-code))))

      (if fn
          (map-delete triode--process-sentinel-hash process)))))

(defun triode--process-filter (process output)
  "Process filter PROCESS and OUTPUT."
  (if (and output (stringp output))
      (let* ((fn (map-elt triode--process-filter-hash process)))

        (cond
         ((string-match-p "^Error: Running was cancelled" output)
          (setq triode--shortcut-cancelled-exit t))

         (t
          (when fn
            (funcall fn process output)
            (map-delete triode--process-filter-hash process)))))))

(defun triode--make-process-request (clause &optional filter sentinel)
  "Make CLAUSE request with FILTER and SENTINEL."
  (let* ((proc-name (format "triode-%s" clause))
         (proc (make-process
                :name proc-name
                :buffer nil
                :command '("shortcuts" "run" "Triode RC JSON")
                :connection-type 'pipe
                :filter #'triode--process-filter
                :sentinel #'triode--process-sentinel)))

    (if filter
        (map-put! triode--process-filter-hash proc filter))

    (if sentinel
        (map-put! triode--process-sentinel-hash proc sentinel))

    (process-send-string proc clause)
    (process-send-eof proc)))

(defun triode-sync-current-state (&optional delay)
  "Get Triode current state with DELAY."

  (let ((delay (if (not delay) 0.3 delay)))
    (sit-for delay)
    (message "⇌")

    (triode--make-process-request
     "now-playing"
     (lambda (_process output)
       (let* ((response (json-parse-string output
                                           :null-object nil))
              (playback-state (map-elt response "playbackState"))
              (station-id (map-elt response "stationID")))

         (mapc (lambda (key)
                 (restlib-json-empty-string-to-nil response key))
               '("track" "artist" "album"))

         (if (string-equal playback-state "Playing")
             (setq triode-play-state :playing)
           (setq triode-play-state :stopped))

         (setq triode-current-station (map-elt triode-station-db station-id "?"))
         (setq triode--current-state response)
         (setq triode--current-state-timestamp (current-time))))

     (lambda (_process _signal)
       (message nil)))))

(defun triode--tmenu-description (current-state)
  "Render description given CURRENT-STATE."
  (let* ((track (map-elt current-state "track"))
         (artist (map-elt current-state "artist"))
         (album (map-elt current-state "album"))
         (station-id (map-elt current-state "stationID"))
         (station (map-elt triode-station-db station-id triode-current-station))

         (msg (cond
               ((and station track artist album)
                (format "[%s] %s • %s • %s"
                        station
                        track
                        artist
                        album))

               ((and station track artist)
                (format "[%s] %s • %s"
                        station
                        track
                        artist))

               ((and station track)
                (format "[%s] %s"
                        station
                        track))

               (station
                (format "[%s]" station))

               (t
                (format "[%s]" triode-current-station)))))
    (setq triode--last-description msg)
    msg))


(defun triode--render-description ()
  "Render TMENU description."

  (if triode--current-state-timestamp
    (let* ((start-time triode--current-state-timestamp)
           (elapsed (float-time (time-subtract (current-time) start-time))))
      (when (> elapsed 45.0)
        (message "⦚")
        (triode-sync-current-state)))
    (triode-sync-current-state))

  (if triode--current-state
      (triode--tmenu-description triode--current-state)
    "Triode"))




;;; Commands

(defun triode-play ()
  "Play Triode."
  (interactive)
  (triode--make-process-request
   "start"
   nil
   (lambda (_process _signal)
     (triode-sync-current-state))))

(defun triode-stop ()
  "Stop Triode."
  (interactive)
  (triode--make-process-request
   "stop"
   nil
   (lambda (_process _signal)
     (triode-sync-current-state))))

(defun triode-toggle-play ()
  "Toggle Play."
  (interactive)

  (cond
   ((eq triode-play-state :playing)
    (setq triode-play-state :stopped)
    (triode-stop))

   ((eq triode-play-state :stopped)
    (setq triode-play-state :playing)
    (triode-play))

   ((eq triode-play-state :requested)
    (message "requested"))

   (t
    (message "Intermediate"))))


(defun triode-mute ()
  "Mute Triode."
  (interactive)
  (setq triode-is-muting t)
  (triode--make-process-request "mute-on"))

(defun triode-unmute ()
  "Unmute Triode."
  (interactive)
  (setq triode-is-muting nil)
    (triode--make-process-request "mute-off"))

(defun triode-station-gui ()
  "Choose station using Triode GUI."
  (interactive)
  (triode--make-process-request
   "station"
   (lambda (_process output)
     (let* ((response (json-parse-string output
                                         :null-object nil))
            (name (map-elt response "name"))
            (station-id (map-elt response "stationID")))

       (unless (map-contains-key triode-station-db station-id)
         (map-put! triode-station-db station-id name))

       (setq triode-current-station name)

       (map-put! triode--current-state "stationID" station-id)
       (map-put! triode--current-state "track" name)
       (map-put! triode--current-state "artist" nil)
       (map-put! triode--current-state "album" nil)
       ;; TODO: Maybe update current state timestamp?

       (triode--refresh-tmenu)))
   (lambda (_process _signal)
     (triode-sync-current-state 2.5))))

(defun triode-launch ()
  "Launch Triode app."
  (interactive)
  (process-lines "open" "-a" "Triode"))

(defun triode-refresh-state ()
  "Refresh menu."
  (interactive)
  (triode-sync-current-state))

(defun triode-customize-group ()
  "Customize ‘triode’ group."
  (interactive)
  (customize-group "triode"))

(defun triode-init (&optional b)
  "Initialize Triode, binding B to `triode-tmenu'.

If B is not defined, then the binding <f14> we be used by default."
  (interactive)
  (let ((b (if (not b) "<f14>" b)))
    (if (not (eq system-type 'darwin))
        (error "Only supported on macOS")
      (if (and (display-graphic-p) (fboundp 'set-fontset-font))
          (set-fontset-font t '(?􀀀 . ?􏿽) "SF Pro Display"))
      (keymap-global-set b #'triode-tmenu))))




;;; Polling

(defun triode-status-polling-p ()
  "Predicate if polling Triode status."
  (if triode--status-poll-timer
      t
    nil))

(defun triode-start-polling-status ()
  "Start polling."
  (interactive)
  (if (triode-status-polling-p)
      (message "Already polling Triode status.")
    (setq triode--status-poll-timer
          (run-at-time nil
                       180
                       #'triode-sync-current-state))))

(defun triode-cancel-polling ()
  "Cancel polling Triode status."
  (interactive)
  (if (not (triode-status-polling-p))
      (message "Not polling Triode status.")
    (cancel-timer triode--status-poll-timer)
    (setq triode--status-poll-timer nil)
    (message "Cancelled polling Triode status")))

;;; Transients

(transient-define-prefix triode-tmenu ()
  "Transient menu for Triode app."
  :refresh-suffixes t
  ["Triode"
   :class transient-row
   :description triode--render-description
   ("s" "􀪔…" triode-station-gui
    :transient triode--dismiss-menu-for-actions)
   ("SPC" "􀊄" triode-toggle-play
    :description (lambda ()
                   (cond
                    ((eql triode-play-state :playing) "􀛷")
                    ((eql triode-play-state :stopped) "􀊄")
                    ((eql triode-play-state :requested) "?")
                    (t "*")))
    :transient triode--dismiss-menu-for-actions)
   ("m" "􀊢" triode-mute
    :transient triode--dismiss-menu-for-actions
    :if-not (lambda () triode-is-muting))
   ("m" "􀊣" triode-unmute
    :transient triode--dismiss-menu-for-actions
    :if (lambda () triode-is-muting))
   ("r" "􀅈" triode-refresh-state :transient t)
   ("w" "􀉁" (lambda ()
              "Copy current station and track to `kill-ring'"
              (interactive)
              (if triode--last-description
                  (kill-new triode--last-description))))
   ("z" "􁈴" shazam)
   ("o" "􀑪" triode-launch)
   ("," "􀣋" triode-customize-group)
   ("RET" "􀀲" transient-quit-all)])

(provide 'triode)
;;; triode.el ends here
