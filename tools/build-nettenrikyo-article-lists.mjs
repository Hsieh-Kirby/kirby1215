import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(process.argv[2] || 'nettenrikyo');
const outputDir = path.join(root, '_organizing');

const categories = [
  ['01-三原典', '三原典'],
  ['02-教理', '教理'],
  ['03-演講稿', '演講稿'],
  ['04-文章與翻譯', '文章與翻譯'],
  ['05-個人札記與系列', '個人札記與系列'],
  ['06-學習資源', '學習資源'],
];

const landingPages = [
  'index.html', 'triple.html', 'teaching.html', 'speech.html', 'article.html', 'resource.html',
  'window/window.html', 'article/article-chi.html', 'article/article-chi-2.html',
  'article/article-chi-3.html', 'article/nishi/nishi.html', 'teaching/teaching-doctrine.html',
  'teaching/teaching-itsuwa.html', 'triple/fude/fude.html', 'triple/uta/uta.html',
].filter((relative) => fs.existsSync(path.join(root, relative)));
const genericTitles = new Set(['教理學習', '參考資料', '文章列表', '']);
const publicText = (value) => String(value || '').replaceAll('謝匡宇', '謝科比');
const indexPages = new Set([
  'article/article-chi.html', 'article/article-chi-2.html', 'article/article-chi-3.html',
  'article/nishi/nishi.html', 'teaching/teaching-doctrine.html', 'teaching/teaching-itsuwa.html',
  'triple/fude/fude.html', 'triple/uta/uta.html',
]);

function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    if (entry.name.startsWith('_')) return [];
    const full = path.join(directory, entry.name);
    return entry.isDirectory() ? walk(full) : [full];
  });
}

function decode(text) {
  const entities = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };
  return text
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&([a-z]+);/gi, (_, name) => entities[name.toLowerCase()] ?? `&${name};`);
}

