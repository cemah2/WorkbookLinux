-- Fenced divs -> environnements LaTeX ; "repondre" -> lignes de réponse
local function fixpipes(t)
  return t:walk({Code = function(c) c.text = c.text:gsub('\\|', '|'); return c end})
end

local known = {wbcheck=true, objectif=true, astuce=true, attention=true, rhel=true, contexte=true,
               pourquoi=true, piege=true, check=true, note=true}

function Div(el)
  local cls = el.classes[1]
  if cls == "check" then cls = "wbcheck" end
  if cls == "repondre" then
    local n = 6
    local txt = pandoc.utils.stringify(el.content)
    local m = txt:match("lignes:%s*(%d+)")
    if m then n = tonumber(m) end
    if n < 2 then n = 2 end
    if n > 14 then n = 14 end
    return pandoc.RawBlock("latex", "\\repondre{" .. n .. "}")
  end
  if cls and known[cls] then
    local out = {pandoc.RawBlock("latex", "\\begin{" .. cls .. "}")}
    for _, b in ipairs(el.content) do table.insert(out, b) end
    table.insert(out, pandoc.RawBlock("latex", "\\end{" .. cls .. "}"))
    return out
  end
  return el.content
end

-- Un seul H1 par fichier -> \chapter ; H2 -> section, etc. (pandoc le fait via --top-level-division)
-- Cases à cocher
function Str(s)
  if s.text:find("☐") then
    local t = s.text:gsub("☐", "\\checkbox{}")
    return pandoc.RawInline("latex", t)
  end
  return s
end

-- Tables : longtable de pandoc, forcer des largeurs de colonnes proportionnelles
function Table(t)
  local ncols = #t.colspecs
  if ncols == 0 then return t end
  local has = false
  for _, cs in ipairs(t.colspecs) do if cs[2] then has = true end end
  if not has then
    -- largeur proportionnelle à la longueur maximale (bornée) du contenu
    local maxlen, maxtok = {}, {}
    for i = 1, ncols do maxlen[i] = 4; maxtok[i] = 1 end
    local function scan(rows)
      for _, row in ipairs(rows) do
        for i, cell in ipairs(row.cells) do
          local txt = pandoc.utils.stringify(cell.contents)
          local l = utf8.len(txt) or #txt
          if l > 60 then l = 60 end
          if i <= ncols and l > maxlen[i] then maxlen[i] = l end
          for tok in txt:gmatch("[^%s/,=:|]+") do
            local tl = utf8.len(tok) or #tok
            if tl > 34 then tl = 34 end
            if i <= ncols and tl > maxtok[i] then maxtok[i] = tl end
          end
        end
      end
    end
    scan(t.head.rows)
    for _, body in ipairs(t.bodies) do scan(body.body) end
    local total = 0
    for i = 1, ncols do total = total + maxlen[i] end
    for i, cs in ipairs(t.colspecs) do
      local w = maxlen[i] / total
      if w < 0.12 then w = 0.12 end
      local need = (maxtok[i] + 2) / 88
      if w < need then w = need end
      t.colspecs[i] = {cs[1], w}
    end
    -- renormaliser
    local s = 0
    for i = 1, ncols do s = s + t.colspecs[i][2] end
    for i = 1, ncols do t.colspecs[i] = {t.colspecs[i][1], t.colspecs[i][2] / s * 0.97} end
  end
  return t
end

-- Code en ligne : coupable en fin de ligne, sans boîte
local esc = {
  ["\\"]="\\textbackslash{}", ["{"]="\\{", ["}"]="\\}", ["$"]="\\$", ["&"]="\\&",
  ["#"]="\\#", ["^"]="\\textasciicircum{}", ["_"]="\\_\\allowbreak{}", ["%"]="\\%",
  ["~"]="\\textasciitilde{}", ["'"]="\\textquotesingle{}", ["`"]="\\textasciigrave{}",
  ['"']="\\textquotedbl{}", [" "]="\\ \\allowbreak{}",
}
local brk = { ["/"]=true, ["-"]=true, [","]=true, ["="]=true, [":"]=true, ["."]=true, ["|"]=true, ["("]=true, [")"]=true, ["["]=true, ["]"]=true, ["@"]=true, ["?"]=true, ["&"]=false }
function Code(el)
  local out = {}
  for ch in el.text:gmatch(utf8.charpattern) do
    if esc[ch] then table.insert(out, esc[ch])
    elseif brk[ch] then table.insert(out, ch .. "\\allowbreak{}")
    else table.insert(out, ch) end
  end
  return pandoc.RawInline("latex", "\\wbcode{" .. table.concat(out) .. "}")
end

return { {Table = fixpipes}, {Table = Table, Div = Div, Str = Str, Code = Code} }
