const express = require("express");
const { prisma } = require("../lib/prisma");
const { requireAuth, requireDeviceOwnership } = require("../lib/authMiddleware");
const { validateBody } = require("../lib/validate");
const { computeScore } = require("../lib/scoring");
const { createDeviceSchema, createSnapshotSchema, updateDeviceSchema } = require("../lib/schemas");

const router = express.Router();

/**
 * @openapi
 * /devices:
 *   post:
 *     tags: [Devices]
 *     summary: Register this device
 *     description: Self-registration for the phone app, called right after its own Firebase sign-in. Laptops don't use this - they arrive through the pairing flow (`POST /devices/claim`) instead. The owning account is taken from the token, never from the body.
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema: { $ref: '#/components/schemas/DeviceInput' }
 *           example:
 *             deviceType: phone
 *             platform: android
 *             manufacturer: Google
 *             model: Pixel 8
 *             label: My phone
 *     responses:
 *       201:
 *         description: Device created
 *         content:
 *           application/json:
 *             schema: { $ref: '#/components/schemas/Device' }
 *       400: { $ref: '#/components/responses/ValidationError' }
 *       401: { $ref: '#/components/responses/Unauthorized' }
 *       500: { $ref: '#/components/responses/InternalError' }
 */
// Self-registration - used by the phone app to register itself as a device
// right after its own Firebase sign-in (Phase 1, step 2). Laptops don't use
// this endpoint - they arrive via the pairing/claim flow instead.
router.post("/", requireAuth, validateBody(createDeviceSchema), async (req, res) => {
  const device = await prisma.device.create({
    data: { userId: req.auth.uid, ...req.body },
  });
  res.status(201).json(device);
});

/**
 * @openapi
 * /devices:
 *   get:
 *     tags: [Devices]
 *     summary: List devices
 *     description: Every device linked to the caller's account, oldest first. Feeds the device switcher in the app.
 *     responses:
 *       200:
 *         description: OK (empty array if the account has no devices yet)
 *         content:
 *           application/json:
 *             schema:
 *               type: array
 *               items: { $ref: '#/components/schemas/Device' }
 *       401: { $ref: '#/components/responses/Unauthorized' }
 *       500: { $ref: '#/components/responses/InternalError' }
 */
// Device switcher list - every device belonging to this account.
router.get("/", requireAuth, async (req, res) => {
  const devices = await prisma.device.findMany({
    where: { userId: req.auth.uid },
    orderBy: { createdAt: "asc" },
  });
  res.json(devices);
});

/**
 * @openapi
 * /devices/{deviceId}/snapshots:
 *   post:
 *     tags: [Snapshots]
 *     summary: Upload a snapshot
 *     description: Stores one telemetry reading for the device. Accepts an account token or a device-scoped token for this same device. All body fields are optional, so send whatever the platform can read.
 *     parameters:
 *       - in: path
 *         name: deviceId
 *         required: true
 *         schema: { type: string }
 *         example: cmfx0a1b20000qzrm5g8h1a2b
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema: { $ref: '#/components/schemas/SnapshotInput' }
 *           examples:
 *             macbook:
 *               summary: macOS laptop
 *               value:
 *                 batteryLevelPercent: 87
 *                 isCharging: false
 *                 voltageMv: 12480
 *                 cycleCount: 214
 *                 designCapacityMah: 4382
 *                 fullChargeCapacityMah: 4011
 *                 storageTotalBytes: 255960498176
 *                 storageFreeBytes: 84120395776
 *                 ramTotalBytes: 17179869184
 *                 ramFreeBytes: 3221225472
 *                 thermalStatus: nominal
 *             android:
 *               summary: Android phone
 *               value:
 *                 batteryLevelPercent: 64
 *                 isCharging: true
 *                 voltageMv: 4012
 *                 healthEnum: 2
 *                 temperatureTenthsC: 312
 *                 thermalStatus: none
 *     responses:
 *       201:
 *         description: Snapshot stored
 *         content:
 *           application/json:
 *             schema: { $ref: '#/components/schemas/Snapshot' }
 *       400: { $ref: '#/components/responses/ValidationError' }
 *       401: { $ref: '#/components/responses/Unauthorized' }
 *       403: { $ref: '#/components/responses/DeviceForbidden' }
 *       404: { $ref: '#/components/responses/DeviceNotFound' }
 *       500: { $ref: '#/components/responses/InternalError' }
 */
