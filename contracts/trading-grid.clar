;; Decentralized Energy Trading Marketplace
;; Core contract for peer-to-peer energy trading between solar panel owners and consumers

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u1000))
(define-constant ERR_INVALID_AMOUNT (err u1001))
(define-constant ERR_INSUFFICIENT_BALANCE (err u1002))
(define-constant ERR_ORDER_NOT_FOUND (err u1003))
(define-constant ERR_INVALID_PRICE (err u1004))
(define-constant ERR_ORDER_EXPIRED (err u1005))
(define-constant ERR_SELF_TRADE (err u1006))
(define-constant ERR_INVALID_LOCATION (err u1007))

;; Data variables
(define-data-var next-order-id uint u1)
(define-data-var platform-fee-rate uint u25) ;; 0.25% in basis points
(define-data-var max-distance uint u10) ;; Maximum distance in km for trading

;; Data maps
(define-map energy-producers principal
  {
    total-capacity: uint, ;; Total solar panel capacity in watts
    available-energy: uint, ;; Available energy in watt-hours
    location-lat: int, ;; Latitude * 1000000 for precision
    location-lng: int, ;; Longitude * 1000000 for precision
    reputation-score: uint, ;; 0-1000 reputation score
    is-verified: bool
  }
)

(define-map energy-consumers principal
  {
    energy-demand: uint, ;; Current energy demand in watt-hours
    location-lat: int,
    location-lng: int,
    reputation-score: uint,
    payment-balance: uint
  }
)

(define-map sell-orders uint
  {
    seller: principal,
    energy-amount: uint, ;; Energy amount in watt-hours
    price-per-kwh: uint, ;; Price per kWh in microSTX
    min-purchase: uint, ;; Minimum purchase amount
    expires-at: uint, ;; Block height when order expires
    is-active: bool,
    location-lat: int,
    location-lng: int
  }
)

(define-map buy-orders uint
  {
    buyer: principal,
    energy-amount: uint,
    max-price-per-kwh: uint,
    expires-at: uint,
    is-active: bool,
    location-lat: int,
    location-lng: int
  }
)

(define-map completed-trades uint
  {
    seller: principal,
    buyer: principal,
    energy-amount: uint,
    price-per-kwh: uint,
    total-cost: uint,
    trade-time: uint,
    delivery-status: (string-ascii 20)
  }
)

(define-map user-balances principal uint)

;; Read-only functions
(define-read-only (get-producer-info (producer principal))
  (map-get? energy-producers producer)
)

(define-read-only (get-consumer-info (consumer principal))
  (map-get? energy-consumers consumer)
)

(define-read-only (get-sell-order (order-id uint))
  (map-get? sell-orders order-id)
)

(define-read-only (get-buy-order (order-id uint))
  (map-get? buy-orders order-id)
)

(define-read-only (get-user-balance (user principal))
  (default-to u0 (map-get? user-balances user))
)

(define-read-only (get-platform-fee-rate)
  (var-get platform-fee-rate)
)

(define-read-only (calculate-distance (lat1 int) (lng1 int) (lat2 int) (lng2 int))
  ;; Simplified distance calculation using Manhattan distance
  ;; In production, would use proper haversine formula
  (let ((lat-diff (if (> lat1 lat2) (- lat1 lat2) (- lat2 lat1)))
        (lng-diff (if (> lng1 lng2) (- lng1 lng2) (- lng2 lng1))))
    ;; Convert to uint since we know the result is always positive
    (to-uint (+ lat-diff lng-diff))
  )
)

(define-read-only (is-within-trading-distance (lat1 int) (lng1 int) (lat2 int) (lng2 int))
  (<= (calculate-distance lat1 lng1 lat2 lng2) (* (var-get max-distance) u1000000))
)

;; Public functions

