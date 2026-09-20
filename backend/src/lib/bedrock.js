const { BedrockRuntimeClient, ConverseCommand } = require("@aws-sdk/client-bedrock-runtime");

// Claude Haiku 4.5 through Bedrock's global inference profile. Credentials
// come from the EC2 instance role (nothing is stored in .env); Docker needs
// the instance metadata hop limit set to 2 for the container to reach them.
const REGION = process.env.AWS_REGION || "ap-south-1";
const MODEL_ID = process.env.BEDROCK_MODEL_ID || "global.anthropic.claude-haiku-4-5-20251001-v1:0";

const client = new BedrockRuntimeClient({ region: REGION });

async function generateText({ system, user, maxTokens = 500 }) {
  const response = await client.send(
    new ConverseCommand({
      modelId: MODEL_ID,
      system: [{ text: system }],
      messages: [{ role: "user", content: [{ text: user }] }],
      inferenceConfig: { maxTokens, temperature: 0.3 },
    })
  );
  const text = response.output?.message?.content?.map((c) => c.text ?? "").join("").trim();
  if (!text) throw new Error("Bedrock returned no text");
  return text;
}

module.exports = { generateText, MODEL_ID };