router.post(
  "/:deviceId/snapshots",
  requireAuth,
  requireDeviceOwnership,
  validateBody(createSnapshotSchema),
  async (req, res) => {
    const snapshot = await prisma.snapshot.create({
      data: { deviceId: req.device.id, ...req.body },
    });
    res.status(201).json(snapshot);
  }
);

/**
 * @openapi
 * /devices/{deviceId}/snapshots/latest:
 *   get:
 *     tags: [Snapshots]
 *     summary: Get latest snapshot
 *     description: The most recent snapshot (by `capturedAt`) for the device. Accepts an account token or a device-scoped token for this same device.
 *     parameters:
 *       - in: path
 *         name: deviceId
 *         required: true
 *         schema: { type: string }
 *         example: cmfx0a1b20000qzrm5g8h1a2b
 *     responses:
 *       200:
 *         description: OK
 *         content:
 *           application/json:
 *             schema: { $ref: '#/components/schemas/Snapshot' }
 *       401: { $ref: '#/components/responses/Unauthorized' }
 *       403: { $ref: '#/components/responses/DeviceForbidden' }
 *       404:
 *         description: Device not found, or it has no snapshots yet
 *         content:
 *           application/json:
 *             schema: { $ref: '#/components/schemas/Error' }
 *             examples:
 *               noDevice: { summary: Unknown device, value: { error: device not found } }
 *               noSnapshots: { summary: Nothing uploaded yet, value: { error: no snapshots yet for this device } }
 *       500: { $ref: '#/components/responses/InternalError' }
 */
router.get("/:deviceId/snapshots/latest", requireAuth, requireDeviceOwnership, async (req, res) => {
  const snapshot = await prisma.snapshot.findFirst({
    where: { deviceId: req.device.id },
    orderBy: { capturedAt: "desc" },
  });
  if (!snapshot) {
    return res.status(404).json({ error: "no snapshots yet for this device" });
  }
  res.json(snapshot);
});

const SCORE_WINDOW_DAYS = 30;
const SCORE_MAX_SNAPSHOTS = 1000;

/**
 * @openapi
 * /devices/{deviceId}/score:
 *   get:
 *     tags: [Snapshots]
 *     summary: Get health score
 *     description: Deterministic 0-100 health score with a per-component breakdown, computed on request from the device's snapshots of the last 30 days (nothing is stored). Laptops and phones use different weights, because only laptops report real battery capacity. The charging habits component needs at least 10 snapshots spanning 24 hours; before that it is a neutral placeholder of 70, not a measurement - its `status` is `placeholder`, `includesPlaceholder` is `true` and `notices` explains it in plain words. A component the device cannot report at all (for example thermal on Windows) has `status` `unavailable` and is left out of the total.
 *     parameters:
 *       - in: path
 *         name: deviceId
 *         required: true
 *         schema: { type: string }
 *         example: cmfx0a1b20000qzrm5g8h1a2b
 *     responses:
 *       200:
 *         description: OK
 *         content:
 *           application/json:
 *             schema: { $ref: '#/components/schemas/Score' }
 *             example:
 *               deviceId: cmfx0a1b20000qzrm5g8h1a2b
 *               profile: laptop
 *               total: 74
 *               includesPlaceholder: true
 *               components:
 *                 - { key: battery, name: Battery, weight: 35, score: 83, status: measured, note: "86% of design capacity, 396 charge cycles" }
 *                 - { key: habits, name: Charging habits, weight: 20, score: 70, status: placeholder, note: "Not enough history yet: 1 snapshot over 0.0 hours (needs at least 10 over 24 hours). A neutral 70 is shown as a placeholder. It is not measured from your usage." }
 *               notices: ["Not enough history yet: 1 snapshot over 0.0 hours (needs at least 10 over 24 hours). A neutral 70 is shown as a placeholder. It is not measured from your usage."]
 *               basedOn: { snapshotCount: 1, firstSnapshotAt: "2026-09-20T11:11:57.615Z", latestSnapshotAt: "2026-09-20T11:11:57.615Z" }
 *               computedAt: "2026-09-20T11:11:58.000Z"
 *       401: { $ref: '#/components/responses/Unauthorized' }
 *       403: { $ref: '#/components/responses/DeviceForbidden' }
 *       404:
 *         description: Device not found, or it has no snapshots yet
 *         content:
 *           application/json:
 *             schema: { $ref: '#/components/schemas/Error' }
 *       500: { $ref: '#/components/responses/InternalError' }
 */
