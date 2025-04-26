# contracts/escrow-vault.clar
;; FreelanceChain: Escrow Vault Module
;; Manages escrow funds for jobs

(use-trait registry-trait .freelance-registry.registry-trait)
(use-trait token-trait .token-utils.token-trait)

;; Platform fee percentage (in basis points: 250 = 2.5%)
(define-data-var platform-fee-bps uint u250)

;; Escrow holder address
(define-data-var platform-address principal tx-sender)

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
        (let ((updated-milestones (replace-at milestones milestone-index
                                            (merge milestone { released: true }))))

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
  (let ((escrow-data (unwrap! (map-get? escrow-vaults { job-id: job-id }) (err u404))))
    (is-eq (get milestone-count escrow-data) (get released-count escrow-data))
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