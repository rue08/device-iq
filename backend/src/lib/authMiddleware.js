const { auth } = require("./firebase");
const { prisma } = require("./prisma");

function extractBearerToken(req) {
  const header = req.header("authorization");
  if (!header || !header.startsWith("Bearer ")) return null;
  return header.slice("Bearer ".length).trim();
}

// Verifies a Firebase ID token (from the phone's own sign-in, or from a
// laptop agent's session obtained via signInWithCustomToken). Attaches
// req.auth = { uid, deviceId } - deviceId is only
// present on agent-issued tokens (minted with createCustomToken(uid,
// {deviceId})), never on the phone's own direct sign-in token.
async function requireAuth(req, res, next) {
  const token = extractBearerToken(req);
  if (!token) {
    return res.status(401).json({ error: "missing bearer token" });
  }
  let decoded;
  try {
    decoded = await auth.verifyIdToken(token);
  } catch (err) {
    console.error("verifyIdToken failed:", err.message);
    return res.status(401).json({ error: "invalid or expired token" });
  }

  try {
    // Lazily create the local User row on first sight of this Firebase
    // user - there's no backend register/login endpoint, Firebase already
    // handled that client-side. User.id IS the Firebase uid (see schema).
    await prisma.user.upsert({
      where: { id: decoded.uid },
      create: { id: decoded.uid, email: decoded.email ?? "" },
      update: {},
    });
  } catch (err) {
    console.error("user upsert failed:", err.message);
    return res.status(500).json({ error: "internal server error" });
  }

  req.auth = {
    uid: decoded.uid,
    deviceId: decoded.deviceId ?? null,
  };
  next();
}

// For routes that operate on a specific :deviceId - enforces both checks:
//  1. the device must actually belong to this token's uid (always)
//  2. if this token is device-scoped (has a deviceId claim), it must match
//     the :deviceId in the URL exactly - a laptop's token can't be reused
//     for a different device even under the same account
async function requireDeviceOwnership(req, res, next) {
  const { deviceId } = req.params;

  const device = await prisma.device.findUnique({ where: { id: deviceId } });
  if (!device) {
    return res.status(404).json({ error: "device not found" });
  }
  if (device.userId !== req.auth.uid) {
    return res.status(403).json({ error: "not your device" });
  }
  if (req.auth.deviceId && req.auth.deviceId !== deviceId) {
    return res.status(403).json({ error: "token is scoped to a different device" });
  }

  req.device = device;
  next();
}

module.exports = { requireAuth, requireDeviceOwnership };
