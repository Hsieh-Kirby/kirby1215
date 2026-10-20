import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";
import fs from "node:fs/promises";
const input = process.argv[2];
const wb = await SpreadsheetFile.importXlsx(await FileBlob.load(input));
const sh = wb.worksheets.getItem("文章選擇");
const grid = sh.getRange("A8:O126");
const values = grid.values;
const formulas = grid.formulas;
const headers = values[0];
const rows = values.slice(1).map((row, i) => ({
  row: i + 9,
  order: row[0], recommendation: row[1], reason: row[2], decision: row[3],
  published: row[4], title: row[5], labels: row[6], youtube: row[7], images: row[8],
  textChars: row[9], videoPlan: row[10], summary: row[11],
  sourceLinkFormula: formulas[i + 1]?.[12] || "", sitePath: row[13], notes: row[14]
})).filter(r => r.title);
const counts = Object.fromEntries([...new Set(rows.map(r => r.decision || "空白"))].map(k => [k, rows.filter(r => (r.decision || "空白") === k).length]));
if (process.argv[3]) await fs.writeFile(process.argv[3], JSON.stringify(rows, null, 2));
console.log(JSON.stringify({headers, counts, publish: rows.filter(r => r.decision === "發佈"), undecided: rows.filter(r => !r.decision || r.decision === "待決定").map(r => ({row:r.row,order:r.order,title:r.title,recommendation:r.recommendation}))}, null, 2));
