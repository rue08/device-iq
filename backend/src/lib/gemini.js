const { GoogleGenAI } = require("@google/genai");

// Gemini 3.5 Flash-Lite on the Gemini API free tier (500 requests/day, no
// billing required - see GEMINI_API_KEY in .env.example).
const MODEL_ID = process.env.GEMINI_MODEL_ID || "gemini-3.5-flash-lite";

const client = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

async function generateText({ system, user, maxTokens = 500 }) {
  const response = await client.models.generateContent({
    model: MODEL_ID,
    contents: user,
    config: { systemInstruction: system, maxOutputTokens: maxTokens, temperature: 0.3 },
  });
  const text = response.text?.trim();
  if (!text) throw new Error("Gemini returned no text");
  return text;
}

module.exports = { generateText, MODEL_ID };
