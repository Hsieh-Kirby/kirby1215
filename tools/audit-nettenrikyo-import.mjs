import fs from 'node:fs';
import path from 'node:path';

const project = path.resolve(process.argv[2] || '.');
const archiveRoot = path.join(project, 'content', 'archive');
const sourceRoot = path.join(project, 'nettenrikyo');

function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(directory, entry.name);
    return entry.isDirectory() ? walk(full) : [full];
  });
}

function cleanHtml(text) {
  return text.replace(/<script\b[\s\S]*?<\/script>/gi, '')
    .replace(/<style\b[\s\S]*?<\/style>/gi, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;|&#160;/gi, ' ')
    .replace(/&[a-z0-9#]+;/gi, ' ')
    .replace(/\s+/g, ' ').trim();
}

const pages = walk(archiveRoot).filter((file) => file.endsWith('.md') && path.basename(file) !== '_index.md');
const findings = { indentedHtml: [], leakedShell: [], missingAsset: [], privacy: [], suspiciousLoss: [] };

for (const file of pages) {
  const markdown = fs.readFileSync(file, 'utf8');
  const body = markdown.split(/^---\s*$/m).slice(2).join('---').trim();
  const source = markdown.match(/^legacy_original_path:\s*"([^"]+)"/m)?.[1] || '';
  if (/^ {4,}</m.test(body)) findings.indentedHtml.push(source);
  if (/<(?:html|head|body)\b/i.test(body)) findings.leakedShell.push(source);
  if (markdown.includes('謝匡宇')) findings.privacy.push(source);
  for (const match of body.matchAll(/\/legacy\/nettenrikyo\/([^"' )>]+)/g)) {
    const target = path.join(sourceRoot, ...decodeURI(match[1]).split('/'));
    if (!fs.existsSync(target)) findings.missingAsset.push(`${source} -> ${match[1]}`);
  }
  if (source.endsWith('.html')) {
    const original = fs.readFileSync(path.join(sourceRoot, ...source.split('/')), 'utf8');
    const cells = [...original.matchAll(/<td\b[^>]*>([\s\S]*?)<\/td>/gi)];
    const main = cells.sort((a, b) => cleanHtml(b[1]).length - cleanHtml(a[1]).length)[0]?.[1] || original;
    const oldLength = cleanHtml(main).length;
    const newLength = cleanHtml(body).length;
    if (oldLength > 300 && newLength / oldLength < 0.7) {
      findings.suspiciousLoss.push(`${source} (${oldLength} -> ${newLength})`);
    }
  }
}

console.log(`Audited ${pages.length} archive pages`);
for (const [name, values] of Object.entries(findings)) {
  console.log(`${name}: ${values.length}`);
  for (const value of values.slice(0, 20)) console.log(`  ${value}`);
}

if (findings.indentedHtml.length || findings.leakedShell.length || findings.missingAsset.length || findings.privacy.length || findings.suspiciousLoss.length) process.exitCode = 1;
