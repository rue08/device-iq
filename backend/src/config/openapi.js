const swaggerJsdoc = require("swagger-jsdoc");
const path = require("path");
const { version } = require("../../package.json");

// Builds the OpenAPI document from the `@openapi` JSDoc blocks living above
// each route handler in src/routes/*.js - swagger-jsdoc only reads those
// files as text, it never requires/executes them, so generating this spec
// never touches Prisma, Firebase, or anything stateful.
const spec = swaggerJsdoc({
  definition: {
    openapi: "3.1.0",
    info: {
      title: "DeviceIQ API",
      version,
      description: [
        "Backend for DeviceIQ: phones and laptops report battery, storage, memory and thermal telemetry, and the phone app reads it back.",
        "",
        "**Authentication.** Every route except `/health` and the three pairing-handshake routes expects `Authorization: Bearer <Firebase ID token>`. There are two kinds of token:",
        "",
        "- **Account token** - the phone's own Firebase sign-in. Can do everything on the account.",
        "- **Device-scoped token** - what a paired laptop agent gets. Carries a `deviceId` claim and may only upload/read snapshots for that one device. Routes that rename or delete things reject it with `403`.",
        "",
        "**Pairing a laptop (QR flow).**",
        "",
        "1. Laptop calls `POST /devices/pending-pairing` (no auth) and renders the returned `token` as a QR code.",
        "2. Phone scans it and calls `POST /devices/claim` with its account token. This creates the device.",
        "3. Laptop polls `GET /devices/pending-pairing/{token}/status` until `claimed` is `true`; the `deviceToken` arrives exactly once.",
        "4. Laptop signs in to Firebase with that custom token and uploads snapshots with the resulting device-scoped ID token.",
        "",
        "Pending pairings expire after 10 minutes.",
        "",
        "**Admin routes.** The `Admin` group is a read-only, cross-user view of the database for the developer. It uses a separate `X-API-Key` header (the server's `ADMIN_API_KEY`) instead of a Firebase token. If the key isn't configured on the server, these routes return `503`.",
      ].join("\n"),
    },
    // Applies to every operation unless a route overrides it with its own
    // `security: []` (health, and the pairing handshake routes that run
    // before the laptop has any identity).
    security: [{ BearerAuth: [] }],
    tags: [
      { name: "Health", description: "Liveness probe." },
      { name: "Devices", description: "Register, list, rename and unlink the account's devices." },
      { name: "Snapshots", description: "Telemetry readings uploaded by a device." },
      { name: "Pairing", description: "QR handshake that links a laptop agent to a phone's account." },
      { name: "Account", description: "Account-level operations." },
      {
        name: "Admin",
        description: "Read-only, cross-user database view for the developer. Authenticated with `X-API-Key`, not a Firebase token.",
      },
    ],
    components: {
      securitySchemes: {
        BearerAuth: {
          type: "http",
          scheme: "bearer",
          bearerFormat: "Firebase ID token",
          description:
            "Firebase ID token. Either the phone's own sign-in (account token) or a laptop agent's session from `signInWithCustomToken` (device-scoped token).",
        },
        ApiKeyAuth: {
          type: "apiKey",
          in: "header",
          name: "X-API-Key",
          description: "The server's `ADMIN_API_KEY`. Only the `/admin` routes accept it.",
        },
      },
      parameters: {
        Limit: {
          in: "query",
          name: "limit",
          schema: { type: "integer", minimum: 1, maximum: 200, default: 50 },
          description: "Page size",
        },
        Offset: {
          in: "query",
          name: "offset",
          schema: { type: "integer", minimum: 0, default: 0 },
          description: "Rows to skip",
        },
      },
      // Shared error responses, referenced from the route blocks so each
      // status is described once.
      responses: {
        Unauthorized: {
          description: "Missing, malformed, invalid or expired bearer token",
          content: {
            "application/json": {
              schema: { $ref: "#/components/schemas/Error" },
              examples: {
                missing: { summary: "No Authorization header", value: { error: "missing bearer token" } },
                invalid: { summary: "Bad or expired token", value: { error: "invalid or expired token" } },
              },
            },
          },
        },
        ValidationError: {
          description: "Request body failed validation",
          content: {
            "application/json": {
              schema: { $ref: "#/components/schemas/ValidationError" },
            },
          },
        },
        DeviceNotFound: {
          description: "No device with that id",
          content: {
            "application/json": {
              schema: { $ref: "#/components/schemas/Error" },
              example: { error: "device not found" },
            },
          },
        },
        DeviceForbidden: {
          description: "The device belongs to another account, or a device-scoped token was used on a different device",
          content: {
            "application/json": {
              schema: { $ref: "#/components/schemas/Error" },
              examples: {
                notYours: { summary: "Belongs to another account", value: { error: "not your device" } },
                wrongDevice: {
                  summary: "Token scoped to another device",
                  value: { error: "token is scoped to a different device" },
                },
              },
            },
          },
        },
        AdminUnauthorized: {
          description: "`X-API-Key` header missing or wrong",
          content: {
            "application/json": {
              schema: { $ref: "#/components/schemas/Error" },
              example: { error: "missing or invalid API key" },
            },
          },
        },
        AdminDisabled: {
          description: "`ADMIN_API_KEY` isn't set (or is shorter than 32 characters) on the server, so the admin API is off",
          content: {
            "application/json": {
              schema: { $ref: "#/components/schemas/Error" },
              example: { error: "admin API is not configured" },
            },
          },
        },
        InternalError: {
          description: "Unexpected server error",
          content: {
            "application/json": {
              schema: { $ref: "#/components/schemas/Error" },
              example: { error: "internal server error" },
            },
          },
        },
      },
      schemas: {
        Device: {
          type: "object",
          description: "A phone or laptop linked to the account. Mirrors the `Device` model in prisma/schema.prisma.",
          properties: {
            id: { type: "string", example: "cmfx0a1b20000qzrm5g8h1a2b" },
            userId: { type: "string", description: "Firebase UID of the owning account", example: "kR3vN8xQmPZ2aTd9LwYb6HcJ0eU1" },
            deviceType: { type: "string", enum: ["phone", "laptop"] },
            platform: { type: "string", enum: ["android", "ios", "macos", "windows"] },
            manufacturer: { type: "string", nullable: true, example: "Apple" },
            model: { type: "string", nullable: true, example: "MacBook Air" },
            label: {
              type: "string",
              nullable: true,
              description: "User-facing name shown in the device switcher",
              example: "Work laptop",
            },
            createdAt: { type: "string", format: "date-time" },
          },
        },
        DeviceInput: {
          type: "object",
          required: ["deviceType", "platform"],
          properties: {
            deviceType: { type: "string", enum: ["phone", "laptop"] },
            platform: { type: "string", enum: ["android", "ios", "macos", "windows"] },
            manufacturer: { type: "string", example: "Google" },
            model: { type: "string", example: "Pixel 8" },
            label: { type: "string", example: "My phone" },
          },
        },
        Snapshot: {
          type: "object",
          description:
            "One telemetry reading. Every metric is nullable because each platform only reports what its OS exposes (see the field notes). Byte counts are serialized as **strings** because they exceed JavaScript's safe integer range.",
          properties: {
            id: { type: "string", example: "cmfx0c3d40001qzrm9k2m4n5p" },
            deviceId: { type: "string" },
            capturedAt: { type: "string", format: "date-time" },
            batteryLevelPercent: { type: "integer", minimum: 0, maximum: 100, nullable: true, example: 87 },
            isCharging: { type: "boolean", nullable: true },
            voltageMv: { type: "integer", nullable: true, example: 12480 },
            healthEnum: {
              type: "integer",
              nullable: true,
              description: "Android `BatteryManager.EXTRA_HEALTH` value. Android only.",
              example: 2,
            },
            temperatureTenthsC: {
              type: "integer",
              nullable: true,
              description: "Battery temperature in tenths of a degree Celsius (312 = 31.2 C). Android only.",
              example: 312,
            },
            cycleCount: { type: "integer", nullable: true, description: "macOS and Windows only.", example: 214 },
            designCapacityMah: {
              type: "integer",
              nullable: true,
              description: "Factory battery capacity. macOS and Windows only. Windows reports mWh natively, stored without conversion.",
              example: 4382,
            },
            fullChargeCapacityMah: {
              type: "integer",
              nullable: true,
              description: "Current full-charge capacity; compare with `designCapacityMah` for battery wear. macOS and Windows only.",
              example: 4011,
            },
            storageTotalBytes: { type: "string", nullable: true, description: "Byte count as a decimal string", example: "255960498176" },
            storageFreeBytes: { type: "string", nullable: true, example: "84120395776" },
            ramTotalBytes: { type: "string", nullable: true, example: "17179869184" },
            ramFreeBytes: { type: "string", nullable: true, example: "3221225472" },
            thermalStatus: { type: "string", nullable: true, example: "nominal" },
            raw: {
              type: "object",
              nullable: true,
              additionalProperties: true,
              description: "Full original payload from the agent, for anything not modeled above.",
            },
            createdAt: { type: "string", format: "date-time" },
          },
        },
        SnapshotInput: {
          type: "object",
          description: "All fields are optional and nullable; send whatever the platform can read. Byte counts are sent as plain numbers.",
          properties: {
            batteryLevelPercent: { type: "integer", minimum: 0, maximum: 100, nullable: true, example: 87 },
            isCharging: { type: "boolean", nullable: true, example: false },
            voltageMv: { type: "integer", nullable: true, example: 12480 },
            healthEnum: { type: "integer", nullable: true },
            temperatureTenthsC: { type: "integer", nullable: true },
            cycleCount: { type: "integer", nullable: true, example: 214 },
            designCapacityMah: { type: "integer", nullable: true, example: 4382 },
            fullChargeCapacityMah: { type: "integer", nullable: true, example: 4011 },
            storageTotalBytes: { type: "number", minimum: 0, nullable: true, example: 255960498176 },
            storageFreeBytes: { type: "number", minimum: 0, nullable: true, example: 84120395776 },
            ramTotalBytes: { type: "number", minimum: 0, nullable: true, example: 17179869184 },
            ramFreeBytes: { type: "number", minimum: 0, nullable: true, example: 3221225472 },
            thermalStatus: { type: "string", nullable: true, example: "nominal" },
            raw: { type: "object", additionalProperties: true },
          },
        },
        AdminUser: {
          type: "object",
          properties: {
            id: { type: "string", description: "Firebase UID", example: "kR3vN8xQmPZ2aTd9LwYb6HcJ0eU1" },
            email: { type: "string", example: "someone@example.com" },
            createdAt: { type: "string", format: "date-time" },
            deviceCount: { type: "integer", example: 2 },
          },
        },
        AdminDevice: {
          description: "A `Device` plus how many snapshots it has stored.",
          allOf: [
            { $ref: "#/components/schemas/Device" },
            {
              type: "object",
              properties: {
                snapshotCount: { type: "integer", example: 1342 },
              },
            },
          ],
        },
        Score: {
          type: "object",
          description:
            "Health score for one device, computed on request. `total` is the weighted average of the components that are not `unavailable`.",
          properties: {
            deviceId: { type: "string" },
            profile: { type: "string", enum: ["laptop", "phone"], description: "Which weight profile was used" },
            total: { type: "integer", minimum: 0, maximum: 100, nullable: true, example: 82 },
            includesPlaceholder: {
              type: "boolean",
              description: "True when the neutral habits placeholder (70) is part of the total because there is not enough history yet",
            },
            components: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  key: { type: "string", enum: ["battery", "storage", "memory", "thermal", "habits"] },
                  name: { type: "string", example: "Charging habits" },
                  weight: { type: "integer", example: 20 },
                  score: { type: "integer", nullable: true, description: "Null when `status` is `unavailable`" },
                  status: {
                    type: "string",
                    enum: ["measured", "placeholder", "unavailable"],
                    description: "`placeholder` = a neutral 70 stands in for a measurement that is not possible yet",
                  },
                  note: { type: "string", description: "Plain-English explanation of this score" },
                },
              },
            },
            notices: {
              type: "array",
              items: { type: "string" },
              description: "Caveats to show the user, e.g. why the habits score is a placeholder",
            },
            basedOn: {
              type: "object",
              properties: {
                snapshotCount: { type: "integer" },
                firstSnapshotAt: { type: "string", format: "date-time" },
                latestSnapshotAt: { type: "string", format: "date-time" },
              },
            },
            computedAt: { type: "string", format: "date-time" },
          },
        },
        Summary: {
          type: "object",
          description: "Cached AI explanation of a device's health score. Show it labelled as AI-generated.",
          properties: {
            text: { type: "string", description: "Two to four sentences plus a one-line suggestion" },
            score: { type: "integer", nullable: true, description: "The score total the text was written for" },
            basedOnSnapshotAt: { type: "string", format: "date-time", description: "capturedAt of the newest snapshot it was based on" },
            generatedAt: { type: "string", format: "date-time" },
            modelId: { type: "string", example: "gemini-3.5-flash-lite" },
            cached: { type: "boolean", description: "False when this request generated it" },
            stale: { type: "boolean", description: "True when regenerating failed and an older summary is returned instead" },
          },
        },
        Error: {
          type: "object",
          properties: {
            error: { type: "string" },
          },
        },
        ValidationError: {
          type: "object",
          properties: {
            error: { type: "string", example: "invalid request body" },
            issues: {
              type: "array",
              description: "Zod issue objects, one per failed field",
              items: {
                type: "object",
                properties: {
                  code: { type: "string", example: "invalid_value" },
                  path: { type: "array", items: { type: ["string", "integer"] }, example: ["platform"] },
                  message: { type: "string", example: "Invalid option: expected one of \"android\"|\"ios\"|\"macos\"|\"windows\"" },
                },
                additionalProperties: true,
              },
            },
          },
        },
      },
    },
  },
  apis: [path.join(__dirname, "../routes/*.js")],
});

module.exports = spec;
