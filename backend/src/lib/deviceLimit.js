const { prisma } = require("./prisma");

// Keeps one account from creating devices without end. Ten is well above
// what a person links (a phone plus a few laptops).
const MAX_DEVICES_PER_ACCOUNT = 10;
const DEVICE_LIMIT_MESSAGE = `device limit reached: an account can have up to ${MAX_DEVICES_PER_ACCOUNT} devices, unlink one first`;

async function deviceLimitReached(userId) {
  const count = await prisma.device.count({ where: { userId } });
  return count >= MAX_DEVICES_PER_ACCOUNT;
}

module.exports = { deviceLimitReached, DEVICE_LIMIT_MESSAGE };
