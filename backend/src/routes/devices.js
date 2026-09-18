const express = require("express");
const { prisma } = require("../lib/prisma");
const { requireAuth, requireDeviceOwnership } = require("../lib/authMiddleware");
const { validateBody } = require("../lib/validate");
const { createDeviceSchema, createSnapshotSchema } = require("../lib/schemas");

const router = express.Router();

// Self-registration - used by the phone app to register itself as a device
// right after its own Firebase sign-in (Phase 1, step 2). Laptops don't use
// this endpoint - they arrive via the pairing/claim flow instead.
router.post("/", requireAuth, validateBody(createDeviceSchema), async (req, res) => {
  const device = await prisma.device.create({
    data: { userId: req.auth.uid, ...req.body },
  });
  res.status(201).json(device);
});

// Device switcher list - every device belonging to this account.
router.get("/", requireAuth, async (req, res) => {
  const devices = await prisma.device.findMany({
    where: { userId: req.auth.uid },
    orderBy: { createdAt: "asc" },
  });
  res.json(devices);
});

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

module.exports = router;
