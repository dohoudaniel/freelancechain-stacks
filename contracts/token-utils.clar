# contracts/token-utils.clar
;; FreelanceChain: Token Utilities Module
;; Handles token transfers and STX operations

;; Define error codes
(define-constant ERR-INSUFFICIENT-FUNDS u1001)
(define-constant ERR-TRANSFER-FAILED u1002)

;; Transfer STX safely with error handling
(define-public (transfer-stx (amount uint) (recipient principal))
  (let
    (
      (balance (stx-get-balance tx-sender))
    )
    (asserts! (>= balance amount) (err ERR-INSUFFICIENT-FUNDS))
    (if (is-ok (stx-transfer? amount tx-sender recipient))
        (ok true)
        (err ERR-TRANSFER-FAILED)
    )
  )
)

;; Safe math functions to prevent overflows
(define-read-only (safe-add (a uint) (b uint))
  (let ((sum (+ a b)))
    (asserts! (>= sum a) (err u3001))
    sum
  )
)

(define-read-only (safe-sub (a uint) (b uint))
  (asserts! (>= a b) (err u3002))
  (- a b)
)

;; Calculate fee based on a percentage
(define-read-only (calculate-fee (amount uint) (fee-percentage uint))
  (/ (* amount fee-percentage) u10000)
)

;; Calculate remaining amount after fee deduction
(define-read-only (amount-after-fee (amount uint) (fee-percentage uint))
  (safe-sub amount (calculate-fee amount fee-percentage))
)

;; Check if a user has sufficient STX balance
(define-read-only (has-sufficient-balance (user principal) (amount uint))
  (>= (stx-get-balance user) amount)
)