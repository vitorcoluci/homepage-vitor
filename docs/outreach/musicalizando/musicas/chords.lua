-- chords.lua
-- Filtro Quarto/Pandoc para blocos ChordPro simples.
--
-- Exemplo no .qmd:
--
-- ```{.chordpro}
-- [G]Mandacaru quando [C]fulorá na [G]seca
-- É um si[G7]ná que a chuva chega no sert[C]ão
-- ```
--
-- Esta versão NÃO calcula posições usando "ch".
-- Cada acorde fica ancorado exatamente no ponto da letra onde aparece [ACORDE],
-- portanto funciona corretamente também com fontes proporcionais.

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

    -- Texto desde o acorde anterior até o novo acorde.
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
  local out = {'<div class="chordpro-line">'}

  for _, seg in ipairs(segments) do
    local chord_html = ""
    if seg.chord ~= nil then
      chord_html =
        '<span class="chordpro-chord">' ..
        html_escape(seg.chord) ..
        '</span>'
    end

    -- Sem quebras/espaços entre spans no HTML para não introduzir
    -- espaços artificiais entre os trechos da letra.
    out[#out + 1] =
      '<span class="chordpro-segment">' ..
      chord_html ..
      '<span class="chordpro-lyric">' ..
      html_escape(seg.text) ..
      '</span></span>'
  end

  out[#out + 1] = '</div>'
  return table.concat(out, "")
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

  local out = {'<div class="chordpro" role="group">'}

  for line in text:gmatch("(.-)\n") do
    out[#out + 1] = render_line(line)
  end

  out[#out + 1] = '</div>'

  return pandoc.RawBlock("html", table.concat(out, "\n"))
end