;; Register as energy producer
(define-public (register-producer (capacity uint) (lat int) (lng int))
  (begin
    (asserts! (> capacity u0) ERR_INVALID_AMOUNT)
    (asserts! (and (>= lat -90000000) (<= lat 90000000)) ERR_INVALID_LOCATION)
    (asserts! (and (>= lng -180000000) (<= lng 180000000)) ERR_INVALID_LOCATION)
    (map-set energy-producers tx-sender
      {
        total-capacity: capacity,
        available-energy: u0,
        location-lat: lat,
        location-lng: lng,
        reputation-score: u500, ;; Start with neutral reputation
        is-verified: false
      }
    )
    (ok true)
  )
)

;; Register as energy consumer
(define-public (register-consumer (demand uint) (lat int) (lng int))
  (begin
    (asserts! (> demand u0) ERR_INVALID_AMOUNT)
    (asserts! (and (>= lat -90000000) (<= lat 90000000)) ERR_INVALID_LOCATION)
    (asserts! (and (>= lng -180000000) (<= lng 180000000)) ERR_INVALID_LOCATION)
    (map-set energy-consumers tx-sender
      {
        energy-demand: demand,
        location-lat: lat,
        location-lng: lng,
        reputation-score: u500,
        payment-balance: u0
      }
    )
    (ok true)
  )
)

;; Update available energy for producers
(define-public (update-available-energy (amount uint))
  (let ((producer-info (unwrap! (map-get? energy-producers tx-sender) ERR_UNAUTHORIZED)))
    (asserts! (<= amount (get total-capacity producer-info)) ERR_INVALID_AMOUNT)
    (map-set energy-producers tx-sender
      (merge producer-info { available-energy: amount })
    )
    (ok true)
  )
)

;; Create sell order
(define-public (create-sell-order (energy-amount uint) (price-per-kwh uint) (min-purchase uint) (duration-blocks uint))
  (let ((order-id (var-get next-order-id))
        (producer-info (unwrap! (map-get? energy-producers tx-sender) ERR_UNAUTHORIZED)))
    (asserts! (> energy-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> price-per-kwh u0) ERR_INVALID_PRICE)
    (asserts! (<= energy-amount (get available-energy producer-info)) ERR_INSUFFICIENT_BALANCE)
    (asserts! (<= min-purchase energy-amount) ERR_INVALID_AMOUNT)

    (map-set sell-orders order-id
      {
        seller: tx-sender,
        energy-amount: energy-amount,
        price-per-kwh: price-per-kwh,
        min-purchase: min-purchase,
        expires-at: (+ stacks-block-height duration-blocks),
        is-active: true,
        location-lat: (get location-lat producer-info),
        location-lng: (get location-lng producer-info)
      }
    )

    ;; Update available energy
    (map-set energy-producers tx-sender
      (merge producer-info
        { available-energy: (- (get available-energy producer-info) energy-amount) }
      )
    )

    (var-set next-order-id (+ order-id u1))
    (ok order-id)
  )
)

;; Create buy order
(define-public (create-buy-order (energy-amount uint) (max-price-per-kwh uint) (duration-blocks uint))
  (let ((order-id (var-get next-order-id))
        (consumer-info (unwrap! (map-get? energy-consumers tx-sender) ERR_UNAUTHORIZED)))
    (asserts! (> energy-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> max-price-per-kwh u0) ERR_INVALID_PRICE)

    (map-set buy-orders order-id
      {
        buyer: tx-sender,
        energy-amount: energy-amount,
        max-price-per-kwh: max-price-per-kwh,
        expires-at: (+ stacks-block-height duration-blocks),
        is-active: true,
        location-lat: (get location-lat consumer-info),
        location-lng: (get location-lng consumer-info)
      }
    )

    (var-set next-order-id (+ order-id u1))
    (ok order-id)
  )
)

