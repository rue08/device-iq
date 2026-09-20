const express = require("express");
const { prisma } = require("../lib/prisma");
const { auth } = require("../lib/firebase");
const { requireAuth } = require("../lib/authMiddleware");

const router = express.Router();

/**
 * @openapi
 * /account:
 *   delete:
 *     tags: [Account]
 *     summary: Delete account
 *     description: Permanently deletes every device and snapshot, any pending pairings, the user record, and finally the Firebase user. **Irreversible.** Account tokens only - a laptop's device-scoped token gets 403. Laptop agents then get 404s on their next upload and unpair themselves.
 *     responses:
 *       204:
 *         description: Account deleted, no body
 *       401: { $ref: '#/components/responses/Unauthorized' }
 *       403:
 *         description: A device-scoped token was used
 *         content:
 *           application/json:
 *             schema: { $ref: '#/components/schemas/Error' }
 *             example: { error: device tokens cannot delete the account }
 *       500: { $ref: '#/components/responses/InternalError' }
 */
// Permanently deletes the caller's account: every device and snapshot, any
// pending pairings, the User row, and finally the Firebase user itself.
// Account-level tokens only - a laptop's device-scoped token must not be able
// to wipe the whole account. Laptop agents then get 404s on their next
// upload and unpair themselves.
router.delete("/", requireAuth, async (req, res) => {
  if (req.auth.deviceId) {
    return res.status(403).json({ error: "device tokens cannot delete the account" });
  }
  const uid = req.auth.uid;

  await prisma.$transaction([
    prisma.snapshot.deleteMany({ where: { device: { userId: uid } } }),
    prisma.deviceSummary.deleteMany({ where: { device: { userId: uid } } }),
    prisma.device.deleteMany({ where: { userId: uid } }),
    prisma.pendingPairing.deleteMany({ where: { userId: uid } }),
    prisma.user.deleteMany({ where: { id: uid } }),
  ]);

  // Last: if this fails the data is already gone, and the next sign-in
  // lazily recreates an empty backend User, so nothing is left inconsistent.
  await auth.deleteUser(uid);

  res.status(204).end();
});

module.exports = router;
