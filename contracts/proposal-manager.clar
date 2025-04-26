# contracts/proposal-manager.clar
;; FreelanceChain: Proposal Manager Module
;; Handles freelancer proposals to jobs

(use-trait registry-trait .freelance-registry.registry-trait)

;; Proposal ID counter
(define-data-var proposal-counter uint u0)

;; Proposals mapping
(define-map proposals
  { proposal-id: uint }
  {
    job-id: uint,
    freelancer: principal,
    bid-amount: uint,
    delivery-time: uint,
    description: (string-utf8 500),
    status: (string-ascii 20),
    created-at: uint
  }
)

;; Job to proposals index
(define-map job-proposals
  { job-id: uint }
  { proposal-ids: (list 50 uint) }
)

;; Proposal statuses
(define-constant STATUS-PENDING "pending")
(define-constant STATUS-ACCEPTED "accepted")
(define-constant STATUS-REJECTED "rejected")
(define-constant STATUS-WITHDRAWN "withdrawn")

;; Get the next proposal ID and increment counter
(define-private (get-next-proposal-id)
  (let ((current-id (var-get proposal-counter)))
    (var-set proposal-counter (+ current-id u1))
    current-id
  )
)

;; Add proposal to job-proposals list
(define-private (add-proposal-to-job (job-id uint) (proposal-id uint))
  (let ((job-props (default-to { proposal-ids: (list) }
                              (map-get? job-proposals { job-id: job-id }))))
    (map-set job-proposals
      { job-id: job-id }
      { proposal-ids: (append (get proposal-ids job-props) proposal-id) }
    )
  )
)

;; Create a new proposal for a job
(define-public (create-proposal (job-id uint)
                               (bid-amount uint)
                               (delivery-time uint)
                               (description (string-utf8 500)))
  (let ((proposal-id (get-next-proposal-id))
        (current-time (unwrap-panic (get-block-info? time u0))))
    (map-set proposals
      { proposal-id: proposal-id }
      {
        job-id: job-id,
        freelancer: tx-sender,
        bid-amount: bid-amount,
        delivery-time: delivery-time,
        description: description,
        status: STATUS-PENDING,
        created-at: current-time
      }
    )
    (add-proposal-to-job job-id proposal-id)
    (ok proposal-id)
  )
)

;; Accept a proposal (only by client)
(define-public (accept-proposal (proposal-id uint) (registry-contract <registry-trait>))
  (let ((proposal-data (unwrap! (map-get? proposals { proposal-id: proposal-id }) (err u404)))
        (job-id (get job-id proposal-data))
        (job-data (unwrap! (contract-call? registry-contract get-job job-id) (err u404))))

    ;; Check if sender is the client
    (asserts! (is-eq tx-sender (get client job-data)) (err u403))

    ;; Check if job is still open
    (asserts! (is-eq (get status job-data) "open") (err u400))

    ;; Update proposal status
    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal-data { status: STATUS-ACCEPTED })
    )

    ;; Update job status and assign freelancer
    (contract-call? registry-contract update-job-status job-id "in-progress")
    (ok true)
  )
)

;; Withdraw a proposal (only by the freelancer who created it)
(define-public (withdraw-proposal (proposal-id uint))
  (let ((proposal-data (unwrap! (map-get? proposals { proposal-id: proposal-id }) (err u404))))
    (asserts! (is-eq tx-sender (get freelancer proposal-data)) (err u403))
    (asserts! (is-eq (get status proposal-data) STATUS-PENDING) (err u400))

    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal-data { status: STATUS-WITHDRAWN })
    )
    (ok true)
  )
)

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id })
)

;; Get all proposals for a job
(define-read-only (get-job-proposal-ids (job-id uint))
  (let ((job-props (map-get? job-proposals { job-id: job-id })))
    (if (is-some job-props)
        (get proposal-ids (unwrap-panic job-props))
        (list)
    )
  )
)