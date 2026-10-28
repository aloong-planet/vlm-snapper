import fs from "node:fs";
import path from "node:path";

const root = path.resolve(import.meta.dirname);
const pages = [
  "companion-shell/prototype-companion-directions.html",
  "management-center/prototype-management-center.html"
];

for (const relativePath of pages) {
  const source = fs.readFileSync(path.join(root, relativePath), "utf8");
  const hasStylesheet = source.includes('../_shared/vlmsnapper-shell.css');
  const hasDeclaration = source.includes('data-shared-block="vlmsnapper-shell"');
  if (!hasStylesheet || !hasDeclaration) {
    throw new Error(`${relativePath} must reference and declare vlmsnapper-shell`);
  }
}

const toolbarPages = [
  "capture-overlay/prototype-toolbar-directions.html",
  "capture-overlay/prototype-snap-region.html"
];

for (const relativePath of toolbarPages) {
  const source = fs.readFileSync(path.join(root, relativePath), "utf8");
  const hasStylesheet = source.includes("../_shared/capture-overlay.css");
  const hasScript = source.includes("../_shared/capture-toolbar.js");
  const hasDeclaration = source.includes('data-shared-block="capture-toolbar"');
  if (!hasStylesheet || !hasScript || !hasDeclaration) {
    throw new Error(`${relativePath} must reference and declare capture-toolbar`);
  }
}

// Reverse check: a page that loads the shared toolbar must declare it and be listed above.
for (const directory of fs.readdirSync(root, { withFileTypes: true })) {
  if (!directory.isDirectory()) continue;
  for (const file of fs.readdirSync(path.join(root, directory.name))) {
    if (!file.endsWith(".html")) continue;
    const relativePath = `${directory.name}/${file}`;
    const source = fs.readFileSync(path.join(root, relativePath), "utf8");
    if (source.includes("capture-toolbar.js") && !toolbarPages.includes(relativePath)) {
      throw new Error(`${relativePath} loads capture-toolbar but is not checked`);
    }
  }
}

console.log(`shared-blocks:ok:${pages.length + toolbarPages.length}`);
