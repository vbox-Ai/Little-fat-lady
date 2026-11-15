#!/usr/bin/env node
// scripts/bump-version.mjs —— 版本递增。VERSION = MAJOR.MINOR.PATCH；deb 版本 = <VERSION>-<BUILD>
// 用法：node scripts/bump-version.mjs --patch|--minor|--major [--dry]
// BUILD 由 CI 取 `git rev-list --count HEAD`（本地无 git 时留空，只打点说明）。
import { readFileSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';

const ROOT = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const p = ROOT + '/VERSION';

const args = process.argv.slice(2);
const kind = args.find((a) => ['--patch', '--minor', '--major'].includes(a));
const dry = args.includes('--dry');
if (!kind) {
  console.error('用法：node scripts/bump-version.mjs --patch|--minor|--major [--dry]');
  process.exit(2);
}

const cur = readFileSync(p, 'utf8').trim();
const m = cur.match(/^(\d+)\.(\d+)\.(\d+)$/);
if (!m) { console.error(`VERSION 格式错：${cur}`); process.exit(1); }
let [maj, min, pat] = [Number(m[1]), Number(m[2]), Number(m[3])];
if (kind === '--major') { maj += 1; min = 0; pat = 0; }
if (kind === '--minor') { min += 1; pat = 0; }
if (kind === '--patch') { pat += 1; }
const next = `${maj}.${min}.${pat}`;

let build = '';
try { build = execSync('git rev-list --count HEAD', { cwd: ROOT, stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(); }
catch { build = 'local'; }

console.log(`${cur} -> ${next}`);
console.log(`deb Version: ${next}-${build}`);
if (!dry) { writeFileSync(p, next + '\n', 'utf8'); console.log('已写入 VERSION'); }
else console.log('--dry：未写入');
