-- chords-transpose-v6.lua — CAMPO HARMÔNICO + 2 SHAPES
-- Cifras ChordPro + tonalidade sonora + capotraste + modo cantor.
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

  /*
    Campo harmônico maior mostrado para as FORMAS efetivamente tocadas.
    Portanto, o capo já está incorporado: se a música soa em G com capo 2,
    o campo mostrado é o de F.
  */
  const HARMONIC_FIELDS_MAJOR = {
    "C":  ["C", "Dm", "Em", "F", "G", "Am", "Bdim"],
    "Db": ["Db", "Ebm", "Fm", "Gb", "Ab", "Bbm", "Cdim"],
    "D":  ["D", "Em", "F#m", "G", "A", "Bm", "C#dim"],
    "Eb": ["Eb", "Fm", "Gm", "Ab", "Bb", "Cm", "Ddim"],
    "E":  ["E", "F#m", "G#m", "A", "B", "C#m", "D#dim"],
    "F":  ["F", "Gm", "Am", "Bb", "C", "Dm", "Edim"],
    "F#": ["F#", "G#m", "A#m", "B", "C#", "D#m", "E#dim"],
    "G":  ["G", "Am", "Bm", "C", "D", "Em", "F#dim"],
    "Ab": ["Ab", "Bbm", "Cm", "Db", "Eb", "Fm", "Gdim"],
    "A":  ["A", "Bm", "C#m", "D", "E", "F#m", "G#dim"],
    "Bb": ["Bb", "Cm", "Dm", "Eb", "F", "Gm", "Adim"],
    "B":  ["B", "C#m", "D#m", "E", "F#", "G#m", "A#dim"]
  };

  const HARMONIC_DEGREES = [
    { degree: "I",    func: "Tônica" },
    { degree: "ii",   func: "Supertônica" },
    { degree: "iii",  func: "Mediante" },
    { degree: "IV",   func: "Subdominante" },
    { degree: "V",    func: "Dominante" },
    { degree: "vi",   func: "Relativa menor" },
    { degree: "vii°", func: "Sensível" }
  ];

  /*
    SHAPE 1 — "Dedilhado":
    reproduz os voicings do guitar.qmd enviado pelo usuário.
    Para os três nomes necessários ao campo de F# que não aparecem
    literalmente no pôster (C#, A#m e E#dim), são usados equivalentes
    enarmônicos / transposição direta no mesmo estilo.
  */
  const SOURCE_GUITAR_SHAPES = {
    "Db":   ["x", 4, "x", 1, 2, 1],
    "C#":   ["x", 4, "x", 1, 2, 1],
    "Ab":   [4, "x", 1, 1, 1, "x"],
    "Eb":   ["x", "x", 1, 3, 4, 3],
    "Bb":   ["x", 1, 0, 3, 3, 1],
    "F":    [1, 0, 3, 2, 1, "x"],
    "C":    [0, 3, 2, 0, 1, 0],
    "G":    [3, "x", 0, 0, 0, "x"],
    "D":    ["x", 0, 0, 2, 3, 2],
    "A":    [0, 0, 2, 2, 2, 0],
    "E":    [0, 2, 2, 1, 0, 0],
    "B":    ["x", 2, 4, 4, 4, "x"],
    "Gb":   [2, "x", 4, 3, 2, "x"],
    "F#":   [2, "x", 4, 3, 2, "x"],

    "Ebm":  ["x", "x", 1, 3, 4, 2],
    "Bbm":  ["x", 1, "x", 3, 2, 1],
    "A#m":  ["x", 1, "x", 3, 2, 1],
    "Fm":   [1, "x", 3, 1, 1, "x"],
    "Cm":   ["x", 3, 1, 0, 1, "x"],
    "Gm":   [3, "x", 0, 3, 3, "x"],
    "Dm":   ["x", 0, 0, 2, 3, 1],
    "Am":   [0, 0, 2, 2, 1, 0],
    "Em":   [0, "x", "x", 0, 0, 0],
    "Bm":   ["x", 2, 4, 4, 3, "x"],
    "F#m":  [2, 0, 4, 2, 2, "x"],
    "C#m":  ["x", "x", 2, 1, 2, 0],
    "G#m":  [4, "x", 1, 1, 0, "x"],
    "D#m":  ["x", "x", 1, 3, 4, 2],

    "Cdim":  ["x", 3, "x", 5, 4, 2],
    "Gdim":  [3, "x", "x", 3, 2, 3],
    "Ddim":  ["x", "x", 0, 1, 3, 1],
    "Adim":  ["x", 0, 1, 2, 1, "x"],
    "Edim":  [0, 1, 2, 0, "x", 0],
    "Bdim":  ["x", 2, 3, 4, 3, "x"],
    "F#dim": [2, 0, "x", 2, 1, 2],
    "C#dim": [0, 4, 2, 0, 2, 0],
    "G#dim": [4, "x", 0, 4, 3, 4],
    "D#dim": ["x", 0, 1, 2, 4, 2],
    "A#dim": [0, 1, 2, 3, 2, 0],

    /* E#dim = Fdim, derivado por transposição do shape de Edim. */
    "E#dim": [1, 2, 3, 1, "x", 1]
  };

  /*
    SHAPE 2 — "Popular":
    formas abertas tradicionais quando elas são usuais; caso contrário,
    shapes móveis de pestana (E-shape / A-shape). Para diminutos,
    usa-se uma forma móvel compacta de tríade.
  */
  const POPULAR_GUITAR_SHAPES = {
    "C":  ["x", 3, 2, 0, 1, 0],
    "Db": ["x", 4, 6, 6, 6, 4],
    "C#": ["x", 4, 6, 6, 6, 4],
    "D":  ["x", "x", 0, 2, 3, 2],
    "Eb": ["x", 6, 8, 8, 8, 6],
    "E":  [0, 2, 2, 1, 0, 0],
    "F":  [1, 3, 3, 2, 1, 1],
    "F#": [2, 4, 4, 3, 2, 2],
    "Gb": [2, 4, 4, 3, 2, 2],
    "G":  [3, 2, 0, 0, 0, 3],
    "Ab": [4, 6, 6, 5, 4, 4],
    "A":  ["x", 0, 2, 2, 2, 0],
    "Bb": ["x", 1, 3, 3, 3, 1],
    "B":  ["x", 2, 4, 4, 4, 2],

    "Cm":  ["x", 3, 5, 5, 4, 3],
    "C#m": ["x", 4, 6, 6, 5, 4],
    "Dm":  ["x", "x", 0, 2, 3, 1],
    "Ebm": ["x", 6, 8, 8, 7, 6],
    "D#m": ["x", 6, 8, 8, 7, 6],
    "Em":  [0, 2, 2, 0, 0, 0],
    "Fm":  [1, 3, 3, 1, 1, 1],
    "F#m": [2, 4, 4, 2, 2, 2],
    "Gm":  [3, 5, 5, 3, 3, 3],
    "G#m": [4, 6, 6, 4, 4, 4],
    "Am":  ["x", 0, 2, 2, 1, 0],
    "Bbm": ["x", 1, 3, 3, 2, 1],
    "A#m": ["x", 1, 3, 3, 2, 1],
    "Bm":  ["x", 2, 4, 4, 3, 2],

    "Cdim":  ["x", 3, 4, 5, 4, "x"],
    "C#dim": ["x", 4, 5, 6, 5, "x"],
    "Ddim":  ["x", 5, 6, 7, 6, "x"],
    "D#dim": ["x", 6, 7, 8, 7, "x"],
    "Edim":  ["x", 7, 8, 9, 8, "x"],
    "E#dim": ["x", 8, 9, 10, 9, "x"],
    "Fdim":  ["x", 8, 9, 10, 9, "x"],
    "F#dim": ["x", 9, 10, 11, 10, "x"],
    "Gdim":  ["x", 10, 11, 12, 11, "x"],
    "G#dim": ["x", 11, 12, 13, 12, "x"],
    "Adim":  ["x", 12, 13, 14, 13, "x"],
    "A#dim": ["x", 13, 14, 15, 14, "x"],
    "Bdim":  ["x", 2, 3, 4, 3, "x"]
  };

  function guitarBaseFret(frets) {
    const pressed = frets.filter(function (value) {
      return typeof value === "number" && value > 0;
    });

    if (pressed.length === 0) return 1;

    const highest = Math.max.apply(null, pressed);
    const lowest = Math.min.apply(null, pressed);

    if (highest <= 5) return 1;
    return lowest;
  }

  function guitarFingeringCode(frets) {
    return frets.map(function (value) {
      return String(value).toUpperCase();
    }).join(" ");
  }

  function guitarChordSVG(frets, label) {
    if (!Array.isArray(frets)) return "";

    const baseFret = guitarBaseFret(frets);
    const width = 80;
    const height = 98;
    const stringX = [12, 23, 34, 45, 56, 67];
    const top = 22;
    const spacing = 10.5;
    const fretCount = 5;
    const bottom = top + spacing * fretCount;

    let svg =
      '<svg class="harmonic-chord-svg" viewBox="0 0 ' + width + ' ' + height + '"' +
      ' role="img" aria-label="' + label + '">' +
      '<rect x="0" y="0" width="' + width + '" height="' + height + '" fill="transparent"/>';

    frets.forEach(function (fret, stringIndex) {
      const x = stringX[stringIndex];

      if (fret === "x") {
        svg += '<text class="harmonic-string-mark" x="' + x + '" y="11">X</text>';
      } else if (fret === 0) {
        svg += '<circle class="harmonic-open-string" cx="' + x + '" cy="8" r="3.3"/>';
      }
    });

    if (baseFret > 1) {
      svg +=
        '<text class="harmonic-base-fret" x="1" y="' +
        (top + spacing * 1.55) + '">' + baseFret + 'ª</text>';
    }

    stringX.forEach(function (x, index) {
      const sw = Math.max(0.75, 1.3 - index * 0.08);
      svg +=
        '<line class="harmonic-string" x1="' + x + '" y1="' + top +
        '" x2="' + x + '" y2="' + bottom + '" stroke-width="' + sw + '"/>';
    });

    for (let fretLine = 0; fretLine <= fretCount; fretLine += 1) {
      const y = top + fretLine * spacing;
      const sw = (fretLine === 0 && baseFret === 1) ? 2.6 : 0.9;

      svg +=
        '<line class="harmonic-fret" x1="' + stringX[0] + '" y1="' + y +
        '" x2="' + stringX[stringX.length - 1] + '" y2="' + y +
        '" stroke-width="' + sw + '"/>';
    }

    frets.forEach(function (fret, stringIndex) {
      if (typeof fret !== "number" || fret <= 0) return;

      const relative = fret - baseFret + 1;
      if (relative < 1 || relative > fretCount) return;

      const x = stringX[stringIndex];
      const y = top + (relative - 0.5) * spacing;

      svg +=
        '<circle class="harmonic-finger" cx="' + x + '" cy="' + y + '" r="3.7"/>';
    });

    svg += '</svg>';
    return svg;
  }

  function harmonicVoicingHTML(chordName, label, frets) {
    if (!Array.isArray(frets)) {
      return '<div class="harmonic-voicing harmonic-voicing-missing">' +
        '<span class="harmonic-voicing-label">' + label + '</span>' +
        '<span>—</span></div>';
    }

    return (
      '<div class="harmonic-voicing">' +
        '<span class="harmonic-voicing-label">' + label + '</span>' +
        guitarChordSVG(frets, chordName + " — " + label) +
        '<code class="harmonic-fingering">' + guitarFingeringCode(frets) + '</code>' +
      '</div>'
    );
  }

  function renderHarmonicField(shapeKey, soundKey, capo) {
    const container = document.querySelector(".harmonic-field-panel");
    if (!container) return;

    /*
      O material-fonte é de campos harmônicos maiores.
      Para músicas menores, o painel é ocultado em vez de inventar
      uma regra de campo menor não presente no anexo.
    */
    if (!shapeKey || shapeKey.endsWith("m")) {
      container.hidden = true;
      return;
    }

    const field = HARMONIC_FIELDS_MAJOR[shapeKey];
    if (!field) {
      container.hidden = true;
      return;
    }

    const title = container.querySelector(".harmonic-field-title");
    const context = container.querySelector(".harmonic-field-context");
    const grid = container.querySelector(".harmonic-field-grid");

    title.textContent = "Campo harmônico — formas em " + shapeKey;

    if (Number(capo) > 0) {
      context.textContent =
        "Tom sonoro: " + soundKey + " • capo " + capo +
        " • diagramas correspondem às formas tocadas";
    } else {
      context.textContent =
        "Tom sonoro: " + soundKey + " • sem capo";
    }

    grid.innerHTML = field.map(function (chordName, index) {
      const degree = HARMONIC_DEGREES[index];
      const source = SOURCE_GUITAR_SHAPES[chordName];
      const popular = POPULAR_GUITAR_SHAPES[chordName];

      return (
        '<article class="harmonic-chord-card">' +
          '<header class="harmonic-chord-head">' +
            '<span class="harmonic-degree">' + degree.degree + '</span>' +
            '<strong class="harmonic-chord-name">' + chordName + '</strong>' +
            '<span class="harmonic-function">' + degree.func + '</span>' +
          '</header>' +
          '<div class="harmonic-voicings">' +
            harmonicVoicingHTML(chordName, "Dedilhado", source) +
            harmonicVoicingHTML(chordName, "Popular", popular) +
          '</div>' +
        '</article>'
      );
    }).join("");

    container.hidden = false;
  }

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
    const lyricsOnly = panel.querySelector(".transpose-lyrics-only");
    const twoColumns = panel.querySelector(".transpose-two-columns");

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
      const soundKey = keyName(soundPc, parsed.minor);
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
      renderHarmonicField(shapeKey, soundKey, capo);
      scheduleTwoPageFit();
    }

    function updateViewMode() {
      const onlyLyrics = Boolean(lyricsOnly && lyricsOnly.checked);
      const useTwoColumns = Boolean(twoColumns && twoColumns.checked);

      document.body.classList.toggle("lyrics-only-mode", onlyLyrics);
      document.body.classList.toggle("two-column-mode", useTwoColumns);

      panel.classList.toggle("lyrics-only-active", onlyLyrics);
      panel.classList.toggle("two-columns-active", useTwoColumns);

      scheduleTwoPageFit();
    }

    soundSelect.addEventListener("change", update);
    capoSelect.addEventListener("change", update);

    if (lyricsOnly) {
      lyricsOnly.addEventListener("change", updateViewMode);
    }

    if (twoColumns) {
      twoColumns.addEventListener("change", updateViewMode);
    }

    if (resetButton) {
      resetButton.addEventListener("click", function () {
        soundSelect.value = String(parsed.pc);
        capoSelect.value = "0";
        if (lyricsOnly) {
          lyricsOnly.checked = false;
        }
        if (twoColumns) {
          twoColumns.checked = false;
        }
        update();
        updateViewMode();
      });
    }

    update();
    updateViewMode();
  }

  function initAutoscroll() {
    const dock = document.querySelector(".autoscroll-dock");
    if (!dock) return;

    const slider = dock.querySelector(".autoscroll-slider");
    const state = dock.querySelector(".autoscroll-state");
    if (!slider || !state) return;

    let rafId = null;
    let lastTs = null;

    const MAX_SPEED = 720;
    const DEAD_ZONE = 3;

    function speedFromSlider() {
      const v = Number(slider.value);
      if (Math.abs(v) <= DEAD_ZONE) return 0;

      const sign = v < 0 ? -1 : 1;
      const normalized = Math.abs(v) / 100;
      return sign * Math.pow(normalized, 1.65) * MAX_SPEED;
    }

    function stop() {
      slider.value = "0";
      state.textContent = "parado";
      dock.classList.remove("autoscroll-active");
      lastTs = null;

      if (rafId !== null) {
        cancelAnimationFrame(rafId);
        rafId = null;
      }
    }

    function updateState(speed) {
      if (speed < 0) {
        state.textContent = "subindo";
        dock.classList.add("autoscroll-active");
      } else if (speed > 0) {
        state.textContent = "descendo";
        dock.classList.add("autoscroll-active");
      } else {
        state.textContent = "parado";
        dock.classList.remove("autoscroll-active");
      }
    }

    function tick(ts) {
      const speed = speedFromSlider();

      if (speed === 0) {
        stop();
        return;
      }

      if (lastTs === null) lastTs = ts;
      const dt = Math.min((ts - lastTs) / 1000, 0.05);
      lastTs = ts;

      window.scrollBy(0, speed * dt);

      const maxScroll = Math.max(
        0,
        document.documentElement.scrollHeight - window.innerHeight
      );

      if ((speed < 0 && window.scrollY <= 0) ||
          (speed > 0 && window.scrollY >= maxScroll - 1)) {
        stop();
        return;
      }

      rafId = requestAnimationFrame(tick);
    }

    function onInput() {
      const speed = speedFromSlider();
      updateState(speed);

      if (speed === 0) {
        stop();
        return;
      }

      if (rafId === null) {
        lastTs = null;
        rafId = requestAnimationFrame(tick);
      }
    }

    slider.addEventListener("input", onInput);
    slider.addEventListener("change", onInput);

    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape") stop();
    });

    document.addEventListener("visibilitychange", function () {
      if (document.hidden) stop();
    });

    stop();
  }

  let twoPageFitRaf = null;

  function prepareSongMiniPages() {
    const content = document.querySelector(".song-content");
    if (!content || content.dataset.minipagesReady === "1") return;

    const originalChildren = Array.from(content.children);
    if (originalChildren.length === 0) return;

    const sections = [];

    // Quarto normalmente transforma cada ## em <section class="level2">.
    // Esses sections devem ser tratados como unidades musicais completas.
    const level2 = originalChildren.filter(function (node) {
      return node.matches && node.matches("section.level2");
    });

    if (level2.length > 0) {
      level2.forEach(function (node) {
        node.classList.add("song-section");
        sections.push(node);
      });
    } else {
      // Fallback para HTML sem section-divs: agrupa por H2.
      let current = null;

      originalChildren.forEach(function (node) {
        if (node.matches && node.matches("h2")) {
          current = document.createElement("section");
          current.className = "song-section";
          sections.push(current);
        }

        if (!current) {
          current = document.createElement("section");
          current.className = "song-section";
          sections.push(current);
        }

        current.appendChild(node);
      });
    }

    if (sections.length === 0) return;

    const staging = document.createElement("div");
    staging.className = "song-minipage-staging";
    sections.forEach(function (section) {
      staging.appendChild(section);
    });
    content.appendChild(staging);

    const heights = sections.map(function (section) {
      return Math.max(1, section.getBoundingClientRect().height);
    });

    let splitIndex = 1;

    if (sections.length > 1) {
      const total = heights.reduce(function (a, b) { return a + b; }, 0);
      let cumulative = 0;
      let bestDistance = Infinity;

      for (let i = 1; i <= sections.length - 1; i += 1) {
        cumulative += heights[i - 1];
        const distance = Math.abs(cumulative - total / 2);

        if (distance < bestDistance) {
          bestDistance = distance;
          splitIndex = i;
        }
      }

      splitIndex = Math.max(1, Math.min(sections.length - 1, splitIndex));
    }

    const spread = document.createElement("div");
    spread.className = "song-spread";

    const left = document.createElement("div");
    left.className = "song-page song-page-left";

    const right = document.createElement("div");
    right.className = "song-page song-page-right";

    sections.forEach(function (section, index) {
      if (sections.length === 1 || index < splitIndex) {
        left.appendChild(section);
      } else {
        right.appendChild(section);
      }
    });

    spread.appendChild(left);
    spread.appendChild(right);

    staging.remove();
    content.appendChild(spread);

    content.dataset.minipagesReady = "1";
    content.dataset.minipageSections = String(sections.length);
    content.dataset.minipageSplit = String(splitIndex);
  }

  function measurePageOverflow(page) {
    const available = Math.max(1, page.clientWidth - 8);
    let widest = 0;

    page.querySelectorAll(".chordpro-line").forEach(function (line) {
      const lineRect = line.getBoundingClientRect();
      let rightmost = line.scrollWidth;

      line.querySelectorAll(".chordpro-lyric, .chordpro-chord").forEach(function (el) {
        const rect = el.getBoundingClientRect();
        rightmost = Math.max(rightmost, rect.right - lineRect.left);
      });

      widest = Math.max(widest, rightmost);
    });

    return widest / available;
  }

  function fitOneSongPage(page) {
    page.style.removeProperty("--two-page-chord-size");

    const firstChordPro = page.querySelector(".chordpro");
    if (!firstChordPro) return;

    // Mede usando o tamanho-base específico do modo de duas páginas.
    const baseSize = parseFloat(getComputedStyle(firstChordPro).fontSize);
    if (!Number.isFinite(baseSize) || baseSize <= 0) return;

    const overflowRatio = measurePageOverflow(page);

    // 0.965 deixa uma pequena folga para acordes longos no fim das frases.
    let scale = overflowRatio > 1 ? (0.965 / overflowRatio) : 1;

    // Evita letras minúsculas. Em vez disso, usa toda a largura disponível
    // e só reduz até um limite ainda confortável.
    scale = Math.max(0.58, Math.min(1, scale));

    page.style.setProperty(
      "--two-page-chord-size",
      (baseSize * scale).toFixed(2) + "px"
    );
  }

  function fitTwoPages() {
    twoPageFitRaf = null;

    const pages = Array.from(document.querySelectorAll(".song-page"));

    if (!document.body.classList.contains("two-column-mode") ||
        window.innerWidth < 980) {
      pages.forEach(function (page) {
        page.style.removeProperty("--two-page-chord-size");
      });
      return;
    }

    pages.forEach(fitOneSongPage);

    // Uma segunda medição curta corrige diferenças causadas por acordes
    // transpostos mais largos e arredondamento de pixels.
    requestAnimationFrame(function () {
      pages.forEach(function (page) {
        const ratio = measurePageOverflow(page);

        if (ratio > 1.015) {
          const current = parseFloat(
            getComputedStyle(page.querySelector(".chordpro")).fontSize
          );

          if (Number.isFinite(current) && current > 0) {
            const corrected = Math.max(15, current * (0.975 / ratio));
            page.style.setProperty(
              "--two-page-chord-size",
              corrected.toFixed(2) + "px"
            );
          }
        }
      });
    });
  }

  function scheduleTwoPageFit() {
    if (twoPageFitRaf !== null) {
      cancelAnimationFrame(twoPageFitRaf);
    }

    twoPageFitRaf = requestAnimationFrame(fitTwoPages);
  }

  function init() {
    prepareSongMiniPages();
    document.querySelectorAll(".transpose-panel").forEach(initPanel);
    initAutoscroll();

    window.addEventListener("resize", scheduleTwoPageFit);
    scheduleTwoPageFit();
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

  <label class="transpose-field instrument-only">
    <span class="transpose-label">Capotraste</span>
    <select class="transpose-capo" aria-label="Casa do capotraste"></select>
  </label>

  <div class="transpose-field transpose-shape instrument-only">
    <span class="transpose-label">Acordes exibidos</span>
    <strong class="transpose-shape-key"></strong>
  </div>

  <label class="transpose-view-toggle">
    <input type="checkbox" class="transpose-lyrics-only">
    <span>Somente letra (cantores)</span>
  </label>

  <label class="transpose-view-toggle">
    <input type="checkbox" class="transpose-two-columns">
    <span>Duas colunas</span>
  </label>

  <button type="button" class="transpose-reset">Original</button>
</div>

<section class="harmonic-field-panel" hidden aria-label="Campo harmônico para violão">
  <div class="harmonic-field-heading">
    <div>
      <h3 class="harmonic-field-title">Campo harmônico</h3>
      <p class="harmonic-field-context"></p>
    </div>
    <span class="harmonic-field-legend">2 shapes por acorde</span>
  </div>
  <div class="harmonic-field-grid"></div>
</section>

<div class="autoscroll-dock" aria-label="Controle de rolagem automática">
  <div class="autoscroll-head">
    <span class="autoscroll-title">Rolagem</span>
    <span class="autoscroll-state">parado</span>
  </div>

  <div class="autoscroll-control">
    <span class="autoscroll-direction" aria-hidden="true">↑</span>
    <input class="autoscroll-slider"
           type="range"
           min="-100"
           max="100"
           value="0"
           step="1"
           aria-label="Rolagem automática: esquerda sobe, centro para, direita desce">
    <span class="autoscroll-direction" aria-hidden="true">↓</span>
  </div>
</div>
]=])
end

