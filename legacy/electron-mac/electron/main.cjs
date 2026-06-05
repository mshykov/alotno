const { app, BrowserWindow, ipcMain, dialog, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const sharp = require('sharp');
const potrace = require('potrace');

function createWindow() {
  const win = new BrowserWindow({
    width: 900,
    height: 880,
    title: 'Alotno',
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  // Defense-in-depth: this is a local-only app, so block all navigation
  // and external window creation.
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.webContents.on('will-navigate', (e) => e.preventDefault());

  win.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'));
}

app.whenReady().then(createWindow);
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });

ipcMain.handle('pick-folder', async () => {
  const res = await dialog.showOpenDialog({ properties: ['openDirectory', 'createDirectory'] });
  if (res.canceled || !res.filePaths[0]) return null;
  return res.filePaths[0];
});

ipcMain.handle('pick-files', async () => {
  const res = await dialog.showOpenDialog({
    properties: ['openFile', 'multiSelections'],
    filters: [{ name: 'PNG Images', extensions: ['png'] }],
  });
  if (res.canceled) return [];
  return res.filePaths;
});

ipcMain.handle('reveal', async (_e, p) => {
  if (p && fs.existsSync(p)) shell.showItemInFolder(p);
});

// Quality presets — tuned for potrace
const PRESETS = {
  low:    { turdSize: 10, optTolerance: 1.2, alphaMax: 1.0, steps: 2 },
  medium: { turdSize: 4,  optTolerance: 0.6, alphaMax: 1.0, steps: 3 },
  high:   { turdSize: 2,  optTolerance: 0.3, alphaMax: 1.0, steps: 4 },
  ultra:  { turdSize: 1,  optTolerance: 0.15, alphaMax: 1.334, steps: 6 },
};

function traceMono(buffer, opts) {
  return new Promise((resolve, reject) => {
    potrace.trace(buffer, opts, (err, svg) => err ? reject(err) : resolve(svg));
  });
}
function tracePosterized(buffer, opts) {
  return new Promise((resolve, reject) => {
    potrace.posterize(buffer, opts, (err, svg) => err ? reject(err) : resolve(svg));
  });
}

// Convert curves to polylines by flattening cubic Béziers (for "lines only" curve type)
function flattenSvgCurves(svg, steps = 8) {
  return svg.replace(/d="([^"]+)"/g, (m, d) => {
    let cx = 0, cy = 0, sx = 0, sy = 0;
    const tokens = d.match(/[a-zA-Z]|-?\d*\.?\d+(?:e[+-]?\d+)?/g) || [];
    let out = '';
    let i = 0;
    while (i < tokens.length) {
      const t = tokens[i];
      if (/[a-zA-Z]/.test(t)) {
        if (t === 'M' || t === 'm') {
          const x = parseFloat(tokens[i+1]), y = parseFloat(tokens[i+2]);
          cx = t === 'm' ? cx + x : x;
          cy = t === 'm' ? cy + y : y;
          sx = cx; sy = cy;
          out += `M${cx} ${cy} `;
          i += 3;
        } else if (t === 'L' || t === 'l') {
          const x = parseFloat(tokens[i+1]), y = parseFloat(tokens[i+2]);
          cx = t === 'l' ? cx + x : x;
          cy = t === 'l' ? cy + y : y;
          out += `L${cx} ${cy} `;
          i += 3;
        } else if (t === 'C' || t === 'c') {
          const rel = t === 'c';
          const x1 = parseFloat(tokens[i+1]) + (rel?cx:0);
          const y1 = parseFloat(tokens[i+2]) + (rel?cy:0);
          const x2 = parseFloat(tokens[i+3]) + (rel?cx:0);
          const y2 = parseFloat(tokens[i+4]) + (rel?cy:0);
          const x  = parseFloat(tokens[i+5]) + (rel?cx:0);
          const y  = parseFloat(tokens[i+6]) + (rel?cy:0);
          for (let s = 1; s <= steps; s++) {
            const u = s / steps, iu = 1 - u;
            const bx = iu*iu*iu*cx + 3*iu*iu*u*x1 + 3*iu*u*u*x2 + u*u*u*x;
            const by = iu*iu*iu*cy + 3*iu*iu*u*y1 + 3*iu*u*u*y2 + u*u*u*y;
            out += `L${bx.toFixed(2)} ${by.toFixed(2)} `;
          }
          cx = x; cy = y;
          i += 7;
        } else if (t === 'Z' || t === 'z') {
          out += 'Z ';
          cx = sx; cy = sy;
          i += 1;
        } else {
          i += 1;
        }
      } else { i += 1; }
    }
    return `d="${out.trim()}"`;
  });
}

function applySvgVersion(svg, version) {
  // version: '1.0' or '1.1'
  if (version === '1.0') {
    return svg.replace(/<svg([^>]*?)>/, (m, attrs) => {
      let a = attrs.replace(/\s*version="[^"]*"/g, '').replace(/\s*xmlns="[^"]*"/g, '');
      return `<svg${a} version="1.0" xmlns="http://www.w3.org/2000/svg">`;
    });
  }
  return svg.replace(/<svg([^>]*?)>/, (m, attrs) => {
    let a = attrs.replace(/\s*version="[^"]*"/g, '').replace(/\s*xmlns="[^"]*"/g, '');
    return `<svg${a} version="1.1" xmlns="http://www.w3.org/2000/svg">`;
  });
}

