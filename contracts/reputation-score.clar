;; contracts/reputation-score.clar
;; FreelanceChain: Reputation Score Module
;; Handles ratings and reputation aggregation

;; Define registry trait
(define-trait registry-trait
  (
    (get-job (uint) (response {
      client: principal,
      title: (string-utf8 100),
      description: (string-utf8 500),
      budget: uint,
      status: (string-ascii 20),
      created-at: uint,
      deadline: uint,
      assigned-freelancer: (optional principal)
    } uint))
    (update-job-status (uint (string-ascii 20)) (response bool uint))
  )
)

;; Rating parameters
(define-constant MIN-RATING u1)
(define-constant MAX-RATING u5)

;; User reputation data
(define-map user-reputation
  { user: principal }
  {
    total-ratings: uint,
    cumulative-score: uint,
    average-score: uint,  ;; Multiplied by 100 for precision (e.g., 450 = 4.5)
    ratings-received: (list 100 {
      job-id: uint,
      rating: uint,
      comment: (string-utf8 200),
      rater: principal,
      timestamp: uint
    })
  }
)

;; Job ratings
(define-map job-ratings
  { job-id: uint, rater-type: (string-ascii 20) }
  {
    rating: uint,
    comment: (string-utf8 200),
    timestamp: uint
  }
)

;; Initialize reputation for new user
(define-private (init-reputation (user principal))
  (default-to
    {
      total-ratings: u0,
      cumulative-score: u0,
      average-score: u0,
      ratings-received: (list)
    }
    (map-get? user-reputation { user: user })
  )
)

;; Calculate new average score
(define-private (calculate-average (total uint) (count uint))
  (if (is-eq count u0)
      u0
      (/ (* total u100) count)
  )
)

;; Add a new rating for a user
(define-public (rate-user (user principal)
                         (job-id uint)
                         (rating uint)
                         (comment (string-utf8 200))
                         (registry-contract <registry-trait>))
  (let ((job-data (unwrap! (contract-call? registry-contract get-job job-id) (err u404))))
    ;; Verify rating is in valid range
    (asserts! (and (>= rating MIN-RATING) (<= rating MAX-RATING)) (err u400))

    ;; Verify caller is related to the job (client or freelancer)
    (asserts! (or (is-eq tx-sender (get client job-data))
              (match (get assigned-freelancer job-data)
                freelancer (is-eq tx-sender freelancer)
                false))
              (err u403))

    ;; Verify user being rated is related to the job and not self-rating
    (asserts! (and (not (is-eq tx-sender user))
                  (or (is-eq user (get client job-data))
                     (match (get assigned-freelancer job-data)
                        freelancer (is-eq user freelancer)
                        false)))
              (err u403))

    ;; Get current reputation or initialize
    (let ((reputation (init-reputation user))
          (current-time (unwrap-panic (get-block-info? time u0)))
          (rater-type (if (is-eq tx-sender (get client job-data))
                         "client"
                         "freelancer")))

      ;; Store job-specific rating
      (map-set job-ratings
        { job-id: job-id, rater-type: rater-type }
        {
          rating: rating,
          comment: comment,
          timestamp: current-time
        }
      )

      ;; Create new rating record
      (let ((new-rating {
              job-id: job-id,
              rating: rating,
              comment: comment,
              rater: tx-sender,
              timestamp: current-time
            })
            (new-total (+ (get total-ratings reputation) u1))
            (new-cumulative (+ (get cumulative-score reputation) rating))
            (new-average (calculate-average new-cumulative new-total))
            (ratings-list (get ratings-received reputation)))

        ;; Update user reputation with new data
        (map-set user-reputation
          { user: user }
          {
            total-ratings: new-total,
            cumulative-score: new-cumulative,
            average-score: new-average,
            ratings-received: (append ratings-list new-rating)
          }
        )
        (ok true)
      )
    )
  )
)

;; Get user's reputation
(define-read-only (get-user-reputation (user principal))
  (map-get? user-reputation { user: user })
)

;; Get rating for a specific job
(define-read-only (get-job-rating (job-id uint) (rater-type (string-ascii 20)))
  (map-get? job-ratings { job-id: job-id, rater-type: rater-type })
)