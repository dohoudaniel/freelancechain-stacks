# contracts/access-control.clar
;; FreelanceChain: Access Control Module
;; Manages permissions and roles for the platform

(define-data-var contract-owner principal tx-sender)

;; Principal variable for admin permissions
(define-map administrators principal bool)

;; Define roles: client, freelancer, arbitrator
(define-map user-roles
  { user: principal, role: (string-ascii 20) }
  { active: bool }
)

;; Check if the caller is the contract owner
(define-read-only (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

;; Check if the caller has admin privileges
(define-read-only (is-admin (user principal))
  (default-to false (map-get? administrators user))
)

;; Check if a user has a specific role
(define-read-only (has-role (user principal) (role (string-ascii 20)))
  (let ((role-data (map-get? user-roles { user: user, role: role })))
    (if (is-some role-data)
        (get active (unwrap-panic role-data))
        false
    )
  )
)

;; Add an administrator
(define-public (add-admin (new-admin principal))
  (begin
    (asserts! (is-contract-owner) (err u403))
    (ok (map-set administrators new-admin true))
  )
)

;; Remove an administrator
(define-public (remove-admin (admin principal))
  (begin
    (asserts! (is-contract-owner) (err u403))
    (ok (map-delete administrators admin))
  )
)

;; Assign a role to a user
(define-public (assign-role (user principal) (role (string-ascii 20)))
  (begin
    (asserts! (or (is-contract-owner) (is-admin tx-sender)) (err u403))
    (ok (map-set user-roles { user: user, role: role } { active: true }))
  )
)

;; Revoke a role from a user
(define-public (revoke-role (user principal) (role (string-ascii 20)))
  (begin
    (asserts! (or (is-contract-owner) (is-admin tx-sender)) (err u403))
    (ok (map-set user-roles { user: user, role: role } { active: false }))
  )
)

;; Transfer ownership of the contract
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-contract-owner) (err u403))
    (ok (var-set contract-owner new-owner))
  )
)