function cleanHtml(text) {
  return decode(text.replace(/<br\s*\/?\s*>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim());
}

function normalizeLink(baseRelative, href) {
  const withoutFragment = href.split('#')[0].split('?')[0].replaceAll('\\', '/');
  if (!withoutFragment || /^(?:https?:|mailto:|javascript:|\/\/|file:)/i.test(withoutFragment)) return null;
  return path.posix.normalize(path.posix.join(path.posix.dirname(baseRelative), withoutFragment));
}

function readText(file) {
  return fs.readFileSync(file, 'utf8');
}

const linkTitles = new Map();
for (const landing of landingPages) {
  const html = readText(path.join(root, landing));
  for (const match of html.matchAll(/<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)) {
    const target = normalizeLink(landing, match[1]);
    const title = cleanHtml(match[2]);
    if (target && title && !linkTitles.has(target)) linkTitles.set(target, title);
  }
}

function extractTitle(html, relative) {
  const linked = linkTitles.get(relative);
  if (linked && !['首頁', '三原典', '演講稿', '教理', '文章', '學習資源'].includes(linked)) return linked;
  const documentTitle = cleanHtml(html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] || '');
  if (!genericTitles.has(documentTitle)) return documentTitle;
  const centered = [...html.matchAll(/<p\b[^>]*align\s*=\s*["']?center["']?[^>]*>([\s\S]*?)<\/p>/gi)]
    .map((match) => cleanHtml(match[1]))
    .find((text) => text && text.length <= 120 && !/首頁|三原典.*演講稿|返回.*目錄/.test(text));
  const fallbackTitles = {
    'triple/triple-sashizu.html': '御指圖',
    'triple/triple-uta.html': '神樂歌',
  };
  if (centered && /[\p{L}\p{N}]/u.test(centered)) return centered;
  return fallbackTitles[relative] || path.posix.basename(relative, path.posix.extname(relative));
}

function extractAuthor(html) {
  const rightAligned = [...html.matchAll(/<p\b[^>]*align\s*=\s*["']?right["']?[^>]*>([\s\S]*?)<\/p>/gi)]
    .map((match) => cleanHtml(match[1]))
    .find((text) => text && text.length <= 60 && !/回首頁|更新|瀏覽/.test(text));
  return rightAligned || '';
}

function classify(relative) {
  if (relative.startsWith('triple/')) {
    if (relative.startsWith('triple/fude/')) return ['01-三原典', '御筆先'];
    if (relative.startsWith('triple/uta/')) return ['01-三原典', '神樂歌'];
    return ['01-三原典', '其他原典資料'];
  }
  if (relative.startsWith('teaching/')) {
    if (relative.startsWith('teaching/itsuwa/')) return ['02-教理', '教祖傳逸話篇'];
    if (relative.startsWith('teaching/doctrine/')) return ['02-教理', '教典'];
    return ['02-教理', '教理文章與資料'];
  }
  if (relative.startsWith('speech/')) return ['03-演講稿', '神殿講話與講演'];
  if (relative.startsWith('article/')) {
    if (relative.startsWith('article/nishi/')) return ['04-文章與翻譯', '黃登洲會長系列'];
    if (relative.startsWith('article/chi')) return ['04-文章與翻譯', '歷年中文文章'];
    return ['04-文章與翻譯', '文章、心得與翻譯'];
  }
  if (relative.startsWith('window/')) return ['05-個人札記與系列', '版主小窗'];
  if (relative.startsWith('happy/')) return ['05-個人札記與系列', '康樂生活系列'];
  if (relative.startsWith('files/')) return ['06-學習資源', '下載資料'];
  return null;
}

const allowedExtensions = new Set(['.html', '.pdf', '.docx', '.pptx']);
const rows = [];
for (const full of walk(root)) {
  const relative = path.relative(root, full).replaceAll('\\', '/');
  const extension = path.extname(relative).toLowerCase();
  const classification = classify(relative);
  if (!classification || !allowedExtensions.has(extension)) continue;
  if (indexPages.has(relative) || /(?:^|[/(])old(?:\)|\.|-)/i.test(relative) || relative.includes('/file/')) continue;
  const html = extension === '.html' ? readText(full) : '';
  rows.push({
    category: classification[0],
    subcategory: classification[1],
    title: publicText(html ? extractTitle(html, relative) : path.posix.basename(relative, extension)),
    author: publicText(html ? extractAuthor(html) : ''),
    source_path: relative,
    status: '檔案存在',
  });
}

// The speech directory is absent from this export. Preserve the titles and paths
// listed on speech.html so the missing source material remains visible.
for (const [relative, title] of linkTitles) {
  if (!relative.startsWith('speech/') || rows.some((row) => row.source_path === relative)) continue;
  rows.push({
    category: '03-演講稿', subcategory: '神殿講話與講演', title, author: '',
    source_path: relative, status: '缺少原始檔',
  });
}

rows.sort((a, b) => a.category.localeCompare(b.category, 'zh-Hant')
  || a.subcategory.localeCompare(b.subcategory, 'zh-Hant')
  || a.source_path.localeCompare(b.source_path, 'en', { numeric: true }));

function csvCell(value) {
  return `"${String(value).replaceAll('"', '""')}"`;
}

const csv = [Object.keys(rows[0]).map(csvCell).join(','), ...rows.map((row) => Object.values(row).map(csvCell).join(','))].join('\r\n') + '\r\n';
fs.mkdirSync(outputDir, { recursive: true });
fs.writeFileSync(path.join(outputDir, 'article-list.csv'), `\ufeff${csv}`, 'utf8');

const lines = [
  '# nettenrikyo 分類文章列表', '',
  '> 這是未來整合進 Kirby 前的內容目錄。原始檔案尚未搬動；「缺少原始檔」代表舊分類頁有連結，但本次資料沒有對應檔案。', '',
];
const listDir = path.join(outputDir, 'lists');
fs.mkdirSync(listDir, { recursive: true });
for (const [category, heading] of categories) {
  const categoryRows = rows.filter((row) => row.category === category);
  const sectionLines = [
    `# ${heading}文章列表`, '',
    `共 ${categoryRows.length} 筆。原始檔案尚未搬動；路徑均以 \`nettenrikyo/\` 為起點。`, '',
  ];
  lines.push(`## ${heading}（${categoryRows.length}）`, '');
  for (const subcategory of [...new Set(categoryRows.map((row) => row.subcategory))]) {
    const subRows = categoryRows.filter((row) => row.subcategory === subcategory);
    const tableHeader = ['| 標題 | 作者／譯者 | 原始路徑 | 狀態 |', '|---|---|---|---|'];
    lines.push(`### ${subcategory}（${subRows.length}）`, '', ...tableHeader);
    sectionLines.push(`## ${subcategory}（${subRows.length}）`, '', ...tableHeader);
    for (const row of subRows) {
      const values = [row.title, row.author, `\`${row.source_path}\``, row.status].map((value) => String(value).replaceAll('|', '\\|'));
      const tableRow = `| ${values.join(' | ')} |`;
      lines.push(tableRow);
      sectionLines.push(tableRow);
    }
    lines.push('');
    sectionLines.push('');
  }
  fs.writeFileSync(path.join(listDir, `${category}.md`), sectionLines.join('\n'), 'utf8');
}
fs.writeFileSync(path.join(outputDir, '分類文章列表.md'), lines.join('\n'), 'utf8');
console.log(`Created ${rows.length} categorized content rows in ${outputDir}`);
