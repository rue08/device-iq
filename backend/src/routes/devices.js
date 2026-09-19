const express = require("express");
const { prisma } = require("../lib/prisma");
const { requireAuth, requireDeviceOwnership } = require("../lib/authMiddleware");
const { validateBody } = require("../lib/validate");
const { createDeviceSchema, createSnapshotSchema, updateDeviceSchema } = require("../lib/schemas");

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
