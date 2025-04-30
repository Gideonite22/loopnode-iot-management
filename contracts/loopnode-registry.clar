;; loopnode-registry
;; 
;; This contract manages the registration and discovery of IoT nodes in the LoopNode network.
;; It allows node operators to register their devices with specific metadata including location,
;; capabilities, and service offerings, while enabling users to discover available nodes based
;; on various criteria. The contract includes a reputation system to track node reliability and
;; service quality, helping users make informed decisions when selecting nodes.

;; =============================
;; Constants & Error Codes
;; =============================

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NODE-ALREADY-EXISTS (err u101))
(define-constant ERR-NODE-NOT-FOUND (err u102))
(define-constant ERR-RATING-OUT-OF-RANGE (err u103))
(define-constant ERR-CATEGORY-NOT-FOUND (err u104))
(define-constant ERR-CANNOT-RATE-OWN-NODE (err u105))
(define-constant ERR-LOCATION-INVALID (err u106))
(define-constant ERR-CAPABILITY-INVALID (err u107))

;; Other constants
(define-constant MAX-RATING u5)
(define-constant MIN-RATING u1)
(define-constant INITIAL-REPUTATION u3)

;; =============================
;; Data Maps & Variables
;; =============================

;; Store the nodes with their basic information
(define-map nodes 
    { node-id: (string-ascii 36) } ;; Unique identifier for the node
    {
        owner: principal,
        name: (string-ascii 64),
        description: (string-utf8 256),
        location: {
            latitude: int,
            longitude: int,
            region: (string-ascii 64)
        },
        status: (string-ascii 16), ;; "online", "offline", "maintenance"
        registration-time: uint,
        last-updated: uint
    }
)

;; Store the capabilities of each node
(define-map node-capabilities
    { node-id: (string-ascii 36) }
    {
        capabilities: (list 20 (string-ascii 64)),  ;; List of capability tags
        service-types: (list 10 (string-ascii 64)), ;; Types of services provided
        pricing-model: (string-ascii 32)            ;; e.g., "per-request", "time-based", "subscription"
    }
)

;; Track reputation and ratings
(define-map node-reputation
    { node-id: (string-ascii 36) }
    {
        average-rating: uint,
        rating-count: uint,
        total-rating-sum: uint
    }
)

;; Individual ratings from users
(define-map user-ratings
    { node-id: (string-ascii 36), user: principal }
    {
        rating: uint,
        review: (optional (string-utf8 256)),
        timestamp: uint
    }
)

;; Categories for easier node discovery
(define-map node-categories
    { category: (string-ascii 32) }
    { 
        node-ids: (list 100 (string-ascii 36)) 
    }
)

;; Track all registered node IDs for global lookups
(define-data-var all-node-ids (list 1000 (string-ascii 36)) (list))

;; =============================
;; Private Functions
;; =============================

;; Checks if a node exists in the registry
(define-private (node-exists (node-id (string-ascii 36)))
    (is-some (map-get? nodes { node-id: node-id }))
)

;; Add a node to a category
(define-private (add-to-category (node-id (string-ascii 36)) (category (string-ascii 32)))
    (let (
        (current-list (default-to { node-ids: (list) } (map-get? node-categories { category: category })))
        (updated-list (unwrap-panic (as-max-len? (append (get node-ids current-list) node-id) u100)))
    )
    (map-set node-categories 
        { category: category } 
        { node-ids: updated-list }
    ))
)

;; Remove a node from a category
(define-private (remove-from-category (node-id (string-ascii 36)) (category (string-ascii 32)))
    (let (
        (current-list (default-to { node-ids: (list) } (map-get? node-categories { category: category })))
        (updated-list (filter (lambda (id) (not (is-eq id node-id))) (get node-ids current-list)))
    )
    (map-set node-categories 
        { category: category } 
        { node-ids: updated-list }
    ))
)

;; Initialize node reputation
(define-private (init-reputation (node-id (string-ascii 36)))
    (map-set node-reputation
        { node-id: node-id }
        {
            average-rating: INITIAL-REPUTATION,
            rating-count: u0,
            total-rating-sum: u0
        }
    )
)

;; Update the global list of all nodes
(define-private (add-to-all-nodes (node-id (string-ascii 36)))
    (let (
        (current-list (var-get all-node-ids))
        (updated-list (unwrap-panic (as-max-len? (append current-list node-id) u1000)))
    )
    (var-set all-node-ids updated-list))
)

;; Remove from the global list of all nodes
(define-private (remove-from-all-nodes (node-id (string-ascii 36)))
    (let (
        (current-list (var-get all-node-ids))
        (updated-list (filter (lambda (id) (not (is-eq id node-id))) current-list))
    )
    (var-set all-node-ids updated-list))
)

;; =============================
;; Read-Only Functions
;; =============================

