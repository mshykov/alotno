declare module "*.astro?raw" {
  const source: string;
  export default source;
}

declare module "*.txt?raw" {
  const source: string;
  export default source;
}

declare module "*.png?url" {
  const source: string;
  export default source;
}

// The Cloudflare Pages headers file has no extension; declare it explicitly so
// the security-header test can `?raw`-import and pin its contents.
declare module "*_headers?raw" {
  const source: string;
  export default source;
}

// The design tokens stylesheet is imported for its side effect only. TypeScript
// 6 checks side-effect imports by default (`noUncheckedSideEffectImports`), and
// a `.css` export has no types to find, so declare it rather than turning the
// check off for everything else.
declare module "@alotno/design/css";
