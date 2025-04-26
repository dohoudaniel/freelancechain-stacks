;; contracts/arbitrator-dao.clar
;; FreelanceChain: Arbitrator DAO Module
;; Manages arbitrator registration, staking, and governance

;; Arbitrator status constants
(define-constant STATUS-ACTIVE "active")
(define-constant STATUS-INACTIVE "inactive")
(define-constant STATUS-SUSPENDED "suspended")

;; Minimum stake required to become an arbitrator (in STX)
(define-data-var min-stake-amount uint u1000000000) ;; 1000 STX

;; Arbitrator registry
(define-map arbitrators
  { address: principal }
  {
    status: (string-ascii 20),
    stake-amount: uint,
    joined-at: uint,
    reputation-score: uint,
    cases-resolved: uint,
    profile: {
      name: (string-utf8 50),
      bio: (string-utf8 200),
      expertise: (list 5 (string-ascii 30))
    }
  }
)

;; Active arbitrator list for quicker access
(define-map active-arbitrators
  { address: principal }
  { active: bool }
)

;; Define traits
(define-trait access-trait
  ((is-admin (principal) (response bool uint)))
)

;; Define arbitrator trait for other contracts
(define-trait arbitrator-trait
  (
    (is-active-arbitrator (principal) (response bool uint))
  )
)

;; Check if a principal is an active arbitrator
(define-read-only (is-active-arbitrator (address principal))
  (let ((status (map-get? active-arbitrators { address: address })))
    (if (is-some status)
        (ok (get active (unwrap-panic status)))
        (err u404)
    )
  )
)

;; Register as a new arbitrator
(define-public (register-arbitrator (name (string-utf8 50))
                                   (bio (string-utf8 200))
                                   (expertise (list 5 (string-ascii 30))))
  (let ((current-time (unwrap-panic (get-block-info? time u0)))
        (stake-amount (var-get min-stake-amount)))

    ;; Check if arbitrator already exists
    (asserts! (is-none (map-get? arbitrators { address: tx-sender })) (err u409))

    ;; Transfer stake to contract
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))

    ;; Register arbitrator
    (map-set arbitrators
      { address: tx-sender }
      {
        status: STATUS-ACTIVE,
        stake-amount: stake-amount,
        joined-at: current-time,
        reputation-score: u0,
        cases-resolved: u0,
        profile: {
          name: name,
          bio: bio,
          expertise: expertise
        }
      }
    )

    ;; Add to active arbitrators
    (map-set active-arbitrators
      { address: tx-sender }
      { active: true }
    )

    (ok true)
  )
)

;; Update arbitrator profile
(define-public (update-profile (name (string-utf8 50))
                              (bio (string-utf8 200))
                              (expertise (list 5 (string-ascii 30))))
  (let ((arbitrator-data (unwrap! (map-get? arbitrators { address: tx-sender }) (err u404))))
    (map-set arbitrators
      { address: tx-sender }
      (merge arbitrator-data {
        profile: {
          name: name,
          bio: bio,
          expertise: expertise
        }
      })
    )
    (ok true)
  )
)

;; Add additional stake
(define-public (add-stake (amount uint))
  (let ((arbitrator-data (unwrap! (map-get? arbitrators { address: tx-sender }) (err u404))))
    ;; Transfer additional stake
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))

    ;; Update stake amount
    (map-set arbitrators
      { address: tx-sender }
      (merge arbitrator-data {
        stake-amount: (+ (get stake-amount arbitrator-data) amount)
      })
    )
    (ok true)
  )
)

;; Withdraw stake (only if status is inactive)
(define-public (withdraw-stake)
  (let ((arbitrator-data (unwrap! (map-get? arbitrators { address: tx-sender }) (err u404))))
    ;; Verify arbitrator is inactive
    (asserts! (is-eq (get status arbitrator-data) STATUS-INACTIVE) (err u403))

    ;; Get stake amount
    (let ((amount (get stake-amount arbitrator-data)))
      ;; Transfer stake back to arbitrator
      (as-contract
        (stx-transfer? amount tx-sender tx-sender)
      )

      ;; Update stake amount
      (map-set arbitrators
        { address: tx-sender }
        (merge arbitrator-data {
          stake-amount: u0
        })
      )
      (ok amount)
    )
  )
)

;; Change arbitrator status
(define-public (change-status (new-status (string-ascii 20)))
  (let ((arbitrator-data (unwrap! (map-get? arbitrators { address: tx-sender }) (err u404))))
    ;; Verify status is valid
    (asserts! (or (is-eq new-status STATUS-ACTIVE)
                 (is-eq new-status STATUS-INACTIVE))
              (err u400))

    ;; Update arbitrator status
    (map-set arbitrators
      { address: tx-sender }
      (merge arbitrator-data {
        status: new-status
      })
    )

    ;; Update active arbitrators map
    (map-set active-arbitrators
      { address: tx-sender }
      { active: (is-eq new-status STATUS-ACTIVE) }
    )

    (ok true)
  )
)

;; Get arbitrator details
(define-read-only (get-arbitrator (address principal))
  (map-get? arbitrators { address: address })
)

;; Update minimum stake requirement (admin only)
(define-public (update-min-stake (new-amount uint) (access-contract <access-trait>))
  (begin
    (asserts! (is-ok (contract-call? access-contract is-admin tx-sender)) (err u403))
    (ok (var-set min-stake-amount new-amount))
  )
)