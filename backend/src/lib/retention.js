const { prisma } = require("./prisma");

const DAY_MS = 24 * 60 * 60 * 1000;
// The score only reads the last 30 days (SCORE_WINDOW_DAYS in
// routes/devices.js), so older snapshots are never used.
const SNAPSHOT_MAX_AGE_DAYS = 30;
// A pairing lives 10 minutes; expired ones are kept a day and then removed.
// POST /devices/pending-pairing needs no login, so nothing else would ever
// clear the rows it creates.
const PAIRING_KEEP_AFTER_EXPIRY_MS = DAY_MS;
const RUN_EVERY_MS = 6 * 60 * 60 * 1000;

async function pruneOldData() {
  const snapshotCutoff = new Date(Date.now() - SNAPSHOT_MAX_AGE_DAYS * DAY_MS);
  // Never removes a device's newest snapshot, so a laptop that has been off
  // for over a month still shows its last reading instead of "no snapshot".
  const snapshots = await prisma.$executeRaw`
    DELETE FROM "Snapshot" AS s
    WHERE s."capturedAt" < ${snapshotCutoff}
      AND EXISTS (
        SELECT 1 FROM "Snapshot" AS n
        WHERE n."deviceId" = s."deviceId" AND n."capturedAt" > s."capturedAt"
      )`;
  const pairings = await prisma.pendingPairing.deleteMany({
    where: { expiresAt: { lt: new Date(Date.now() - PAIRING_KEEP_AFTER_EXPIRY_MS) } },
  });
  if (snapshots || pairings.count) {
    console.log(`retention: removed ${snapshots} old snapshots and ${pairings.count} expired pairings`);
  }
}

// Runs once at startup, then every few hours. A failure is logged and the
// next run tries again; it must never take the server down.
function startRetention() {
  const run = () => pruneOldData().catch((err) => console.error("retention failed:", err.name, err.message));
  run();
  setInterval(run, RUN_EVERY_MS).unref();
}

module.exports = { startRetention };
