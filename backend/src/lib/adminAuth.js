const crypto = require("crypto");

// Long enough that a random `openssl rand -hex 32` key always passes, short
// enough to catch an accidental "changeme". Anything shorter is treated as
// "not configured" rather than silently protecting all users' data with it.
const MIN_KEY_LENGTH = 32;

// Compare fixed-length digests so timingSafeEqual never throws on a length
// mismatch and the comparison time doesn't leak how much of the key matched.
const digest = (value) => crypto.createHash("sha256").update(value).digest();

// Guards the /admin routes with a static X-API-Key from the server's env.
// Fails closed: with no (or a too-short) ADMIN_API_KEY the admin API is
// simply off, so deploying this code before the key is set exposes nothing.
function requireAdminKey(req, res, next) {
  const expected = process.env.ADMIN_API_KEY;
  if (!expected || expected.length < MIN_KEY_LENGTH) {
    return res.status(503).json({ error: "admin API is not configured" });
  }

  const provided = req.header("x-api-key");
  if (!provided || !crypto.timingSafeEqual(digest(provided), digest(expected))) {
    return res.status(401).json({ error: "missing or invalid API key" });
  }
  next();
}

module.exports = { requireAdminKey };
