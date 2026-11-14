// scripts/translate-lang.js
//
// Duplicates a source .lang file (default: en_US.lang) into every target
// locale, machine-translates each value, and keeps the matching
// languages.json in sync -- for one or more "texts" folders (bp, rp, ...).
//
// This is invoked by batchs\translate-lang.bat, which sets the
// configuration below via environment variables. You can also run it
// directly, e.g.:
//
//   set BASE_DIR=C:\path\to\project
//   set TEXTS_DIRS=sources\behavior_packs\bp\texts;sources\resource_packs\rp\texts
//   set SOURCE_LOCALE=en_US
//   set TARGET_LOCALES=vi_VN de_DE ja_JP
//   set PROTECTED_WORDS=RP BP
//   set GEMINI_API_KEY=your-key-here
//   node scripts/translate-lang.js
//
// Requires Node.js 18+ (uses the built-in global fetch).
//
// TRANSLATION BACKEND -------------------------------------------------
// This calls the Google Gemini API (generateContent) instead of the free
// unofficial Google Translate endpoint. It requires a Gemini API key
// (free tier available -- create one at https://aistudio.google.com/apikey)
// read from the GEMINI_API_KEY environment variable.
//
// Rather than one network call per string, all untranslated strings for a
// given locale are collected first and sent in a handful of batched
// requests (JSON array in, JSON array out via Gemini's structured-output
// mode), which is both far fewer requests and far less likely to be
// rate-limited than the old segment-by-segment approach.
//
// Everything else (parsing, placeholder protection, file writing,
// languages.json sync) is unchanged.
// -----------------------------------------------------------------------

// NOTE: this project's package.json has "type": "module", so this file
// is loaded as an ES module -- hence `import` instead of `require`.
import fs from "fs";
import path from "path";

// ------------------------------------------------------------------
// Configuration (env vars set by translate-lang.bat, with fallbacks)
// ------------------------------------------------------------------

const BASE_DIR = process.env.BASE_DIR || process.cwd();

const DEFAULT_TEXTS_DIRS = [
  "sources/behavior_packs/bp/texts",
  "sources/resource_packs/rp/texts",
];

const DEFAULT_TARGET_LOCALES = [
  "en_GB",
  "de_DE",
  "es_ES",
  "es_MX",
  "fr_FR",
  "fr_CA",
  "it_IT",
  "ja_JP",
  "ko_KR",
  "pt_BR",
  "pt_PT",
  "ru_RU",
  "zh_CN",
  "zh_TW",
  "nl_NL",
  "bg_BG",
  "cs_CZ",
  "da_DK",
  "el_GR",
  "fi_FI",
  "hu_HU",
  "id_ID",
  "nb_NO",
  "pl_PL",
  "sk_SK",
  "sv_SE",
  "tr_TR",
  "uk_UA",
];

const DEFAULT_PROTECTED_WORDS = ["RP", "BP"];

const SOURCE_LOCALE = process.env.SOURCE_LOCALE || "en_US";

const TEXTS_DIRS = (process.env.TEXTS_DIRS
  ? process.env.TEXTS_DIRS.split(";")
  : DEFAULT_TEXTS_DIRS
)
  .map((p) => p.trim())
  .filter(Boolean);

const TARGET_LOCALES = (process.env.TARGET_LOCALES
  ? process.env.TARGET_LOCALES.split(/\s+/)
  : DEFAULT_TARGET_LOCALES
)
  .map((l) => l.trim())
  .filter((l) => l && l !== SOURCE_LOCALE);

const PROTECTED_WORDS = (process.env.PROTECTED_WORDS
  ? process.env.PROTECTED_WORDS.split(/\s+/)
  : DEFAULT_PROTECTED_WORDS
)
  .map((w) => w.trim())
  .filter(Boolean);

// ------------------------------------------------------------------
// Gemini configuration
// ------------------------------------------------------------------

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;

// gemini-2.5-flash is a good default: solid translation quality and a
// usable free-tier quota. If you're translating a LOT of strings and hit
// free-tier rate limits often, try GEMINI_MODEL=gemini-2.5-flash-lite
// (faster/higher RPM, slightly lower quality).
const GEMINI_MODEL = process.env.GEMINI_MODEL || "gemini-2.5-flash";

