import fs from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { FileBlob, PresentationFile } from "@oai/artifact-tool";

const SKILL_DIR = "C:/Users/ky/.codex/plugins/cache/openai-primary-runtime/presentations/26.1015.12040/skills/presentations";
const workspaceDir = "D:/kirby1215";
const sourcePath = "C:/Users/ky/Downloads/115衣珠簡報.pptx";
const buildDir = path.join(workspaceDir, ".codex-pptx", "build");
const previewDir = path.join(workspaceDir, ".codex-pptx", "preview");
const FINAL_PPTX = path.join(workspaceDir, "output", "115衣珠簡報_第5頁整合表.pptx");
const RUNTIME_PYTHON = "C:/Users/ky/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe";

await fs.mkdir(previewDir, { recursive: true });
await fs.mkdir(path.dirname(FINAL_PPTX), { recursive: true });

const presentation = await PresentationFile.importPptx(await FileBlob.load(sourcePath));
const slide = presentation.slides.items[4];

presentation.delete([
  "sh/dgbulwnm", "sh/cf2tcr61", "sh/z2tcnm5s", "sh/yhkbe1o7", "sh/l4bupwny", "sh/032tgr6d",
  "sh/n6dcr65o", "sh/m5kbi1oj", "sh/w32dkbuh", "sh/x4vedgvm", "sh/ahkvi1cb", "sh/v2twb6dw",
  "sh/k7mxovud", "sh/58vehgvy", "sh/i54fmlc7", "sh/j6dwfqds", "sh/sb6xsvu9", "sh/tcfel0vu",
  "sh/hgrmpwj2", "sh/gfi5grih", "sh/fe94nm1w", "sh/ud0ne10b", "sh/pkr6tgjy", "sh/4ji5kbid",
  "sh/3i94r61s", "sh/2h0ni107", "sh/5o7mhcju", "sh/kny587i9", "sh/atcjidg7", "sh/vu5kbihc",
  "sh/wve1knyx", "sh/xwn2dszi", "sh/ihw3mxg3", "sh/ji5kf2ho", "sh/kjelony9", "sh/5kn2hszu"
]);

slide.background.fill = "#F9F8F2";

function addText(name, text, position, style) {
  const shape = slide.shapes.add({
    geometry: "textbox",
    name,
    position,
    fill: "none",
    line: { style: "solid", fill: "none", width: 0 },
  });
  shape.text = text;
  shape.text.style = { fontFamily: "Microsoft JhengHei", ...style };
  shape.text.insets = 0;
  return shape;
}

slide.shapes.add({
  geometry: "rect",
  name: "左側識別線",
  position: { left: 0, top: 0, width: 15.36, height: 720 },
  fill: "#1C5B46",
  line: { style: "solid", fill: "none", width: 0 },
});

addText("標題", "出國身分別結構｜原住民人次成長最明顯", { left: 52.8, top: 30.72, width: 1161.6, height: 48 }, {
  fontSize: 33.33, bold: true, color: "#1C5B46", alignment: "left",
});
addText("副標題", "以人次比較113與114學年度，三類身分均增加", { left: 55.68, top: 87.36, width: 1152, height: 40.32 }, {
  fontSize: 16, color: "#5F6B65", alignment: "left",
});

const table = slide.tables.add({
  rows: 5,
  columns: 5,
  left: 70,
  top: 158,
  width: 1140,
  height: 342,
  columnWidths: [290, 190, 190, 190, 280],
  values: [
    ["身分類別", "113學年度\n人次", "114學年度\n人次", "增減\n人次", "成長率"],
    ["原住民", "8", "53", "+45", "+562.5%"],
    ["其他弱勢\n（114：完善生）", "33", "46", "+13", "+39.4%"],
    ["一般身分", "260", "283", "+23", "+8.8%"],
    ["總計", "301", "382", "+81", "+26.9%"],
  ],
});

table.borders.assign({ style: "solid", fill: "#D5DED8", width: 1 });
table.cells.block({ row: 0, column: 0, rowCount: 5, columnCount: 5 }).assign({
  textStyle: { fontFamily: "Microsoft JhengHei", fontSize: 20, color: "#223930", alignment: "center" },
  margins: { left: 14, right: 14, top: 8, bottom: 8 },
  anchor: "middle",
});
table.cells.block({ row: 0, column: 0, rowCount: 1, columnCount: 5 }).assign({
  fill: "#1C5B46",
  textStyle: { fontFamily: "Microsoft JhengHei", fontSize: 18, bold: true, color: "#FFFFFF", alignment: "center" },
});
table.cells.block({ row: 1, column: 0, rowCount: 1, columnCount: 5 }).assign({ fill: "#FFF3D6" });
table.cells.block({ row: 2, column: 0, rowCount: 1, columnCount: 5 }).assign({ fill: "#F4F7F4" });
table.cells.block({ row: 3, column: 0, rowCount: 1, columnCount: 5 }).assign({ fill: "#FFFFFF" });
table.cells.block({ row: 4, column: 0, rowCount: 1, columnCount: 5 }).assign({
  fill: "#DCEDE1",
  textStyle: { fontFamily: "Microsoft JhengHei", fontSize: 20, bold: true, color: "#1C5B46", alignment: "center" },
});
table.cells.block({ row: 1, column: 3, rowCount: 1, columnCount: 2 }).assign({
  fill: "#F0D596",
  textStyle: { fontFamily: "Microsoft JhengHei", fontSize: 22, bold: true, color: "#7A4E00", alignment: "center" },
});
table.cells.block({ row: 2, column: 4, rowCount: 1, columnCount: 1 }).assign({
  textStyle: { fontFamily: "Microsoft JhengHei", fontSize: 20, bold: true, color: "#1C5B46", alignment: "center" },
});
table.cells.block({ row: 1, column: 0, rowCount: 4, columnCount: 1 }).assign({
  textStyle: { fontFamily: "Microsoft JhengHei", fontSize: 19, bold: true, color: "#223930", alignment: "left" },
});

