const { z } = require("zod");

const deviceTypeSchema = z.enum(["phone", "laptop"]);
const platformSchema = z.enum(["android", "ios", "macos", "windows"]);

const createDeviceSchema = z.object({
  deviceType: deviceTypeSchema,
  platform: platformSchema,
  manufacturer: z.string().optional(),
  model: z.string().optional(),
  label: z.string().optional(),
});

const claimPairingSchema = createDeviceSchema.extend({
  token: z.string().min(1),
});

// All fields optional/nullable: a single snapshot payload covers phone,
// macOS, and Windows shapes, and each platform only populates the fields
// it can actually read.
const createSnapshotSchema = z.object({
  batteryLevelPercent: z.number().int().min(0).max(100).nullable().optional(),
  isCharging: z.boolean().nullable().optional(),
  voltageMv: z.number().int().nullable().optional(),

  healthEnum: z.number().int().nullable().optional(),
  temperatureTenthsC: z.number().int().nullable().optional(),

  cycleCount: z.number().int().nullable().optional(),
  designCapacityMah: z.number().int().nullable().optional(),
  fullChargeCapacityMah: z.number().int().nullable().optional(),

  storageTotalBytes: z.number().nonnegative().nullable().optional(),
  storageFreeBytes: z.number().nonnegative().nullable().optional(),

  ramTotalBytes: z.number().nonnegative().nullable().optional(),
  ramFreeBytes: z.number().nonnegative().nullable().optional(),

  thermalStatus: z.string().nullable().optional(),

  raw: z.record(z.string(), z.unknown()).optional(),
});

const updateDeviceSchema = z.object({
  label: z.string().trim().min(1).max(60),
});

// Query strings for the /admin list routes. Values arrive as strings, hence
// coerce. limit is capped so a stray request can't pull the whole table.
const adminPageSchema = z.object({
  limit: z.coerce.number().int().min(1).max(200).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});

const adminDevicesQuerySchema = adminPageSchema.extend({
  userId: z.string().min(1).optional(),
});

const adminSnapshotsQuerySchema = adminPageSchema.extend({
  deviceId: z.string().min(1).optional(),
});

module.exports = {
  adminPageSchema,
  adminDevicesQuerySchema,
  adminSnapshotsQuerySchema,
  deviceTypeSchema,
  platformSchema,
  createDeviceSchema,
  claimPairingSchema,
  createSnapshotSchema,
  updateDeviceSchema,
};
