function setTheme(theme) {
  document.body.classList.remove('light-theme', 'dark-theme');
  document.body.classList.add(theme + '-theme');
  document.getElementById('themeSwitch').checked = (theme === 'dark');
  localStorage.setItem('theme', theme);
}
// On load, set theme from localStorage or system preference
(function() {
  let theme = localStorage.getItem('theme');
  if (!theme) {
    theme = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }
  setTheme(theme);
})();
document.getElementById('themeSwitch').addEventListener('change', function() {
  setTheme(this.checked ? 'dark' : 'light');
});