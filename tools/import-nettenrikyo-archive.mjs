import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const project = path.resolve(process.argv[2] || '.');
const inventoryPath = path.join(project, 'nettenrikyo', '_organizing', 'article-list.csv');
const contentRoot = path.join(project, 'content', 'archive');
const publicText = (value) => String(value || '').replaceAll('謝匡宇', '謝科比');

function parseCsv(text) {
  const rows = [];
  let row = [], cell = '', quoted = false;
  for (let i = 0; i < text.length; i += 1) {
    const char = text[i];
    if (quoted && char === '"' && text[i + 1] === '"') { cell += '"'; i += 1; }
    else if (char === '"') quoted = !quoted;
    else if (char === ',' && !quoted) { row.push(cell); cell = ''; }
    else if ((char === '\n' || char === '\r') && !quoted) {
      if (char === '\r' && text[i + 1] === '\n') i += 1;
      row.push(cell); cell = '';
      if (row.some(Boolean)) rows.push(row);
      row = [];
    } else cell += char;
  }
  if (cell || row.length) { row.push(cell); rows.push(row); }
  const headers = rows.shift().map((value) => value.replace(/^\ufeff/, ''));
  return rows.map((values) => Object.fromEntries(headers.map((header, index) => [header, values[index] || ''])));
}

const yaml = (value) => JSON.stringify(String(value));

function slugFor(source) {
  const stem = source.replace(/\.[^.]+$/, '').replace(/[^a-zA-Z0-9]+/g, '-').replace(/^-|-$/g, '').toLowerCase();
  const hash = crypto.createHash('sha1').update(source).digest('hex').slice(0, 8);
  return `${stem || 'legacy'}-${hash}`;
}

function inferredDate(source, title) {
  const text = `${source} ${title}`;
  let match = text.match(/(20\d{2})-(\d{2})(\d{2})(?!\d)/);
  if (match) return `${match[1]}-${match[2]}-${match[3]}`;
  match = text.match(/(20\d{2})[-年](\d{1,2})[-月](\d{1,2})/);
  if (match) return `${match[1]}-${match[2].padStart(2, '0')}-${match[3].padStart(2, '0')}`;
  match = text.match(/(20\d{2})[-年](\d{1,2})/);
  return match ? `${match[1]}-${match[2].padStart(2, '0')}` : '';
}

