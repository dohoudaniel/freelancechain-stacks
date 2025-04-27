;; contracts/dispute-resolution.clar
;; FreelanceChain: Dispute Resolution Module
;; Manages dispute processes between clients and freelancers

;; Define traits
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

(define-trait escrow-trait
  (
    (get-escrow (uint) (response {
      client: principal,
      freelancer: (optional principal),
      total-amount: uint,
      milestone-count: uint,
      released-count: uint,
      milestones: (list 10 {
        amount: uint,
        description: (string-utf8 200),
        released: bool
      })
    } uint))
    (is-escrow-completed (uint) (response bool uint))
  )
)

(define-trait arbitrator-trait
  (
    (is-active-arbitrator (principal) (response bool uint))
  )
)

;; Dispute status constants
(define-constant STATUS-OPEN "open")
(define-constant STATUS-VOTING "voting")
(define-constant STATUS-RESOLVED "resolved")
(define-constant STATUS-CANCELLED "cancelled")

;; Dispute resolution outcomes
(define-constant OUTCOME-PENDING "pending")
(define-constant OUTCOME-CLIENT "client")
(define-constant OUTCOME-FREELANCER "freelancer")
(define-constant OUTCOME-SPLIT "split")

;; Dispute counter
(define-data-var dispute-counter uint u0)

;; Disputes mapping
(define-map disputes
  { dispute-id: uint }
  {
    job-id: uint,
    client: principal,
    freelancer: principal,
    initiator: principal,
    description: (string-utf8 500),
    status: (string-ascii 20),
    outcome: (string-ascii 20),
    created-at: uint,
    resolved-at: (optional uint),
    evidence: (list 10 {
      provider: principal,
      description: (string-utf8 500),
      timestamp: uint
    })
  }
)

;; Dispute votes by arbitrators
(define-map dispute-votes
  { dispute-id: uint, arbitrator: principal }
  { vote: (string-ascii 20), timestamp: uint }
)

;; Vote count tracking
(define-map vote-counts
  { dispute-id: uint }
  {
    client-votes: uint,
    freelancer-votes: uint,
    split-votes: uint,
    total-votes: uint
  }
)

;; Get next dispute ID and increment counter
(define-private (get-next-dispute-id)
  (let ((current-id (var-get dispute-counter)))
    (var-set dispute-counter (+ current-id u1))
    current-id
  )
)

;; Initialize vote count for new dispute
(define-private (init-vote-count (dispute-id uint))
  (map-set vote-counts
    { dispute-id: dispute-id }
    {
      client-votes: u0,
      freelancer-votes: u0,
      split-votes: u0,
      total-votes: u0
    }
  )
)

;; Create a new dispute
(define-public (create-dispute (job-id uint)
                              (description (string-utf8 500))
                              (registry-contract <registry-trait>))
  (let ((job-data (unwrap! (contract-call? registry-contract get-job job-id) (err u404)))
        (dispute-id (get-next-dispute-id))
        (current-time u0))

    ;; Verify caller is client or freelancer
    (asserts! (or (is-eq tx-sender (get client job-data))
              (match (get assigned-freelancer job-data)
                freelancer (is-eq tx-sender freelancer)
                false))
              (err u403))

    ;; Create dispute record
    (map-set disputes
      { dispute-id: dispute-id }
      {
        job-id: job-id,
        client: (get client job-data),
        freelancer: (unwrap-panic (get assigned-freelancer job-data)),
        initiator: tx-sender,
        description: description,
        status: STATUS-OPEN,
        outcome: OUTCOME-PENDING,
        created-at: current-time,
        resolved-at: none,
        evidence: (list)
      }
    )

    ;; Initialize vote count
    (init-vote-count dispute-id)

    ;; Update job status
    (try! (contract-call? registry-contract update-job-status job-id "disputed"))

    (ok dispute-id)
  )
)

;; Add evidence to a dispute
(define-public (add-evidence (dispute-id uint) (description (string-utf8 500)))
  (let ((dispute-data (unwrap! (map-get? disputes { dispute-id: dispute-id }) (err u404)))
        (current-time u0))

    ;; Verify caller is client or freelancer
    (asserts! (or (is-eq tx-sender (get client dispute-data))
                 (is-eq tx-sender (get freelancer dispute-data)))
              (err u403))

    ;; Verify dispute is still open
    (asserts! (is-eq (get status dispute-data) STATUS-OPEN) (err u400))

    ;; Create evidence record
    (let ((new-evidence {
            provider: tx-sender,
            description: description,
            timestamp: current-time
          })
          (evidence-list (get evidence dispute-data)))

      ;; Update dispute with new evidence
      (map-set disputes
        { dispute-id: dispute-id }
        (merge dispute-data {
          evidence: (unwrap-panic (as-max-len? (append evidence-list new-evidence) u10))
        })
      )
      (ok true)
    )
  )
)