function Pandoc(doc)
  if not FORMAT:match("html") then
    return doc
  end

  -- Mantém introdução, forma e eventual sugestão de dedilhado em largura total.
  -- A partir do primeiro cabeçalho H2 começa a área que pode virar duas colunas.
  local prefix_blocks = {}
  local song_blocks = {}
  local song_started = false

  for _, block in ipairs(doc.blocks) do
    if not song_started and block.t == "Header" and block.level == 2 then
      song_started = true
    end

    if song_started then
      song_blocks[#song_blocks + 1] = block
    else
      prefix_blocks[#prefix_blocks + 1] = block
    end
  end

  -- Se a página não tiver H2, ainda assim envolve todo o conteúdo musical.
  if #song_blocks == 0 then
    song_blocks = prefix_blocks
    prefix_blocks = {}
  end

  local new_blocks = {}
  local base_meta = doc.meta["tom-base"]

  if base_meta ~= nil then
    local base_key = pandoc.utils.stringify(base_meta)
    new_blocks[#new_blocks + 1] = transpose_panel(base_key)
  else
    new_blocks[#new_blocks + 1] = pandoc.RawBlock("html", [=[
<div class="transpose-panel transpose-panel-error">
  <strong>Transposição:</strong>
  defina <code>tom-base:</code> no YAML da música.
</div>
]=])
  end

  for _, block in ipairs(prefix_blocks) do
    new_blocks[#new_blocks + 1] = block
  end

  new_blocks[#new_blocks + 1] =
    pandoc.Div(song_blocks, pandoc.Attr("", {"song-content"}))

  new_blocks[#new_blocks + 1] = pandoc.RawBlock("html", TRANSPOSE_JS)

  doc.blocks = new_blocks
  return doc
end
