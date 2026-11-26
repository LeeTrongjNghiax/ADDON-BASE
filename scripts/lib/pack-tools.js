// scripts/lib/pack-tools.js
//
// Shared by scripts/release.js and scripts/market.js: reading a pack's
// version from its manifest.json, picking the next
// assets/version/v<BP>__<RP>__<index> folder, and writing the zip. No npm
// dependency: the zip is written here, with forward-slash entry names so
// the archive also imports on Android, iOS and macOS (Windows PowerShell
// 5.1's Compress-Archive writes backslashes).

import fs from "fs";
import path from "path";
import zlib from "zlib";
import { fileURLToPath } from "url";

export const PROJECT_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
export const DEFAULT_OUT = path.join(PROJECT_ROOT, "assets", "version");
export const BUILD_BAT = path.join(PROJECT_ROOT, "batchs", "build.bat");

// Never worth shipping, whatever the folder holds.
const IGNORED_FILES = new Set([".ds_store", "thumbs.db", "desktop.ini"]);

// Word used in the failure message ("Release failed: ...").
let label = "Release";
export function setLabel(text) {
  label = text;
}

export function fail(message) {
  console.error(`\n${label} failed: ${message}`);
  process.exit(1);
}

// ------------------------------------------------------------ manifest

// Manifests may carry // and /* */ comments (Bedrock accepts them).
// String-aware, so a "//" inside a URL string is left alone.
function stripJsonComments(text) {
  let out = "";
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (ch === '"') {
      let j = i + 1;
      while (j < text.length && text[j] !== '"') j += text[j] === "\\" ? 2 : 1;
      out += text.slice(i, j + 1);
      i = j;
    } else if (ch === "/" && text[i + 1] === "/") {
      while (i < text.length && text[i] !== "\n") i++;
      out += "\n";
    } else if (ch === "/" && text[i + 1] === "*") {
      i += 2;
      while (i < text.length && !(text[i] === "*" && text[i + 1] === "/")) i++;
      i++;
    } else {
      out += ch;
    }
  }
  return out;
}

export function readVersion(packDir, label) {
  const manifestPath = path.join(packDir, "manifest.json");
  if (!fs.existsSync(packDir) || !fs.statSync(packDir).isDirectory()) {
    fail(`${label} folder not found: ${packDir}\n  Build the packs first (release.bat and market.bat do that for you).`);
  }
  if (!fs.existsSync(manifestPath)) fail(`${label} folder has no manifest.json: ${packDir}`);

  // A BOM would make JSON.parse throw, so drop it first.
  const text = fs.readFileSync(manifestPath, "utf8").replace(/^\uFEFF/, "");
  let manifest;
  try {
    manifest = JSON.parse(text);
  } catch {
    try {
      manifest = JSON.parse(stripJsonComments(text));
    } catch (err) {
      fail(`Could not parse ${manifestPath}: ${err.message}`);
    }
  }

  const v = manifest?.header?.version;
  // Usual form is [major, minor, patch]; newer manifests also allow a
  // "1.2.3" string.
  if (Array.isArray(v) && v.length === 3 && v.every((n) => Number.isInteger(n) && n >= 0)) {
    return v.join(".");
  }
  if (typeof v === "string" && /^\d+\.\d+\.\d+([-+][0-9A-Za-z.-]+)?$/.test(v)) return v;
  fail(`${label} manifest has no usable header.version (expected [1, 0, 0]): ${manifestPath}`);
}

// ------------------------------------------------------------ file name

// PROJECT_NAME_DEFAULT from batchs/build.bat, so the project name is
// configured in one place only. Returns null when it can't be read.
export function projectNameFromBuildBat() {
  let text;
  try {
    text = fs.readFileSync(BUILD_BAT, "utf8");
  } catch {
    return null;
  }
  const match = /^[ \t]*set[ \t]+"PROJECT_NAME_DEFAULT=(.*)"[ \t]*\r?$/im.exec(text);
  if (!match || !match[1].trim()) return null;
  if (/[%!]/.test(match[1])) {
    console.warn(`Note: PROJECT_NAME_DEFAULT in ${BUILD_BAT} uses a variable; pass --name instead.`);
    return null;
  }
  return match[1].trim();
}