;; Execute trade
(define-public (execute-trade (sell-order-id uint) (buy-order-id uint) (trade-amount uint))
  (let ((sell-order (unwrap! (map-get? sell-orders sell-order-id) ERR_ORDER_NOT_FOUND))
        (buy-order (unwrap! (map-get? buy-orders buy-order-id) ERR_ORDER_NOT_FOUND)))

    ;; Validate trade conditions
    (asserts! (get is-active sell-order) ERR_ORDER_NOT_FOUND)
    (asserts! (get is-active buy-order) ERR_ORDER_NOT_FOUND)
    (asserts! (< stacks-block-height (get expires-at sell-order)) ERR_ORDER_EXPIRED)
    (asserts! (< stacks-block-height (get expires-at buy-order)) ERR_ORDER_EXPIRED)
    (asserts! (not (is-eq (get seller sell-order) (get buyer buy-order))) ERR_SELF_TRADE)
    (asserts! (>= (get max-price-per-kwh buy-order) (get price-per-kwh sell-order)) ERR_INVALID_PRICE)
    (asserts! (>= trade-amount (get min-purchase sell-order)) ERR_INVALID_AMOUNT)
    (asserts! (<= trade-amount (get energy-amount sell-order)) ERR_INVALID_AMOUNT)
    (asserts! (<= trade-amount (get energy-amount buy-order)) ERR_INVALID_AMOUNT)

    ;; Check location proximity
    (asserts! (is-within-trading-distance
                (get location-lat sell-order) (get location-lng sell-order)
                (get location-lat buy-order) (get location-lng buy-order))
              ERR_INVALID_LOCATION)

    (let ((total-cost (* trade-amount (get price-per-kwh sell-order)))
          (platform-fee (/ (* total-cost (var-get platform-fee-rate)) u10000))
          (seller-amount (- total-cost platform-fee)))

      ;; Transfer payment
      (try! (stx-transfer? total-cost (get buyer buy-order) (get seller sell-order)))

      ;; Update order amounts
      (if (is-eq trade-amount (get energy-amount sell-order))
        (map-set sell-orders sell-order-id (merge sell-order { is-active: false }))
        (map-set sell-orders sell-order-id
                 (merge sell-order { energy-amount: (- (get energy-amount sell-order) trade-amount) }))
      )

      (if (is-eq trade-amount (get energy-amount buy-order))
        (map-set buy-orders buy-order-id (merge buy-order { is-active: false }))
        (map-set buy-orders buy-order-id
                 (merge buy-order { energy-amount: (- (get energy-amount buy-order) trade-amount) }))
      )

      ;; Record completed trade
      (map-set completed-trades (var-get next-order-id)
        {
          seller: (get seller sell-order),
          buyer: (get buyer buy-order),
          energy-amount: trade-amount,
          price-per-kwh: (get price-per-kwh sell-order),
          total-cost: total-cost,
          trade-time: stacks-block-height,
          delivery-status: "pending"
        }
      )

      (var-set next-order-id (+ (var-get next-order-id) u1))
      (ok true)
    )
  )
)

;; Cancel order
(define-public (cancel-sell-order (order-id uint))
  (let ((order (unwrap! (map-get? sell-orders order-id) ERR_ORDER_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get seller order)) ERR_UNAUTHORIZED)
    (asserts! (get is-active order) ERR_ORDER_NOT_FOUND)

    ;; Return energy to available pool
    (let ((producer-info (unwrap! (map-get? energy-producers tx-sender) ERR_UNAUTHORIZED)))
      (map-set energy-producers tx-sender
        (merge producer-info
          { available-energy: (+ (get available-energy producer-info) (get energy-amount order)) }
        )
      )
    )

    (map-set sell-orders order-id (merge order { is-active: false }))
    (ok true)
  )
)

(define-public (cancel-buy-order (order-id uint))
  (let ((order (unwrap! (map-get? buy-orders order-id) ERR_ORDER_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get buyer order)) ERR_UNAUTHORIZED)
    (asserts! (get is-active order) ERR_ORDER_NOT_FOUND)

    (map-set buy-orders order-id (merge order { is-active: false }))
    (ok true)
  )
)

;; Admin functions
(define-public (set-platform-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-rate u1000) ERR_INVALID_AMOUNT) ;; Max 10%
    (var-set platform-fee-rate new-rate)
    (ok true)
  )
)

(define-public (verify-producer (producer principal))
  (let ((producer-info (unwrap! (map-get? energy-producers producer) ERR_UNAUTHORIZED)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set energy-producers producer
      (merge producer-info { is-verified: true })
    )
    (ok true)
  )
)
