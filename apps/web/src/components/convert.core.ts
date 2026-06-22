// Pure conversion-dispatch core, extracted from the Web Worker so it's testable
// without instantiating the WASM module. The worker wires the real WASM exports
// and `postMessage`; tests inject fakes.

export type Opts = { preset: string; colorMode: string; curveType: string };

export type ConvertMsg = {
  type: "convert";
  reqId: number;
  files: { name: string; bytes: Uint8Array }[];
  formats: string[];
  opts: Opts;
  lossless: boolean;
  mono: boolean;
};

/** The subset of the wasm-pack module the dispatch loop calls. */
export interface WasmApi {
  pngToSvg(bytes: Uint8Array, opts: Opts): string;
  pngToEps(bytes: Uint8Array, opts: Opts): string;
  pngToDxf(bytes: Uint8Array, opts: Opts): string;
  pngToPdf(bytes: Uint8Array, opts: Opts): Uint8Array;
  pngToWebp(bytes: Uint8Array, quality: number, lossless: boolean, mono: boolean): Uint8Array;
}

type Post = (message: unknown) => void;

/**
 * Convert every file into every requested format, posting a `progress` message
 * per file and a final `result`. Per-file/format try/catch means one bad PNG or
 * unsupported format can't abort the batch — it lands in `failed` instead.
 */
export function convertBatch(
  msg: ConvertMsg,
  wasm: WasmApi,
  post: Post,
  enc: TextEncoder = new TextEncoder(),
): void {
  const out: Record<string, Uint8Array> = {};
  const failed: { name: string; fmt: string; error: string }[] = [];
  let inBytes = 0;
  let outBytes = 0;
  let done = 0;

  for (const f of msg.files) {
    inBytes += f.bytes.length;
    const base = f.name.replace(/\.png$/i, "");
    for (const fmt of msg.formats) {
      try {
        let data: Uint8Array;
        if (fmt === "svg") data = enc.encode(wasm.pngToSvg(f.bytes, msg.opts));
        else if (fmt === "eps") data = enc.encode(wasm.pngToEps(f.bytes, msg.opts));
        else if (fmt === "dxf") data = enc.encode(wasm.pngToDxf(f.bytes, msg.opts));
        else if (fmt === "pdf") data = wasm.pngToPdf(f.bytes, msg.opts);
        else data = wasm.pngToWebp(f.bytes, 82, msg.lossless, msg.mono);
        out[`${base}.${fmt}`] = data;
        outBytes += data.length;
      } catch (err) {
        failed.push({ name: f.name, fmt, error: String(err) });
      }
    }
    done++;
    post({ type: "progress", reqId: msg.reqId, done, total: msg.files.length });
  }

  post({ type: "result", reqId: msg.reqId, out, inBytes, outBytes, failed });
}
