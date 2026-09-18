require("dotenv/config");
const { defineConfig } = require("prisma/config");

module.exports = defineConfig({
  schema: "prisma/schema.prisma",
  migrations: {
    path: "prisma/migrations",
  },
  datasource: {
    // MIGRATE_DATABASE_URL lets migrations use a different sslmode than the
    // app (Prisma's schema engine doesn't support verify-full, pg does).
    url: process.env["MIGRATE_DATABASE_URL"] || process.env["DATABASE_URL"],
  },
});