function cleanHtml(text) {
  return text.replace(/<br\s*\/?\s*>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;|&#160;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/\s+/g, ' ').trim();
}

function normalized(text) {
  return text.replace(/[\s「」『』（）()，。、：:／/・　]/g, '').toLowerCase();
}

function extractPageMetadata(source, title, author) {
  if (path.extname(source).toLowerCase() !== '.html') return { cover: '', provenance: '', date: inferredDate(source, title), fragment: '' };
  const fullPath = path.join(project, 'nettenrikyo', ...source.split('/'));
  const html = fs.readFileSync(fullPath, 'utf8');
  const tableStart = html.search(/<table\b/i);
  const content = tableStart >= 0 ? html.slice(tableStart) : html;
  const cells = [...content.matchAll(/<td\b[^>]*>([\s\S]*?)<\/td>/gi)];
  let fragment = cells.sort((a, b) => cleanHtml(b[1]).length - cleanHtml(a[1]).length)[0]?.[1] || content;
  const paragraphs = [...fragment.matchAll(/<p\b[^>]*>([\s\S]*?)<\/p>/gi)].map((match) => cleanHtml(match[1]));
  const titleKey = normalized(title);
  let titleIndex = paragraphs.findIndex((text) => {
    const key = normalized(text);
    return key && titleKey && (key.includes(titleKey) || titleKey.includes(key));
  });
  const sourcePattern = /中文天理|海外部報|神殿講話|月次祭|神殿演講|講稿|摘譯|NHK|出刊號數|\d{4}年\d{1,2}月|立教\d+年/;
  const sourceWindow = paragraphs.slice(0, titleIndex >= 0 ? Math.max(titleIndex, 3) : 5);
  let provenance = sourceWindow.find((text) => sourcePattern.test(text) && normalized(text) !== normalized(author)) || '';
  if (!provenance && titleIndex > 0) {
    provenance = paragraphs.slice(0, titleIndex)
      .filter((text) => text && text.length <= 180 && normalized(text) !== normalized(author) && !/回首頁|返回.*目錄|首頁.*三原典|^文章列表$/.test(text))
      .at(-1) || '';
  }
  provenance = publicText(provenance);
  if (titleIndex < 0) titleIndex = Math.min(paragraphs.length, 4);
  const imageMatch = [...fragment.matchAll(/<img\b[^>]*src\s*=\s*["']([^"']+)["'][^>]*>/gi)]
    .find((match) => !/(?:^|\/)(?:title|coverback|list)(?:[-_.]|$)/i.test(match[1]));
  let cover = '';
  if (imageMatch) {
    const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(source), imageMatch[1].replaceAll('\\', '/')));
    if (!resolved.startsWith('../')) cover = `/legacy/nettenrikyo/${encodeURI(resolved)}`;
  }
  const preTitleText = paragraphs.slice(0, Math.max(titleIndex, 6)).join(' ');
  const exactDate = preTitleText.match(/(20\d{2})年(\d{1,2})月(\d{1,2})日/);
  const date = exactDate
    ? `${exactDate[1]}-${exactDate[2].padStart(2, '0')}-${exactDate[3].padStart(2, '0')}`
    : inferredDate(source, title);
  let paragraphNumber = 0;
  fragment = fragment.replace(/<p\b[^>]*>([\s\S]*?)<\/p>/gi, (block, inner) => {
    paragraphNumber += 1;
    const text = cleanHtml(inner);
    const removable = paragraphNumber <= 8 && [title, author, provenance].some((value) => value && normalized(text) === normalized(publicText(value)));
    return removable ? '' : block;
  });
  if (imageMatch) fragment = fragment.replace(imageMatch[0], '');
  fragment = fragment.replace(/<script\b[\s\S]*?<\/script>/gi, '').replace(/<style\b[\s\S]*?<\/style>/gi, '');
  fragment = fragment.replace(/\bsrc\s*=\s*(["'])([^"']+)\1/gi, (all, quote, value) => {
    if (/^(?:https?:|data:|\/)/i.test(value)) return all;
    const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(source), value.replaceAll('\\', '/')));
    return `src=${quote}/legacy/nettenrikyo/${encodeURI(resolved)}${quote}`;
  });
  fragment = fragment.replace(/\bhref\s*=\s*(["'])([^"']+)\1/gi, (all, quote, value) => {
    if (/^(?:https?:|mailto:|#|\/)/i.test(value) || /\.html?(?:[#?]|$)/i.test(value)) return all;
    const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(source), value.replaceAll('\\', '/')));
    const localTarget = path.join(project, 'nettenrikyo', ...resolved.split('/'));
    if (!fs.existsSync(localTarget)) return 'href="#" class="missing-legacy-file" aria-disabled="true" title="原始檔案缺失"';
    return `href=${quote}/legacy/nettenrikyo/${encodeURI(resolved)}${quote}`;
  });
  fragment = publicText(fragment).split(/\r?\n/).map((line) => line.trimStart()).join('\n').trim();
  // The old pages commonly used two full-width spaces as a paragraph indent.
  // The archive uses the current site's flush-left paragraph style instead.
  fragment = fragment
    .replace(/(<p\b[^>]*>)\s*[　]{2,}/gi, '$1')
    .replace(/(<br\s*\/?>)\s*[　]{2,}/gi, '$1');
  return { cover, provenance, date, fragment };
}

const sectionMap = {
  '01-三原典': ['scriptures', '三原典', '神樂歌、御指圖及其他原典資料'],
  '02-教理': ['doctrine', '教典與教理資料', '教典及舊站教理文章與資料'],
  '03-演講稿': ['sermons', '演講稿', '神殿講話與講演'],
  '04-文章與翻譯': ['articles', '文章與翻譯', '舊站文章、心得與翻譯'],
  '05-個人札記與系列': ['notes', '個人札記與系列', '版主小窗及康樂生活系列'],
  '06-學習資源': ['resources', '學習資源', '舊站下載資料'],
};

