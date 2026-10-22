// Only an explicit user gesture can change the pane that drives synchronized scrolling.
(function (root) {
  function mapPosition(top, sourceMax, targetMax, source, target) {
    if (top <= 0 || targetMax <= 0) return 0;
    if (sourceMax > 0 && top >= sourceMax - 1) return targetMax;
    const targetByID = new Map(target.map(anchor => [anchor.id, anchor]));
    const anchors = source.filter(anchor => targetByID.has(anchor.id));
    if (!anchors.length) return Math.max(0, Math.min(targetMax, sourceMax > 0 ? top / sourceMax * targetMax : 0));
    let index = -1;
    for (let i = 0; i < anchors.length && anchors[i].top <= top; i++) index = i;
    if (index < 0) {
      const first = anchors[0];
      return Math.min(targetMax, top / Math.max(1, first.top) * targetByID.get(first.id).top);
    }
    const anchor = anchors[index], peer = targetByID.get(anchor.id), next = anchors[index + 1];
    const end = next ? next.top : anchor.top + anchor.height;
    const peerEnd = next ? targetByID.get(next.id).top : peer.top + peer.height;
    const fraction = Math.max(0, Math.min(1, (top - anchor.top) / Math.max(1, end - anchor.top)));
    return Math.max(0, Math.min(targetMax, peer.top + fraction * (peerEnd - peer.top)));
  }

  function createController({ sync, frame = requestAnimationFrame, cancelFrame = cancelAnimationFrame }) {
    let owner = null, suspended = false, generation = 0, scheduled = null;
    function cancelScheduled() {
      if (scheduled !== null) cancelFrame(scheduled);
      scheduled = null;
    }
    return {
      get owner() { return owner; },
      claim(index) {
        if (owner !== index || suspended) cancelScheduled();
        generation++; owner = index; suspended = false;
      },
      changed(index) {
        if (owner !== index || suspended || scheduled !== null) return;
        scheduled = frame(() => {
          scheduled = null;
          if (!suspended && owner === index) sync(index);
        });
      },
      suspend() { generation++; suspended = true; cancelScheduled(); },
      resume(afterLayout) {
        const token = generation;
        frame(() => frame(() => {
          if (generation !== token || !suspended) return;
          if (afterLayout) afterLayout();
          suspended = false;
          if (owner !== null) sync(owner);
        }));
      },
      reset() { generation++; owner = null; suspended = false; cancelScheduled(); }
    };
  }
  root.OneReadScroll = { mapPosition, createController };
  if (typeof module !== 'undefined' && module.exports) module.exports = root.OneReadScroll;
})(globalThis);
