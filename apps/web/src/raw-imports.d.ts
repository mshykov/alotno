declare module "*.astro?raw" {
  const source: string;
  export default source;
}

declare module "*.png?url" {
  const source: string;
  export default source;
}