function applyStrokeFill(svg, mode, strokeColor, strokeWidth, nonScalingStroke) {
  // mode: 'fill' | 'stroke' | 'both'
  const vectorEffect = nonScalingStroke ? ' vector-effect="non-scaling-stroke"' : '';
  return svg.replace(/<path\s+([^>]*?)\/>/g, (m, attrs) => {
    // strip existing fill/stroke
    let a = attrs
      .replace(/\s*fill="[^"]*"/g, '')
      .replace(/\s*stroke="[^"]*"/g, '')
      .replace(/\s*stroke-width="[^"]*"/g, '')
      .replace(/\s*vector-effect="[^"]*"/g, '');
    // preserve original fill colour (potrace sets fill=)
    const origFill = (attrs.match(/fill="([^"]*)"/) || [, '#000000'])[1];
    let result = '';
    if (mode === 'fill') {
      result = `fill="${origFill}"`;
    } else if (mode === 'stroke') {
      result = `fill="none" stroke="${strokeColor}" stroke-width="${strokeWidth}"${vectorEffect}`;
    } else {
      result = `fill="${origFill}" stroke="${strokeColor}" stroke-width="${strokeWidth}"${vectorEffect}`;
    }
    return `<path ${a.trim()} ${result}/>`;
  });
}

// Convert SVG with M/L/C/Z paths to EPS PostScript
function svgToEps(svg) {
  const widthMatch = svg.match(/width="(\d+(?:\.\d+)?)"/);
  const heightMatch = svg.match(/height="(\d+(?:\.\d+)?)"/);
  const W = widthMatch ? parseFloat(widthMatch[1]) : 1000;
  const H = heightMatch ? parseFloat(heightMatch[1]) : 1000;

  const paths = [...svg.matchAll(/<path\s+([^>]*?)\/>/g)];
  let ps = '';
  ps += '%!PS-Adobe-3.0 EPSF-3.0\n';
  ps += `%%BoundingBox: 0 0 ${Math.ceil(W)} ${Math.ceil(H)}\n`;
  ps += '%%Creator: Alotno\n%%EndComments\n';
  ps += `gsave\n`;

  for (const [, attrs] of paths) {
    const d = (attrs.match(/d="([^"]+)"/) || [, ''])[1];
    const fill = (attrs.match(/fill="([^"]+)"/) || [, '#000000'])[1];
    const stroke = (attrs.match(/stroke="([^"]+)"/) || [])[1];
    const strokeWidth = parseFloat((attrs.match(/stroke-width="([^"]+)"/) || [, '1'])[1]);

    const hexToRgb = (h) => {
      if (!h || h === 'none') return null;
      const x = h.replace('#','');
      const n = x.length === 3 ? x.split('').map(c => c+c).join('') : x;
      return [parseInt(n.slice(0,2),16)/255, parseInt(n.slice(2,4),16)/255, parseInt(n.slice(4,6),16)/255];
    };

    // emit path
    let cx = 0, cy = 0, sx = 0, sy = 0;
    const tokens = d.match(/[a-zA-Z]|-?\d*\.?\d+(?:e[+-]?\d+)?/g) || [];
    let i = 0;
    ps += 'newpath\n';
    const fy = (y) => H - y; // flip y
    while (i < tokens.length) {
      const t = tokens[i];
      if (t === 'M' || t === 'm') {
        const x = parseFloat(tokens[i+1]), y = parseFloat(tokens[i+2]);
        cx = t === 'm' ? cx + x : x;
        cy = t === 'm' ? cy + y : y;
        sx = cx; sy = cy;
        ps += `${cx.toFixed(3)} ${fy(cy).toFixed(3)} moveto\n`;
        i += 3;
      } else if (t === 'L' || t === 'l') {
        const x = parseFloat(tokens[i+1]), y = parseFloat(tokens[i+2]);
        cx = t === 'l' ? cx + x : x;
        cy = t === 'l' ? cy + y : y;
        ps += `${cx.toFixed(3)} ${fy(cy).toFixed(3)} lineto\n`;
        i += 3;
      } else if (t === 'C' || t === 'c') {
        const rel = t === 'c';
        const x1 = parseFloat(tokens[i+1]) + (rel?cx:0);
        const y1 = parseFloat(tokens[i+2]) + (rel?cy:0);
        const x2 = parseFloat(tokens[i+3]) + (rel?cx:0);
        const y2 = parseFloat(tokens[i+4]) + (rel?cy:0);
        const x  = parseFloat(tokens[i+5]) + (rel?cx:0);
        const y  = parseFloat(tokens[i+6]) + (rel?cy:0);
        ps += `${x1.toFixed(3)} ${fy(y1).toFixed(3)} ${x2.toFixed(3)} ${fy(y2).toFixed(3)} ${x.toFixed(3)} ${fy(y).toFixed(3)} curveto\n`;
        cx = x; cy = y;
        i += 7;
      } else if (t === 'Z' || t === 'z') {
        ps += 'closepath\n';
        cx = sx; cy = sy;
        i += 1;
      } else {
        i += 1;
      }
    }

    if (fill && fill !== 'none') {
      const rgb = hexToRgb(fill);
      if (rgb) ps += `${rgb[0].toFixed(3)} ${rgb[1].toFixed(3)} ${rgb[2].toFixed(3)} setrgbcolor\n`;
      ps += stroke && stroke !== 'none' ? 'gsave fill grestore\n' : 'fill\n';
    }
    if (stroke && stroke !== 'none') {
      const rgb = hexToRgb(stroke);
      if (rgb) ps += `${rgb[0].toFixed(3)} ${rgb[1].toFixed(3)} ${rgb[2].toFixed(3)} setrgbcolor\n`;
      ps += `${strokeWidth} setlinewidth\nstroke\n`;
    }
  }
  ps += 'grestore\n%%EOF\n';
  return ps;
}

ipcMain.handle('convert', async (event, payload) => {
  const {
    files, outDir, formats,
    webpQuality, lossless,
    preset = 'high',
    colorMode = 'mono',       // 'mono' | 'posterized'
    posterizeSteps,
    threshold = 128,
    fillStroke = 'fill',      // 'fill' | 'stroke' | 'both'
    strokeColor = '#000000',
    strokeWidth = 1,
    nonScalingStroke = false,
    curveType = 'curves',     // 'curves' | 'lines'
    stacking = 'cutouts',     // 'cutouts' | 'stacked'
    svgVersion = '1.1',
    lineFitTolerance,         // overrides preset optTolerance if set
  } = payload;

  const sender = event.sender;
  const results = [];
  const presetCfg = PRESETS[preset] || PRESETS.high;
  const steps = posterizeSteps || presetCfg.steps;
  const optTolerance = lineFitTolerance != null ? lineFitTolerance : presetCfg.optTolerance;
  // alphaMax=0 forces polygon-only output for mono trace
  const monoAlphaMax = curveType === 'lines' ? 0 : presetCfg.alphaMax;

  for (let i = 0; i < files.length; i++) {
    const input = files[i];
    const base = path.basename(input, path.extname(input));
    const dir = outDir || path.dirname(input);
    const result = { input, webp: null, svg: null, eps: null, errors: {} };

    if (formats.includes('webp')) {
      try {
        const out = path.join(dir, `${base}.webp`);
        await sharp(input).webp({ quality: webpQuality, lossless }).toFile(out);
        result.webp = out;
      } catch (e) { result.errors.webp = e.message; }
    }

    let svgString = null;
    if (formats.includes('svg') || formats.includes('eps')) {
      try {
        const bmp = await sharp(input).flatten({ background: '#ffffff' }).png().toBuffer();
        const baseOpts = {
          turdSize: presetCfg.turdSize,
          optTolerance,
          turnPolicy: potrace.Potrace.TURNPOLICY_MINORITY,
        };
        if (colorMode === 'posterized') {
          // CRITICAL: do NOT pass an explicit threshold to Posterizer when
          // using auto range distribution — it nulls out the histogram and
          // crashes in _calcColorIntensity.
          svgString = await tracePosterized(bmp, {
            ...baseOpts,
            steps,
            // alphaMax controls curve smoothness; keep preset value (don't zero it out)
            alphaMax: presetCfg.alphaMax,
            fillStrategy: stacking === 'stacked'
              ? potrace.Posterizer.FILL_DOMINANT
              : potrace.Posterizer.FILL_SPREAD,
            rangeDistribution: potrace.Posterizer.RANGES_AUTO,
            // threshold omitted on purpose — let Posterizer auto-detect
          });
        } else {
          svgString = await traceMono(bmp, {
            ...baseOpts,
            threshold,
            alphaMax: monoAlphaMax,
            color: '#000000',
          });
        }

        svgString = applySvgVersion(svgString, svgVersion);
        svgString = applyStrokeFill(svgString, fillStroke, strokeColor, strokeWidth, nonScalingStroke);
        if (curveType === 'lines') svgString = flattenSvgCurves(svgString, 6);
      } catch (e) {
        result.errors.svg = e.message;
        if (formats.includes('eps')) result.errors.eps = e.message;
      }
    }

    if (formats.includes('svg') && svgString) {
      try {
        const out = path.join(dir, `${base}.svg`);
        fs.writeFileSync(out, svgString);
        result.svg = out;
      } catch (e) { result.errors.svg = e.message; }
    }

    if (formats.includes('eps') && svgString) {
      try {
        const out = path.join(dir, `${base}.eps`);
        fs.writeFileSync(out, svgToEps(svgString));
        result.eps = out;
      } catch (e) { result.errors.eps = e.message; }
    }

    results.push(result);
    sender.send('convert-progress', { index: i, total: files.length, result });
  }

  return { outDir: outDir || path.dirname(files[0] || ''), results };
});
