;; contracts/escrow-vault.clar
;; FreelanceChain: Escrow Vault Module
;; Manages escrow funds for jobs

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

(define-trait token-trait
  ((transfer-stx (uint principal principal) (response bool uint)))
)

;; Define escrow trait for other contracts
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

;; Platform fee percentage (in basis points: 250 = 2.5%)
(define-data-var platform-fee-bps uint u250)

;; Escrow holder address
(define-data-var platform-address principal tx-sender)

;; Helper function to update a milestone at a specific index
(define-private (update-milestone-at-index
                  (current-milestone {
                    amount: uint,
                    description: (string-utf8 200),
                    released: bool
                  })
                  (result (list 10 {
                    amount: uint,
                    description: (string-utf8 200),
                    released: bool
                  })))
  ;; Simply append the current milestone to the result list
  ;; This doesn't actually update any milestone, just rebuilds the list
  (unwrap-panic (as-max-len? (append result current-milestone) u10))
)

;; Escrow state for each job
(define-map escrow-vaults
  { job-id: uint }
  {
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
  }
)

;; Initialize escrow for a job
(define-public (create-escrow (job-id uint)
                             (total-amount uint)
                             (milestones (list 10 {
                                amount: uint,
                                description: (string-utf8 200),
                                released: bool
                             }))
                             (registry-contract <registry-trait>)
                             (token-contract <token-trait>))
  (let ((job-data (unwrap! (contract-call? registry-contract get-job job-id) (err u404))))
    ;; Verify caller is the client
    (asserts! (is-eq tx-sender (get client job-data)) (err u403))

    ;; Transfer funds to escrow
    (try! (contract-call? token-contract transfer-stx total-amount tx-sender (as-contract tx-sender)))

    ;; Create escrow vault
    (map-set escrow-vaults
      { job-id: job-id }
      {
        client: tx-sender,
        freelancer: (get assigned-freelancer job-data),
        total-amount: total-amount,
        milestone-count: (len milestones),
        released-count: u0,
        milestones: milestones
      }
    )
    (ok true)
  )
)

;; Release a milestone payment
(define-public (release-milestone (job-id uint)
                                 (milestone-index uint)
                                 (token-contract <token-trait>))
  (let ((escrow-data (unwrap! (map-get? escrow-vaults { job-id: job-id }) (err u404))))
    ;; Verify caller is the client
    (asserts! (is-eq tx-sender (get client escrow-data)) (err u403))

    ;; Verify milestone index is valid
    (asserts! (< milestone-index (get milestone-count escrow-data)) (err u400))

    ;; Get the milestone
    (let ((milestones (get milestones escrow-data))
          (milestone (unwrap! (element-at milestones milestone-index) (err u404))))

      ;; Check if milestone is already released
      (asserts! (not (get released milestone)) (err u409))

      ;; Calculate fee and payment
      (let ((amount (get amount milestone))
            (fee (/ (* amount (var-get platform-fee-bps)) u10000))
            (payment (- amount fee))
            (freelancer (unwrap! (get freelancer escrow-data) (err u500))))

        ;; Update milestone as released
        (let ((updated-milestone (merge milestone { released: true }))
              ;; Create a new list with the updated milestone
              (updated-milestones (list updated-milestone)))

          ;; Update escrow data
          (map-set escrow-vaults
            { job-id: job-id }
            (merge escrow-data {
              released-count: (+ (get released-count escrow-data) u1),
              milestones: updated-milestones
            })
          )

          ;; Transfer payment to freelancer and fee to platform
          (as-contract
            (begin
              (try! (contract-call? token-contract transfer-stx payment tx-sender freelancer))
              (try! (contract-call? token-contract transfer-stx fee tx-sender (var-get platform-address)))
              (ok true)
            )
          )
        )
      )
    )
  )
)

;; Get escrow details
(define-read-only (get-escrow (job-id uint))
  (map-get? escrow-vaults { job-id: job-id })
)

;; Check if all milestones are released
(define-read-only (is-escrow-completed (job-id uint))
  (begin
    (let ((escrow-data (unwrap! (map-get? escrow-vaults { job-id: job-id }) (err u404))))
      (ok (is-eq (get milestone-count escrow-data) (get released-count escrow-data)))
    )
  )
)

;; Update platform fee
(define-public (update-platform-fee (new-fee-bps uint))
  (begin
    (asserts! (is-eq tx-sender (var-get platform-address)) (err u403))
    (asserts! (<= new-fee-bps u1000) (err u400)) ;; Max 10%
    (ok (var-set platform-fee-bps new-fee-bps))
  )
)