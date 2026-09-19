require("dotenv/config");
const path = require("path");
const express = require("express");
const cors = require("cors");

// Prisma's BigInt columns (storage/RAM byte counts - see schema.prisma)
// don't have a native JSON representation; res.json() throws on them
// otherwise ("Do not know how to serialize a BigInt"). Standard fix.
BigInt.prototype.toJSON = function () {
  return this.toString();
};

const devicesRouter = require("./routes/devices");
const pairingRouter = require("./routes/pairing");
const accountRouter = require("./routes/account");
const healthRouter = require("./routes/health");
const docsRouter = require("./routes/docs");

const app = express();
app.use(cors());
app.use(express.json());

app.use(healthRouter);
app.use(docsRouter);

// Static pages: /pair renders the pairing QR for laptop agents that can't
// draw one themselves (the Windows agent). See src/public/pair.html.
const publicDir = path.join(__dirname, "public");
app.get("/pair", (req, res) => res.sendFile(path.join(publicDir, "pair.html")));
app.get("/qrcode.js", (req, res) => res.sendFile(path.join(publicDir, "qrcode.js")));

app.use("/devices", devicesRouter);
app.use("/devices", pairingRouter);
app.use("/account", accountRouter);

// Catch-all error handler - so a thrown/rejected error in any route
// returns JSON instead of Express's default HTML error page.
app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: "internal server error" });
});

const port = process.env.PORT || 4000;
app.listen(port, () => {
  console.log(`device-iq backend listening on :${port}`);
});
