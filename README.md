# Decentralized Energy Trading Marketplace

A Clarity smart contract enabling **peer-to-peer energy trading** between solar panel owners (producers) and energy consumers. This protocol facilitates local, transparent, and secure trading of renewable energy on the Stacks blockchain.

---

## 📦 Features

* 🔌 **Register Producers & Consumers**
  Track capacity, location, and reputation for all market participants.

* 📈 **Sell/Buy Orders**
  Producers list energy for sale; consumers place buy requests based on proximity and price.

* 🔁 **Secure Trade Execution**
  Matching buy/sell orders with fair pricing, distance checks, and platform fees.

* 🧠 **Smart Trade Logic**
  Location-based matching (using simplified distance calc) and configurable expiration times.

* ⚠️ **Cancellations & Admin Controls**
  Order cancellations, fee updates, and producer verifications.

---

## 🔐 Contract Overview

### 📍 Core Concepts

| Role           | Description                                                 |
| -------------- | ----------------------------------------------------------- |
| **Producer**   | A solar panel owner who supplies energy                     |
| **Consumer**   | A user needing energy in a nearby location                  |
| **Sell Order** | Offer to sell a certain amount of energy at a defined price |
| **Buy Order**  | Request to buy energy up to a maximum price                 |
| **Trade**      | A matched transaction between a sell and buy order          |

---

## 🔧 Main Functions

### 🧑‍🌾 Producers

* `register-producer(capacity, lat, lng)`
* `update-available-energy(amount)`
* `create-sell-order(energy, price, min, duration)`
* `cancel-sell-order(order-id)`

### ⚡ Consumers

* `register-consumer(demand, lat, lng)`
* `create-buy-order(energy, max-price, duration)`
* `cancel-buy-order(order-id)`

### 🔄 Trade Execution

* `execute-trade(sell-order-id, buy-order-id, trade-amount)`

### 🛠️ Admin Controls

* `set-platform-fee-rate(new-rate)` – Up to 10%
* `verify-producer(producer)` – Mark as trusted

---

## 📊 Data Structures

* `energy-producers`, `energy-consumers` – Participant info with location & reputation
* `sell-orders`, `buy-orders` – Active order book
* `completed-trades` – Archived successful trades
* `user-balances`, `platform-fee-rate` – Accounting

---

## 📍 Location Logic

* Latitude/Longitude stored as `int` scaled ×1,000,000
* Distance check uses Manhattan approximation
* Max allowed trading radius = 10 km (configurable)

---

## 💡 Example Use Case

1. A verified solar producer lists 5 kWh at ₦50/kWh.
2. A consumer within 8 km submits a buy order for 3 kWh at ₦55/kWh.
3. The protocol matches, verifies distance, executes STX transfer, and records trade.

---

## 🧪 To-Do / Extensions

* Reputation incentives and penalties
* Oracle integration for location verification
* Haversine-based precise distance calc
* Delivery tracking & energy metering

## License

MIT © 2025
