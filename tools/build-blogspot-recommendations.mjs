import fs from "node:fs/promises";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const workspace = process.argv[2] || process.cwd();
const reviewDir = path.join(workspace, "blogspot", "review");
const records = JSON.parse(await fs.readFile(path.join(reviewDir, "article-inventory.json"), "utf8"));
const outputPath = path.join(reviewDir, "blogspot-文章發布選擇表.xlsx");
const priority = new Set([1,4,6,8,11,14,16,18,20,21,22,23,26,30,31,32,33,35,37,39,40,42,47,48,50,51,52,54,55,59,60,61,62,63,64,65,66,69]);
const skip = new Set([3,5,17,45]);
const recommendation = (r) => priority.has(r.order) ? "優先轉入" : skip.has(r.order) ? "暫不轉入" : "可選轉入";
const specialReasons = {
  3: "平台搬家公告，時效性低，不適合新站長期閱讀。",
  5: "內容短、主要依賴兩段 Blogger 影片，可保留在備份。",
  17: "篇幅較短且主題偏當日心情，獨立轉入價值較低。",
  45: "舊平台分類與 nidbox 導覽說明，應改寫為新站導覽，不宜原文轉入。",
};
function reason(r) {
  if (specialReasons[r.order]) return specialReasons[r.order];
  if (priority.has(r.order)) {
    if (r.labels === "縱目古意") return "史蹟與建築資料完整、圖片多，具長期搜尋與在地文化價值。";
    if (["洄瀾看花", "出門看花"].includes(r.labels)) return "花蓮／台灣在地遊記完整，兼具個人敘事、景點資訊與圖像紀錄。";
    if (["親親寳貝", "人物風情"].includes(r.labels)) return "人物或家族故事完整，有明確主題與長期保存價值。";
    if (r.labels === "繞樑餘音") return "有明確的人物／音樂記憶主題，可作為個人檔案保留。";
    return "故事完整、圖文豐富，主題不依賴短期時事，適合長期收錄。";
  }
  if (r.youtube_count > 0) return "可保留音樂與 YouTube 影片；轉入前建議縮短歌詞引用，降低版權風險。";
  if (r.blogger_video_count > 0) return "內容可保留，但依賴 Blogger 影片；選定後要改接本地 MP4。";
  if (r.image_count <= 3) return "篇幅或圖像較少，適合依個人紀念價值再決定。";
  return "內容完整，但偏日常隨筆；若要精簡新站，可第二批再轉。";
}
function videoPlan(r) {
  const parts = [];
  if (r.youtube_count) parts.push(`YouTube ${r.youtube_count}個：已轉響應式播放器`);
  if (r.blogger_video_count) parts.push(`Blogger ${r.blogger_video_count}個：正式轉入時改用匯出 MP4`);
  return parts.length ? parts.join("；") : "無影片";
}

