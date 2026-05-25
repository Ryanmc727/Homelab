// Gulf Wave Home Network — header injection
(function addHeader() {
  const existing = document.getElementById('gw-header');
  if (existing) return;
  const target = document.getElementById('page_container');
  if (!target) { setTimeout(addHeader, 300); return; }
  const header = document.createElement('div');
  header.id = 'gw-header';
  header.textContent = 'Gulf Wave Home Network';
  target.prepend(header);
})();
