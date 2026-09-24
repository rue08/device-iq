const { GoogleGenAI } = require("@google/genai");

// Gemini 3.5 Flash-Lite on the Gemini API free tier (500 requests/day, no
// billing required - see GEMINI_API_KEY in .env.example).
const MODEL_ID = process.env.GEMINI_MODEL_ID || "gemini-3.5-flash-lite";

// A call that hangs would otherwise hold the request until nginx cuts it off
// at 60s. No retry here: after this the route answers 502 (or the older
// summary) and the user pulls down to try again.
const REQUEST_TIMEOUT_MS = 20 * 1000;

const client = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

async function generateText({ system, user, maxTokens = 500 }) {
  const response = await client.models.generateContent({
    model: MODEL_ID,
    contents: user,
    config: {
      systemInstruction: system,
      maxOutputTokens: maxTokens,
      temperature: 0.3,
      abortSignal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    },
  });
  const text = response.text?.trim();
  if (!text) throw new Error("Gemini returned no text");
  return text;
}

module.exports = { generateText, MODEL_ID };
