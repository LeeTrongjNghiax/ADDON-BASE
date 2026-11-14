# Bedrock Addon Template

Source for a Minecraft Bedrock behavior pack and resource pack. You edit readable files under `sources/`. A build stages a copy, drops tooling files and folders, renames the `your_namespace` placeholder, obfuscates JSON, and copies the finished packs to Minecraft or an output folder. Translation is a separate step that writes `.lang` files back into the source tree.

Requires Windows (the deploy scripts use `cmd`, PowerShell, and `robocopy`) and Node.js 18+.

## Layout

```
sources/behavior_packs/bp/     behavior pack (manifest, entities, scripts, …)
sources/resource_packs/rp/     resource pack (textures, models, texts, …)
sources/behavior_packs/bp/sources/   TypeScript gameplay scripts
batchs/                        build, deploy, and translate scripts
scripts/                       translate-lang.js, obfuscate-json.js
```

Author identifiers, file names, and folders with the placeholder `your_namespace` (for example `your_namespace:custom_block`, or a folder named `your_namespace`). The build replaces that text in file contents, file names, and folder names.

Gameplay scripts live in `sources/behavior_packs/bp/sources/` and bundle to `scripts/index.js`, which is the script module entry in the behavior pack manifest.

## Setup

```bat
npm install
copy .env.example .env
```

Put a Gemini API key in `.env` if you will translate lang files. A free key is available at https://aistudio.google.com/apikey. `.env` is gitignored.

Before you ship a pack, give the behavior pack and resource pack their own UUIDs in `manifest.json`, and point each pack’s dependency UUID at the other pack. Pack display names come from `texts/en_US.lang` (`pack.name`, `pack.description`).

Then set the project defaults at the top of `batchs/build.bat`:

| Setting | What it controls |
| --- | --- |
| `NAMESPACE_DEFAULT` | Text that replaces `your_namespace` when you press Enter at the prompt. Default `acme_addon`. |
| `PROJECT_NAME_DEFAULT` | Folder name used by the dev and live copy profiles (`My Addon Project Source BP` / `RP`). |
| `BP_PROFILE_*` / `RP_PROFILE_*` | Where each pack is copied. |
| `EXCLUDE_DIRS` / `EXCLUDE_FILES` | Folders and files left out of the shipped copy. |
| `ENABLE_JSON_OBFUSCATION` | `1` obfuscates JSON in the staged copy. `0` leaves JSON readable. |
| `PLACEHOLDER_NAMESPACE` | Search text. Leave this as `your_namespace` unless you change the placeholder in source. |

`dev.bat` and `output.bat` pass the namespace with `/NS:`. Change `rl_yn` in both files to the namespace you actually ship.

## Commands

