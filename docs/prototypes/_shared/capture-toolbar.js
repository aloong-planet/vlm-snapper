// Capture overlay shared block: the toolbar attached below a confirmed selection. Each page mounts
// it on an element declaring data-shared-block="capture-toolbar"; styles live in capture-overlay.css.
window.CaptureToolbar = {
  /** The eight handles of a confirmed selection, appended to its box. */
  handles() {
    return ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w']
      .map((edge) => `<span class="selection-handle ${edge}" data-handle="${edge}"></span>`).join('');
  },
  /** `current` is the operation whose result box is showing; `busy` means a request is running; `unavailable` lists operations that cannot start now. */
  render(mount, { current = null, busy = false, unavailable = [], language = { short: 'ZH', name: '简体中文' } } = {}) {
    const blocked = (kind) => ((busy && current !== kind) || unavailable.includes(kind) ? ' disabled' : '');
    const whenIdle = busy ? ' disabled' : '';
    mount.innerHTML = `
      <button class="action-button${current === 'extract' ? ' is-current' : ''}" data-operation="extract"${blocked('extract')}><svg class="icon" viewBox="0 0 24 24"><path d="M4 5h16M4 10h11M4 15h16M4 20h11"/></svg>提取</button>
      <div class="split-action${current === 'translate' ? ' is-current' : ''}">
        <button class="split-action-main" data-operation="translate"${blocked('translate')}><svg class="icon" viewBox="0 0 24 24"><path d="m5 8 4 4m-6 2 6-6 2-3M4 5h8M13 19l4-10 4 10m-6-4h4"/></svg>翻译</button>
        <button class="split-action-menu" data-toolbar-language aria-label="目标语言：${language.name}" title="目标语言：${language.name}"><strong>${language.short}</strong><svg class="icon" viewBox="0 0 24 24"><path d="m7 10 5 5 5-5"/></svg></button>
      </div>
      <span class="toolbar-divider"></span>
      <button class="tool-button" data-toolbar-action="copy" aria-label="复制图片" title="复制图片"${whenIdle}><span class="icon-mask icon-copy"></span></button>
      <button class="tool-button" data-toolbar-action="save" aria-label="保存图片" title="保存图片"${whenIdle}><span class="icon-mask icon-save"></span></button>
      <button class="tool-button" data-toolbar-action="cancel" aria-label="取消截图"><svg class="icon" viewBox="0 0 24 24"><path d="M6 6l12 12M18 6 6 18"/></svg></button>
    `;
  }
};