const groupSections = [
  ['articles/general', '文章列表', '心得分享與各類文章翻譯', 10],
  ['articles/huang', '黃登洲會長系列', '執筆與翻譯文章', 20],
  ['articles/chinese-tenri', '中文天理', '依原站的年代區間查找文章', 30],
  ['articles/chinese-tenri/1988-2000', '1988年～2000年', '中文天理第1號～49號', 10],
  ['articles/chinese-tenri/2001-2005', '2001年～2005年', '中文天理第50號～98號', 20],
  ['articles/chinese-tenri/2006-later', '2006年～', '中文天理第99號以後', 30],
  ['doctrine/doctrine-text', '教典', '天理教教典各章', 10],
  ['doctrine/teaching-materials', '教理文章與資料', '八種灰塵、十全祐護及其他教理資料', 20],
  ['notes/window', '版主小窗', '版主小窗系列文章', 10],
  ['notes/happy-life', '康樂生活系列', '康樂生活系列文章', 20],
  ['resources/downloads', '下載資料', '舊站學習與下載資源', 10],
  ...['2002', '2003', '2004', '2005', '2006', '2007', '2016'].map((year, index) => [
    `sermons/${year}`, `${year}年`, `${year}年演講稿`, (index + 1) * 10,
  ]),
];

function chineseTenriPeriod(source) {
  if (source.startsWith('article/chi-2006/')) return '2006-later';
  const issue = Number(source.match(/article-ch(\d+)/i)?.[1] || 0);
  if (issue && issue <= 49) return '1988-2000';
  if (issue && issue <= 98) return '2001-2005';
  return '2006-later';
}

function sermonYear(source) {
  if (/speech\/2016-/i.test(source)) return '2016';
  let issue = Number(source.match(/speech-chi-(\d+)/i)?.[1] || 0);
  if (issue > 999) issue = Math.floor(issue / 10);
  if (issue <= 62) return '2002';
  if (issue <= 72) return '2003';
  if (issue <= 85) return '2004';
  if (issue <= 98) return '2005';
  if (issue <= 108) return '2006';
  return '2007';
}

function groupedDirectory(row, section) {
  if (section === 'articles') {
    if (row.subcategory === '黃登洲會長系列') return 'articles/huang';
    if (row.subcategory === '歷年中文文章') return `articles/chinese-tenri/${chineseTenriPeriod(row.source_path)}`;
    return 'articles/general';
  }
  if (section === 'doctrine') return row.subcategory === '教典' ? 'doctrine/doctrine-text' : 'doctrine/teaching-materials';
  if (section === 'sermons') return `sermons/${sermonYear(row.source_path)}`;
  if (section === 'notes') return row.subcategory === '版主小窗' ? 'notes/window' : 'notes/happy-life';
  if (section === 'resources') return 'resources/downloads';
  return section;
}

const rows = parseCsv(fs.readFileSync(inventoryPath, 'utf8')).filter((row) => {
  if (row.source_path.startsWith('teaching/itsuwa/')) return false;
  if (row.source_path.startsWith('triple/fude/')) return false;
  // Source attachment linked from the translated article, not a standalone post.
  if (row.source_path === 'article/nishi/images/sayu-fude.pdf') return false;
  if (row.category === '01-三原典') return false;
  return Boolean(sectionMap[row.category]);
});

// This directory is generated from the inventory. Clear it so entries removed
// from the import rules do not remain as stale pages after a rebuild.
fs.rmSync(contentRoot, { recursive: true, force: true });
fs.mkdirSync(contentRoot, { recursive: true });
fs.writeFileSync(path.join(contentRoot, '_index.md'), `---\ntitle: "舊站典藏"\nlayout: "legacy-list"\ndescription: "早期 nettenrikyo 網站保存下來的文章與資料。"\n---\n\n這裡收錄早期網站文章，正文與圖片已套用目前網站版面，並與現在的新文章分開呈現。\n`, 'utf8');

