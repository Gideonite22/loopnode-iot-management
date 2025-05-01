;; loopnode-transactions.clar
;; This contract manages economic transactions between IoT node operators and service consumers
;; in the LoopNode ecosystem. It handles payments for services, subscription management,
;; escrow of funds, and resolution of service disputes.

;; Error Codes
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-PAYMENT-TOO-SMALL (err u1001))
(define-constant ERR-NODE-NOT-REGISTERED (err u1002))
(define-constant ERR-SERVICE-NOT-FOUND (err u1003))
(define-constant ERR-INSUFFICIENT-FUNDS (err u1004))
(define-constant ERR-INVALID-SUBSCRIPTION (err u1005))
(define-constant ERR-INVALID-PAYMENT-MODEL (err u1006))
(define-constant ERR-PAYMENT-ALREADY-PROCESSED (err u1007))
(define-constant ERR-DISPUTE-ALREADY-FILED (err u1008))
(define-constant ERR-DISPUTE-NOT-FOUND (err u1009))
(define-constant ERR-ESCROW-NOT-FOUND (err u1010))
(define-constant ERR-SUBSCRIPTION-NOT-FOUND (err u1011))
(define-constant ERR-SERVICE-NOT-COMPLETED (err u1012))
(define-constant ERR-PAYMENT-NOT-DUE (err u1013))
(define-constant ERR-INVALID-AMOUNT (err u1014))

;; Payment Model Types
(define-constant PAYMENT-MODEL-PAY-PER-USE u1)
(define-constant PAYMENT-MODEL-SUBSCRIPTION u2)
(define-constant PAYMENT-MODEL-CONDITIONAL u3)

;; Dispute Status Types
(define-constant DISPUTE-STATUS-PENDING u1)
(define-constant DISPUTE-STATUS-RESOLVED-CONSUMER u2)
(define-constant DISPUTE-STATUS-RESOLVED-PROVIDER u3)

;; Service Status Types
(define-constant SERVICE-STATUS-PENDING u1)
(define-constant SERVICE-STATUS-ACTIVE u2)
(define-constant SERVICE-STATUS-COMPLETED u3)
(define-constant SERVICE-STATUS-CANCELLED u4)
(define-constant SERVICE-STATUS-DISPUTED u5)

;; Platform fee percentage (in basis points, e.g., 250 = 2.5%)
(define-constant PLATFORM-FEE-BPS u250)

