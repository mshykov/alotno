const { contextBridge, ipcRenderer, webUtils } = require('electron');

contextBridge.exposeInMainWorld('api', {
  pickFolder: () => ipcRenderer.invoke('pick-folder'),
  pickFiles: () => ipcRenderer.invoke('pick-files'),
  convert: (payload) => ipcRenderer.invoke('convert', payload),
  reveal: (p) => ipcRenderer.invoke('reveal', p),
  onProgress: (cb) => {
    const fn = (_e, data) => cb(data);
    ipcRenderer.on('convert-progress', fn);
    return () => ipcRenderer.removeListener('convert-progress', fn);
  },
  getPathForFile: (file) => {
    try {
      const p = webUtils && webUtils.getPathForFile ? webUtils.getPathForFile(file) : null;
      if (p) return p;
    } catch (e) { /* fall through */ }
    // Legacy fallback (older Electron / some platforms)
    try { return file && file.path ? file.path : null; } catch { return null; }
  },
});