for (const [section, title, description] of Object.values(sectionMap)) {
  const directory = path.join(contentRoot, section);
  fs.mkdirSync(directory, { recursive: true });
  fs.writeFileSync(path.join(directory, '_index.md'), `---\ntitle: ${yaml(title)}\nlayout: "legacy-list"\ndescription: ${yaml(description)}\n---\n`, 'utf8');
}

for (const [relative, title, description, weight] of groupSections) {
  const directory = path.join(contentRoot, ...relative.split('/'));
  fs.mkdirSync(directory, { recursive: true });
  fs.writeFileSync(path.join(directory, '_index.md'), `---\ntitle: ${yaml(title)}\nlayout: "legacy-list"\ndescription: ${yaml(description)}\nweight: ${weight}\n---\n`, 'utf8');
}

for (const row of rows) {
  const [section] = sectionMap[row.category];
  const slug = slugFor(row.source_path);
  const relativeDirectory = groupedDirectory(row, section);
  const metadata = extractPageMetadata(row.source_path, row.title, row.author);
  const fields = [
    '---', `title: ${yaml(publicText(row.title))}`, `slug: ${yaml(slug)}`,
    `url: ${yaml(`/archive/${section}/${slug}/`)}`,
    'categories:', '  - "舊站典藏"',
    'legacy_archive: true',
    `legacy_category: ${yaml(row.subcategory)}`,
    `legacy_source: ${yaml(`/legacy/nettenrikyo/${encodeURI(row.source_path)}`)}`,
    `legacy_original_path: ${yaml(row.source_path)}`,
    `legacy_author: ${yaml(publicText(row.author))}`,
    `legacy_provenance: ${yaml(metadata.provenance)}`,
    `legacy_cover: ${yaml(metadata.cover)}`,
    `legacy_download: ${['.docx', '.pptx'].includes(path.extname(row.source_path).toLowerCase())}`,
    ...(metadata.date ? [`legacy_original_date: ${yaml(metadata.date)}`] : []),
    '---', '', metadata.fragment,
  ];
  const directory = path.join(contentRoot, ...relativeDirectory.split('/'));
  fs.writeFileSync(path.join(directory, `${slug}.md`), fields.join('\n'), 'utf8');
}

