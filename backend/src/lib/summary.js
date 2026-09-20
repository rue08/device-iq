const { generateText, MODEL_ID } = require("./bedrock");

const SYSTEM_PROMPT = `You write the short health summary shown to a user of DeviceIQ, an app that monitors the battery, storage, memory and heat of their phone and laptops.

You are given a JSON object with the device's health score, a breakdown by component, plain-English notes, and history statistics. Write:
1. Two to four sentences in plain English explaining what the score says and which part matters most.
2. One line starting with "Suggestion:" with one concrete, low-effort action.

Rules:
- Use only the data provided. Never invent numbers, dates or causes.
- If any component has status "placeholder", say clearly that this part is not measured yet and only a neutral value is being used, and do not describe the user's charging habits.
- If a component has status "unavailable", say this device does not report it. Do not guess its value.
- Do not claim precise battery degradation on phones. Android does not report it.
- On macOS the memory "free" figure counts only completely unused pages, so a low value is normal; do not treat it as a problem.
- No greetings, no markdown, no emojis, under 110 words.`;

function round1(n) {
  return n == null ? null : Math.round(n * 10) / 10;
}

// Builds what the model sees: score, component notes and history stats.
// Deliberately excludes ids, emails and device names.
function buildInput(device, score, trend) {
  return {
    deviceType: device.deviceType,
    platform: device.platform,
    total: score.total,
    includesPlaceholder: score.includesPlaceholder,
    components: score.components.map((c) => ({
      name: c.name,
      weight: c.weight,
      score: c.score,
      status: c.status,
      note: c.note,
    })),
    history: {
      snapshotCount: trend.snapshotCount,
      spanHours: round1(trend.spanHours),
      hotChargingSharePct: round1(trend.hotChargingSharePct),
      capacityDropPct: round1(trend.capacityDropPct),
    },
  };
}

async function generateSummary(device, score, trend) {
  const text = await generateText({
    system: SYSTEM_PROMPT,
    user: JSON.stringify(buildInput(device, score, trend)),
  });
  return { text, modelId: MODEL_ID };
}

module.exports = { generateSummary };