;; Get node information
(define-read-only (get-node-info (node-id (string-ascii 36)))
    (map-get? nodes { node-id: node-id })
)

;; Get node capabilities
(define-read-only (get-node-capabilities (node-id (string-ascii 36)))
    (map-get? node-capabilities { node-id: node-id })
)

;; Get node reputation
(define-read-only (get-node-reputation (node-id (string-ascii 36)))
    (map-get? node-reputation { node-id: node-id })
)

;; Get user rating for a specific node
(define-read-only (get-user-rating (node-id (string-ascii 36)) (user principal))
    (map-get? user-ratings { node-id: node-id, user: user })
)

;; Get list of nodes in a category
(define-read-only (get-nodes-by-category (category (string-ascii 32)))
    (let ((category-data (map-get? node-categories { category: category })))
        (if (is-some category-data)
            (ok (get node-ids (unwrap-panic category-data)))
            ERR-CATEGORY-NOT-FOUND))
)

;; Get all registered node IDs
(define-read-only (get-all-node-ids)
    (var-get all-node-ids)
)

;; Check if user is the owner of a node
(define-read-only (is-node-owner (node-id (string-ascii 36)) (user principal))
    (let ((node-info (map-get? nodes { node-id: node-id })))
        (if (is-some node-info)
            (is-eq (get owner (unwrap-panic node-info)) user)
            false))
)

;; =============================
;; Public Functions
;; =============================