// Health score, computed on request from recent snapshots - see lib/scoring.js.
router.get("/:deviceId/score", requireAuth, requireDeviceOwnership, async (req, res) => {
  const since = new Date(Date.now() - SCORE_WINDOW_DAYS * 24 * 60 * 60 * 1000);
  const recent = await prisma.snapshot.findMany({
    where: { deviceId: req.device.id, capturedAt: { gte: since } },
    orderBy: { capturedAt: "desc" },
    take: SCORE_MAX_SNAPSHOTS,
  });
  if (!recent.length) {
    return res.status(404).json({ error: "no recent snapshots yet for this device" });
  }
  res.json(computeScore(req.device, recent.reverse()));
});

/**
 * @openapi
 * /devices/{deviceId}:
 *   patch:
 *     tags: [Devices]
 *     summary: Rename device
 *     description: Changes the device's user-facing label. Account tokens only - a device-scoped token gets 403.
 *     parameters:
 *       - in: path
 *         name: deviceId
 *         required: true
 *         schema: { type: string }
 *         example: cmfx0a1b20000qzrm5g8h1a2b
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required: [label]
 *             properties:
 *               label: { type: string, minLength: 1, maxLength: 60, description: Trimmed before validation, example: Work laptop }
 *     responses:
 *       200:
 *         description: Device updated
 *         content:
 *           application/json:
 *             schema: { $ref: '#/components/schemas/Device' }
 *       400: { $ref: '#/components/responses/ValidationError' }
 *       401: { $ref: '#/components/responses/Unauthorized' }
 *       403:
 *         description: Not your device, token scoped to another device, or a device-scoped token was used at all
 *         content:
 *           application/json:
 *             schema: { $ref: '#/components/schemas/Error' }
 *             examples:
 *               notYours: { summary: Belongs to another account, value: { error: not your device } }
 *               deviceToken: { summary: Device-scoped token, value: { error: device tokens cannot rename devices } }
 *       404: { $ref: '#/components/responses/DeviceNotFound' }
 *       500: { $ref: '#/components/responses/InternalError' }
 */
// Rename a device. Account-level tokens only, same as unlinking.
router.patch(
  "/:deviceId",
  requireAuth,
  requireDeviceOwnership,
  validateBody(updateDeviceSchema),
  async (req, res) => {
    if (req.auth.deviceId) {
      return res.status(403).json({ error: "device tokens cannot rename devices" });
    }
    const device = await prisma.device.update({
      where: { id: req.device.id },
      data: { label: req.body.label },
    });
    res.json(device);
  }
);

/**
 * @openapi
 * /devices/{deviceId}:
 *   delete:
 *     tags: [Devices]
 *     summary: Unlink device
 *     description: Deletes the device and all of its snapshots. Account tokens only - a laptop's device-scoped token can't delete itself or others. The laptop agent then gets 404s on its next upload and unpairs itself.
 *     parameters:
 *       - in: path
 *         name: deviceId
 *         required: true
 *         schema: { type: string }
 *         example: cmfx0a1b20000qzrm5g8h1a2b
 *     responses:
 *       204:
 *         description: Deleted, no body
 *       401: { $ref: '#/components/responses/Unauthorized' }
 *       403:
 *         description: Not your device, token scoped to another device, or a device-scoped token was used at all
 *         content:
 *           application/json:
 *             schema: { $ref: '#/components/schemas/Error' }
 *             examples:
 *               notYours: { summary: Belongs to another account, value: { error: not your device } }
 *               deviceToken: { summary: Device-scoped token, value: { error: device tokens cannot unlink devices } }
 *       404: { $ref: '#/components/responses/DeviceNotFound' }
 *       500: { $ref: '#/components/responses/InternalError' }
 */
// Unlink a device: removes it and its snapshots. Account-level tokens only -
// a laptop's device-scoped token must not be able to delete itself or others.
router.delete("/:deviceId", requireAuth, requireDeviceOwnership, async (req, res) => {
  if (req.auth.deviceId) {
    return res.status(403).json({ error: "device tokens cannot unlink devices" });
  }
  await prisma.$transaction([
    prisma.snapshot.deleteMany({ where: { deviceId: req.device.id } }),
    prisma.device.delete({ where: { id: req.device.id } }),
  ]);
  res.status(204).end();
});

module.exports = router;
