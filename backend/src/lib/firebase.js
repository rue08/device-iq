const fs = require("fs");
const path = require("path");
const { initializeApp, getApps, cert } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");

// Two ways to provide the service account, whichever is set:
// - FIREBASE_SERVICE_ACCOUNT_JSON: the whole key file's JSON as one string
// - GOOGLE_APPLICATION_CREDENTIALS: a path to the key file
// Get the JSON file from: Firebase Console -> Project Settings ->
// Service Accounts -> Generate new private key. Server-side only, never
// ship this to the phone app or the laptop agent - see PROJECT.md 2b.
//
// Deliberately NOT using admin.credential.applicationDefault() here - it
// resolves credentials via Google's generic ADC search order, which can
// silently land on a path that lacks a usable private key and falls back
// to signing custom tokens remotely via the IAM Service Account
// Credentials API (extra API to enable, extra permissions, extra latency).
// Loading and parsing the key file ourselves and passing it to cert()
// guarantees local, private-key-based signing every time.
function buildCredential() {
  const inlineJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (inlineJson) {
    return cert(JSON.parse(inlineJson));
  }

  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (credPath) {
    const resolved = path.resolve(process.cwd(), credPath);
    const serviceAccount = JSON.parse(fs.readFileSync(resolved, "utf8"));
    return cert(serviceAccount);
  }

  throw new Error(
    "No Firebase credentials configured - set FIREBASE_SERVICE_ACCOUNT_JSON or GOOGLE_APPLICATION_CREDENTIALS in .env"
  );
}

if (!getApps().length) {
  initializeApp({ credential: buildCredential() });
}

const auth = getAuth();

module.exports = { auth };