// How many strings to send per API call. Larger batches = fewer requests,
// but keep it modest so a single bad response doesn't lose too much work.
const GEMINI_BATCH_SIZE = Number(process.env.GEMINI_BATCH_SIZE || 40);

// Pause between successive Gemini calls, to stay under free-tier
// requests-per-minute limits (which are quite low, e.g. 10-15 RPM
// depending on model). Increase this if you still see 429s.
const GEMINI_REQUEST_DELAY_MS = Number(
  process.env.GEMINI_REQUEST_DELAY_MS || 4500
);

const GEMINI_ENDPOINT = (model) =>
  `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(
    model
  )}:generateContent`;

// Maps a Minecraft locale code to a human-readable language name, used in
// the prompt sent to Gemini. Locales that share an underlying language
// (e.g. es_ES/es_MX) get the same translation -- Gemini is not asked to
// produce regional dialect variants. en_GB is intentionally skipped (see
// translateLocaleFile) since its target language is the same as the
// source.
const LOCALE_TO_LANG = {
  en_GB: "English",
  de_DE: "German",
  es_ES: "Spanish",
  es_MX: "Spanish",
  fr_FR: "French",
  fr_CA: "French",
  it_IT: "Italian",
  ja_JP: "Japanese",
  ko_KR: "Korean",
  pt_BR: "Portuguese",
  pt_PT: "Portuguese",
  ru_RU: "Russian",
  zh_CN: "Simplified Chinese",
  zh_TW: "Traditional Chinese",
  nl_NL: "Dutch",
  bg_BG: "Bulgarian",
  cs_CZ: "Czech",
  da_DK: "Danish",
  el_GR: "Greek",
  fi_FI: "Finnish",
  hu_HU: "Hungarian",
  id_ID: "Indonesian",
  nb_NO: "Norwegian",
  pl_PL: "Polish",
  sk_SK: "Slovak",
  sv_SE: "Swedish",
  tr_TR: "Turkish",
  uk_UA: "Ukrainian",
  vi_VN: "Vietnamese",
};

const SOURCE_LANG_NAME = LOCALE_TO_LANG[SOURCE_LOCALE] || "English";

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ------------------------------------------------------------------
// Placeholder protection
// ------------------------------------------------------------------
// Builds one regex that matches anything that must survive translation
// untouched: Minecraft formatting codes (\u00a7 + code), the literal
// ~LINEBREAK~ token, and any protected word (e.g. "RP"/"BP").

function buildProtectedPattern(protectedWords) {
  const parts = ["\u00a7[0-9a-fk-or]", "~LINEBREAK~"];
  for (const word of protectedWords) {
    const escaped = word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    parts.push(`\\b${escaped}\\b`);
  }
  return new RegExp(`(${parts.join("|")})`, "g");
}

function isProtectedSegment(segment, protectedPattern) {
  return new RegExp(`^(${protectedPattern.source})$`).test(segment);
}

function needsTranslation(segment, protectedPattern) {
  if (segment === "") return false;
  if (isProtectedSegment(segment, protectedPattern)) return false;
  if (!/[^\s]/.test(segment)) return false; // whitespace-only
  if (!/\p{L}/u.test(segment)) return false; // no letters (numbers/punct)
  return true;
}

// Splits a raw .lang value into ordered segments, same behavior as
// before: protected tokens are carved out and never sent to the
// translation backend at all.
function splitIntoSegments(value, protectedPattern) {
  return value.split(protectedPattern);
}

// ------------------------------------------------------------------
// Translation backend (Gemini API, batched with structured output)
// ------------------------------------------------------------------

