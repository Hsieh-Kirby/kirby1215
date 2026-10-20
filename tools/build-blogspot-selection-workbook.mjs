import fs from "node:fs/promises";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const workspace = process.argv[2] || process.cwd();
const reviewDir = path.join(workspace, "blogspot", "review");
const records = JSON.parse(await fs.readFile(path.join(reviewDir, "article-inventory.json"), "utf8"));
const outputPath = path.join(reviewDir, "blogspot-文章發布選擇表.xlsx");
const wb = Workbook.create();
const sheet = wb.worksheets.add("文章選擇");
sheet.showGridLines = false;
sheet.tabColor = "#355C7D";

sheet.getRange("A2:M2").merge();
sheet.getRange("A2").values = [["Blogspot 文章發布選擇"]];
sheet.getRange("A2").format.font = { name: "Arial", size: 16, bold: true, color: "#17324D" };
sheet.getRange("A3:M3").merge();
sheet.getRange("A3").values = [["請在「發布選擇」欄選擇：待決定、發佈或不發佈。修改後保留此檔案即可。"]];
sheet.getRange("A3").format.font = { name: "Arial", size: 10, italic: true, color: "#5B6573" };

sheet.getRange("A5:F5").values = [["文章總數", records.length, "待決定", null, "已選發佈", null]];
sheet.getRange("D5").formulas = [[`=COUNTIF(B8:B${records.length + 7},"待決定")`]];
sheet.getRange("F5").formulas = [[`=COUNTIF(B8:B${records.length + 7},"發佈")`]];
sheet.getRange("A5:F5").format = { fill: "#EAF0F5", font: { name: "Arial", size: 10, bold: true, color: "#17324D" } };

const headers = ["序號", "發布選擇", "發布日期", "文章標題", "原標籤", "YouTube", "Blogger影片", "圖片", "摘要", "原文網址", "Blogger ID", "待審檔案", "備註"];
sheet.getRange("A7:M7").values = [headers];
sheet.getRange("A7:M7").format = {
  fill: "#355C7D",
  font: { name: "Arial", size: 10, bold: true, color: "#FFFFFF" },
  horizontalAlignment: "center",
  verticalAlignment: "center",
  borders: { preset: "inside", style: "thin", color: "#FFFFFF" },
};

const rows = records.map((r) => [
  r.order, r.decision, new Date(r.published.replace(" ", "T") + ":00Z"), r.title, r.labels,
  r.youtube_count, r.blogger_video_count, r.image_count, r.summary, r.source_url,
  `post-${r.blogger_id}`, r.review_file, r.notes,
]);
sheet.getRange(`A8:M${records.length + 7}`).values = rows;
const body = sheet.getRange(`A8:M${records.length + 7}`);
body.format.font = { name: "Arial", size: 10, color: "#263238" };
body.format.verticalAlignment = "top";
sheet.getRange(`B8:B${records.length + 7}`).dataValidation = { rule: { type: "list", values: ["待決定", "發佈", "不發佈"] } };
sheet.getRange(`B8:B${records.length + 7}`).format.fill = "#FFF2CC";
sheet.getRange(`C8:C${records.length + 7}`).format.numberFormat = "yyyy-mm-dd hh:mm";
sheet.getRange(`A8:A${records.length + 7}`).format.horizontalAlignment = "center";
sheet.getRange(`B8:B${records.length + 7}`).format.horizontalAlignment = "center";
sheet.getRange(`F8:H${records.length + 7}`).format.horizontalAlignment = "center";
sheet.getRange(`D8:E${records.length + 7}`).format.wrapText = true;
sheet.getRange(`I8:I${records.length + 7}`).format.wrapText = true;
sheet.getRange(`M8:M${records.length + 7}`).format.wrapText = true;

const decisionRange = sheet.getRange(`B8:B${records.length + 7}`);
decisionRange.conditionalFormats.add("containsText", { text: "發佈", format: { fill: "#D9EAD3", font: { color: "#276221", bold: true } } });
decisionRange.conditionalFormats.add("containsText", { text: "不發佈", format: { fill: "#F4CCCC", font: { color: "#990000", bold: true } } });
decisionRange.conditionalFormats.add("containsText", { text: "待決定", format: { fill: "#FFF2CC", font: { color: "#7F6000" } } });

sheet.getRange(`A7:M${records.length + 7}`).format.borders = {
  insideHorizontal: { style: "thin", color: "#DCE3E8" },
  bottom: { style: "thin", color: "#9EADB8" },
};
sheet.getRange("A:A").format.columnWidth = 7;
sheet.getRange("B:B").format.columnWidth = 12;
sheet.getRange("C:C").format.columnWidth = 17;
sheet.getRange("D:D").format.columnWidth = 30;
sheet.getRange("E:E").format.columnWidth = 20;
sheet.getRange("F:H").format.columnWidth = 10;
sheet.getRange("I:I").format.columnWidth = 44;
sheet.getRange("J:J").format.columnWidth = 36;
sheet.getRange("K:K").format.columnWidth = 22;
sheet.getRange("L:L").format.columnWidth = 42;
sheet.getRange("M:M").format.columnWidth = 24;
sheet.getRange("7:7").format.rowHeight = 28;
sheet.freezePanes.freezeRows(7);
sheet.freezePanes.freezeColumns(4);
const table = sheet.tables.add(`A7:M${records.length + 7}`, true, "BlogspotPostSelection");
table.style = "TableStyleMedium2";
table.showFilterButton = true;

wb.recalculate();
const inspect = await wb.inspect({ kind: "table", range: `文章選擇!A2:M14`, include: "values,formulas", tableMaxRows: 14, tableMaxCols: 13 });
console.log(inspect.ndjson);
const errors = await wb.inspect({ kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!", options: { useRegex: true, maxResults: 100 }, summary: "formula error scan" });
console.log(errors.ndjson);
const preview = await wb.render({ sheetName: "文章選擇", range: "A1:M18", scale: 1, format: "png" });
await fs.writeFile(path.join(reviewDir, "selection-preview.png"), new Uint8Array(await preview.arrayBuffer()));
const xlsx = await SpreadsheetFile.exportXlsx(wb);
await xlsx.save(outputPath);
console.log(`Saved ${outputPath}`);
