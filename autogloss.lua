-- autogloss.lua -- automatic page-referenced glossary/index for LuaLaTeX
-- Companion to autogloss.sty. Scans typeset text (paragraphs and hboxes),
-- finds declared terms, and records the page each occurrence is shipped on.

autogloss = autogloss or {}
local AG = autogloss

AG.terms    = {}   -- list: { key=, id=, patterns={ {cp...},... }, sortkey= }
AG.bykey    = {}   -- key -> term id
AG.first    = {}   -- first codepoint -> list of {pat=, id=}
AG.hits     = {}   -- id -> { [abs]=label }  (this run)
AG.old      = {}   -- key -> { [abs]=label }  (previous run, from .aux)
AG.case     = false
AG.plurals  = true
AG.ranges   = true
AG.sort     = "alpha"
AG.curabs   = 0
AG.curlabel = "?"

local GLYPH   = node.id("glyph")
local GLUE    = node.id("glue")
local KERN    = node.id("kern")
local DISC    = node.id("disc")
local MATH    = node.id("math")
local WHATSIT = node.id("whatsit")
local LATE_LUA = node.subtype("late_lua")
local USERKERN = 1

local has_attr = node.has_attribute
local utf8char = utf8.char

local scan_attr -- set from TeX once the attribute is allocated
function AG.set_attr(n) scan_attr = n end

---------------------------------------------------------------------------
-- character helpers
---------------------------------------------------------------------------
local SEP, SPACE = 0, 32

local ligs = {
  [0xFB00]={102,102}, [0xFB01]={102,105}, [0xFB02]={102,108},
  [0xFB03]={102,102,105}, [0xFB04]={102,102,108}, [0xFB05]={115,116}, [0xFB06]={115,116},
}

local function lower(cp)
  if AG.case then return cp end
  if cp >= 65 and cp <= 90 then return cp + 32 end
  if cp < 128 then return cp end
  if cp >= 0x391 and cp <= 0x3A9 and cp ~= 0x3A2 then return cp + 32 end -- Greek
  if (cp >= 0xC0 and cp <= 0xDE and cp ~= 0xD7) then return cp + 32 end   -- Latin-1
  return cp
end

local function isword(cp)
  if cp == SEP or cp == SPACE then return false end
  if cp < 128 then
    return (cp >= 48 and cp <= 57) or (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122)
  end
  if cp == 0xD7 or cp == 0xF7 then return false end
  if cp >= 0x2000 and cp <= 0x2BFF then return false end -- punctuation, dashes, symbols
  return cp >= 0xC0
end

-- Unicode math alphanumerics (unicode-math) -> plain letters
local function unmath(cp)
  if cp >= 0x1D400 and cp <= 0x1D6A3 then
    local off = (cp - 0x1D400) % 52
    return off < 26 and (65 + off) or (97 + off - 26)
  elseif cp == 0x210E then return 104 -- italic h
  elseif cp >= 0x1D6A8 and cp <= 0x1D7C9 then
    local off = (cp - 0x1D6A8) % 58
    if off <= 16 then return 0x391 + off
    elseif off == 17 then return 0x398
    elseif off <= 24 then return 0x3A3 + off - 18
    elseif off >= 26 and off <= 50 then return 0x3B1 + off - 26
    end
    return SEP
  elseif cp >= 0x1D7CE and cp <= 0x1D7FF then
    return 48 + (cp - 0x1D7CE) % 10
  end
  return cp
end

-- Legacy TeX math fonts (OML/OT1 in math mode) put Greek in slots 0x00-0x21
local tex_greek = {
  [0]=0x393,0x394,0x398,0x39B,0x39E,0x3A0,0x3A3,0x3A5,0x3A6,0x3A8,0x3A9,
  0x3B1,0x3B2,0x3B3,0x3B4,0x3F5,0x3B6,0x3B7,0x3B8,0x3B9,0x3BA,0x3BB,0x3BC,
  0x3BD,0x3BE,0x3C0,0x3C1,0x3C3,0x3C4,0x3C5,0x3D5,0x3C7,0x3C8,0x3C9,
}

