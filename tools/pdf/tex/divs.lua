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

-- H1 "Module 07 — Titre" -> ouverture de chapitre stylée
local function texesc(str)
  return (str:gsub("\\", "\\textbackslash{}"):gsub("([&%%$#_{}])", "\\%1"))
end
function Header(h)
  if h.level ~= 1 then return h end
  local full = pandoc.utils.stringify(h.content)
  local kicker, num, title = "", "", full
  local k, n, t = full:match("^(Module)%s+(%d+)%s+[—%-]+%s+(.+)$")
  if k then kicker, num, title = k, n, t
  else
    k, n, t = full:match("^(Projet)%s+(%a)%s+[—%-]+%s+(.+)$")
    if k then kicker, num, title = k, n, t
    else
      k, n, t = full:match("^(Chapitre)%s+(%d+)%s+[—%-]+%s+(.+)$")
      if k then kicker, num, title = k, n, t end
    end
  end
  local toc = texesc(full)
  local set = "\\wbchapterset{" .. texesc(kicker) .. "}{" .. texesc(num) .. "}"
  -- le titre garde les inlines (code, etc.) : on passe par pandoc pour le rendu
  local tt = pandoc.write(pandoc.Pandoc({pandoc.Plain(pandoc.Inlines(title))}), "latex"):gsub("\n$", "")
  return pandoc.RawBlock("latex", set .. "\\chapter[" .. toc .. "]{" .. tt .. "}\\markboth{" .. tt .. "}{}")
end

-- Cases à cocher, étoiles de difficulté
function Str(s)
  local changed = false
  local t = s.text
  if t:find("☐") then t = t:gsub("☐", "\\checkbox{}"); changed = true end
  if t:find("★") then t = t:gsub("★", "\\wbstar{}"); changed = true end
  if changed then return pandoc.RawInline("latex", t) end
  return s
end

-- **Q7.3** en début de ligne -> pastille
function Strong(el)
  local txt = pandoc.utils.stringify(el.content)
  if txt:match("^%u%u?%d+%.%d+$") or txt:match("^D%d+$") or txt:match("^P[ABC]%.%d+$") or txt:match("^PC%.%d+%.%d+$") then
    return pandoc.RawInline("latex", "\\wbid{" .. txt .. "}")
  end
  return el
end

-- Blocs de code : cadre avec étiquette de langage
function CodeBlock(cb)
  local lang = cb.classes[1] or ""
  local label = ({bash="bash", sh="sh", ini="ini", yaml="yaml", yml="yaml", json="json", python="python",
    nginx="nginx", sql="sql", hcl="hcl", terraform="hcl", dockerfile="Dockerfile", toml="toml",
    text="", console="console", diff="diff", xml="xml", conf="conf", jinja="jinja2", makefile="make"})[lang] or lang
  return { pandoc.RawBlock("latex", "\\begin{codeframe}{" .. texesc(label) .. "}"), cb,
           pandoc.RawBlock("latex", "\\end{codeframe}") }
end

-- Figures : un paragraphe "@fig(nom): légende"
function Para(p)
  local txt = pandoc.utils.stringify(p.content)
  local name, cap = txt:match("^@fig%(([%w%-_]+)%)%s*:%s*(.*)$")
  if name then
    -- garder la mise en forme de la légende : retirer le marqueur des inlines
    local inl = pandoc.List()
    local skipping = true
    for _, x in ipairs(p.content) do
      if skipping then
        if x.t == "Str" and x.text:match(":$") then skipping = false end
      else
        inl:insert(x)
      end
    end
    if #inl > 0 and inl[1].t == "Space" then inl:remove(1) end
    local capl = pandoc.write(pandoc.Pandoc({pandoc.Plain(inl)}), "latex"):gsub("\n$", "")
    return pandoc.RawBlock("latex", "\\wbfigure{" .. name .. "}{" .. capl .. "}")
  end
  return p
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
  -- en-tête : gras + couleur
  for _, row in ipairs(t.head.rows) do
    for _, cell in ipairs(row.cells) do
      if #cell.contents > 0 and cell.contents[1].t == "Plain" then
        table.insert(cell.contents[1].content, 1, pandoc.RawInline("latex", "\\bfseries\\color{accent}"))
      end
    end
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


-- Index des commandes (activé par la variable d'environnement WB_INDEX=1)
local index_on = os.getenv("WB_INDEX") == "1"
local wl = {}
if index_on then
  local f = io.open(os.getenv("WB_INDEX_FILE") or "tex/index-commands.txt")
  if f then for l in f:lines() do wl[l] = true end f:close() end
end
local old_code = Code
function Code(el)
  local r = old_code(el)
  if not index_on then return r end
  local tok = el.text:match("^%s*([^%s]+)")
  if tok and wl[tok] then
    local disp = tok:gsub("_", "\\_")
    return { r, pandoc.RawInline("latex", "\\index{" .. tok .. "@\\texttt{" .. disp .. "}}") }
  end
  return r
end


-- Cartes : un item (**Q7.3** … / **E7.2** … / **BF7.1** …) et les blocs qui le suivent
-- jusqu'au prochain item, titre ou règle horizontale forment une carte.
local function is_item_para(b)
  if b.t ~= "Para" and b.t ~= "Plain" then return false end
  local first = b.content[1]
  if not first or first.t ~= "Strong" then return false end
  local txt = pandoc.utils.stringify(first.content)
  return txt:match("^%u%u?%d+%.%d+$") or txt:match("^D%d+$") or txt:match("^P[ABC]%.%d+$") or txt:match("^PC%.%d+%.%d+$")
end
local function is_break(b)
  return b.t == "Header" or b.t == "HorizontalRule"
end
local function cardify(blocks)
  local out, card = pandoc.List(), nil
  local function flush()
    if card then
      out:insert(pandoc.RawBlock("latex", "\\begin{wbcard}"))
      for _, x in ipairs(card) do out:insert(x) end
      out:insert(pandoc.RawBlock("latex", "\\end{wbcard}"))
      card = nil
    end
  end
  for _, b in ipairs(blocks) do
    if is_item_para(b) then
      flush(); card = pandoc.List({b})
    elseif card and is_break(b) then
      flush(); out:insert(b)
    elseif card then
      -- un encadré "pourquoi/piege/repondre/check" reste dans la carte ; un autre Div aussi
      card:insert(b)
    else
      out:insert(b)
    end
  end
  flush()
  return out
end
local function Cards(doc)
  doc.blocks = cardify(doc.blocks)
  return doc
end

return { {Table = fixpipes}, {Pandoc = Cards}, {Table = Table, Div = Div, Str = Str, Code = Code, Header = Header, Strong = Strong, CodeBlock = CodeBlock, Para = Para} }