const wb = Workbook.create();
const sheet = wb.worksheets.add("文章選擇");
sheet.showGridLines = false;
sheet.tabColor = "#355C7D";
const lastRow = records.length + 8;
sheet.getRange("A2:P2").merge();
sheet.getRange("A2").values = [["Blogspot 文章轉入建議"]];
sheet.getRange("A2").format.font = { name: "Arial", size: 16, bold: true, color: "#17324D" };
sheet.getRange("A3:P3").merge();
sheet.getRange("A3").values = [["先參考「分析建議」與「建議理由」，再在黃色的「發布選擇」欄決定是否轉入 kirby1215.tw。"]];
sheet.getRange("A3").format.font = { name: "Arial", size: 10, italic: true, color: "#5B6573" };
sheet.getRange("A5:H5").values = [["文章總數", records.length, "優先轉入", priority.size, "可選轉入", records.length-priority.size-skip.size, "暫不轉入", skip.size]];
sheet.getRange("A5:H5").format = { fill: "#EAF0F5", font: { name: "Arial", size: 10, bold: true, color: "#17324D" } };
const headers = ["序號", "分析建議", "建議理由", "發布選擇", "發布日期", "文章標題", "原標籤", "YouTube", "Blogger影片", "圖片", "影片處理", "摘要", "原文網址", "Blogger ID", "待審檔案", "備註"];
sheet.getRange("A8:P8").values = [headers];
sheet.getRange("A8:P8").format = { fill: "#355C7D", font: { name: "Arial", size: 10, bold: true, color: "#FFFFFF" }, horizontalAlignment: "center", verticalAlignment: "center", borders: { preset: "inside", style: "thin", color: "#FFFFFF" } };
// Treat the already-local Taipei wall time as the displayed spreadsheet value.
const rows = records.map((r) => [r.order, recommendation(r), reason(r), r.decision, new Date(r.published.replace(" ", "T") + ":00Z"), r.title, r.labels, r.youtube_count, r.blogger_video_count, r.image_count, videoPlan(r), r.summary, r.source_url, `post-${r.blogger_id}`, r.review_file, r.notes]);
sheet.getRange(`A9:P${lastRow}`).values = rows;
const body = sheet.getRange(`A9:P${lastRow}`);
body.format.font = { name: "Arial", size: 10, color: "#263238" };
body.format.verticalAlignment = "top";
sheet.getRange(`D9:D${lastRow}`).dataValidation = { rule: { type: "list", values: ["待決定", "發佈", "不發佈"] } };
sheet.getRange(`D9:D${lastRow}`).format.fill = "#FFF2CC";
sheet.getRange(`E9:E${lastRow}`).format.numberFormat = "yyyy-mm-dd hh:mm";
sheet.getRange(`A9:B${lastRow}`).format.horizontalAlignment = "center";
sheet.getRange(`D9:D${lastRow}`).format.horizontalAlignment = "center";
sheet.getRange(`H9:J${lastRow}`).format.horizontalAlignment = "center";
for (const col of ["B:C","F:G","K:L","P:P"]) sheet.getRange(`${col.split(':')[0]}9:${col.split(':')[1]}${lastRow}`).format.wrapText = true;
const recRange = sheet.getRange(`B9:B${lastRow}`);
recRange.conditionalFormats.add("containsText", { text: "優先轉入", format: { fill: "#D9EAD3", font: { color: "#276221", bold: true } } });
recRange.conditionalFormats.add("containsText", { text: "可選轉入", format: { fill: "#FFF2CC", font: { color: "#7F6000" } } });
recRange.conditionalFormats.add("containsText", { text: "暫不轉入", format: { fill: "#F4CCCC", font: { color: "#990000", bold: true } } });
const decisionRange = sheet.getRange(`D9:D${lastRow}`);
decisionRange.conditionalFormats.add("containsText", { text: "發佈", format: { fill: "#D9EAD3", font: { color: "#276221", bold: true } } });
decisionRange.conditionalFormats.add("containsText", { text: "不發佈", format: { fill: "#F4CCCC", font: { color: "#990000", bold: true } } });
sheet.getRange(`A8:P${lastRow}`).format.borders = { insideHorizontal: { style: "thin", color: "#DCE3E8" }, bottom: { style: "thin", color: "#9EADB8" } };
const widths = {"A:A":7,"B:B":13,"C:C":36,"D:D":12,"E:E":17,"F:F":30,"G:G":16,"H:J":10,"K:K":36,"L:L":44,"M:M":34,"N:N":22,"O:O":40,"P:P":24};
for (const [range,width] of Object.entries(widths)) sheet.getRange(range).format.columnWidth = width;
sheet.getRange("8:8").format.rowHeight = 30;
sheet.freezePanes.freezeRows(8);
sheet.freezePanes.freezeColumns(6);
const table = sheet.tables.add(`A8:P${lastRow}`, true, "BlogspotPostSelection");
table.style = "TableStyleMedium2";
table.showFilterButton = true;
wb.recalculate();
console.log((await wb.inspect({ kind: "table", range: "文章選擇!A2:P15", include: "values,formulas", tableMaxRows: 15, tableMaxCols: 16 })).ndjson);
console.log((await wb.inspect({ kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!", options: { useRegex: true, maxResults: 100 }, summary: "formula error scan" })).ndjson);
const preview = await wb.render({ sheetName: "文章選擇", range: "A1:P20", scale: 1, format: "png" });
await fs.writeFile(path.join(reviewDir, "selection-preview.png"), new Uint8Array(await preview.arrayBuffer()));
const xlsx = await SpreadsheetFile.exportXlsx(wb);
await xlsx.save(outputPath);
console.log(`Saved ${outputPath}`);
