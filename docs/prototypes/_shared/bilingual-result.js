// Prototype rendering only: callers supply explicit paragraph and alignment
// groups. This never guesses sentence boundaries or calls a model.
window.BilingualResult = (() => {
  // Reuse the management prototype's copy glyph; SVG keeps its geometry and
  // currentColor consistent across hosts, unlike a font-dependent character.
  const copyIcon = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect width="14" height="14" x="8" y="8" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/></svg>';
  function mount(root, labels, separators = {source: ' ', translation: ''}) {
    root.dataset.sharedBlock = 'bilingual-result';
    root.innerHTML = '<div class="bt-columns"><div class="bt-column-head"><strong></strong><button type="button" class="bt-copy" data-copy-field="source" aria-live="polite"></button></div><div class="bt-column-head"><strong></strong><button type="button" class="bt-copy" data-copy-field="translation" aria-live="polite"></button></div></div><div class="bt-reading"><section class="bt-flow" data-field="source" dir="auto"></section><section class="bt-flow" data-field="translation" dir="auto"></section></div>';
    let selected = new Set(), hovered;
    let copyEpoch = 0;
    const copyTimers = new Map();
    function refreshCopyButtons() {
      root.querySelectorAll('.bt-copy').forEach(button => {
        button.disabled = !root.querySelector(`.bt-flow[data-field="${button.dataset.copyField}"]`).textContent.trim();
      });
    }
    function setLabels(next) {
      labels = next;
      root.querySelectorAll('.bt-column-head').forEach((e,i) => {
        e.querySelector('strong').textContent = next[i];
        const button = e.querySelector('.bt-copy');
        button.innerHTML = copyIcon + '<span class="bt-copy-feedback" role="status"></span>';
        button.title = `${next[2]} ${next[i]}`;
        button.setAttribute('aria-label', button.title);
      });
    }
    function paint() {
      root.querySelectorAll('.bt-sentence').forEach(e => {
        e.classList.toggle('bt-linked', selected.has(e.dataset.id));
        e.classList.toggle('bt-hovered', e.dataset.id === hovered);
      });
    }
    function sentence(group, field) {
      const flow = root.querySelector(`.bt-flow[data-field="${field}"]`);
      let span = [...flow.querySelectorAll('.bt-sentence')].find(e => e.dataset.id === group.id);
      if (span) return span;
      let block = [...flow.querySelectorAll('[data-block]')].find(e => e.dataset.block === group.block);
      if (!block) {
        let parent = flow;
        if (group.list) {
          parent = [...flow.querySelectorAll('.bt-list')].find(e => e.dataset.list === group.list);
          if (!parent) { parent = document.createElement('ol'); parent.className = 'bt-list'; parent.dataset.list = group.list; flow.append(parent); }
        }
        block = document.createElement(group.kind === 'heading' ? 'h2' : group.list ? 'li' : 'p');
        block.className = 'bt-block'; block.dataset.block = group.block; parent.append(block);
      }
      if (block.childNodes.length) block.append(document.createTextNode(separators[field]));
      span = document.createElement('span'); span.className = 'bt-sentence'; span.dataset.id = group.id; span.tabIndex = 0;
      span.append(document.createTextNode('')); block.append(span); paint(); return span;
    }
    function update(group, field, text, pending = false) {
      const span = sentence(group, field), node = span.firstChild;
      if (node.data !== text) {
        if (text.startsWith(node.data)) node.appendData(text.slice(node.length));
        else node.replaceData(0, node.length, text);
      }
      span.classList.toggle('bt-pending', pending);
      refreshCopyButtons();
    }
    function reset() {
      const selection = getSelection();
      if (selection.anchorNode && root.contains(selection.anchorNode)) selection.removeAllRanges();
      root.querySelectorAll('.bt-flow').forEach(e => e.replaceChildren()); selected = new Set(); hovered = undefined;
      copyEpoch++; copyTimers.forEach(clearTimeout); copyTimers.clear(); setLabels(labels); refreshCopyButtons();
    }
    root.addEventListener('pointerover', e => { hovered = e.target.closest('.bt-sentence')?.dataset.id; paint(); });
    root.addEventListener('pointerout', e => { hovered = root.contains(e.relatedTarget) ? e.relatedTarget?.closest?.('.bt-sentence')?.dataset.id : undefined; paint(); });
    root.addEventListener('click', async e => {
      const button = e.target.closest('.bt-copy');
      if (button) {
        const run = copyEpoch;
        const flow = root.querySelector(`.bt-flow[data-field="${button.dataset.copyField}"]`);
        const text = [...flow.children].map(block => block.matches('ol')
          ? [...block.children].map((item,i) => `${i+1}. ${item.textContent}`).join('\n')
          : block.textContent).join('\n\n');
        try {
          await navigator.clipboard.writeText(text);
          if (run !== copyEpoch || !root.isConnected) return;
          button.querySelector('.bt-copy-feedback').textContent = labels[3];
        } catch {
          if (run !== copyEpoch || !root.isConnected) return;
          button.querySelector('.bt-copy-feedback').textContent = labels[4];
        }
        clearTimeout(copyTimers.get(button));
        copyTimers.set(button,setTimeout(() => { button.querySelector('.bt-copy-feedback').textContent = ''; copyTimers.delete(button); },1800));
        return;
      }
      if (!getSelection().isCollapsed) return;
      const span = e.target.closest('.bt-sentence'); selected = new Set(span ? [span.dataset.id] : []); paint();
    });
    root.addEventListener('keydown', e => {
      if (e.key === 'Enter' && e.target.matches('.bt-sentence')) { selected = new Set([e.target.dataset.id]); e.preventDefault(); paint(); }
      if (e.key === 'Escape') { selected = new Set(); paint(); }
    });
    function selectionChanged() {
      const selection = getSelection();
      if (!root.isConnected || !selection.rangeCount || selection.isCollapsed) return;
      const range = selection.getRangeAt(0), ids = new Set();
      for (const span of root.querySelectorAll('.bt-sentence')) {
        if (!range.intersectsNode(span)) continue;
        const content = document.createRange(); content.selectNodeContents(span);
        if (range.compareBoundaryPoints(Range.END_TO_START, content) < 0 && range.compareBoundaryPoints(Range.START_TO_END, content) > 0) ids.add(span.dataset.id);
      }
      selected = ids; paint();
    }
    document.addEventListener('selectionchange', selectionChanged);
    setLabels(labels);
    refreshCopyButtons();
    return {root, sentence, update, reset, setLabels, destroy: () => { copyEpoch++; copyTimers.forEach(clearTimeout); document.removeEventListener('selectionchange', selectionChanged); }};
  }
  return {mount};
})();
