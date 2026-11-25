// scripts/obfuscate-json.js
//
// Recursively finds every *.json file under the given directories,
// strips all whitespace/newlines, and obfuscates it by re-encoding every
// object key and string value character-by-character as \uXXXX escapes
// (the same approach as tools like the PixelPoly JSON Obfuscator for
// Minecraft Bedrock). Numbers, booleans, and null are left as-is --
// there's no safe way to "hide" those without changing their type.
//
// This is a pure re-encoding: valid JSON in, functionally identical
// (but human-unreadable) JSON out. \uXXXX is standard JSON syntax, so
// any spec-compliant parser -- including Minecraft's -- reads the
// obfuscated file and gets back the exact same strings, numbers, and
// structure as the original.
//
// Usage:
//   node scripts/obfuscate-json.js "<dir1>" "<dir2>" ...
//
// Intended to run against a STAGED/temp copy of bp/rp (see build.bat),
// never against your real source files, so your source stays readable
// and only the exported copy is obfuscated.
//
// Safety: after transforming each file, the output is parsed back and
// compared against the original parsed value. If anything doesn't match
// bit-for-bit, that file is left untouched and reported as skipped --
// this script will never silently ship a broken JSON file.

import fs from "fs";
import path from "path";

function collectJsonFiles(dir, out = []) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      collectJsonFiles(full, out);
    } else if (entry.isFile() && entry.name.toLowerCase().endsWith(".json")) {
      out.push(full);
    }
  }
  return out;
}

// Strips // line comments and /* */ block comments that lie outside of
// string literals. Some Bedrock JSON files (e.g. some entity/item files)
// are authored with comments even though strict JSON doesn't allow them.
// If a file has none, this is a no-op.
function stripJsonComments(text) {
  let out = "";
  let inString = false;
  let stringQuote = "";
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    const next = text[i + 1];

    if (inString) {
      out += ch;
      if (ch === "\\") {
        // Preserve the escaped character verbatim, including inside strings.
        out += next ?? "";
        i++;
        continue;
      }
      if (ch === stringQuote) inString = false;
      continue;
    }

    if (ch === '"' || ch === "'") {
      inString = true;
      stringQuote = ch;
      out += ch;
      continue;
    }

    if (ch === "/" && next === "/") {
      while (i < text.length && text[i] !== "\n") i++;
      continue;
    }
    if (ch === "/" && next === "*") {
      i += 2;
      while (i < text.length && !(text[i] === "*" && text[i + 1] === "/")) i++;
      i++; // skip the closing '/'
      continue;
    }

    out += ch;
  }
  return out;
}

// Escapes every UTF-16 code unit of a string as \uXXXX. Supplementary
// characters (e.g. emoji) are already stored as surrogate pairs in JS
// strings, so escaping unit-by-unit round-trips them correctly.
function escapeStringToUnicode(str) {
  let out = '"';
  for (let i = 0; i < str.length; i++) {
    out += "\\u" + str.charCodeAt(i).toString(16).padStart(4, "0");
  }
  return out + '"';
}

// Recursively re-serializes a parsed JSON value with every key/string
// obfuscated and zero extraneous whitespace.
function obfuscateValue(value) {
  if (value === null) return "null";
  const type = typeof value;
  if (type === "boolean") return value ? "true" : "false";
  if (type === "number") return JSON.stringify(value);
  if (type === "string") return escapeStringToUnicode(value);
  if (Array.isArray(value)) {
    return "[" + value.map(obfuscateValue).join(",") + "]";
  }
  if (type === "object") {
    const parts = Object.keys(value).map(
      (key) => escapeStringToUnicode(key) + ":" + obfuscateValue(value[key])
    );
    return "{" + parts.join(",") + "}";
  }
  // Shouldn't happen for anything JSON.parse can produce.
  return JSON.stringify(value);
}

function processFile(filePath, stats) {
  // Strip a UTF-8 BOM if present: JSON.parse rejects it, and that used to
  // make every file touched by the namespace rename get silently skipped.
  const original = fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, "");

  let parsed;
  try {
    parsed = JSON.parse(original);
  } catch {
    try {
      parsed = JSON.parse(stripJsonComments(original));
    } catch (err) {
      console.warn(`  ! Skipping (not valid JSON): ${filePath} (${err.message})`);
      stats.skipped++;
      return;
    }
  }

  const obfuscated = obfuscateValue(parsed);

  // Round-trip safety check -- never ship a file we can't prove is
  // semantically identical to the original.
  let reparsed;
  try {
    reparsed = JSON.parse(obfuscated);
  } catch (err) {
    console.warn(`  ! Skipping (obfuscated output failed to re-parse): ${filePath} (${err.message})`);
    stats.skipped++;
    return;
  }
  if (JSON.stringify(reparsed) !== JSON.stringify(parsed)) {
    console.warn(`  ! Skipping (round-trip mismatch, left untouched): ${filePath}`);
    stats.skipped++;
    return;
  }

  const beforeSize = Buffer.byteLength(original, "utf8");
  const afterSize = Buffer.byteLength(obfuscated, "utf8");
  fs.writeFileSync(filePath, obfuscated, "utf8");
  stats.processed++;
  stats.beforeBytes += beforeSize;
  stats.afterBytes += afterSize;
}

function main() {
  const dirs = process.argv.slice(2);
  if (dirs.length === 0) {
    console.error("Usage: node scripts/obfuscate-json.js <dir1> [dir2] ...");
    process.exit(1);
  }

  const stats = { processed: 0, skipped: 0, beforeBytes: 0, afterBytes: 0 };

  for (const dir of dirs) {
    const dirAbs = path.resolve(dir);
    if (!fs.existsSync(dirAbs)) {
      console.warn(`! Directory not found, skipping: ${dirAbs}`);
      continue;
    }
    console.log(`Obfuscating JSON under: ${dirAbs}`);
    const files = collectJsonFiles(dirAbs);
    for (const file of files) processFile(file, stats);
  }

  console.log(
    `Done. ${stats.processed} file(s) obfuscated, ${stats.skipped} skipped. ` +
      `${stats.beforeBytes} -> ${stats.afterBytes} bytes.`
  );

  // Skips are just informational (comments/odd files) -- never fail the
  // whole build over them, but do fail if literally nothing worked.
  if (stats.processed === 0 && stats.skipped > 0) process.exit(1);
}

main();
