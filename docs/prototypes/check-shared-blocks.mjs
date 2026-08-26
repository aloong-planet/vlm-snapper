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

console.log(`shared-blocks:ok:${pages.length}`);