;; Cast a vote on a dispute (arbitrators only)
(define-public (vote-on-dispute (dispute-id uint)
                               (vote-for (string-ascii 20))
                               (arbitrator-contract <arbitrator-trait>))
  (let ((dispute-data (unwrap! (map-get? disputes { dispute-id: dispute-id }) (err u404)))
        (current-time u0))

    ;; Verify caller is an arbitrator
    (asserts! (is-ok (contract-call? arbitrator-contract is-active-arbitrator tx-sender)) (err u403))

    ;; Verify dispute is open for voting
    (asserts! (is-eq (get status dispute-data) STATUS-VOTING) (err u400))

    ;; Verify vote is valid
    (asserts! (or (is-eq vote-for OUTCOME-CLIENT)
                 (is-eq vote-for OUTCOME-FREELANCER)
                 (is-eq vote-for OUTCOME-SPLIT))
              (err u400))

    ;; Record the vote
    (map-set dispute-votes
      { dispute-id: dispute-id, arbitrator: tx-sender }
      { vote: vote-for, timestamp: current-time }
    )

    ;; Update vote counts
    (let ((counts (unwrap! (map-get? vote-counts { dispute-id: dispute-id }) (err u404))))
      (map-set vote-counts
        { dispute-id: dispute-id }
        (merge counts {
          client-votes: (if (is-eq vote-for OUTCOME-CLIENT)
                           (+ (get client-votes counts) u1)
                           (get client-votes counts)),
          freelancer-votes: (if (is-eq vote-for OUTCOME-FREELANCER)
                               (+ (get freelancer-votes counts) u1)
                               (get freelancer-votes counts)),
          split-votes: (if (is-eq vote-for OUTCOME-SPLIT)
                          (+ (get split-votes counts) u1)
                          (get split-votes counts)),
          total-votes: (+ (get total-votes counts) u1)
        })
      )
      (ok true)
    )
  )
)

;; contracts/dispute-resolution.clar (continued)
;; Get dispute details
(define-read-only (get-dispute (dispute-id uint))
  (map-get? disputes { dispute-id: dispute-id })
)

;; Get vote counts for a dispute
(define-read-only (get-vote-counts (dispute-id uint))
  (map-get? vote-counts { dispute-id: dispute-id })
)

;; Finalize a dispute with result based on voting
(define-public (finalize-dispute (dispute-id uint)
                                (registry-contract <registry-trait>)
                                (escrow-contract <escrow-trait>))
  (let ((dispute-data (unwrap! (map-get? disputes { dispute-id: dispute-id }) (err u404)))
        (counts (unwrap! (map-get? vote-counts { dispute-id: dispute-id }) (err u404)))
        (current-time u0))

    ;; Verify dispute is in voting status
    (asserts! (is-eq (get status dispute-data) STATUS-VOTING) (err u400))

    ;; Determine outcome based on votes
    (let ((client-votes (get client-votes counts))
          (freelancer-votes (get freelancer-votes counts))
          (outcome (if (> client-votes freelancer-votes)
                      OUTCOME-CLIENT
                      (if (> freelancer-votes client-votes)
                          OUTCOME-FREELANCER
                          OUTCOME-SPLIT))))

      ;; Update dispute status and outcome
      (map-set disputes
        { dispute-id: dispute-id }
        (merge dispute-data {
          status: STATUS-RESOLVED,
          outcome: outcome,
          resolved-at: (some current-time)
        })
      )

      ;; Update job status back to in-progress or completed
      (try! (contract-call? registry-contract update-job-status
                          (get job-id dispute-data)
                          "in-progress"))

      (ok outcome)
    )
  )
)

;; Start voting period for a dispute
(define-public (start-voting-period (dispute-id uint))
  (let ((dispute-data (unwrap! (map-get? disputes { dispute-id: dispute-id }) (err u404))))
    ;; Verify dispute is open
    (asserts! (is-eq (get status dispute-data) STATUS-OPEN) (err u400))

    ;; Update dispute status to voting
    (map-set disputes
      { dispute-id: dispute-id }
      (merge dispute-data {
        status: STATUS-VOTING
      })
    )
    (ok true)
  )
)