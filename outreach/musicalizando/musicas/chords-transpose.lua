-- chords-transpose-v1.lua
-- Cifras ChordPro + controles de tonalidade sonora e capotraste.
--
-- No YAML da música, defina:
--   tom-base: G
--
-- No corpo, continue escrevendo normalmente:
-- ```{.chordpro}
-- [G]Mandacaru quando [C]fulorá na [G]seca
-- ```
--
-- O filtro:
--   1) renderiza os acordes sobre a sílaba correta;
--   2) guarda o acorde original em data-original-chord;
--   3) cria os controles "Tonalidade sonora" e "Capotraste";
--   4) injeta o JavaScript que transpõe os acordes no navegador.
--
-- Não requer Python no servidor nem recompilação ao mudar o tom.

local function html_escape(s)
  s = s:gsub("&", "&amp;")
  s = s:gsub("<", "&lt;")
  s = s:gsub(">", "&gt;")
  s = s:gsub('"', "&quot;")
  return s
end

local function parse_line(line)
  local segments = {}
  local pos = 1
  local current_chord = nil

  while true do
    local a, b, chord = line:find("%[([^%]]+)%]", pos)

    if not a then
      local text = line:sub(pos)
      segments[#segments + 1] = {
        chord = current_chord,
        text = text
      }
      break
    end

    local text_before = line:sub(pos, a - 1)

    if current_chord ~= nil or text_before ~= "" then
      segments[#segments + 1] = {
        chord = current_chord,
        text = text_before
      }
    end

    current_chord = chord
    pos = b + 1
  end

  return segments
end