slide.shapes.add({
  geometry: "roundRect",
  name: "重點摘要底色",
  position: { left: 70, top: 527, width: 1140, height: 104 },
  fill: "#FFFFFF",
  line: { style: "solid", fill: "#D5DED8", width: 1 },
  borderRadius: "rounded-xl",
});
addText("重點標籤", "成長差異", { left: 96, top: 548, width: 150, height: 28 }, {
  fontSize: 18, bold: true, color: "#C18A25", alignment: "left",
});
addText("重點說明", "原住民增加45人次，成長562.5%，增幅遠高於其他弱勢39.4%與一般身分8.8%。", { left: 238, top: 543, width: 930, height: 46 }, {
  fontSize: 22, bold: true, color: "#223930", alignment: "left",
});
addText("口徑說明", "註：114學年度「其他弱勢」採其他弱勢完善生口徑；數據為人次，非去重人數。", { left: 238, top: 588, width: 930, height: 26 }, {
  fontSize: 14, color: "#5F6B65", alignment: "left",
});

slide.shapes.add({
  geometry: "rect",
  name: "頁尾分隔線",
  position: { left: 55.68, top: 683.52, width: 1161.6, height: 1.15 },
  fill: "#E8EDE8",
  line: { style: "solid", fill: "none", width: 0 },
});
addText("頁尾", "慈濟大學｜全球事務處｜114學年度衣珠計畫", { left: 57.6, top: 689.28, width: 960, height: 17.28 }, {
  fontSize: 10.67, color: "#5F6B65", alignment: "left",
});
addText("頁碼", "05", { left: 1152, top: 687.36, width: 52.8, height: 19.2 }, {
  fontSize: 12, color: "#5F6B65", alignment: "right",
});

const preview = await presentation.export({ slide, format: "png", scale: 1.5 });
await fs.writeFile(path.join(previewDir, "slide-05-after.png"), new Uint8Array(await preview.arrayBuffer()));
const layout = await slide.export({ format: "layout" });
await fs.writeFile(path.join(previewDir, "slide-05-after.layout.json"), await layout.text(), "utf8");

const montage = await presentation.export({ format: "webp", montage: { columns: 4, slideWidth: 320, gap: 12, padding: 12 } });
await fs.writeFile(path.join(previewDir, "deck-after.webp"), new Uint8Array(await montage.arrayBuffer()));

const requirements = {
  explicitTotalSlideCount: 21,
  requiredNativeTableOwnerSlides: [5],
  requiredNativeChartOwnerSlides: [3],
  nativeChartTargetApplication: "powerpoint",
  tableArithmeticContracts: [
    { slide: 5, table: 1, label_column: 0, total_row: 4, value_columns: [1, 2, 3], component_rows: [1, 2, 3] },
  ],
};
const fontPolicy = {
  basis: "design",
  families: ["Microsoft JhengHei", "微軟正黑體", "Calibri", "Times New Roman", "標楷體"],
};
const { finalizePresentation } = await import(pathToFileURL(path.join(SKILL_DIR, "container_tools/artifact_tool_utils.mjs")).href);
const stagingDir = path.join(workspaceDir, ".codex-finalizer");
await fs.mkdir(stagingDir, { recursive: true });
const candidatePath = path.join(stagingDir, "candidate-115-clothing-slide5.pptx");
await (await PresentationFile.exportPptx(presentation)).save(candidatePath);
const result = await finalizePresentation({
  ...requirements,
  workspaceDir,
  candidatePath,
  finalPath: FINAL_PPTX,
  pythonExecutable: RUNTIME_PYTHON,
  integrityValidatorPath: path.join(SKILL_DIR, "container_tools/inspect_presentation_package_integrity.py"),
  layoutValidatorPath: path.join(SKILL_DIR, "container_tools/inspect_presentation_layout_geometry.py"),
  layoutArgs: [
    "--expected-slide-size-emu", "12192000,6858000",
    "--validate-bullet-geometry",
    "--validate-heading-fit",
    "--require-native-table-slide", "5",
  ],
  requiredNativeTableOwnerSlides: [5],
  fontPolicy,
  verifyArtifactToolImport: true,
  receiptPath: path.join(stagingDir, `${path.basename(FINAL_PPTX)}.validation.json`),
});
console.log(JSON.stringify({ FINAL_PPTX, result }, null, 2));
