// scripts/release.js
//
// Packs a built behavior pack and resource pack into ONE .mcaddon file
// and files it under assets/version/, in a sub-directory named after the
// two pack versions plus a running index:
//
//   assets/version/v<BP>__<RP>__<index>/<project name> - v<BP>__<RP>__<index>.mcaddon
//
// The project name is PROJECT_NAME_DEFAULT in batchs/build.bat. Example:
// BP 1.0.1 + RP 1.0.2 with the project name "My Addon" gives
//   assets/version/v1.0.1__1.0.2__0/My Addon - v1.0.1__1.0.2__0.mcaddon
//
// Every run creates a NEW sub-directory. The index is the next unused
// number for that exact BP/RP version pair (0, 1, 2, ...), so releasing
// again without touching either version gives ..__1, ..__2 and so on.
// As soon as the BP or RP version in its manifest.json changes, the pair
// is new and the index starts again at 0. Nothing already in
// assets/version is ever overwritten or deleted. (scripts/market.js uses
// the same folders and the same counter.)
//
// The versions come from "header.version" in the manifest.json of the
// folders being packed, so the packs you point this at should be BUILT
// ones (namespace renamed, JSON obfuscated, dev files removed), not the
// raw sources/ folders. batchs/release.bat builds exactly that into a
// scratch folder and then calls this script.
//
// A .mcaddon is a plain zip with each pack folder at its root.
//
// Usage:
//   node scripts/release.js --bp <behavior pack dir> --rp <resource pack dir>
//                           [--out <dir, default: <project>/assets/version>]
//                           [--name <project name, default: from build.bat>]

import path from "path";
import {
  BUILD_BAT,
  DEFAULT_OUT,
  collectFiles,
  fail,
  projectNameFromBuildBat,
  readVersion,
  toFileName,
  writeVersionedArchive,
} from "./lib/pack-tools.js";

// ---------------------------------------------------------------- args

function parseArgs(argv) {
  const args = { bp: null, rp: null, out: DEFAULT_OUT, name: null };
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    if (flag === "--bp" || flag === "--rp" || flag === "--out") {
      const value = argv[++i];
      if (!value) fail(`${flag} needs a value.`);
      args[flag.slice(2)] = path.resolve(value);
    } else if (flag === "--name") {
      const value = argv[++i];
      if (!value) fail("--name needs a value.");
      args.name = value;
    } else {
      fail(`Unknown argument: ${flag}`);
    }
  }
  if (!args.bp || !args.rp) {
    fail("Usage: node scripts/release.js --bp <behavior pack dir> --rp <resource pack dir> [--out <dir>] [--name <project name>]");
  }
  return args;
}

// ----------------------------------------------------------------- main

function main() {
  const { bp, rp, out, name } = parseArgs(process.argv.slice(2));

  const bpName = path.basename(bp);
  const rpName = path.basename(rp);
  if (bp === rp || bpName.toLowerCase() === rpName.toLowerCase()) {
    fail(`The behavior and resource pack folders need different names (both are "${bpName}").`);
  }

  const bpVersion = readVersion(bp, "Behavior pack");
  const rpVersion = readVersion(rp, "Resource pack");

  // "<project name> - <version folder name>"; just the folder name when
  // no project name can be found.
  const projectName = toFileName(name ?? projectNameFromBuildBat() ?? "");
  if (!projectName) {
    console.warn(`Note: no project name found in ${BUILD_BAT}; naming the file after the folder only.`);
  }

  const files = [...collectFiles(bp, bpName), ...collectFiles(rp, rpName)];
  if (files.length === 0) fail("Both pack folders are empty.");

  console.log(`Behavior pack : ${bp}  (v${bpVersion})`);
  console.log(`Resource pack : ${rp}  (v${rpVersion})`);

  writeVersionedArchive({
    out,
    bpVersion,
    rpVersion,
    files,
    fileNameFor: (releaseName) =>
      `${projectName ? `${projectName} - ` : ""}${releaseName}.mcaddon`,
  });
}

main();
