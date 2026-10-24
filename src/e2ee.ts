const encoder = new TextEncoder();
const decoder = new TextDecoder();
const KEY_STORAGE_PREFIX = "kmct-e2ee-private-v1:";

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  bytes.forEach((b) => { binary += String.fromCharCode(b); });
  return btoa(binary);
}
function fromBase64(value: string): Uint8Array {
  return Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
}

export async function ensureE2EEKeyPair(userId: string): Promise<{ publicKey: string; privateKey: CryptoKey }> {
  const storageKey = KEY_STORAGE_PREFIX + userId;
  const stored = localStorage.getItem(storageKey);
  if (stored) {
    try {
      const parsed = JSON.parse(stored);
      const privateKey = await crypto.subtle.importKey("jwk", parsed.privateKey, { name: "ECDH", namedCurve: "P-256" }, false, ["deriveKey"]);
      return { publicKey: parsed.publicKey, privateKey };
    } catch {
      // A malformed or incompatible local key is replaced below.
    }
  }
  const pair = await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveKey"]);
  const publicJwk = await crypto.subtle.exportKey("jwk", pair.publicKey);
  const privateJwk = await crypto.subtle.exportKey("jwk", pair.privateKey);
  localStorage.setItem(storageKey, JSON.stringify({ publicKey: JSON.stringify(publicJwk), privateKey: privateJwk }));
  const privateKey = await crypto.subtle.importKey("jwk", privateJwk, { name: "ECDH", namedCurve: "P-256" }, false, ["deriveKey"]);
  return { publicKey: JSON.stringify(publicJwk), privateKey };
}

async function deriveAesKey(privateKey: CryptoKey, peerPublicKey: string): Promise<CryptoKey> {
  const jwk = JSON.parse(peerPublicKey);
  const publicKey = await crypto.subtle.importKey("jwk", jwk, { name: "ECDH", namedCurve: "P-256" }, false, []);
  const bits = await crypto.subtle.deriveBits({ name: "ECDH", public: publicKey }, privateKey, 256);
  const material = await crypto.subtle.importKey("raw", bits, "HKDF", false, ["deriveKey"]);
  return crypto.subtle.deriveKey(
    { name: "HKDF", hash: "SHA-256", salt: encoder.encode("KMCT-Community-E2EE-v1"), info: encoder.encode("private-chat") },
    material,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
}

export async function encryptChatPayload(userId: string, peerPublicKey: string, data: ArrayBuffer | Uint8Array): Promise<string> {
  const own = await ensureE2EEKeyPair(userId);
  const key = await deriveAesKey(own.privateKey, peerPublicKey);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  const ciphertext = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, bytes);
  return "E2EE1:" + JSON.stringify({ iv: toBase64(iv), data: toBase64(new Uint8Array(ciphertext)) });
}

export async function decryptChatPayload(userId: string, peerPublicKey: string, value: string): Promise<Uint8Array> {
  if (!value.startsWith("E2EE1:")) throw new Error("This message is not end-to-end encrypted.");
  const payload = JSON.parse(value.slice(6));
  const own = await ensureE2EEKeyPair(userId);
  const key = await deriveAesKey(own.privateKey, peerPublicKey);
  const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv: fromBase64(payload.iv) }, key, fromBase64(payload.data));
  return new Uint8Array(plain);
}