const scripturePages = [
  {
    file: 'ofudesaki.md',
    title: '御筆先',
    source: 'triple/fude/fude.html',
    cover: '/legacy/nettenrikyo/triple/fude/images/fude-1.jpg',
    body: `
<div class="legacy-resource-page">
<h2>御筆先相關資料</h2>
<p><strong>現代日文＋註解版：</strong> <a href="/legacy/nettenrikyo/triple/fude/file/OfudesakiJ.pdf">下載</a></p>
<p><strong>現代日文＋白話文翻譯：</strong> <a href="/legacy/nettenrikyo/triple/fude/file/OfudesakiJC.pdf">單頁版下載</a>　<a href="/legacy/nettenrikyo/triple/fude/file/OfudesakiJCA4.pdf">雙頁版下載</a></p>
<h3>依號數區分（手機尺寸）</h3>
<div class="legacy-resource-table-wrap"><table class="legacy-resource-table legacy-resource-table--three"><tbody>
<tr><td><a href="/legacy/nettenrikyo/triple/fude/file/o-1.pdf">第一號</a></td><td><a href="/legacy/nettenrikyo/triple/fude/file/o-2.pdf">第二號</a></td><td><a href="/legacy/nettenrikyo/triple/fude/file/o-3%281-76%29.pdf">第三號（1–76）</a></td></tr>
<tr><td><a href="/legacy/nettenrikyo/triple/fude/file/o-3%2877-149%29.pdf">第三號（77–149）</a></td><td><a href="/legacy/nettenrikyo/triple/fude/file/o-4%281-68%29.pdf">第四號（1–68）</a></td><td><a href="/legacy/nettenrikyo/triple/fude/file/o-4%2869-134%29.pdf">第四號（69–134）</a></td></tr>
<tr><td><a href="/legacy/nettenrikyo/triple/fude/file/o-5.pdf">第五號</a></td><td><a href="/legacy/nettenrikyo/triple/fude/file/o-6%281-68%29.pdf">第六號（1–68）</a></td><td><a href="/legacy/nettenrikyo/triple/fude/file/o-6%2869-134%29.pdf">第六號（69–134）</a></td></tr>
<tr><td><a href="/legacy/nettenrikyo/triple/fude/file/o-7%281-56%29.pdf">第七號（1–56）</a></td><td><a href="/legacy/nettenrikyo/triple/fude/file/o-7%2857-111%29.pdf">第七號（57–111）</a></td><td><a href="/legacy/nettenrikyo/triple/fude/file/o-8.pdf">第八號</a></td></tr>
</tbody></table></div>
</div>`,
  },
  {
    file: 'mikagura-uta.md',
    title: '神樂歌',
    source: 'triple/uta/uta.html',
    cover: '/legacy/nettenrikyo/triple/uta/images/uta-1.jpg',
    body: `
<div class="legacy-resource-page">
<h2>神樂歌相關資料</h2>
<div class="legacy-resource-table-wrap"><table class="legacy-resource-table legacy-resource-table--four"><tbody>
<tr><th colspan="4">現代日文＋白話文翻譯</th></tr>
<tr><td colspan="2"><strong>傳統中文版</strong><br><a href="/legacy/nettenrikyo/triple/uta/uta.pdf">下載</a></td><td><strong>簡體字版</strong><br><a href="/legacy/nettenrikyo/triple/uta/uta-china.pdf">下載</a></td><td><strong>字母版</strong><br><a href="/legacy/nettenrikyo/triple/uta/uta-afabeta.pdf">下載</a></td></tr>
<tr><th colspan="4">手機尺寸</th></tr>
<tr><td><strong>傳統中文版（全）</strong><br><a href="/legacy/nettenrikyo/triple/uta/uta-JP.pdf">下載</a></td><td><strong>坐拜＋八首</strong><br><a href="/legacy/nettenrikyo/triple/uta/uta-JP-part1.pdf">下載</a></td><td><strong>前半</strong><br><a href="/legacy/nettenrikyo/triple/uta/uta-JP-part2.pdf">下載</a></td><td><strong>後半</strong><br><a href="/legacy/nettenrikyo/triple/uta/uta-JP-part3.pdf">下載</a></td></tr>
<tr><td><strong>字母版（全）</strong><br><a href="/legacy/nettenrikyo/triple/uta/uta-ABC.pdf">下載</a></td><td><strong>字母坐拜＋八首</strong><br><a href="/legacy/nettenrikyo/triple/uta/uta-ABC-part1.pdf">下載</a></td><td><strong>字母前半</strong><br><a href="/legacy/nettenrikyo/triple/uta/uta-ABC-part2.pdf">下載</a></td><td><strong>字母後半</strong><br><a href="/legacy/nettenrikyo/triple/uta/uta-ABC-part3.pdf">下載</a></td></tr>
</tbody></table></div>
</div>`,
  },
  {
    file: 'oyasama-answers.md',
    title: '教祖回答弟子問題',
    source: 'triple/ask-anser.pdf',
    cover: '',
    body: '',
  },
];

for (const page of scripturePages) {
  const fields = [
    '---', `title: ${yaml(page.title)}`, `slug: ${yaml(path.basename(page.file, '.md'))}`,
    'categories:', '  - "舊站典藏"', 'legacy_archive: true',
    'legacy_category: "三原典"',
    `legacy_source: ${yaml(`/legacy/nettenrikyo/${page.source}`)}`,
    `legacy_original_path: ${yaml(page.source)}`,
    'legacy_author: ""', 'legacy_provenance: ""',
    `legacy_cover: ${yaml(page.cover)}`, 'legacy_download: false',
    '---', '', page.body.trim(),
  ];
  fs.writeFileSync(path.join(contentRoot, 'scriptures', page.file), fields.join('\n'), 'utf8');
}

console.log(`Imported ${rows.length + scripturePages.length} archive entries into ${contentRoot}`);
