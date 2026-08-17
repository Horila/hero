// Supabase Edge Function: ocr-plan
// Receives a base64 photo of the DISA plan screen, sends it to Gemini's
// vision API (free tier), returns a parsed array of job objects.
//
// The GEMINI_API_KEY never touches the browser — it lives only here,
// as a Supabase secret.
//
// Deploy via Dashboard: Edge Functions → Deploy a new function → Via Editor
// → paste this in → name it exactly "ocr-plan"
// Then: Edge Functions → Secrets → add GEMINI_API_KEY

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");

// Verify this model name is still current in Google AI Studio when you set
// this up — model names change. As of writing, gemini-2.5-flash is on the
// free tier and handles vision fine for this use case.
const GEMINI_MODEL = "gemini-2.5-flash";
const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const EXTRACTION_PROMPT = `You are reading a photo of a DISA foundry production plan screen.
Extract every job row visible into a JSON array. For each job, return exactly
these fields — use null for anything not visible or not legible, never guess
or invent a value:

{
  "grade": string|null,
  "am_number": string|null,
  "item_number": string|null,
  "customer_name": string|null,
  "weight_kg": number|null,
  "planned_qty": number|null,
  "mingzhi_hansberg_no": string|null,
  "status": string|null,
  "is_trial": boolean
}

Return ONLY a raw JSON array. No commentary, no explanation — the response
body must be valid JSON and nothing else.`;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (!GEMINI_API_KEY) {
    return new Response(JSON.stringify({ error: "GEMINI_API_KEY not configured" }), {
      status: 500,
      headers: { ...CORS_HEADERS, "content-type": "application/json" },
    });
  }

  try {
    const { imageBase64, mediaType } = await req.json();

    if (!imageBase64) {
      return new Response(JSON.stringify({ error: "missing imageBase64" }), {
        status: 400,
        headers: { ...CORS_HEADERS, "content-type": "application/json" },
      });
    }

    const geminiRes = await fetch(GEMINI_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-goog-api-key": GEMINI_API_KEY,
      },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              {
                inline_data: {
                  mime_type: mediaType || "image/jpeg",
                  data: imageBase64,
                },
              },
              { text: EXTRACTION_PROMPT },
            ],
          },
        ],
        generationConfig: {
          responseMimeType: "application/json",
          // No output cap by default meant a plan photo with many job rows
          // could get silently truncated mid-JSON-array. Set explicitly to
          // gemini-2.5-flash's actual max so a busy plan never gets cut off.
          maxOutputTokens: 65536,
        },
      }),
    });

    if (!geminiRes.ok) {
      const errText = await geminiRes.text();
      return new Response(JSON.stringify({ error: "gemini_api_error", detail: errText }), {
        status: 502,
        headers: { ...CORS_HEADERS, "content-type": "application/json" },
      });
    }

    const data = await geminiRes.json();
    const rawText = data.candidates?.[0]?.content?.parts?.[0]?.text ?? "[]";

    let jobs;
    try {
      jobs = JSON.parse(rawText);
    } catch (parseErr) {
      return new Response(JSON.stringify({ error: "parse_failed", raw: rawText }), {
        status: 200,
        headers: { ...CORS_HEADERS, "content-type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ jobs }), {
      headers: { ...CORS_HEADERS, "content-type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...CORS_HEADERS, "content-type": "application/json" },
    });
  }
});