async function translateBatchGemini(segments, targetLangName, attempt = 1) {
  const body = {
    system_instruction: {
      parts: [
        {
          text:
            `You translate UI strings for a Minecraft add-on from ${SOURCE_LANG_NAME} to ${targetLangName}. ` +
            `Keep translations concise, natural for in-game text, and preserve the tone of the original. ` +
            `Return exactly one translation per input string, in the same order. ` +
            `Do not add quotes, notes, or explanations -- only the translated text itself for each entry.`,
        },
      ],
    },
    contents: [
      {
        role: "user",
        parts: [{ text: JSON.stringify(segments) }],
      },
    ],
    generationConfig: {
      responseMimeType: "application/json",
      responseSchema: {
        type: "ARRAY",
        items: { type: "STRING" },
      },
    },
  };

  try {
    const res = await fetch(GEMINI_ENDPOINT(GEMINI_MODEL), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": GEMINI_API_KEY,
      },
      body: JSON.stringify(body),
    });

    if (res.status === 429 || res.status >= 500) {
      throw new Error(`HTTP ${res.status}`);
    }
    if (!res.ok) {
      const errText = await res.text().catch(() => "");
      throw new Error(`HTTP ${res.status} (non-retryable): ${errText}`);
    }

    const data = await res.json();
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!text) throw new Error("No text in Gemini response");

    const translated = JSON.parse(text);
    if (!Array.isArray(translated) || translated.length !== segments.length) {
      throw new Error(
        `Gemini returned ${
          Array.isArray(translated) ? translated.length : "non-array"
        } items for ${segments.length} inputs`
      );
    }
    return translated;
  } catch (err) {
    if (attempt < 4) {
      const backoff = 2000 * attempt;
      console.warn(
        `  ! Gemini batch failed (${err.message}), retrying in ${backoff}ms (attempt ${attempt}/3)...`
      );
      await sleep(backoff);
      return translateBatchGemini(segments, targetLangName, attempt + 1);
    }
    console.warn(
      `  ! Gemini batch failed permanently (${err.message}). Keeping original text for these ${segments.length} strings.`
    );
    return segments; // fall back to untranslated originals rather than crash the run
  }
}

function chunk(array, size) {
  const out = [];
  for (let i = 0; i < array.length; i += size) out.push(array.slice(i, i + size));
  return out;
}

// ------------------------------------------------------------------
// .lang file parsing / writing
// ------------------------------------------------------------------

function readLangFile(filePath) {
  const raw = fs.readFileSync(filePath, "utf8");
  const usesCRLF = raw.includes("\r\n");
  const lines = raw.split(/\r\n|\n/);
  return { lines, usesCRLF };
}

function writeLangFile(filePath, lines, usesCRLF) {
  const eol = usesCRLF ? "\r\n" : "\n";
  fs.writeFileSync(filePath, lines.join(eol), "utf8");
}

// Parses each line into either a passthrough string (comments, blanks,
// malformed lines) or a { key, segments } record where segments is the
// value split around protected tokens.
function parseLines(lines, protectedPattern) {
  return lines.map((line) => {
    if (!line.trim() || line.trim().startsWith("#") || !line.includes("=")) {
      return { passthrough: line };
    }
    const eqIndex = line.indexOf("=");
    const key = line.slice(0, eqIndex);
    const value = line.slice(eqIndex + 1);
    const segments = splitIntoSegments(value, protectedPattern);
    return { key, segments };
  });
}

// Translates one locale's worth of parsed lines: collects every unique
// translatable segment not already in the cache, batch-translates them
// via Gemini, then rebuilds the lines.
async function translateLocaleFile(parsedLines, langName, protectedPattern, cache) {
  const toTranslate = new Set();
  for (const entry of parsedLines) {
    if (entry.passthrough !== undefined) continue;
    for (const segment of entry.segments) {
      if (!needsTranslation(segment, protectedPattern)) continue;
      const cacheKey = `${langName}::${segment}`;
      if (!cache.has(cacheKey)) toTranslate.add(segment);
    }
  }

  const uniqueSegments = [...toTranslate];
  if (uniqueSegments.length > 0) {
    const batches = chunk(uniqueSegments, GEMINI_BATCH_SIZE);
    console.log(
      `  Translating ${uniqueSegments.length} unique string(s) in ${batches.length} batch(es)...`
    );
    for (let i = 0; i < batches.length; i++) {
      const batch = batches[i];
      const translated = await translateBatchGemini(batch, langName);
      batch.forEach((segment, idx) => {
        cache.set(`${langName}::${segment}`, translated[idx]);
      });
      if (i < batches.length - 1) await sleep(GEMINI_REQUEST_DELAY_MS);
    }
  }

  return parsedLines.map((entry) => {
    if (entry.passthrough !== undefined) return entry.passthrough;
    const value = entry.segments
      .map((segment) => {
        if (!needsTranslation(segment, protectedPattern)) return segment;
        return cache.get(`${langName}::${segment}`) ?? segment;
      })
      .join("");
    return `${entry.key}=${value}`;
  });
}

