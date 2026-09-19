const express = require("express");
const { prisma } = require("../lib/prisma");
const { requireAdminKey } = require("../lib/adminAuth");
const { validateQuery } = require("../lib/validate");
const { adminPageSchema, adminDevicesQuerySchema, adminSnapshotsQuerySchema } = require("../lib/schemas");

const router = express.Router();

// Read-only, cross-user view of the database for the developer - the
// stand-in for a Django-style admin. Guarded by a static X-API-Key rather
// than a Firebase token (see lib/adminAuth.js); nothing here can write.
router.use(requireAdminKey);

/**
 * @openapi
 * /admin/users:
 *   get:
 *     tags: [Admin]
 *     summary: List users
 *     security: [{ ApiKeyAuth: [] }]
 *     description: Every account, newest first, with how many devices each has. Read-only and spans all users. Needs the server's `X-API-Key`, not a Firebase token.
 *     parameters:
 *       - $ref: '#/components/parameters/Limit'
 *       - $ref: '#/components/parameters/Offset'
 *     responses:
 *       200:
 *         description: OK
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 total: { type: integer, description: Users matching, ignoring limit/offset }
 *                 limit: { type: integer }
 *                 offset: { type: integer }
 *                 items:
 *                   type: array
 *                   items: { $ref: '#/components/schemas/AdminUser' }
 *       400: { $ref: '#/components/responses/ValidationError' }
 *       401: { $ref: '#/components/responses/AdminUnauthorized' }
 *       503: { $ref: '#/components/responses/AdminDisabled' }
 */
router.get("/users", validateQuery(adminPageSchema), async (req, res) => {
  const { limit, offset } = res.locals.query;
  const [total, users] = await Promise.all([
    prisma.user.count(),
    prisma.user.findMany({
      orderBy: [{ createdAt: "desc" }, { id: "asc" }],
      take: limit,
      skip: offset,
      include: { _count: { select: { devices: true } } },
    }),
  ]);
  const items = users.map(({ _count, ...user }) => ({ ...user, deviceCount: _count.devices }));
  res.json({ total, limit, offset, items });
});

/**
 * @openapi
 * /admin/devices:
 *   get:
 *     tags: [Admin]
 *     summary: List devices
 *     security: [{ ApiKeyAuth: [] }]
 *     description: Devices across all accounts, newest first, each with its snapshot count. Filter to one account with `userId`. Read-only. Needs `X-API-Key`.
 *     parameters:
 *       - in: query
 *         name: userId
 *         schema: { type: string }
 *         description: Only devices owned by this Firebase UID (see `GET /admin/users`)
 *       - $ref: '#/components/parameters/Limit'
 *       - $ref: '#/components/parameters/Offset'
 *     responses:
 *       200:
 *         description: OK
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 total: { type: integer, description: Devices matching the filter, ignoring limit/offset }
 *                 limit: { type: integer }
 *                 offset: { type: integer }
 *                 items:
 *                   type: array
 *                   items: { $ref: '#/components/schemas/AdminDevice' }
 *       400: { $ref: '#/components/responses/ValidationError' }
 *       401: { $ref: '#/components/responses/AdminUnauthorized' }
 *       503: { $ref: '#/components/responses/AdminDisabled' }
 */
router.get("/devices", validateQuery(adminDevicesQuerySchema), async (req, res) => {
  const { limit, offset, userId } = res.locals.query;
  const where = userId ? { userId } : {};
  const [total, devices] = await Promise.all([
    prisma.device.count({ where }),
    prisma.device.findMany({
      where,
      orderBy: [{ createdAt: "desc" }, { id: "asc" }],
      take: limit,
      skip: offset,
      include: { _count: { select: { snapshots: true } } },
    }),
  ]);
  const items = devices.map(({ _count, ...device }) => ({ ...device, snapshotCount: _count.snapshots }));
  res.json({ total, limit, offset, items });
});

/**
 * @openapi
 * /admin/snapshots:
 *   get:
 *     tags: [Admin]
 *     summary: List snapshots
 *     security: [{ ApiKeyAuth: [] }]
 *     description: Telemetry readings across all devices, most recently captured first. Filter to one device with `deviceId`. Read-only. Needs `X-API-Key`.
 *     parameters:
 *       - in: query
 *         name: deviceId
 *         schema: { type: string }
 *         description: Only snapshots from this device (see `GET /admin/devices`)
 *       - $ref: '#/components/parameters/Limit'
 *       - $ref: '#/components/parameters/Offset'
 *     responses:
 *       200:
 *         description: OK
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 total: { type: integer, description: Snapshots matching the filter, ignoring limit/offset }
 *                 limit: { type: integer }
 *                 offset: { type: integer }
 *                 items:
 *                   type: array
 *                   items: { $ref: '#/components/schemas/Snapshot' }
 *       400: { $ref: '#/components/responses/ValidationError' }
 *       401: { $ref: '#/components/responses/AdminUnauthorized' }
 *       503: { $ref: '#/components/responses/AdminDisabled' }
 */
router.get("/snapshots", validateQuery(adminSnapshotsQuerySchema), async (req, res) => {
  const { limit, offset, deviceId } = res.locals.query;
  const where = deviceId ? { deviceId } : {};
  const [total, items] = await Promise.all([
    prisma.snapshot.count({ where }),
    prisma.snapshot.findMany({
      where,
      orderBy: [{ capturedAt: "desc" }, { id: "asc" }],
      take: limit,
      skip: offset,
    }),
  ]);
  res.json({ total, limit, offset, items });
});

module.exports = router;
