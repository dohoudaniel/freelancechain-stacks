# contracts/freelance-registry.clar
;; FreelanceChain: Freelance Registry Module
;; Manages job postings and metadata for the platform

(use-trait access-trait .access-control.access-trait)
(use-trait token-trait .token-utils.token-trait)

;; Job status enumeration
(define-constant STATUS-OPEN "open")
(define-constant STATUS-IN-PROGRESS "in-progress")
(define-constant STATUS-COMPLETED "completed")
(define-constant STATUS-CANCELLED "cancelled")
(define-constant STATUS-DISPUTED "disputed")

;; Job counter for unique IDs
(define-data-var job-counter uint u0)

;; Job registry - main mapping of jobs
(define-map jobs
  { job-id: uint }
  {
    client: principal,
    title: (string-utf8 100),
    description: (string-utf8 500),
    budget: uint,
    status: (string-ascii 20),
    created-at: uint,
    deadline: uint,
    assigned-freelancer: (optional principal)
  }
)

;; Additional job metadata
(define-map job-metadata
  { job-id: uint }
  {
    category: (string-ascii 50),
    skills-required: (list 10 (string-ascii 20)),
    location-required: (optional (string-ascii 50)),
    estimated-hours: uint
  }
)

;; Get the next job ID and increment counter
(define-private (get-next-job-id)
  (let ((current-id (var-get job-counter)))
    (var-set job-counter (+ current-id u1))
    current-id
  )
)

;; Create a new job posting
(define-public (create-job (title (string-utf8 100))
                          (description (string-utf8 500))
                          (budget uint)
                          (deadline uint)
                          (category (string-ascii 50))
                          (skills-required (list 10 (string-ascii 20)))
                          (location-required (optional (string-ascii 50)))
                          (estimated-hours uint))
  (let ((job-id (get-next-job-id))
        (current-time (unwrap-panic (get-block-info? time u0))))
    (map-set jobs
      { job-id: job-id }
      {
        client: tx-sender,
        title: title,
        description: description,
        budget: budget,
        status: STATUS-OPEN,
        created-at: current-time,
        deadline: deadline,
        assigned-freelancer: none
      }
    )
    (map-set job-metadata
      { job-id: job-id }
      {
        category: category,
        skills-required: skills-required,
        location-required: location-required,
        estimated-hours: estimated-hours
      }
    )
    (ok job-id)
  )
)

;; Get job details
(define-read-only (get-job (job-id uint))
  (map-get? jobs { job-id: job-id })
)

;; Get job metadata
(define-read-only (get-job-metadata (job-id uint))
  (map-get? job-metadata { job-id: job-id })
)

;; Update job status
(define-public (update-job-status (job-id uint) (new-status (string-ascii 20)))
  (let ((job-data (unwrap! (map-get? jobs { job-id: job-id }) (err u404))))
    (asserts! (or (is-eq tx-sender (get client job-data))
              (is-some-and (get assigned-freelancer job-data)
                          (compose is-eq tx-sender)))
              (err u403))
    (map-set jobs
      { job-id: job-id }
      (merge job-data { status: new-status })
    )
    (ok true)
  )
)

;; Cancel a job (only by client and only if status is open)
(define-public (cancel-job (job-id uint))
  (let ((job-data (unwrap! (map-get? jobs { job-id: job-id }) (err u404))))
    (asserts! (is-eq tx-sender (get client job-data)) (err u403))
    (asserts! (is-eq (get status job-data) STATUS-OPEN) (err u400))
    (map-set jobs
      { job-id: job-id }
      (merge job-data { status: STATUS-CANCELLED })
    )
    (ok true)
  )
)