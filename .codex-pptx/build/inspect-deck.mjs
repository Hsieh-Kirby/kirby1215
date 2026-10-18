import fs from "node:fs/promises";
import { FileBlob, PresentationFile } from "@oai/artifact-tool";

const source = "C:/Users/ky/Downloads/115衣珠簡報.pptx";
const outDir = "D:/kirby1215/.codex-pptx/inspect";
const presentation = await PresentationFile.importPptx(await FileBlob.load(source));
console.log(`SLIDES=${presentation.slides.items.length}`);
const report = await presentation.inspect({
  kind: "slide,textbox,shape,image,table,chart,layout",
  maxChars: 30000,
});
await fs.writeFile(`${outDir}/inspect.ndjson`, report.ndjson, "utf8");
const slide = presentation.slides.items[4];
const slideReport = await presentation.inspect({
  target: { id: slide.id },
  kind: "slide,textbox,shape,image,table,chart,layout",
  maxChars: 30000,
});
await fs.writeFile(`${outDir}/slide-05-inspect.ndjson`, slideReport.ndjson, "utf8");
const png = await presentation.export({ slide, format: "png", scale: 1.5 });
await fs.writeFile(`${outDir}/slide-05-before.png`, new Uint8Array(await png.arrayBuffer()));
const layout = await slide.export({ format: "layout" });
await fs.writeFile(`${outDir}/slide-05-before.layout.json`, await layout.text(), "utf8");
console.log(`SLIDE5_ID=${slide.id}`);