| Command | What it does |
| --- | --- |
| `npm run bundle` | Bundles and minifies `bp/sources/index.ts` to `bp/scripts/index.js`. |
| `npm run dev` | Bundles, then copies both packs to the **dev** profile with `/NS:rl_yn`. |
| `npm run output` | Bundles, then copies both packs to the **output** profile with `/NS:rl_yn`. |
| `npm run build` | Bundles, then opens `build.bat` so you can pick profiles and a namespace. |
| `npm run watch` | Re-runs `npm run dev` when files under `bp` or `rp` change. |
| `npm run translate` | Translates `en_US.lang` into the locale list and updates `languages.json`. |
| `npm run zip` | Zips a behavior pack and a resource pack into one archive. See [Zip](#zip). |

`npm run dev`, `npm run output`, and `npm run build` launch the batch files only. After you change TypeScript under `bp/sources/`, run `npm run bundle` before a deploy so `scripts/index.js` is current. `npm run watch` repeats `npm run dev` and does not bundle on its own.

## Build pipeline

`batchs/build.bat` is the deploy script. `dev.bat` and `output.bat` call it with switches so they skip every prompt.

1. **Stage.** Copies `sources/behavior_packs/bp` and `sources/resource_packs/rp` into a temp folder. The folders under `sources/` stay as you wrote them.
2. **Drop unused files and folders.** `robocopy` applies `EXCLUDE_DIRS` and `EXCLUDE_FILES`, so git metadata, `node_modules`, this repo’s `sources` and `batchs` trees, configs, and `*.md` / `*.zip` / `*.mcpack` never land in the pack.
3. **Rename the namespace.** `batchs/rename-namespace.ps1` replaces `your_namespace` inside file contents, then renames files and folders whose names contain it. Deepest folders are renamed first. Images, audio, fonts, and archives (`.png`, `.ogg`, `.ttf`, `.zip`, `.mcpack`, and the rest of the skip list in that script) are left byte-for-byte. `.mcstructure` is not on that list, so a structure file whose bytes contain the placeholder text is rewritten as UTF-8.
4. **Obfuscate JSON.** `scripts/obfuscate-json.js` minifies every `.json` file in the staged packs and rewrites keys and string values as `\uXXXX` escapes. Numbers, booleans, and `null` stay literal. Each file is parsed back and compared to the original; a file that does not round-trip is left unchanged and reported. `//` and `/* */` comments outside strings are stripped before parse. Set `ENABLE_JSON_OBFUSCATION=0` in `build.bat` to skip this step.
5. **Copy the packs.** Copies the staged behavior pack and resource pack into the profiles you selected, then deletes the temp folder.

One-click mode (answering `Y`, or passing any of `/BP:`, `/RP:`, `/NS:`) deletes an existing destination folder and copies over it. Manual mode asks before that delete.

### Profiles

Each pack has its own list in `build.bat`. The defaults are:

| # | Name | Behavior pack parent | Resource pack parent | Copied folder name |
| --- | --- | --- | --- | --- |
| 1 | dev | `C:\Users\Admin\AppData\Roaming\Minecraft Bedrock\Users\Shared\games\com.mojang\development_behavior_packs` | `...\development_resource_packs` | `My Addon Project Source BP` / `RP` |
| 2 | live | `...\com.mojang\behavior_packs` | `...\com.mojang\resource_packs` | same display name |
| 3 | output | `C:\My Addon Project Source\Content\behavior_packs` | `...\Content\resource_packs` | `<namespace>_b` / `<namespace>_r` |

Those `com.mojang` paths are written for the `Admin` Windows user. Point `BP_PROFILE_*_PARENT` and `RP_PROFILE_*_PARENT` at your own Minecraft folders.

Profile 3’s folder name is filled from the `/NS:` switch (`rl_yn_b`, `rl_yn_r` with the wrappers). A namespace typed at the interactive prompt updates file contents and file names; it does not rewrite those profile-3 folder names, because they are set from `/NS:` when the script starts.

`dev.bat` runs:

```bat
build.bat /BP:1 /RP:1 /NS:rl_yn
```

`output.bat` runs:

```bat
build.bat /BP:3 /RP:3 /NS:rl_yn
```

Selection values are profile numbers, `ALL`, or a comma list such as `/BP:1,3`. A pack with no `/BP:` or `/RP:` switch uses profile 1.

### Files and folders left out of the copy

Default `EXCLUDE_DIRS`:

`.git` `.github` `.husky` `batchs` `douments` `node_modules` `sources` `.vscode`

Default `EXCLUDE_FILES`:

`.gitignore` `.mcignore` `.prettierignore` `.prettierrc` `build.js` `commitlint.config.cjs` `eslint.config.ts` `package-lock.json` `package.json` `tsconfig.json` `*.zip` `*.md` `*.mcpack`

Add a name to those lists when a new tooling file should stay out of the shipped pack. The same lists are applied again when the staged copy is copied to a destination.

## Translation

`npm run translate` (or `batchs\translate-lang.bat`) reads `en_US.lang`, writes one `.lang` file per target locale, and rewrites `languages.json` in that texts folder so every locale is listed.

Defaults in the batch file:

- Source locale: `en_US`
- Texts folder: `sources\resource_packs\rp\texts` (the behavior pack texts folder is commented in the script; add it to `TEXTS_DIRS_DEFAULT`, separated by `;`, when BP strings should be translated too)
- Protected words, left in the source language: `RP` `BP`
- Locales: `en_GB de_DE es_ES es_MX fr_FR fr_CA it_IT ja_JP ko_KR pt_BR pt_PT ru_RU zh_CN zh_TW nl_NL bg_BG cs_CZ da_DK el_GR fi_FI hu_HU id_ID nb_NO pl_PL sk_SK sv_SE tr_TR uk_UA`

`scripts/translate-lang.js` sends strings to Gemini (`gemini-2.5-flash`, 40 strings per request) using `GEMINI_API_KEY`. Minecraft formatting codes and `~LINEBREAK~` tokens stay in place. `en_GB` is copied from the source because the target language is English. Answering `Y` at the first prompt uses every default; otherwise each value can be overridden, and Enter keeps the value in brackets.

Optional `.env` overrides: `GEMINI_MODEL`, `GEMINI_BATCH_SIZE`, `GEMINI_REQUEST_DELAY_MS` (default delay 4500 ms, to stay under free-tier rate limits).

## Zip

`batchs\zip.bat` stages a behavior pack and a resource pack with its own exclude lists, zips the contents of each (no wrapping `bp` or `rp` folder), and puts `bp.zip` and `rp.zip` inside one archive. Default destination is `C:\My Addon Project`, filename `My Addon Project.zip`.

The default source paths are `behavior_packs\bp` and `resource_packs\rp` next to the batch file. This template keeps packs under `sources\`, so at the prompts set Folder A to `..\sources\behavior_packs` and Folder B to `..\sources\resource_packs`, or change `FOLDER_A_NAME_DEFAULT` and `FOLDER_B_NAME_DEFAULT` in `zip.bat`. The zip step does not rename the namespace or obfuscate JSON; run `output` when you want the processed packs, and zip that output if you need an archive of the shipped files.
