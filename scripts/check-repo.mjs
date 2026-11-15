#!/usr/bin/env node
// scripts/check-repo.mjs —— 仓库自检。阶段闸门第①步跑这个，必须 exit 0。
// 用法：node scripts/check-repo.mjs
import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { join, relative, extname } from 'node:path';

const ROOT = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const fails = [];
const notes = [];
const ok = (m) => notes.push('  ok   ' + m);
const bad = (m) => fails.push(m);

// 1) 必需文件
const REQUIRED = [
  'README.md', 'LICENSE', 'LICENSE-ASSETS', 'CREDITS.md',
  'AGENTS.md', 'MEMORY.md', 'VERSION', '.gitignore',
  'docs/PLAN.md', 'docs/journal/README.md', 'docs/journal/S00.md',
  'scripts/check-repo.mjs', 'scripts/bump-version.mjs',
  '.github/workflows/ci.yml', '.github/workflows/release.yml',
];
for (const f of REQUIRED) {
  existsSync(join(ROOT, f)) ? ok(f) : bad(`缺文件：${f}`);
}

// 2) VERSION 格式
let ver = '';
try {
  ver = readFileSync(join(ROOT, 'VERSION'), 'utf8').trim();
  /^\d+\.\d+\.\d+$/.test(ver) ? ok(`VERSION=${ver}`) : bad(`VERSION 格式错：${ver}（要 MAJOR.MINOR.PATCH）`);
} catch { bad('VERSION 读不到'); }

// 3) 方案版本 vs 仓库 VERSION 的两条独立事实（不允许混用）
try {
  const plan = readFileSync(join(ROOT, 'docs/PLAN.md'), 'utf8');
  const m = plan.match(/开发方案 v(\d+\.\d+)/);
  m ? ok(`PLAN=v${m[1]}（与 VERSION 无关，别混）`) : bad('PLAN 里找不到「开发方案 vX.Y」');
  if (!plan.includes('## 20 阶段关闭闸门')) bad('PLAN 缺 §20 阶段闸门');
} catch { bad('docs/PLAN.md 读不到'); }

// 4) 素材不许入库
const FORBIDDEN_DIRS = ['assets/webm', 'assets/mov', 'assets/memes'];
for (const d of FORBIDDEN_DIRS) {
  if (existsSync(join(ROOT, d))) bad(`素材目录不该入库：${d}（见 LICENSE-ASSETS §3）`);
}

// 5) 凭据扫描 + 体积扫描
const SKIP = new Set(['.git', 'node_modules', '.theos', 'build', 'out', 'dist']);
const SECRET_RE = /(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,})/;
const MAX_BYTES = 5 * 1024 * 1024;
let scanned = 0;
(function walk(dir) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (SKIP.has(e.name)) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) { walk(p); continue; }
    const st = statSync(p);
    if (st.size > MAX_BYTES) { bad(`文件过大（>5MB）：${relative(ROOT, p)}`); continue; }
    if (['.md', '.mjs', '.js', '.yml', '.yaml', '.sh', '.json', '.txt', ''].includes(extname(p))) {
      const txt = readFileSync(p, 'utf8');
      if (SECRET_RE.test(txt)) bad(`疑似凭据写入：${relative(ROOT, p)}`);
      scanned++;
    }
  }
})(ROOT);
ok(`扫描 ${scanned} 个文本文件，无凭据`);

// 6) journal 六段（每个 S*.md 都要 ≥6 个编号小节，且末段是「下一步」）
try {
  const jdir = join(ROOT, 'docs/journal');
  const files = readdirSync(jdir).filter((f) => /^S\d+\.md$/.test(f)).sort();
  if (!files.length) bad('docs/journal 下没有任何 S*.md');
  for (const f of files) {
    const body = readFileSync(join(jdir, f), 'utf8');
    const nums = new Set([...body.matchAll(/^##\s*(\d+)[.、\s]/gm)].map((m) => m[1]));
    if (nums.size < 6) bad(`${f} 编号小节只有 ${nums.size} 段（需 ≥6）`);
    if (!/下一步/.test(body)) bad(`${f} 缺「下一步」`);
    ok(`${f} ${nums.size} 段齐`);
  }
} catch (e) { bad(`journal 检查失败：${e.message}`); }

// 输出
console.log('check-repo:');
for (const n of notes) console.log(n);
if (fails.length) {
  console.log('\nFAIL:');
  for (const f of fails) console.log('  x   ' + f);
  process.exit(1);
}
console.log(`\nPASS  VERSION=${ver}  files_ok=${notes.length}`);
