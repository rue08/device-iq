const express = require("express");
const crypto = require("crypto");
const { prisma } = require("../lib/prisma");
const { auth } = require("../lib/firebase");
const { requireAuth } = require("../lib/authMiddleware");
const { validateBody } = require("../lib/validate");
const { claimPairingSchema } = require("../lib/schemas");
const { deviceLimitReached, DEVICE_LIMIT_MESSAGE } = require("../lib/deviceLimit");

const router = express.Router();

const PAIRING_TTL_MS = 10 * 60 * 1000; // 10 minutes

/**
 * @openapi
 * /devices/pending-pairing:
 *   post:
 *     tags: [Pairing]
 *     summary: Start pairing (laptop)
 *     security: []
 *     description: Step 1 of the QR flow. Called by the laptop agent, which has no identity yet, so no token is needed. Returns a random single-use `token` for the agent to render as a QR code; it expires after 10 minutes. No request body.
 *     responses:
 *       201:
 *         description: Pairing created
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 token: { type: string, description: 48 hex characters }
 *                 expiresAt: { type: string, format: date-time }
 *             example:
 *               token: 9f2c4e7a1b8d3f6052ac91e4d7b03c68f1a5e2d49b7c0a83
 *               expiresAt: '2026-09-19T10:42:00.000Z'
 *       429:
 *         description: Too many pairings started from one IP address (about 6 a minute). Sent by nginx, not by the app, so the body is not JSON
 *       500: { $ref: '#/components/responses/InternalError' }
 */
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

/**
 * @openapi
 * /devices/pending-pairing/{token}/status:
 *   get:
 *     tags: [Pairing]
 *     summary: Poll pairing status (laptop)
 *     security: []
 *     description: 'Step 3 of the QR flow. The laptop agent polls this until `claimed` is `true`. The `deviceToken` (a Firebase custom token) is returned **once** and then cleared, so any later poll gets `deviceToken: null`. No bearer token needed; the pairing `token` itself is the secret.'
 *     parameters:
 *       - in: path
 *         name: token
 *         required: true
 *         schema: { type: string }
 *         description: The token returned by `POST /devices/pending-pairing`
 *         example: 9f2c4e7a1b8d3f6052ac91e4d7b03c68f1a5e2d49b7c0a83
 *     responses:
 *       200:
 *         description: Current state of the pairing
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 claimed: { type: boolean }
 *                 deviceId: { type: string }
 *                 deviceToken: { type: string, nullable: true, description: 'Firebase custom token, non-null on the first poll after the claim only' }
 *             examples:
 *               waiting:
 *                 summary: Not claimed yet
 *                 value: { claimed: false }
 *               firstDelivery:
 *                 summary: First poll after the claim
 *                 value: { claimed: true, deviceId: cmfx0a1b20000qzrm5g8h1a2b, deviceToken: eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9... }
 *               alreadyDelivered:
 *                 summary: Any later poll
 *                 value: { claimed: true, deviceId: cmfx0a1b20000qzrm5g8h1a2b, deviceToken: null }
 *       404:
 *         description: Unknown or expired pairing
 *         content:
 *           application/json:
 *             schema: { $ref: '#/components/schemas/Error' }
 *             example: { error: pairing not found or expired }
 *       500: { $ref: '#/components/responses/InternalError' }
 */
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

/**
 * @openapi
 * /devices/claim:
 *   post:
 *     tags: [Pairing]
 *     summary: Claim a pairing (phone)
 *     description: Step 2 of the QR flow. The phone calls this after scanning the laptop's QR, with its own account token. Creates the laptop's Device row under the phone's account and mints a device-scoped custom token, which the laptop collects from the status endpoint. The body is a device description plus the scanned `token`.
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             allOf:
 *               - $ref: '#/components/schemas/DeviceInput'
 *               - type: object
 *                 required: [token]
 *                 properties:
 *                   token: { type: string, minLength: 1, description: The pairing token from the laptop's QR code }
 *           example:
 *             token: 9f2c4e7a1b8d3f6052ac91e4d7b03c68f1a5e2d49b7c0a83
 *             deviceType: laptop
 *             platform: macos
 *             manufacturer: Apple
 *             model: MacBook Air
 *             label: Work laptop
 *     responses:
 *       201:
 *         description: Device created and pairing marked claimed
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 deviceId: { type: string }
 *             example: { deviceId: cmfx0a1b20000qzrm5g8h1a2b }
 *       400: { $ref: '#/components/responses/ValidationError' }
 *       401: { $ref: '#/components/responses/Unauthorized' }
 *       403:
 *         description: The account already has the maximum of 10 devices
 *         content:
 *           application/json:
 *             schema: { $ref: '#/components/schemas/Error' }
 *       404:
 *         description: Unknown or expired pairing
 *         content:
 *           application/json:
 *             schema: { $ref: '#/components/schemas/Error' }
 *             example: { error: pairing not found or expired }
 *       409:
 *         description: Someone already claimed this pairing
 *         content:
 *           application/json:
 *             schema: { $ref: '#/components/schemas/Error' }
 *             example: { error: pairing already claimed }
 *       500: { $ref: '#/components/responses/InternalError' }
 */
// Called by the phone after scanning the laptop's QR - authenticated with
// the phone's own Firebase ID token. Creates the Device row under the
// phone's uid, then mints a device-scoped custom token for the laptop to
// pick up (createCustomToken happens here, server-side, and never on the
// laptop itself).
router.post("/claim", requireAuth, validateBody(claimPairingSchema), async (req, res) => {
  const { token, deviceType, platform, manufacturer, model, label } = req.body;

  const pairing = await prisma.pendingPairing.findUnique({ where: { token } });
  if (!pairing || pairing.expiresAt < new Date()) {
    return res.status(404).json({ error: "pairing not found or expired" });
  }
  if (pairing.claimedAt) {
    return res.status(409).json({ error: "pairing already claimed" });
  }
  if (await deviceLimitReached(req.auth.uid)) {
    return res.status(403).json({ error: DEVICE_LIMIT_MESSAGE });
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
