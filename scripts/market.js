// scripts/market.js
//
// Packs a built behavior pack and resource pack into ONE .zip whose only
// root folder is "Content", the layout used to submit to the Marketplace:
//
//   Content/behavior_packs/<behavior pack folder>/...
//   Content/resource_packs/<resource pack folder>/...
//
// The zip is filed exactly like scripts/release.js files its .mcaddon: in
// a NEW sub-directory of assets/version/, named from the two pack
// versions plus the next unused index for that version pair. The two
// scripts share the counter, so a release and a market zip made from the
// same versions land in ..__0 and ..__1, never in the same folder.
//
//   assets/version/v<BP>__<RP>__<index>/<ProjectName>_<version>.zip
//
// <ProjectName> is PROJECT_NAME_DEFAULT in batchs/build.bat with every
// space and underscore removed, and <version> is the text you give with
// --version (any label made of letters, digits and . _ + -). It is only
// used for the file name; the folder name still comes from the manifests.
// Example: "My Addon Project Source" + 1.2.0 gives
//   assets/version/v1.0.1__1.0.2__0/MyAddonProjectSource_1.2.0.zip
//
// Point it at BUILT packs (namespace renamed, dev files removed), not the
// raw sources/ folders. batchs/market.bat builds them into a scratch
// folder and then calls this script.
//
// Usage:
//   node scripts/market.js --bp <behavior pack dir> --rp <resource pack dir>
//                          --version <label>
//                          [--out <dir, default: <project>/assets/version>]
//                          [--name <project name, default: from build.bat>]
//   node scripts/market.js --check-version <label>    (validate and exit)

import path from "path";
import {
  BUILD_BAT,
  DEFAULT_OUT,
  collectFiles,
  fail,
  projectNameFromBuildBat,
  readVersion,
  setLabel,
  writeVersionedArchive,
} from "./lib/pack-tools.js";

setLabel("Market zip");

const VERSION_PATTERN = /^[0-9A-Za-z][0-9A-Za-z._+-]*$/;

function checkVersionLabel(version) {
  if (!VERSION_PATTERN.test(version)) {
    fail(
      `"${version}" is not a usable version. Use letters, digits and . _ + - only ` +
        `(for example 1.0.0), starting with a letter or digit.`,
    );
  }
}

// Project name as the Marketplace file name wants it: no spaces, no
// underscores, and nothing Windows rejects in a file name.
function marketProjectName(name) {
  return name
    .replace(/[\s_<>:"/\\|?*\u0000-\u001f]/g, "")
    .replace(/\.+$/, "");
}

// ---------------------------------------------------------------- args

function parseArgs(argv) {
  const args = { bp: null, rp: null, out: DEFAULT_OUT, name: null, version: null, checkOnly: false };
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    if (flag === "--bp" || flag === "--rp" || flag === "--out") {
      const value = argv[++i];
      if (!value) fail(`${flag} needs a value.`);
      args[flag.slice(2)] = path.resolve(value);
    } else if (flag === "--name" || flag === "--version" || flag === "--check-version") {
      const value = argv[++i];
      if (!value) fail(`${flag} needs a value.`);
      if (flag === "--check-version") {
        args.version = value;
        args.checkOnly = true;
      } else {
        args[flag.slice(2)] = value;
      }
    } else {
      fail(`Unknown argument: ${flag}`);
    }
  }
  return args;
}

// ----------------------------------------------------------------- main

function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.checkOnly) {
    checkVersionLabel(args.version);
    return;
  }
  if (!args.bp || !args.rp || !args.version) {
    fail(
      "Usage: node scripts/market.js --bp <behavior pack dir> --rp <resource pack dir> " +
        "--version <label> [--out <dir>] [--name <project name>]",
    );
  }
  const { bp, rp, out, name, version } = args;
  checkVersionLabel(version);

  const projectName = marketProjectName(name ?? projectNameFromBuildBat() ?? "");
  if (!projectName) {
    fail(`No project name found in ${BUILD_BAT} to name the zip after. Pass --name <project name>.`);
  }

  const bpName = path.basename(bp);
  const rpName = path.basename(rp);
  const bpVersion = readVersion(bp, "Behavior pack");
  const rpVersion = readVersion(rp, "Resource pack");

  const files = [
    ...collectFiles(bp, `Content/behavior_packs/${bpName}`),
    ...collectFiles(rp, `Content/resource_packs/${rpName}`),
  ];
  if (files.length === 0) fail("Both pack folders are empty.");

  console.log(`Behavior pack : ${bp}  (v${bpVersion})`);
  console.log(`Resource pack : ${rp}  (v${rpVersion})`);

  writeVersionedArchive({
    out,
    bpVersion,
    rpVersion,
    files,
    fileNameFor: () => `${projectName}_${version}.zip`,
  });
}

main();
