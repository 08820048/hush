// The hero's "New" button: a fresh 20-character password, generated in your browser with
// crypto.getRandomValues (uniform, rejection-sampled), every character type at least once.
// Nothing is sent anywhere.
(() => {
  const upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  const lower = "abcdefghijklmnopqrstuvwxyz";
  const digits = "0123456789";
  const symbols = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~";
  const alphabet = upper + lower + digits + symbols;

  function uniform(n) {
    const limit = Math.floor(0x100000000 / n) * n;
    const buf = new Uint32Array(1);
    for (;;) {
      crypto.getRandomValues(buf);
      if (buf[0] < limit) return buf[0] % n;
    }
  }

  function generate(length = 20) {
    for (;;) {
      let s = "";
      for (let i = 0; i < length; i++) s += alphabet[uniform(alphabet.length)];
      if ([upper, lower, digits, symbols].every(set => [...s].some(c => set.includes(c)))) return s;
    }
  }

  function render(target, value) {
    target.textContent = "";
    for (const c of value) {
      const span = document.createElement("span");
      span.textContent = c;
      if (digits.includes(c)) span.className = "n";
      else if (symbols.includes(c)) span.className = "y";
      target.appendChild(span);
    }
  }

  const target = document.getElementById("demo-secret");
  const button = document.getElementById("demo-shuffle");
  if (!target || !button || !window.crypto) return;
  button.addEventListener("click", () => render(target, generate()));
})();