// Replace what Windows does not allow in a file name, and trailing dots/spaces.
export function toFileName(name) {
  return name.replace(/[<>:"/\\|?*\u0000-\u001f]/g, "_").replace(/[. ]+$/, "");
}

// ------------------------------------------------------- index / folder

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// Next unused index for this version pair: highest existing + 1, else 0.
export function nextIndex(outRoot, prefix) {
  if (!fs.existsSync(outRoot)) return 0;
  const pattern = new RegExp(`^${escapeRegExp(prefix)}(\\d+)$`);
  let highest = -1;
  for (const entry of fs.readdirSync(outRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const match = pattern.exec(entry.name);
    if (match) highest = Math.max(highest, Number(match[1]));
  }
  return highest + 1;
}

// ----------------------------------------------------------- zip writer

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function dosDateTime(date) {
  const year = Math.max(date.getFullYear(), 1980);
  return {
    time: (date.getHours() << 11) | (date.getMinutes() << 5) | (date.getSeconds() >> 1),
    date: ((year - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate(),
  };
}

// Every file under dir, as { abs, rel } with rel using "/" separators.
export function collectFiles(dir, relBase, files = []) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  entries.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  for (const entry of entries) {
    const abs = path.join(dir, entry.name);
    const rel = `${relBase}/${entry.name}`;
    if (entry.isDirectory()) collectFiles(abs, rel, files);
    else if (entry.isFile() && !IGNORED_FILES.has(entry.name.toLowerCase())) files.push({ abs, rel });
  }
  return files;
}

export function writeZip(zipPath, files) {
  if (files.length > 0xfffe) throw new Error(`Too many files for a plain zip (${files.length}).`);

  const fd = fs.openSync(zipPath, "w");
  let offset = 0;
  const write = (buf) => {
    fs.writeSync(fd, buf);
    offset += buf.length;
  };
  const central = [];

  try {
    for (const file of files) {
      const raw = fs.readFileSync(file.abs);
      if (raw.length > 0xfffffffe) throw new Error(`File too large for a plain zip: ${file.abs}`);

      // Deflate, but store the bytes as-is when that is not smaller
      // (png/ogg are already compressed).
      const deflated = zlib.deflateRawSync(raw, { level: 9 });
      const stored = deflated.length >= raw.length;
      const data = stored ? raw : deflated;
      const method = stored ? 0 : 8;

      const name = Buffer.from(file.rel, "utf8");
      const { time, date } = dosDateTime(fs.statSync(file.abs).mtime);
      const crc = crc32(raw);

      const local = Buffer.alloc(30);
      local.writeUInt32LE(0x04034b50, 0);
      local.writeUInt16LE(20, 4); // version needed
      local.writeUInt16LE(0x0800, 6); // flags: UTF-8 names
      local.writeUInt16LE(method, 8);
      local.writeUInt16LE(time, 10);
      local.writeUInt16LE(date, 12);
      local.writeUInt32LE(crc, 14);
      local.writeUInt32LE(data.length, 18);
      local.writeUInt32LE(raw.length, 22);
      local.writeUInt16LE(name.length, 26);
      local.writeUInt16LE(0, 28); // extra length

      central.push({ name, method, time, date, crc, csize: data.length, usize: raw.length, offset });
      write(local);
      write(name);
      write(data);
    }

    const centralStart = offset;
    for (const c of central) {
      const h = Buffer.alloc(46);
      h.writeUInt32LE(0x02014b50, 0);
      h.writeUInt16LE(20, 4); // version made by
      h.writeUInt16LE(20, 6); // version needed
      h.writeUInt16LE(0x0800, 8);
      h.writeUInt16LE(c.method, 10);
      h.writeUInt16LE(c.time, 12);
      h.writeUInt16LE(c.date, 14);
      h.writeUInt32LE(c.crc, 16);
      h.writeUInt32LE(c.csize, 20);
      h.writeUInt32LE(c.usize, 24);
      h.writeUInt16LE(c.name.length, 28);
      // extra, comment, disk, internal attrs, external attrs: all zero
      h.writeUInt32LE(c.offset, 42);
      write(h);
      write(c.name);
    }

    const centralSize = offset - centralStart;
    const end = Buffer.alloc(22);
    end.writeUInt32LE(0x06054b50, 0);
    end.writeUInt16LE(central.length, 8);
    end.writeUInt16LE(central.length, 10);
    end.writeUInt32LE(centralSize, 12);
    end.writeUInt32LE(centralStart, 16);
    write(end);
  } finally {
    fs.closeSync(fd);
  }
}

// ------------------------------------------------- versioned archive

// Creates assets/version/v<BP>__<RP>__<index>/ (next unused index for
// this exact version pair) and writes the zip into it as
// fileNameFor(<folder name>). Never touches an existing folder, and a
// failed run leaves nothing behind. Returns the path of the new file.
export function writeVersionedArchive({ out, bpVersion, rpVersion, files, fileNameFor }) {
  const prefix = `v${bpVersion}__${rpVersion}__`;
  const index = nextIndex(out, prefix);
  const releaseName = `${prefix}${index}`;
  const releaseDir = path.join(out, releaseName);
  const finalPath = path.join(releaseDir, fileNameFor(releaseName));

  console.log(`Packing ${files.length} file(s) ...`);

  // Write to a temp name and rename, so a failed run never leaves a
  // half-written archive (or an empty release folder) behind.
  if (fs.existsSync(releaseDir)) fail(`Release folder already exists: ${releaseDir}`);
  fs.mkdirSync(releaseDir, { recursive: true });
  const tempPath = `${finalPath}.tmp`;
  try {
    writeZip(tempPath, files);
    fs.renameSync(tempPath, finalPath);
  } catch (err) {
    fs.rmSync(releaseDir, { recursive: true, force: true });
    fail(err.message);
  }

  const kb = (fs.statSync(finalPath).size / 1024).toFixed(1);
  console.log(`\nCreated: ${finalPath}  (${kb} KB)`);
  return finalPath;
}