;; Register a new IoT node
(define-public (register-node
    (node-id (string-ascii 36))
    (name (string-ascii 64))
    (description (string-utf8 256))
    (latitude int)
    (longitude int)
    (region (string-ascii 64))
    (status (string-ascii 16))
    (capabilities (list 20 (string-ascii 64)))
    (service-types (list 10 (string-ascii 64)))
    (pricing-model (string-ascii 32))
    (categories (list 10 (string-ascii 32)))
)
    (let (
        (caller tx-sender)
        (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
        ;; Check if node already exists
        (asserts! (not (node-exists node-id)) ERR-NODE-ALREADY-EXISTS)
        
        ;; Check for valid location data
        (asserts! (and (< latitude 90) (> latitude -90)) ERR-LOCATION-INVALID)
        (asserts! (and (< longitude 180) (> longitude -180)) ERR-LOCATION-INVALID)
        
        ;; Store basic node information
        (map-set nodes
            { node-id: node-id }
            {
                owner: caller,
                name: name,
                description: description,
                location: {
                    latitude: latitude,
                    longitude: longitude,
                    region: region
                },
                status: status,
                registration-time: current-time,
                last-updated: current-time
            }
        )
        
        ;; Store node capabilities
        (map-set node-capabilities
            { node-id: node-id }
            {
                capabilities: capabilities,
                service-types: service-types,
                pricing-model: pricing-model
            }
        )
        
        ;; Initialize node reputation
        (init-reputation node-id)
        
        ;; Add to global node list
        (add-to-all-nodes node-id)
        
        ;; Add to all specified categories
        (map add-to-category (list node-id) categories)
        
        (ok node-id)
    )
)

;; Update node status
(define-public (update-node-status (node-id (string-ascii 36)) (new-status (string-ascii 16)))
    (let (
        (caller tx-sender)
        (node-info (map-get? nodes { node-id: node-id }))
        (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
        ;; Check if node exists
        (asserts! (is-some node-info) ERR-NODE-NOT-FOUND)
        ;; Check if caller is the owner
        (asserts! (is-eq (get owner (unwrap-panic node-info)) caller) ERR-NOT-AUTHORIZED)
        
        ;; Update with new status
        (map-set nodes
            { node-id: node-id }
            (merge (unwrap-panic node-info) { 
                status: new-status,
                last-updated: current-time
            })
        )
        
        (ok true)
    )
)

;; Update node capabilities
(define-public (update-node-capabilities
    (node-id (string-ascii 36))
    (capabilities (list 20 (string-ascii 64)))
    (service-types (list 10 (string-ascii 64)))
    (pricing-model (string-ascii 32))
)
    (let (
        (caller tx-sender)
        (node-info (map-get? nodes { node-id: node-id }))
    )
        ;; Check if node exists
        (asserts! (is-some node-info) ERR-NODE-NOT-FOUND)
        ;; Check if caller is the owner
        (asserts! (is-eq (get owner (unwrap-panic node-info)) caller) ERR-NOT-AUTHORIZED)
        
        ;; Update capabilities
        (map-set node-capabilities
            { node-id: node-id }
            {
                capabilities: capabilities,
                service-types: service-types,
                pricing-model: pricing-model
            }
        )
        
        (ok true)
    )
)

;; Update node metadata
(define-public (update-node-metadata
    (node-id (string-ascii 36))
    (name (string-ascii 64))
    (description (string-utf8 256))
    (latitude int)
    (longitude int)
    (region (string-ascii 64))
)
    (let (
        (caller tx-sender)
        (node-info (map-get? nodes { node-id: node-id }))
        (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
        ;; Check if node exists
        (asserts! (is-some node-info) ERR-NODE-NOT-FOUND)
        ;; Check if caller is the owner
        (asserts! (is-eq (get owner (unwrap-panic node-info)) caller) ERR-NOT-AUTHORIZED)
        ;; Check for valid location data
        (asserts! (and (< latitude 90) (> latitude -90)) ERR-LOCATION-INVALID)
        (asserts! (and (< longitude 180) (> longitude -180)) ERR-LOCATION-INVALID)
        
        ;; Update metadata
        (map-set nodes
            { node-id: node-id }
            (merge (unwrap-panic node-info) { 
                name: name,
                description: description,
                location: {
                    latitude: latitude,
                    longitude: longitude,
                    region: region
                },
                last-updated: current-time
            })
        )
        
        (ok true)
    )
)

;; Rate a node
(define-public (rate-node
    (node-id (string-ascii 36))
    (rating uint)
    (review (optional (string-utf8 256)))
)
    (let (
        (caller tx-sender)
        (node-info (map-get? nodes { node-id: node-id }))
        (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
        (reputation-data (default-to { 
            average-rating: INITIAL_REPUTATION, 
            rating-count: u0,
            total-rating-sum: u0 
          } (map-get? node-reputation { node-id: node-id })))
    )
        ;; Check if node exists
        (asserts! (is-some node-info) ERR-NODE-NOT-FOUND)
        ;; Check if rating is within valid range
        (asserts! (and (>= rating MIN-RATING) (<= rating MAX-RATING)) ERR-RATING-OUT-OF-RANGE)
        ;; Check that user is not rating their own node
        (asserts! (not (is-eq (get owner (unwrap-panic node-info)) caller)) ERR-CANNOT-RATE-OWN-NODE)
        
        ;; Record the user rating
        (map-set user-ratings
            { node-id: node-id, user: caller }
            {
                rating: rating,
                review: review,
                timestamp: current-time
            }
        )
        
        ;; Get previous rating if it exists
        (let (
            (previous-rating (map-get? user-ratings { node-id: node-id, user: caller }))
            (new-count (+ (get rating-count reputation-data) u1))
            (new-sum (+ (get total-rating-sum reputation-data) rating))
            (new-average (/ new-sum new-count))
        )
            ;; Update the node reputation
            (map-set node-reputation
                { node-id: node-id }
                {
                    average-rating: new-average,
                    rating-count: new-count,
                    total-rating-sum: new-sum
                }
            )
            
            (ok true)
        )
    )
)

;; Deregister a node
(define-public (deregister-node (node-id (string-ascii 36)))
    (let (
        (caller tx-sender)
        (node-info (map-get? nodes { node-id: node-id }))
        (node-caps (map-get? node-capabilities { node-id: node-id }))
    )
        ;; Check if node exists
        (asserts! (is-some node-info) ERR-NODE-NOT-FOUND)
        ;; Check if caller is the owner
        (asserts! (is-eq (get owner (unwrap-panic node-info)) caller) ERR-NOT-AUTHORIZED)
        
        ;; Delete node data
        (map-delete nodes { node-id: node-id })
        (map-delete node-capabilities { node-id: node-id })
        (map-delete node-reputation { node-id: node-id })
        
        ;; Remove from global node list
        (remove-from-all-nodes node-id)
        
        ;; Note: Individual user ratings are kept for historical purposes
        
        (ok true)
    )
)

;; Add node to categories
(define-public (add-node-to-categories (node-id (string-ascii 36)) (categories (list 10 (string-ascii 32))))
    (let (
        (caller tx-sender)
        (node-info (map-get? nodes { node-id: node-id }))
    )
        ;; Check if node exists
        (asserts! (is-some node-info) ERR-NODE-NOT-FOUND)
        ;; Check if caller is the owner
        (asserts! (is-eq (get owner (unwrap-panic node-info)) caller) ERR-NOT-AUTHORIZED)
        
        ;; Add to all specified categories
        (map add-to-category (list node-id) categories)
        
        (ok true)
    )
)

;; Remove node from categories
(define-public (remove-node-from-categories (node-id (string-ascii 36)) (categories (list 10 (string-ascii 32))))
    (let (
        (caller tx-sender)
        (node-info (map-get? nodes { node-id: node-id }))
    )
        ;; Check if node exists
        (asserts! (is-some node-info) ERR-NODE-NOT-FOUND)
        ;; Check if caller is the owner
        (asserts! (is-eq (get owner (unwrap-panic node-info)) caller) ERR-NOT-AUTHORIZED)
        
        ;; Remove from specified categories
        (map remove-from-category (list node-id) categories)
        
        (ok true)
    )
)