// ------------------------------------------------------------------
// languages.json
// ------------------------------------------------------------------

function updateLanguagesJson(dirAbs, sourceLocale, targetLocales) {
  const jsonPath = path.join(dirAbs, "languages.json");
  let locales = [sourceLocale];

  if (fs.existsSync(jsonPath)) {
    try {
      const existing = JSON.parse(fs.readFileSync(jsonPath, "utf8"));
      if (Array.isArray(existing)) locales = existing;
    } catch {
      console.warn(`  ! Could not parse existing ${jsonPath}, recreating it.`);
    }
  }

  for (const locale of [sourceLocale, ...targetLocales]) {
    if (!locales.includes(locale)) locales.push(locale);
  }

  const formatted = `[${locales.map((l) => `"${l}"`).join(", ")}]`;
  fs.writeFileSync(jsonPath, formatted, "utf8");
  console.log(`  Updated ${jsonPath}`);
}

// ------------------------------------------------------------------
// Main
// ------------------------------------------------------------------

async function main() {
  console.log("============================================================");
  console.log(" Translating .lang files (backend: Gemini API)");
  console.log("============================================================");
  console.log(`Source locale : ${SOURCE_LOCALE}`);
  console.log(`Target locales: ${TARGET_LOCALES.join(", ")}`);
  console.log(`Protected     : ${PROTECTED_WORDS.join(", ")}`);
  console.log(`Gemini model  : ${GEMINI_MODEL}`);
  console.log("");

  if (!GEMINI_API_KEY) {
    console.error(
      "Fatal error: GEMINI_API_KEY environment variable is not set.\n" +
        "Get a free key at https://aistudio.google.com/apikey and set it, e.g.:\n" +
        "  set GEMINI_API_KEY=your-key-here"
    );
    process.exit(1);
  }

  const protectedPattern = buildProtectedPattern(PROTECTED_WORDS);
  const cache = new Map();

  let hadError = false;

  for (const relDir of TEXTS_DIRS) {
    const dirAbs = path.resolve(BASE_DIR, relDir);
    const sourceFile = path.join(dirAbs, `${SOURCE_LOCALE}.lang`);

    console.log(`------------------------------------------------------------`);
    console.log(` Folder: ${dirAbs}`);
    console.log(`------------------------------------------------------------`);

    if (!fs.existsSync(sourceFile)) {
      console.error(`  ! Source file not found, skipping: ${sourceFile}`);
      hadError = true;
      continue;
    }

    const { lines, usesCRLF } = readLangFile(sourceFile);
    const parsedLines = parseLines(lines, protectedPattern);

    for (const locale of TARGET_LOCALES) {
      const targetFile = path.join(dirAbs, `${locale}.lang`);
      const langName = LOCALE_TO_LANG[locale];

      if (!langName) {
        console.warn(`  ! No language mapping for locale "${locale}", skipping.`);
        continue;
      }

      console.log(`  ${locale} (${langName}):`);

      let translatedLines;
      if (langName === SOURCE_LANG_NAME) {
        // Same underlying language as the source (e.g. en_GB vs en_US)
        // -- duplicate without calling the translation API.
        translatedLines = lines;
      } else {
        translatedLines = await translateLocaleFile(
          parsedLines,
          langName,
          protectedPattern,
          cache
        );
      }

      writeLangFile(targetFile, translatedLines, usesCRLF);
      console.log(`  Wrote ${locale}.lang`);
    }

    updateLanguagesJson(dirAbs, SOURCE_LOCALE, TARGET_LOCALES);
    console.log("");
  }

  console.log("============================================================");
  console.log(hadError ? " Done, with some warnings/errors above." : " Done.");
  console.log("============================================================");

  process.exit(hadError ? 1 : 0);
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
