import { describe, it, expect, vi } from "vitest";
import { convertBatch, type ConvertMsg, type WasmApi } from "./convert.core";

const opts = { preset: "high", colorMode: "mono", curveType: "curves" };

// Fake WASM: records calls, returns deterministic output, can be told to throw.
function fakeWasm(throwOn: Partial<Record<string, boolean>> = {}): WasmApi {
  const guard = (fmt: string) => {
    if (throwOn[fmt]) throw new Error(`boom-${fmt}`);
  };
  return {
    pngToSvg: () => (guard("svg"), "<svg/>"),
    pngToEps: () => (guard("eps"), "%!PS"),
    pngToDxf: () => (guard("dxf"), "ENTITIES"),
    pngToPdf: () => (guard("pdf"), new Uint8Array([0x25, 0x50, 0x44, 0x46])),
    pngToWebp: () => (guard("webp"), new Uint8Array([0x52, 0x49, 0x46, 0x46])),
  };
}

const file = (name: string, n = 4) => ({ name, bytes: new Uint8Array(n) });

function run(msg: Partial<ConvertMsg>, wasm: WasmApi) {
  const posts: any[] = [];
  const full: ConvertMsg = {
    type: "convert",
    reqId: 1,
    files: [],
    formats: [],
    opts,
    lossless: false,
    mono: true,
    ...msg,
  };
  convertBatch(full, wasm, (m) => posts.push(m));
  return posts;
}

describe("convertBatch", () => {
  it("dispatches each format and names outputs base.fmt (strips .png)", () => {
    const posts = run(
      { files: [file("falcon.png")], formats: ["svg", "pdf", "eps", "dxf", "webp"] },
      fakeWasm(),
    );
    const result = posts.at(-1);
    expect(result.type).toBe("result");
    expect(Object.keys(result.out).sort()).toEqual(
      ["falcon.dxf", "falcon.eps", "falcon.pdf", "falcon.svg", "falcon.webp"].sort(),
    );
    expect(result.failed).toEqual([]);
  });

  it("strips .png case-insensitively", () => {
    const posts = run({ files: [file("IMG.PNG")], formats: ["svg"] }, fakeWasm());
    expect(Object.keys(posts.at(-1).out)).toEqual(["IMG.svg"]);
  });

  it("isolates a failing format — the rest of the batch still succeeds", () => {
    const posts = run(
      { files: [file("a.png")], formats: ["svg", "pdf"] },
      fakeWasm({ pdf: true }),
    );
    const result = posts.at(-1);
    expect(Object.keys(result.out)).toEqual(["a.svg"]);
    expect(result.failed).toEqual([{ name: "a.png", fmt: "pdf", error: "Error: boom-pdf" }]);
  });

  it("one bad file does not abort the others", () => {
    // svg throws only via the shared guard, so make svg always throw and check
    // both files report the failure but the batch completes.
    const posts = run(
      { files: [file("a.png"), file("b.png")], formats: ["svg"] },
      fakeWasm({ svg: true }),
    );
    const result = posts.at(-1);
    expect(result.out).toEqual({});
    expect(result.failed.map((f: any) => f.name)).toEqual(["a.png", "b.png"]);
  });

  it("emits one progress message per file with a running done/total", () => {
    const posts = run(
      { files: [file("a.png"), file("b.png"), file("c.png")], formats: ["svg"] },
      fakeWasm(),
    );
    const progress = posts.filter((m) => m.type === "progress");
    expect(progress.map((p) => p.done)).toEqual([1, 2, 3]);
    expect(progress.every((p) => p.total === 3)).toBe(true);
  });

  it("tallies inBytes/outBytes across the batch", () => {
    const posts = run(
      { files: [file("a.png", 10), file("b.png", 20)], formats: ["svg"] },
      fakeWasm(),
    );
    const result = posts.at(-1);
    expect(result.inBytes).toBe(30);
    expect(result.outBytes).toBe(2 * "<svg/>".length); // utf-8 encoded length
  });

  it("passes lossless/mono through to the webp encoder", () => {
    const wasm = fakeWasm();
    const spy = vi.spyOn(wasm, "pngToWebp");
    run({ files: [file("a.png")], formats: ["webp"], lossless: true, mono: false }, wasm);
    expect(spy).toHaveBeenCalledWith(expect.any(Uint8Array), 82, true, false);
  });
});
