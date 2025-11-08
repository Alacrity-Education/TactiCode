const express = require("express");
const { GoogleGenAI } = require("@google/genai");
const app = express();

const PORT = process.env.PORT || 3001;
const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const ai = new GoogleGenAI({ apiKey: GEMINI_API_KEY });

// Parse JSON bodies
app.use(express.json());

function createGenerationPrompt(scheme) {
  // Convert the scheme object to a formatted JSON string
  const schemeString = JSON.stringify(scheme, null, 2);

  // This is the prompt you and I designed in the previous step
  return `
Act as an expert web audio developer. Your task is to convert the following JSON-based music scheme into a **single, complete HTML file** that uses the \`tone.js\` library.

The code must parse this JSON logic, allow the user to play the music, and provide a button to download the resulting audio.

**Input JSON Scheme:**
\`\`\`json
${schemeString}
\`\`\`

**Requirements for the HTML file:**

1.  **HTML Structure:** Include a basic HTML skeleton (\`<html>\`, \`<head>\`, \`<body>\`).
2.  **Import \`tone.js\`:** Include \`tone.js\` from a public CDN (e.g., \`https://cdnjs.cloudflare.com/ajax/libs/tone/14.7.77/Tone.js\`).
3.  **UI Elements:**
    * A "Play" button.
    * A "Download" button.
4.  **JavaScript Logic (Interpretation):**
    * **\`setInstrument\`:** This should load a \`Tone.Sampler\`. Since the value is "Drums," load samples for "Kick" and "Snare." You can use publicly available sample URLs for this (e.g., from a GitHub repository). Map "Kick" to "C1" and "Snare" to "C2" (or similar).
    * **\`repeat\`:** This defines the main music loop. Use a \`Tone.Sequence\` to schedule the events in the \`body\`. The sequence should be **two steps** long (for the Kick and Snare) and repeat **4 times**.
    * **\`addBeat\`:** These commands populate the \`Tone.Sequence\`. The sequence should play "Kick" on the first beat and "Snare" on the second beat.
    * **\`play\`:** The "Play" button should:
        1.  Call \`Tone.start()\` to initialize audio (required by browsers).
        2.  Call \`Tone.Transport.start()\` to begin playback.
5.  **Download Functionality (\`params: ["downloadable song"]\`):**
    * This is the most critical part. The "Download" button must **not** just link to a file.
    * It must trigger an **offline rendering** of the sequence using \`Tone.Offline()\`.
    * The duration for the offline render should match the length of the sequence (e.g., 4 measures).
    * After rendering, convert the resulting \`AudioBuffer\` into a WAV file.
    * Generate a \`Blob\` from the WAV data and create a temporary \`<a>\` link with a \`download\` attribute to trigger the file download.

Please generate the complete, copy-and-paste-ready HTML file that implements all of these requirements.
`;
}

// POST /compile - logs the request body to the console
app.post("/compile", async (req, res) => {
  const input = req.body.program;
  console.log("POST /compile body:", JSON.stringify(req.body.program));

  //linearity
  const response = await ai.models.generateContent({
    model: "gemini-2.5-flash",
    contents: createGenerationPrompt(input),
  });
  console.log("AI Response:", response);
  res.status(200).json({ status: "received" });
});

app.listen(PORT, () => {
  console.log(`Compiler server listening on port ${PORT}`);
});
