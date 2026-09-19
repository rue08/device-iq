const express = require("express");

const router = express.Router();

/**
 * @openapi
 * /health:
 *   get:
 *     tags: [Health]
 *     summary: Health
 *     security: []
 *     description: Liveness probe. Returns 200 whenever the process is up; it does not touch Postgres or Firebase. No bearer token required.
 *     responses:
 *       200:
 *         description: Server is up
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 ok: { type: boolean }
 *             example: { ok: true }
 */
router.get("/health", (req, res) => res.json({ ok: true }));

module.exports = router;
