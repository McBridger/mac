# McBridge Encryption Protocol (Draft v1.0)

## Goal
Achieve secure, private, and seamless clipboard synchronization between owner devices without relying on unstable system-level Bluetooth pairing dialogs.

## 1. Key Derivation (The "Handshake")
Instead of a fixed password, we use a **User Passphrase**.

*   **Input:** User-defined string (e.g., "Correct-Horse-Battery-Staple").
*   **Salt:** A hardcoded, high-entropy binary salt stored in the app's secret configuration.
*   **KDF:** PBKDF2 (Password-Based Key Derivation Function 2) using HMAC-SHA256.
*   **Iterations:** 100,000+ (to prevent brute-force attacks).
*   **Output:** A 256-bit **Master Key**.
*   **Storage:** The Master Key is stored securely in the system **Keychain**.

## 2. Discovery & Masking (The "Invisible Cloak")
To prevent tracking and identification by third parties:

*   **No Device Names:** The `CBAdvertisementDataLocalNameKey` is removed.
*   **Static Service UUID:** Use the fixed `SERVICE_UUID` for background scanning.
*   **Discovery Hash:**
    *   `Hash = HMAC-SHA256(MasterKey, "McBridge_Discovery_Salt")`
    *   First 4-6 bytes of this hash are placed in `CBAdvertisementDataManufacturerDataKey`.
*   **Verification:** A device only attempts to connect if the Discovery Hash in the air matches its own derived hash.

## 3. Application-Level Security
We drop `.readEncryptionRequired` and `.writeEncryptionRequired` flags to avoid system pairing hell.

*   **Cipher:** AES-GCM (Advanced Encryption Standard in Galois/Counter Mode).
*   **Process:**
    1.  JSON Payload (BridgerMessage) -> Binary.
    2.  Encrypt with **Master Key**.
    3.  AES-GCM produces: `Ciphertext` + `Nonce` (Initialization Vector) + `Tag` (Authentication MAC).
*   **Integrity:** If the `Tag` doesn't match upon decryption (wrong key or corrupted data), the message is silently discarded.

## 4. UX Workflow
1.  **First Launch:** User is prompted to enter a "Sync Phrase" on both devices.
2.  **Background:** App derives the Master Key and stores it.
3.  **Ongoing:** Devices find each other via the Discovery Hash and exchange encrypted clipboard data. No popups, no pairing codes.

---

## Revision 1.1 (Security Hardening)

### 1. Key Derivation Improvements
*   **Iterations:** Increase to **600,000** (OWASP compliance).
*   **Domain Separation:** 
    *   `DiscoveryKey = HMAC-SHA256(MasterKey, "McBridge_Discovery_Domain")`
    *   `SessionKey = HMAC-SHA256(MasterKey, "McBridge_Encryption_Domain")`
    *   *Purpose:* Prevents cross-protocol key leakage.

### 2. Anti-Tracking (Dynamic Discovery)
*   **Rotating Hash:** 
    *   `TimeStep = floor(CurrentTimestamp / 3600)`
    *   `DiscoveryHash = HMAC-SHA256(DiscoveryKey, String(TimeStep))`
    *   *Purpose:* Makes the device untrackable for longer than 1 hour. Receiver checks `T` and `T-1`.

### 3. Enhanced Payload & Replay Protection
*   **Payload Schema:**
    ```json
    {
      "v": 1,
      "content": "...",
      "ts": 1702982400,
      "nonce": "random_hex_string"
    }
    ```
*   **Validation Rules:**
    1.  Discard if `abs(now - ts) > 60s`.
    2.  Check `nonce` against a small LRU cache of recently processed messages.

### 4. Transport Strategy
*   **BLE for Small Payloads:** Use BLE for short control messages and small clipboard snippets that fit within a single MTU (e.g., < 512 bytes).
*   **External Transports for Large Payloads:** For large data (images, long text), BLE serves only as a "notification" or "trigger". The actual transfer will be handled by a broker or a direct TCP/Socket connection.
*   **No BLE Fragmentation:** Manual chunking over BLE characteristics is explicitly excluded to keep the implementation simple and avoid reliability issues.

---
*Status: Planned / Pending Implementation (Updated 2025-12-19)*