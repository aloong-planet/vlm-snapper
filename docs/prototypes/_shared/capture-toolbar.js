// Capture overlay shared block: the toolbar attached below a confirmed selection. Each page mounts
// it on an element declaring data-shared-block="capture-toolbar"; styles live in capture-overlay.css.
window.CaptureToolbar = {
  /** The eight handles of a confirmed selection, appended to its box. */
  handles() {
    return ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w']
      .map((edge) => `<span class="selection-handle ${edge}" data-handle="${edge}"></span>`).join('');
  },
  render(mount) {
    mount.innerHTML = `
      <button class="action-button primary"><svg class="icon" viewBox="0 0 24 24"><path d="M4 5h16M4 10h11M4 15h16M4 20h11"/></svg>提取文字</button>
      <button class="action-button"><svg class="icon" viewBox="0 0 24 24"><path d="m5 8 4 4m-6 2 6-6 2-3M4 5h8M13 19l4-10 4 10m-6-4h4"/></svg>翻译</button>
      <span class="toolbar-divider"></span>
      <button class="value-button"><svg class="icon" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a15 15 0 0 1 0 18M12 3a15 15 0 0 0 0 18"/></svg><strong>简体中文</strong><svg class="icon" viewBox="0 0 24 24"><path d="m7 10 5 5 5-5"/></svg></button>
      <button class="value-button model"><svg class="icon" viewBox="0 0 24 24"><path d="M4 7h16v10H4zM8 3v4m8-4v4M8 17v4m8-4v4"/></svg><strong>DeepSeek · deepseek-v4-flash-vision-exp</strong><svg class="icon" viewBox="0 0 24 24"><path d="m7 10 5 5 5-5"/></svg></button>
      <span class="toolbar-divider"></span>
      <button class="tool-button" data-toolbar-action="copy" aria-label="复制图片" title="复制图片"><span class="icon-mask icon-copy"></span></button>
      <button class="tool-button" data-toolbar-action="save" aria-label="保存图片" title="保存图片"><span class="icon-mask icon-save"></span></button>
      <button class="tool-button" data-toolbar-action="cancel" aria-label="取消截图"><svg class="icon" viewBox="0 0 24 24"><path d="M6 6l12 12M18 6 6 18"/></svg></button>
    `;
  }
};
