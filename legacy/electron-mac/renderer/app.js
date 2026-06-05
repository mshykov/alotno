const state = {
  files: [],
  outDir: null,
  lastOutPath: null,
};

const $ = (id) => document.getElementById(id);
const drop = $('drop');
const list = $('list');

function render() {
  $('count').textContent = `(${state.files.length})`;
  list.innerHTML = '';
  for (const f of state.files) {
    const li = document.createElement('li');
    const name = document.createElement('span');
    name.className = 'fname';
    name.textContent = f.name;
    const status = document.createElement('span');
    status.className = 'status';
    const parts = [];
    const esc = (s) => String(s ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
    const fmtTag = (label, st, err) => {
      if (st === 'ok') return `<span class="ok">${label} ✓</span>`;
      if (st === 'err') return `<span class="err" title="${esc(err)}">${label} ✗</span>`;
      if (st === 'pending') return `<span class="pending">${label}…</span>`;
      return '';
    };
    if (f.webp !== null) parts.push(fmtTag('webp', f.webp, f.webpErr));
    if (f.svg !== null) parts.push(fmtTag('svg', f.svg, f.svgErr));
    if (f.eps !== null) parts.push(fmtTag('eps', f.eps, f.epsErr));
    status.innerHTML = parts.join(' &nbsp; ');
    li.append(name, status);
    list.appendChild(li);
  }
  $('convert').disabled = state.files.length === 0;
}

function addPaths(paths) {
  const seen = new Set(state.files.map((f) => f.path));
  let added = 0, skipped = 0;
  for (const p of paths) {
    if (!p) { skipped++; continue; }
    if (seen.has(p)) continue;
    if (!p.toLowerCase().endsWith('.png')) { skipped++; continue; }
    state.files.push({ path: p, name: p.split('/').pop(), webp: null, svg: null, eps: null });
    added++;
  }
  render();
  if (added === 0 && paths.length > 0) {
    alert(`Couldn't read file paths from the drop (got ${paths.length} item(s), ${skipped} skipped). Try clicking the dropzone to browse instead.`);
  }
}

['dragenter', 'dragover'].forEach((ev) =>
  drop.addEventListener(ev, (e) => { e.preventDefault(); e.stopPropagation(); drop.classList.add('drag'); })
);
['dragleave'].forEach((ev) =>
  drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.remove('drag'); })
);
drop.addEventListener('drop', (e) => {
  e.preventDefault();
  e.stopPropagation();
  drop.classList.remove('drag');
  const paths = [];
  const files = e.dataTransfer ? Array.from(e.dataTransfer.files || []) : [];
  for (const file of files) {
    const p = window.api.getPathForFile(file);
    if (p) paths.push(p);
  }
  addPaths(paths);
});
drop.addEventListener('click', async () => {
  const paths = await window.api.pickFiles();
  addPaths(paths);
});
$('browse').addEventListener('click', (e) => { e.stopPropagation(); drop.click(); });

$('quality').addEventListener('input', (e) => { $('qval').textContent = e.target.value; });
$('threshold').addEventListener('input', (e) => { $('thval').textContent = e.target.value; });
$('tolerance').addEventListener('input', (e) => {
  const v = parseInt(e.target.value, 10);
  $('tolval').textContent = v === 0 ? 'preset' : (v / 100).toFixed(2);
});
$('pick-out').addEventListener('click', async () => {
  const p = await window.api.pickFolder();
  if (p) { state.outDir = p; $('outdir').textContent = p; }
});
$('clear-out').addEventListener('click', () => {
  state.outDir = null; $('outdir').textContent = 'Same as source file';
});
$('clear').addEventListener('click', () => { state.files = []; render(); });

window.api.onProgress(({ index, result }) => {
  const f = state.files[index];
  if (!f) return;
  if (f.webp === 'pending') { f.webp = result.webp ? 'ok' : 'err'; f.webpOut = result.webp; f.webpErr = result.errors?.webp; }
  if (f.svg === 'pending')  { f.svg  = result.svg  ? 'ok' : 'err'; f.svgOut  = result.svg;  f.svgErr  = result.errors?.svg; }
  if (f.eps === 'pending')  { f.eps  = result.eps  ? 'ok' : 'err'; f.epsOut  = result.eps;  f.epsErr  = result.errors?.eps; }
  state.lastOutPath = result.webp || result.svg || result.eps || state.lastOutPath;
  render();
});

$('convert').addEventListener('click', async () => {
  const formats = [];
  if ($('fmt-webp').checked) formats.push('webp');
  if ($('fmt-svg').checked)  formats.push('svg');
  if ($('fmt-eps').checked)  formats.push('eps');
  if (formats.length === 0) { alert('Select at least one output format.'); return; }

  for (const f of state.files) {
    f.webp = formats.includes('webp') ? 'pending' : null;
    f.svg  = formats.includes('svg')  ? 'pending' : null;
    f.eps  = formats.includes('eps')  ? 'pending' : null;
    f.webpErr = f.svgErr = f.epsErr = undefined;
  }
  render();

  const tolRaw = parseInt($('tolerance').value, 10);
  $('convert').disabled = true;
  try {
    const res = await window.api.convert({
      files: state.files.map((f) => f.path),
      outDir: state.outDir,
      formats,
      webpQuality: parseInt($('quality').value, 10),
      lossless: $('lossless').checked,
      preset: $('preset').value,
      colorMode: $('color-mode').value,
      posterizeSteps: parseInt($('poster-steps').value, 10),
      threshold: parseInt($('threshold').value, 10),
      lineFitTolerance: tolRaw === 0 ? null : tolRaw / 100,
      fillStroke: $('fill-stroke').value,
      strokeColor: $('stroke-color').value,
      strokeWidth: parseFloat($('stroke-width').value),
      nonScalingStroke: $('non-scaling').checked,
      curveType: $('curve-type').value,
      stacking: $('stacking').value,
      svgVersion: $('svg-version').value,
    });
    if (res.results?.length) {
      const last = res.results[res.results.length - 1];
      state.lastOutPath = last.webp || last.svg || last.eps || state.lastOutPath;
    }
    $('reveal').disabled = !state.lastOutPath;
  } finally {
    $('convert').disabled = false;
  }
});

$('reveal').addEventListener('click', () => {
  if (state.lastOutPath) window.api.reveal(state.lastOutPath);
});

render();