local function glyph_chars(n, out, inmath)
  local comp = n.components
  if comp then
    for c in node.traverse_id(GLYPH, comp) do glyph_chars(c, out, inmath) end
    return
  end
  local ch = n.char
  if inmath then
    if ch < 0x22 then ch = tex_greek[ch] or SEP else ch = unmath(ch) end
    if ch == 0x3F5 then ch = 0x3B5 end
  end
  local l = ligs[ch]
  if l then for _, c in ipairs(l) do out[#out+1] = c end return end
  if ch >= 0xE000 and ch <= 0xF8FF then
    -- private-use glyph from an OpenType font: try its tounicode
    local f = font.getfont(n.font)
    local cd = f and f.characters and f.characters[ch]
    local tu = cd and cd.tounicode
    if type(tu) == "string" then
      for i = 1, #tu, 4 do out[#out+1] = tonumber(tu:sub(i, i+3), 16) or SEP end
      return
    end
    out[#out+1] = SEP
    return
  end
  out[#out+1] = ch
end

---------------------------------------------------------------------------
-- term declaration
---------------------------------------------------------------------------
local greek_names = {
  alpha=0x3B1, beta=0x3B2, gamma=0x3B3, delta=0x3B4, epsilon=0x3B5, varepsilon=0x3B5,
  zeta=0x3B6, eta=0x3B7, theta=0x3B8, vartheta=0x3B8, iota=0x3B9, kappa=0x3BA,
  lambda=0x3BB, mu=0x3BC, nu=0x3BD, xi=0x3BE, pi=0x3C0, rho=0x3C1, sigma=0x3C3,
  tau=0x3C4, upsilon=0x3C5, phi=0x3C6, varphi=0x3C6, chi=0x3C7, psi=0x3C8, omega=0x3C9,
  Gamma=0x393, Delta=0x394, Theta=0x398, Lambda=0x39B, Xi=0x39E, Pi=0x3A0,
  Sigma=0x3A3, Upsilon=0x3A5, Phi=0x3A6, Psi=0x3A8, Omega=0x3A9,
}

-- turn a detokenized term ("large-$R$ jet", "$\eta$-intercalibration") into
-- a normalized matching string
local function normalize(s)
  s = s:gsub("\\(%a+)%s*", function(name)
    local g = greek_names[name]
    if g then return utf8char(g) end
    if name == "textendash" then return "\u{2013}" end
    return ""
  end)
  s = s:gsub("\\.", "")            -- other control symbols (\, \- etc.)
  s = s:gsub("[%$%{%}]", "")
  s = s:gsub("~", " ")
  s = s:gsub("%-%-%-", "\u{2014}"):gsub("%-%-", "\u{2013}")
  s = s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  return s
end

local function codepoints(s)
  local t = {}
  for _, c in utf8.codes(s) do
    if c == 0x3F5 then c = 0x3B5 end
    t[#t+1] = lower(c)
  end
  return t
end

-- returns the term id; aliases is a list of extra strings
function AG.declare(term, aliases)
  local key = normalize(term)
  if key == "" then return 0 end
  local id = AG.bykey[key]
  if not id then
    id = #AG.terms + 1
    AG.terms[id] = { key = key, id = id, patterns = {}, order = id,
                     sortkey = utf8char(table.unpack(codepoints(key))) }
    AG.bykey[key] = id
    AG.hits[id] = {}
  end
  local function addpat(str)
    local p = codepoints(normalize(str))
    if #p == 0 then return end
    local t = AG.terms[id]
    t.patterns[#t.patterns+1] = p
    local f = AG.first[p[1]]
    if not f then f = {}; AG.first[p[1]] = f end
    f[#f+1] = { pat = p, id = id }
  end
  addpat(term)
  for _, a in ipairs(aliases or {}) do addpat(a) end
  tex.sprint(tostring(id))
end

---------------------------------------------------------------------------
-- scanning
---------------------------------------------------------------------------
local D            = node.direct
local todirect     = D.todirect
local tonode       = D.tonode
local getid        = D.getid
local getnext      = D.getnext
local getchar      = D.getchar
local getfont      = D.getfont
local getsubtype   = D.getsubtype
local getattr      = D.has_attribute
local getcomps     = D.getcomponents
local getreplace   = function(n) local _, _, r = D.getdisc(n); return r end
local d_new        = D.new
local d_setdata    = D.setdata
local d_insert     = D.insert_before

local PENALTY  = node.id("penalty")
local LOCALPAR = node.id("local_par")
local DIR      = node.id("dir")
local BOUNDARY = node.id("boundary")
local MARK     = node.id("mark")
local INS      = node.id("ins")
local ADJUST   = node.id("adjust")
local transparent = { [WHATSIT]=true, [PENALTY]=true, [LOCALPAR]=true, [DIR]=true,
                      [BOUNDARY]=true, [MARK]=true, [INS]=true, [ADJUST]=true }

-- reusable buffers (no per-paragraph allocation)
local cps, nds, ncp = {}, {}, 0
local inmath = false

local function push(c, n)
  if c == SPACE then
    local last = cps[ncp]
    if ncp == 0 or last == SPACE or last == SEP then return end
  elseif c < 128 then
    if c >= 65 and c <= 90 and not AG.case then c = c + 32 end
  else
    c = lower(c)
  end
  ncp = ncp + 1
  cps[ncp] = c; nds[ncp] = n
end

local function push_glyph(g, owner)
  local comp = getcomps(g)
  if comp then
    local c = comp
    while c do
      if getid(c) == GLYPH then push_glyph(c, owner) end
      c = getnext(c)
    end
    return
  end
  local ch = getchar(g)
  if ch < 128 and ch >= 0x22 then push(ch, owner) return end  -- fast path
  if inmath then
    if ch < 0x22 then ch = tex_greek[ch] or SEP else ch = unmath(ch) end
    if ch == 0x3F5 then ch = 0x3B5 end
  end
  local l = ligs[ch]
  if l then for k = 1, #l do push(l[k], owner) end return end
  if ch >= 0xE000 and ch <= 0xF8FF then
    local f = font.getfont(getfont(g))
    local cd = f and f.characters and f.characters[ch]
    local tu = cd and cd.tounicode
    if type(tu) == "string" then
      for i = 1, #tu, 4 do push(tonumber(tu:sub(i, i+3), 16) or SEP, owner) end
    else
      push(SEP, owner)
    end
    return
  end
  push(ch, owner)
end

local function build(head)
  ncp = 0
  inmath = false
  local found = false
  local n = head
  while n do
    local id = getid(n)
    if id == GLYPH then
      if getattr(n, scan_attr) then push_glyph(n, n); found = true
      else push(SEP, n) end
    elseif id == GLUE then
      push(SPACE, n)
    elseif id == KERN then
      if getsubtype(n) == USERKERN then push(SPACE, n) end
    elseif id == DISC then
      local r = getreplace(n)
      while r do
        if getid(r) == GLYPH then
          if getattr(r, scan_attr) then push_glyph(r, n) else push(SEP, n) end
        end
        r = getnext(r)
      end
    elseif id == MATH then
      inmath = (getsubtype(n) == 0)
    elseif not transparent[id] then
      push(SEP, n)
    end
    n = getnext(n)
  end
  return found
end

local function isword_fast(c)
  if c == nil then return false end
  if c < 128 then
    return (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or (c >= 65 and c <= 90)
  end
  return isword(c)
end

local function match_at(i, pat)
  local np = #pat
  if i + np - 1 > ncp then return false end
  for k = 2, np do
    if cps[i + k - 1] ~= pat[k] then return false end
  end
  local lastword = isword_fast(pat[np])
  local j = i + np
  if AG.plurals and lastword then
    local c1 = cps[j]
    if c1 == 115 and not isword_fast(cps[j+1]) then j = j + 1
    elseif c1 == 101 and cps[j+1] == 115 and not isword_fast(cps[j+2]) then j = j + 2 end
  end
  if j <= ncp and lastword and isword_fast(cps[j]) then return false end
  return true
end

local function scan(head)
  if not head or not scan_attr or #AG.terms == 0 or status.output_active then
    return head
  end
  local dhead = todirect(head)
  if not build(dhead) then return head end
  local first = AG.first
  local inserted = false
  local prevword = false
  for i = 1, ncp do
    local c = cps[i]
    local cw = isword_fast(c)
    if c ~= SPACE and c ~= SEP and (not prevword or not cw) then
      local cands = first[c]
      if cands then
        for k = 1, #cands do
          local cand = cands[k]
          if match_at(i, cand.pat) then
            local w = d_new(WHATSIT, LATE_LUA)
            d_setdata(w, "autogloss.hit(" .. cand.id .. ")")
            dhead = d_insert(dhead, nds[i], w)
            inserted = true
          end
        end
      end
    end
    prevword = cw
  end
  for i = 1, ncp do nds[i] = nil end -- don't keep node refs alive
  if inserted then return tonode(dhead) end
  return head
end

function AG.pre_linebreak(head) return scan(head) end
function AG.hpack(head) return scan(head) end

---------------------------------------------------------------------------
-- shipout-time recording
---------------------------------------------------------------------------
function AG.setpage(abs, label) AG.curabs = abs; AG.curlabel = label end

function AG.hit(id)
  local h = AG.hits[id]
  if h and not h[AG.curabs] then h[AG.curabs] = AG.curlabel end
end

---------------------------------------------------------------------------
-- aux I/O
---------------------------------------------------------------------------
local function tohex(s) return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local function fromhex(h) return (h:gsub("%x%x", function(x) return string.char(tonumber(x, 16)) end)) end

function AG.load(hkey, abs, hlabel)
  local key = fromhex(hkey)
  local t = AG.old[key]
  if not t then t = {}; AG.old[key] = t end
  t[abs] = fromhex(hlabel)
end

function AG.writeaux()
  local cct = luatexbase.registernumber("catcodetable@atletter")
  for id, t in ipairs(AG.terms) do
    local abss = {}
    for a in pairs(AG.hits[id]) do abss[#abss+1] = a end
    table.sort(abss)
    for _, a in ipairs(abss) do
      tex.sprint(cct, string.format("\\autogloss@w{%s}{%d}{%s}", tohex(t.key), a, tohex(AG.hits[id][a])))
    end
  end
end

local function same(a, b)
  a, b = a or {}, b or {}
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k, v in pairs(b) do if a[k] ~= v then return false end end
  return true
end

function AG.changed()
  for id, t in ipairs(AG.terms) do
    if not same(AG.hits[id], AG.old[t.key]) then return true end
  end
  return false
end

---------------------------------------------------------------------------
-- typesetting the glossary
---------------------------------------------------------------------------
local function texesc(s)
  return (s:gsub("[\\{}#%%&%$%^_~]", function(c) return "\\char" .. c:byte() .. " " end))
end

local function pagelist(t)
  local abss = {}
  for a in pairs(t) do abss[#abss+1] = a end
  table.sort(abss)
  local parts, i = {}, 1
  local function pg(a) return "\\autogloss@page{" .. texesc(t[a]) .. "}" end
  while i <= #abss do
    local j = i
    while AG.ranges and abss[j+1] == abss[j] + 1 do j = j + 1 end
    if j - i >= 2 then
      parts[#parts+1] = pg(abss[i]) .. "\\autoglossrangesep " .. pg(abss[j])
      i = j + 1
    else
      parts[#parts+1] = pg(abss[i])
      i = i + 1
    end
  end
  return table.concat(parts, "\\autoglosspagesep ")
end

function AG.typeset()
  local cct = luatexbase.registernumber("catcodetable@atletter")
  local order = {}
  for _, t in ipairs(AG.terms) do order[#order+1] = t end
  if AG.sort == "alpha" then
    table.sort(order, function(a, b)
      if a.sortkey == b.sortkey then return a.order < b.order end
      return a.sortkey < b.sortkey
    end)
  end
  for _, t in ipairs(order) do
    local old = AG.old[t.key]
    local pages
    if old and next(old) then pages = pagelist(old) else pages = "\\autogloss@none{" .. t.id .. "}" end
    tex.sprint(cct, string.format("\\autogloss@item{%d}{%s}", t.id, pages))
  end
end

return AG
