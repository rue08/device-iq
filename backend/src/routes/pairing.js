const express = require("express");
const crypto = require("crypto");
const { prisma } = require("../lib/prisma");
const { auth } = require("../lib/firebase");
const { requireAuth } = require("../lib/authMiddleware");
const { validateBody } = require("../lib/validate");
const { claimPairingSchema } = require("../lib/schemas");

const router = express.Router();

const PAIRING_TTL_MS = 10 * 60 * 1000; // 10 minutes, per PROJECT.md 2b

// Called by the laptop agent, unauthenticated - it has no identity yet.
// Returns a short-lived token for the agent to render as a QR code.
router.post("/pending-pairing", async (req, res) => {
  const token = crypto.randomBytes(24).toString("hex");
  const pairing = await prisma.pendingPairing.create({
    data: {
      token,
      expiresAt: new Date(Date.now() + PAIRING_TTL_MS),
    },
  });
  res.status(201).json({ token: pairing.token, expiresAt: pairing.expiresAt });
});

// Polled repeatedly by the laptop agent (simple interval polling, per our
// discussion) until claimed:true shows up. deviceToken is returned once,
// then cleared from the DB - single-use delivery.
router.get("/pending-pairing/:token/status", async (req, res) => {
  const pairing = await prisma.pendingPairing.findUnique({
    where: { token: req.params.token },
  });

  if (!pairing || pairing.expiresAt < new Date()) {
    return res.status(404).json({ error: "pairing not found or expired" });
  }

  if (!pairing.claimedAt) {
    return res.json({ claimed: false });
  }

  // Already delivered once - don't hand the custom token out again.
  if (!pairing.deviceToken) {
    return res.json({ claimed: true, deviceId: pairing.deviceId, deviceToken: null });
  }

  const deviceToken = pairing.deviceToken;
  await prisma.pendingPairing.update({
    where: { token: pairing.token },
    data: { deviceToken: null },
  });

  res.json({ claimed: true, deviceId: pairing.deviceId, deviceToken });
});

// Called by the phone after scanning the laptop's QR - authenticated with
// the phone's own Firebase ID token. Creates the Device row under the
// phone's uid, then mints a device-scoped custom token for the laptop to
// pick up (see PROJECT.md 2b for why createCustomToken happens here,
// server-side, and never on the laptop itself).
router.post("/claim", requireAuth, validateBody(claimPairingSchema), async (req, res) => {
  const { token, deviceType, platform, manufacturer, model, label } = req.body;

  const pairing = await prisma.pendingPairing.findUnique({ where: { token } });
  if (!pairing || pairing.expiresAt < new Date()) {
    return res.status(404).json({ error: "pairing not found or expired" });
  }
  if (pairing.claimedAt) {
    return res.status(409).json({ error: "pairing already claimed" });
  }

  const device = await prisma.device.create({
    data: {
      userId: req.auth.uid,
      deviceType,
      platform,
      manufacturer,
      model,
      label,
    },
  });

  const deviceToken = await auth.createCustomToken(req.auth.uid, {
    deviceId: device.id,
  });

  await prisma.pendingPairing.update({
    where: { token },
    data: {
      userId: req.auth.uid,
      claimedAt: new Date(),
      deviceId: device.id,
      deviceToken,
    },
  });

  res.status(201).json({ deviceId: device.id });
});

module.exports = router;