;; DAO contract that gets platform fees
(define-constant PLATFORM-ADDRESS 'SP000000000000000000002Q6VF78)

;; Data Structures

;; Map to track registered IoT nodes and their providers
(define-map nodes 
    { node-id: uint }
    { 
      provider: principal,
      active: bool 
    }
)

;; Map of services offered by nodes
(define-map services
    { service-id: uint }
    {
      node-id: uint,
      payment-model: uint,
      price-per-use: uint,
      subscription-price: uint,
      subscription-period: uint,
      active: bool
    }
)

;; Map of escrow payments for pay-per-use services
(define-map escrow-payments
    { payment-id: uint }
    {
      consumer: principal,
      provider: principal,
      service-id: uint,
      amount: uint,
      created-at: uint,
      status: uint,
      completed-at: uint
    }
)

;; Map of active subscriptions
(define-map subscriptions
    { subscription-id: uint }
    {
      consumer: principal,
      provider: principal,
      service-id: uint,
      price: uint,
      period: uint,
      start-block: uint,
      end-block: uint,
      next-payment-block: uint,
      status: uint
    }
)

;; Map of service disputes
(define-map disputes
    { dispute-id: uint }
    {
      payment-id: uint,
      subscription-id: uint,
      consumer: principal,
      provider: principal,
      amount: uint,
      reason: (string-ascii 256),
      status: uint,
      created-at: uint,
      resolved-at: uint
    }
)

;; Counters for generating IDs
(define-data-var payment-id-counter uint u0)
(define-data-var subscription-id-counter uint u0)
(define-data-var dispute-id-counter uint u0)

;; Define a data variable to hold the ID we want to filter
(define-data-var target-node-id uint u0)

;; Private Functions

;; Calculate platform fee
(define-private (calculate-platform-fee (amount uint))
  (/ (* amount PLATFORM-FEE-BPS) u10000)
)

;; Process payment by sending to provider and platform
(define-private (process-payment (amount uint) (provider principal))
  (let
    (
      (platform-fee (calculate-platform-fee amount))
      (provider-amount (- amount platform-fee))
    )
    (begin
      ;; Send fee to platform
      (try! (stx-transfer? platform-fee tx-sender PLATFORM-ADDRESS))
      ;; Send payment to provider
      (try! (stx-transfer? provider-amount tx-sender provider))
      (ok true)
    )
  )
)

;; Check if node exists and is active
(define-private (is-node-active (node-id uint))
  (match (map-get? nodes { node-id: node-id })
    node-info (ok (get active node-info))
    (err ERR-NODE-NOT-REGISTERED)
  )
)

;; Check if service exists and is active
(define-private (is-service-active (service-id uint))
  (match (map-get? services { service-id: service-id })
    service-info (ok (and (get active service-info) 
                          (unwrap-panic (is-node-active (get node-id service-info)))))
    (err ERR-SERVICE-NOT-FOUND)
  )
)

;; Check if caller is the provider of a node
(define-private (is-node-provider (node-id uint) (caller principal))
  (match (map-get? nodes { node-id: node-id })
    node-info (ok (is-eq (get provider node-info) caller))
    (err ERR-NODE-NOT-REGISTERED)
  )
)

;; Check if the current block height is greater than or equal to the target
(define-private (is-block-reached (target-block uint))
  (>= block-height target-block)
)

;; Increment payment ID counter
(define-private (get-next-payment-id)
  (let
    ((current (var-get payment-id-counter)))
    (begin
      (var-set payment-id-counter (+ current u1))
      current
    )
  )
)

;; Increment subscription ID counter
(define-private (get-next-subscription-id)
  (let
    ((current (var-get subscription-id-counter)))
    (begin
      (var-set subscription-id-counter (+ current u1))
      current
    )
  )
)

;; Increment dispute ID counter
(define-private (get-next-dispute-id)
  (let
    ((current (var-get dispute-id-counter)))
    (begin
      (var-set dispute-id-counter (+ current u1))
      current
    )
  )
)

;; Read-only Functions

;; Get details of an escrow payment
(define-read-only (get-payment-details (payment-id uint))
  (match (map-get? escrow-payments { payment-id: payment-id })
    payment-info (ok payment-info)
    (err ERR-ESCROW-NOT-FOUND)
  )
)

;; Get details of a subscription
(define-read-only (get-subscription-details (subscription-id uint))
  (match (map-get? subscriptions { subscription-id: subscription-id })
    subscription-info (ok subscription-info)
    (err ERR-SUBSCRIPTION-NOT-FOUND)
  )
)

;; Get details of a dispute
(define-read-only (get-dispute-details (dispute-id uint))
  (match (map-get? disputes { dispute-id: dispute-id })
    dispute-info (ok dispute-info)
    (err ERR-DISPUTE-NOT-FOUND)
  )
)

;; Get service details
(define-read-only (get-service-details (service-id uint))
  (match (map-get? services { service-id: service-id })
    service-info (ok service-info)
    (err ERR-SERVICE-NOT-FOUND)
  )
)

;; Check if a subscription is active
(define-read-only (is-subscription-active (subscription-id uint))
  (match (map-get? subscriptions { subscription-id: subscription-id })
    subscription-info (ok (and (is-eq (get status subscription-info) SERVICE-STATUS-ACTIVE)
                              (< block-height (get end-block subscription-info))))
    (err ERR-SUBSCRIPTION-NOT-FOUND)
  )
)

;; Public Functions

;; Create a one-time payment in escrow for a pay-per-use service
(define-public (pay-for-service (service-id uint) (amount uint))
  (let
    ((payment-id (get-next-payment-id)))
    (match (map-get? services { service-id: service-id })
      service-info
        (begin
          ;; Check service is active
          (asserts! (is-some (is-service-active service-id)) (err ERR-SERVICE-NOT-FOUND))
          (asserts! (unwrap-panic (is-service-active service-id)) (err ERR-SERVICE-NOT-FOUND))
          
          ;; Check payment model is pay-per-use
          (asserts! (is-eq (get payment-model service-info) PAYMENT-MODEL-PAY-PER-USE) (err ERR-INVALID-PAYMENT-MODEL))
          
          ;; Check payment is sufficient
          (asserts! (>= amount (get price-per-use service-info)) ERR-PAYMENT-TOO-SMALL)
          
          ;; Get node provider
          (match (map-get? nodes { node-id: (get node-id service-info) })
            node-info
              (begin
                ;; Transfer STX to escrow (contract holds it)
                (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
                
                ;; Record escrow payment
                (map-set escrow-payments
                  { payment-id: payment-id }
                  {
                    consumer: tx-sender,
                    provider: (get provider node-info),
                    service-id: service-id,
                    amount: amount,
                    created-at: block-height,
                    status: SERVICE-STATUS-PENDING,
                    completed-at: u0
                  }
                )
                
                (ok payment-id)
              )
            (err ERR-NODE-NOT-REGISTERED)
          )
        )
      (err ERR-SERVICE-NOT-FOUND)
    )
  )
)

;; Create a subscription for a subscription-based service
(define-public (subscribe-to-service (service-id uint) (duration uint))
  (let
    (
      (subscription-id (get-next-subscription-id))
    )
    (match (map-get? services { service-id: service-id })
      service-info
        (begin
          ;; Check service is active
          (try! (is-service-active service-id))
          
          ;; Check payment model is subscription
          (asserts! (is-eq (get payment-model service-info) PAYMENT-MODEL-SUBSCRIPTION) ERR-INVALID-PAYMENT-MODEL)
          
          ;; Calculate total subscription cost
          (let
            (
              (period (get subscription-period service-info))
              (price-per-period (get subscription-price service-info))
              (total-price (* price-per-period duration))
              (end-block (+ block-height (* period duration)))
            )
            
            ;; Get node provider
            (match (map-get? nodes { node-id: (get node-id service-info) })
              node-info
                (begin
                  ;; Process the payment immediately
                  (try! (process-payment total-price (get provider node-info)))
                  
                  ;; Record subscription
                  (map-set subscriptions
                    { subscription-id: subscription-id }
                    {
                      consumer: tx-sender,
                      provider: (get provider node-info),
                      service-id: service-id,
                      price: price-per-period,
                      period: period,
                      start-block: block-height,
                      end-block: end-block,
                      next-payment-block: end-block, ;; For renewal if implemented
                      status: SERVICE-STATUS-ACTIVE
                    }
                  )
                  
                  (ok subscription-id)
                )
              (err ERR-NODE-NOT-REGISTERED)
            )
          )
        )
      (err ERR-SERVICE-NOT-FOUND)
    )
  )
)

;; Complete a service and release payment from escrow
(define-public (complete-service (payment-id uint))
  (match (map-get? escrow-payments { payment-id: payment-id })
    payment-info
      (begin
        ;; Check that caller is the provider
        (asserts! (is-eq tx-sender (get provider payment-info)) ERR-NOT-AUTHORIZED)
        
        ;; Check that payment is pending
        (asserts! (is-eq (get status payment-info) SERVICE-STATUS-PENDING) ERR-PAYMENT-ALREADY-PROCESSED)
        
        ;; Update payment status
        (map-set escrow-payments
          { payment-id: payment-id }
          (merge payment-info {
            status: SERVICE-STATUS-COMPLETED,
            completed-at: block-height
          })
        )
        
        ;; Release payment from escrow
        (as-contract 
          (begin
            (let
              (
                (amount (get amount payment-info))
                (platform-fee (calculate-platform-fee amount))
                (provider-amount (- amount platform-fee))
              )
              (begin
                ;; Send fee to platform
                (try! (stx-transfer? platform-fee tx-sender PLATFORM-ADDRESS))
                ;; Send payment to provider
                (try! (stx-transfer? provider-amount tx-sender (get provider payment-info)))
                (ok true)
              )
            )
          )
        )
      )
    (err ERR-ESCROW-NOT-FOUND)
  )
)

;; Confirm receipt of service as a consumer
(define-public (confirm-service-received (payment-id uint))
  (match (map-get? escrow-payments { payment-id: payment-id })
    payment-info
      (begin
        ;; Check that caller is the consumer
        (asserts! (is-eq tx-sender (get consumer payment-info)) ERR-NOT-AUTHORIZED)
        
        ;; Check that payment is pending
        (asserts! (is-eq (get status payment-info) SERVICE-STATUS-PENDING) ERR-PAYMENT-ALREADY-PROCESSED)
        
        ;; Update payment status
        (map-set escrow-payments
          { payment-id: payment-id }
          (merge payment-info {
            status: SERVICE-STATUS-COMPLETED,
            completed-at: block-height
          })
        )
        
        ;; Release payment from escrow
        (as-contract 
          (begin
            (let
              (
                (amount (get amount payment-info))
                (platform-fee (calculate-platform-fee amount))
                (provider-amount (- amount platform-fee))
              )
              (begin
                ;; Send fee to platform
                (try! (stx-transfer? platform-fee tx-sender PLATFORM-ADDRESS))
                ;; Send payment to provider
                (try! (stx-transfer? provider-amount tx-sender (get provider payment-info)))
                (ok true)
              )
            )
          )
        )
      )
    (err ERR-ESCROW-NOT-FOUND)
  )
)

;; Cancel a subscription
(define-public (cancel-subscription (subscription-id uint))
  (match (map-get? subscriptions { subscription-id: subscription-id })
    subscription-info
      (begin
        ;; Check that caller is the consumer
        (asserts! (is-eq tx-sender (get consumer subscription-info)) ERR-NOT-AUTHORIZED)
        
        ;; Check that subscription is active
        (asserts! (is-eq (get status subscription-info) SERVICE-STATUS-ACTIVE) ERR-INVALID-SUBSCRIPTION)
        
        ;; Update subscription status
        (map-set subscriptions
          { subscription-id: subscription-id }
          (merge subscription-info {
            status: SERVICE-STATUS-CANCELLED,
            end-block: block-height
          })
        )
        
        (ok true)
      )
    (err ERR-SUBSCRIPTION-NOT-FOUND)
  )
)

;; File a dispute for a service
(define-public (file-dispute (payment-id uint) (reason (string-ascii 256)))
  (match (map-get? escrow-payments { payment-id: payment-id })
    payment-info
      (begin
        ;; Check that caller is the consumer
        (asserts! (is-eq tx-sender (get consumer payment-info)) ERR-NOT-AUTHORIZED)
        
        ;; Check that payment is pending
        (asserts! (is-eq (get status payment-info) SERVICE-STATUS-PENDING) ERR-PAYMENT-ALREADY-PROCESSED)
        
        ;; Update payment status
        (map-set escrow-payments
          { payment-id: payment-id }
          (merge payment-info {
            status: SERVICE-STATUS-DISPUTED
          })
        )
        
        ;; Create dispute record
        (let
          (
            (dispute-id (get-next-dispute-id))
          )
          (map-set disputes
            { dispute-id: dispute-id }
            {
              payment-id: payment-id,
              subscription-id: u0, ;; Not applicable for pay-per-use
              consumer: (get consumer payment-info),
              provider: (get provider payment-info),
              amount: (get amount payment-info),
              reason: reason,
              status: DISPUTE-STATUS-PENDING,
              created-at: block-height,
              resolved-at: u0
            }
          )
          
          (ok dispute-id)
        )
      )
    (err ERR-ESCROW-NOT-FOUND)
  )
)

;; File a dispute for a subscription service
(define-public (file-subscription-dispute (subscription-id uint) (reason (string-ascii 256)))
  (match (map-get? subscriptions { subscription-id: subscription-id })
    subscription-info
      (begin
        ;; Check that caller is the consumer
        (asserts! (is-eq tx-sender (get consumer subscription-info)) ERR-NOT-AUTHORIZED)
        
        ;; Check that subscription is active
        (asserts! (is-eq (get status subscription-info) SERVICE-STATUS-ACTIVE) ERR-INVALID-SUBSCRIPTION)
        
        ;; Update subscription status
        (map-set subscriptions
          { subscription-id: subscription-id }
          (merge subscription-info {
            status: SERVICE-STATUS-DISPUTED
          })
        )
        
        ;; Create dispute record
        (let
          (
            (dispute-id (get-next-dispute-id))
          )
          (map-set disputes
            { dispute-id: dispute-id }
            {
              payment-id: u0, ;; Not applicable for subscription
              subscription-id: subscription-id,
              consumer: (get consumer subscription-info),
              provider: (get provider subscription-info),
              amount: (get price subscription-info),
              reason: reason,
              status: DISPUTE-STATUS-PENDING,
              created-at: block-height,
              resolved-at: u0
            }
          )
          
          (ok dispute-id)
        )
      )
    (err ERR-SUBSCRIPTION-NOT-FOUND)
  )
)

;; Resolve dispute in favor of consumer (refund payment)
;; This would typically be called by a governance mechanism or arbitrator
(define-public (resolve-dispute-for-consumer (dispute-id uint))
  (match (map-get? disputes { dispute-id: dispute-id })
    dispute-info
      (begin
        ;; In a real implementation, check caller is authorized arbitrator
        ;; For this contract, we'll just check it's not the involved parties
        (asserts! (and (not (is-eq tx-sender (get consumer dispute-info))) 
                       (not (is-eq tx-sender (get provider dispute-info)))) 
                  ERR-NOT-AUTHORIZED)
        
        ;; Check that dispute is pending
        (asserts! (is-eq (get status dispute-info) DISPUTE-STATUS-PENDING) ERR-DISPUTE-ALREADY-FILED)
        
        ;; Handle escrow payment dispute
        (if (> (get payment-id dispute-info) u0)
          (match (map-get? escrow-payments { payment-id: (get payment-id dispute-info) })
            payment-info
              (begin
                ;; Update payment status
                (map-set escrow-payments
                  { payment-id: (get payment-id dispute-info) }
                  (merge payment-info {
                    status: SERVICE-STATUS-CANCELLED
                  })
                )
                
                ;; Refund from escrow to consumer
                (as-contract 
                  (stx-transfer? (get amount dispute-info) tx-sender (get consumer dispute-info))
                )
              )
            (err ERR-ESCROW-NOT-FOUND)
          )
          ;; Handle subscription dispute - no refund mechanism in this simple implementation
          (ok true)
        )
        
        ;; Update dispute status
        (map-set disputes
          { dispute-id: dispute-id }
          (merge dispute-info {
            status: DISPUTE-STATUS-RESOLVED-CONSUMER,
            resolved-at: block-height
          })
        )
        
        (ok true)
      )
    (err ERR-DISPUTE-NOT-FOUND)
  )
)

;; Resolve dispute in favor of provider (release payment)
;; This would typically be called by a governance mechanism or arbitrator
(define-public (resolve-dispute-for-provider (dispute-id uint))
  (match (map-get? disputes { dispute-id: dispute-id })
    dispute-info
      (begin
        ;; In a real implementation, check caller is authorized arbitrator
        ;; For this contract, we'll just check it's not the involved parties
        (asserts! (and (not (is-eq tx-sender (get consumer dispute-info))) 
                       (not (is-eq tx-sender (get provider dispute-info)))) 
                  ERR-NOT-AUTHORIZED)
        
        ;; Check that dispute is pending
        (asserts! (is-eq (get status dispute-info) DISPUTE-STATUS-PENDING) ERR-DISPUTE-ALREADY-FILED)
        
        ;; Handle escrow payment dispute
        (if (> (get payment-id dispute-info) u0)
          (match (map-get? escrow-payments { payment-id: (get payment-id dispute-info) })
            payment-info
              (begin
                ;; Update payment status
                (map-set escrow-payments
                  { payment-id: (get payment-id dispute-info) }
                  (merge payment-info {
                    status: SERVICE-STATUS-COMPLETED,
                    completed-at: block-height
                  })
                )
                
                ;; Release payment from escrow to provider
                (as-contract 
                  (begin
                    (let
                      (
                        (amount (get amount dispute-info))
                        (platform-fee (calculate-platform-fee amount))
                        (provider-amount (- amount platform-fee))
                      )
                      (begin
                        ;; Send fee to platform
                        (try! (stx-transfer? platform-fee tx-sender PLATFORM-ADDRESS))
                        ;; Send payment to provider
                        (try! (stx-transfer? provider-amount tx-sender (get provider dispute-info)))
                        (ok true)
                      )
                    )
                  )
                )
              )
            (err ERR-ESCROW-NOT-FOUND)
          )
          ;; Handle subscription dispute - reactivate subscription
          (match (map-get? subscriptions { subscription-id: (get subscription-id dispute-info) })
            subscription-info
              (begin
                ;; Update subscription status
                (map-set subscriptions
                  { subscription-id: (get subscription-id dispute-info) }
                  (merge subscription-info {
                    status: SERVICE-STATUS-ACTIVE
                  })
                )
                (ok true)
              )
            (err ERR-SUBSCRIPTION-NOT-FOUND)
          )
        )
        
        ;; Update dispute status
        (map-set disputes
          { dispute-id: dispute-id }
          (merge dispute-info {
            status: DISPUTE-STATUS-RESOLVED-PROVIDER,
            resolved-at: block-height
          })
        )
        
        (ok true)
      )
    (err ERR-DISPUTE-NOT-FOUND)
  )
)

;; Renew a subscription
(define-public (renew-subscription (subscription-id uint) (duration uint))
  (match (map-get? subscriptions { subscription-id: subscription-id })
    subscription-info
      (begin
        ;; Check that caller is the consumer
        (asserts! (is-eq tx-sender (get consumer subscription-info)) ERR-NOT-AUTHORIZED)
        
        ;; Check that subscription exists and is active or expired but not cancelled/disputed
        (asserts! (or (is-eq (get status subscription-info) SERVICE-STATUS-ACTIVE)
                      (and (is-eq (get status subscription-info) SERVICE-STATUS-COMPLETED)
                           (<= (get end-block subscription-info) block-height)))
                  ERR-INVALID-SUBSCRIPTION)
        
        ;; Calculate new subscription details
        (let
          (
            (period (get period subscription-info))
            (price-per-period (get price subscription-info))
            (total-price (* price-per-period duration))
            (start-block (if (> block-height (get end-block subscription-info))
                            block-height
                            (get end-block subscription-info)))
            (new-end-block (+ start-block (* period duration)))
          )
          
          ;; Process the payment
          (try! (process-payment total-price (get provider subscription-info)))
          
          ;; Update subscription
          (map-set subscriptions
            { subscription-id: subscription-id }
            (merge subscription-info {
              start-block: start-block,
              end-block: new-end-block,
              next-payment-block: new-end-block,
              status: SERVICE-STATUS-ACTIVE
            })
          )
          
          (ok true)
        )
      )
    (err ERR-SUBSCRIPTION-NOT-FOUND)
  )
)

;; Helper function for filtering with fold - uses the global target-node-id
(define-private (filter-node-id 
    (id uint) 
    (result-list (list 100 uint)))
    
    (if (is-eq id (var-get target-node-id))
        result-list  ;; Skip this ID
        (unwrap-panic (as-max-len? (append result-list id) u100))  ;; Keep this ID
    )
)

(define-public (remove-node-from-category (node-id uint) (category (string-ascii 20)))
  (begin
    ;; Set the target ID for filtering
    (var-set target-node-id node-id)
    
    (let 
      ((current-list (default-to { node-ids: (list) } (map-get? node-categories { category: category })))
       (filtered-list (fold filter-node-id (list) (get node-ids current-list))))
      
      (map-set node-categories 
        { category: category } 
        { node-ids: filtered-list }
      )
      (ok true)
    )
  )
)