local function render_line(line)
  if line:match("^%s*$") then
    return '<div class="chordpro-spacer" aria-hidden="true"></div>'
  end

  local segments = parse_line(line)
  local parts = {'<div class="chordpro-line">'}

  for _, seg in ipairs(segments) do
    local chord_html = ""

    if seg.chord ~= nil then
      local chord = html_escape(seg.chord)
      chord_html =
        '<span class="chordpro-chord" data-original-chord="' ..
        chord ..
        '">' ..
        chord ..
        '</span>'
    end

    parts[#parts + 1] =
      '<span class="chordpro-segment">' ..
      chord_html ..
      '<span class="chordpro-lyric">' ..
      html_escape(seg.text) ..
      '</span></span>'
  end

  parts[#parts + 1] = '</div>'
  return table.concat(parts, "")
end

function CodeBlock(el)
  if not el.classes:includes("chordpro") then
    return nil
  end

  if not FORMAT:match("html") then
    return el
  end

  local text = el.text:gsub("\r\n", "\n"):gsub("\r", "\n")
  if text:sub(-1) ~= "\n" then
    text = text .. "\n"
  end

  local parts = {'<div class="chordpro" role="group">'}

  for line in text:gmatch("(.-)\n") do
    parts[#parts + 1] = render_line(line)
  end

  parts[#parts + 1] = '</div>'
  return pandoc.RawBlock("html", table.concat(parts, "\n"))
end

local TRANSPOSE_JS = [=[
<script>
(function () {
  "use strict";

  const NOTE_TO_PC = {
    "C": 0, "C#": 1, "Db": 1,
    "D": 2, "D#": 3, "Eb": 3,
    "E": 4,
    "F": 5, "F#": 6, "Gb": 6,
    "G": 7, "G#": 8, "Ab": 8,
    "A": 9, "A#": 10, "Bb": 10,
    "B": 11
  };

  // Nomes preferidos para tonalidades maiores e menores.
  // A grafia escolhida aqui também orienta a grafia dos acordes exibidos.
  const MAJOR_KEYS = [
    "C", "Db", "D", "Eb", "E", "F",
    "F#", "G", "Ab", "A", "Bb", "B"
  ];

  const MINOR_KEYS = [
    "Cm", "C#m", "Dm", "Ebm", "Em", "Fm",
    "F#m", "Gm", "G#m", "Am", "Bbm", "Bm"
  ];

  const SHARP_NAMES = [
    "C", "C#", "D", "D#", "E", "F",
    "F#", "G", "G#", "A", "A#", "B"
  ];

  const FLAT_NAMES = [
    "C", "Db", "D", "Eb", "E", "F",
    "Gb", "G", "Ab", "A", "Bb", "B"
  ];

  function normalizeAccidentals(s) {
    return String(s)
      .replaceAll("♯", "#")
      .replaceAll("♭", "b");
  }

  function mod12(n) {
    return ((n % 12) + 12) % 12;
  }

  function parseKey(key) {
    key = normalizeAccidentals(key).trim();
    const m = key.match(/^([A-G](?:#|b)?)(m)?$/);
    if (!m) return null;

    const pc = NOTE_TO_PC[m[1]];
    if (pc === undefined) return null;

    return {
      pc: pc,
      minor: Boolean(m[2])
    };
  }

  function keyName(pc, minor) {
    return (minor ? MINOR_KEYS : MAJOR_KEYS)[mod12(pc)];
  }

  function prefersFlats(keyLabel) {
    return normalizeAccidentals(keyLabel).includes("b");
  }

  function transposeNote(note, semitones, useFlats) {
    note = normalizeAccidentals(note);
    const pc = NOTE_TO_PC[note];
    if (pc === undefined) return note;

    const names = useFlats ? FLAT_NAMES : SHARP_NAMES;
    return names[mod12(pc + semitones)];
  }

  function transposeChord(chord, semitones, useFlats) {
    chord = normalizeAccidentals(chord).trim();

    // Fundamental no início.
    const m = chord.match(/^([A-G](?:#|b)?)(.*)$/);
    if (!m) return chord;

    const newRoot = transposeNote(m[1], semitones, useFlats);
    let rest = m[2];

    // Baixo de acorde invertido no final: D/F#, C/E etc.
    rest = rest.replace(
      /\/([A-G](?:#|b)?)$/,
      function (_, bass) {
        return "/" + transposeNote(bass, semitones, useFlats);
      }
    );

    return newRoot + rest;
  }

  function initPanel(panel) {
    const baseRaw = panel.dataset.baseKey || "";
    const parsed = parseKey(baseRaw);

    if (!parsed) {
      panel.classList.add("transpose-panel-error");
      panel.innerHTML =
        '<strong>Transposição:</strong> defina <code>tom-base:</code> ' +
        'no YAML da música (por exemplo, <code>tom-base: G</code>).';
      return;
    }

    const soundSelect = panel.querySelector(".transpose-sound-key");
    const capoSelect = panel.querySelector(".transpose-capo");
    const baseLabel = panel.querySelector(".transpose-base-key");
    const shapeLabel = panel.querySelector(".transpose-shape-key");
    const resetButton = panel.querySelector(".transpose-reset");

    const names = parsed.minor ? MINOR_KEYS : MAJOR_KEYS;

    names.forEach(function (name, pc) {
      const opt = document.createElement("option");
      opt.value = String(pc);
      opt.textContent = name;
      soundSelect.appendChild(opt);
    });

    for (let capo = 0; capo <= 12; capo += 1) {
      const opt = document.createElement("option");
      opt.value = String(capo);
      if (capo === 0) {
        opt.textContent = "0 (sem capo)";
      } else {
        opt.textContent = String(capo);
      }
      capoSelect.appendChild(opt);
    }

    baseLabel.textContent = keyName(parsed.pc, parsed.minor);
    soundSelect.value = String(parsed.pc);
    capoSelect.value = "0";

    const chordEls = Array.from(
      document.querySelectorAll(".chordpro-chord[data-original-chord]")
    );

    function update() {
      const soundPc = Number(soundSelect.value);
      const capo = Number(capoSelect.value);

      // A forma tocada no violão precisa estar "capo" semitons abaixo
      // da tonalidade sonora escolhida.
      const shapePc = mod12(soundPc - capo);
      const shapeKey = keyName(shapePc, parsed.minor);
      const useFlats = prefersFlats(shapeKey);

      // A cifra original está escrita no tom-base.
      // Alteração aplicada às FORMAS mostradas:
      // (tom sonoro - tom base) - capo
      const delta = mod12(soundPc - parsed.pc - capo);

      chordEls.forEach(function (el) {
        const original = el.dataset.originalChord;
        el.textContent = transposeChord(original, delta, useFlats);
      });

      shapeLabel.textContent = shapeKey;
    }

    soundSelect.addEventListener("change", update);
    capoSelect.addEventListener("change", update);

    if (resetButton) {
      resetButton.addEventListener("click", function () {
        soundSelect.value = String(parsed.pc);
        capoSelect.value = "0";
        update();
      });
    }

    update();
  }

  function init() {
    document.querySelectorAll(".transpose-panel").forEach(initPanel);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
</script>
]=]

local function transpose_panel(base_key)
  local key = html_escape(base_key)

  return pandoc.RawBlock("html", [=[
<div class="transpose-panel" data-base-key="]=] .. key .. [=[">
  <div class="transpose-field transpose-original">
    <span class="transpose-label">Tom base</span>
    <strong class="transpose-base-key">]=] .. key .. [=[</strong>
  </div>

  <label class="transpose-field">
    <span class="transpose-label">Tonalidade sonora</span>
    <select class="transpose-sound-key" aria-label="Tonalidade sonora"></select>
  </label>

  <label class="transpose-field">
    <span class="transpose-label">Capotraste</span>
    <select class="transpose-capo" aria-label="Casa do capotraste"></select>
  </label>

  <div class="transpose-field transpose-shape">
    <span class="transpose-label">Acordes exibidos</span>
    <strong class="transpose-shape-key"></strong>
  </div>

  <button type="button" class="transpose-reset">Original</button>
</div>
]=])
end

function Pandoc(doc)
  if not FORMAT:match("html") then
    return doc
  end

  local base_meta = doc.meta["tom-base"]

  if base_meta ~= nil then
    local base_key = pandoc.utils.stringify(base_meta)
    table.insert(doc.blocks, 1, transpose_panel(base_key))
  else
    table.insert(doc.blocks, 1, pandoc.RawBlock("html", [=[
<div class="transpose-panel transpose-panel-error">
  <strong>Transposição:</strong>
  defina <code>tom-base:</code> no YAML da música.
</div>
]=]))
  end

  table.insert(doc.blocks, pandoc.RawBlock("html", TRANSPOSE_JS))
  return doc
end
