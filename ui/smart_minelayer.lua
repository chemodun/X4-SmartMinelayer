-- Smart Minelayer: the slot config window on the map. It shows the slots the request copies, computes the
-- positions of one and hands the order one op (add, edit, delete) on the pilot's blackboard; design notes in
-- claude/mod-smart_minelayer.md.

---@diagnostic disable-next-line: unresolved-require
local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
  typedef uint64_t UniverseID;
  typedef struct {
    const char* type;
    const char* ware;
    const char* macro;
    int amount;
  } EquipmentWareInfo;
  typedef struct { int major; int minor; } GameVersion;
  typedef uint64_t AIOrderID;
  typedef struct {
    uint32_t id;
    AIOrderID orderid;
    const char* orderdef;
    const char* message;
    double timestamp;
    bool wasdefaultorder;
    bool wasinloop;
  } OrderFailure;
  uint32_t GetAvailableEquipment(EquipmentWareInfo* result, uint32_t resultlen, UniverseID containerid, const char* classid);
  const char* GetComponentClass(UniverseID componentid);
  bool GetDefaultOrderFailure(OrderFailure* result, UniverseID controllableid);
  void SetFocusMapComponent(UniverseID holomapid, UniverseID componentid, bool resetplayerpan);
  GameVersion GetGameVersion();
  uint32_t GetNumAvailableEquipment(UniverseID containerid, const char* classid);
  uint32_t GetNumWares(const char* tags, bool research, const char* licenceownerid, const char* exclusiontags);
  UniverseID GetPlayerID(void);
  UniverseID GetPlayerObjectID(void);
  uint32_t GetWares(const char** result, uint32_t resultlen, const char* tags, bool research, const char* licenceownerid, const char* exclusiontags);
  bool IsDeployableMacroCompatible(UniverseID containerid, const char* macroname, const char* deployablemacroname);
  void RemoveDefaultOrderFailure(UniverseID controllableid);
]]

local PAGE = 1972092417

local config = {
  -- above the map, below its context menus
  frameLayer         = 1,
  isV9               = C.GetGameVersion().major >= 9,
  configBlackboard   = "$SmartMinelayerConfig",
  requestVar         = "$SmartMinelayerConfigRequestData",
  -- the order applies it to the common slot list, which Lua never writes
  opVar              = "$SmartMinelayerConfigOp",
  deployableMacroVar = "$SmartMinelayerDeployableMacro",
  deployableInputsVar = "$SmartMinelayerDeployableInputs",
  deployablesVar     = "$SmartMinelayerDeployables",
  configPositionVar  = "$SmartMinelayerConfigPosition",
  restockNpcVar      = "$SmartMinelayerRestockNpc",
  lowAttentionVar    = "$SmartMinelayerLowAttention",
  mineStatsVar       = "$SmartMinelayerMineStats",
  -- px between the ship and the window corner, before UI scaling
  shipGap            = 16,
  -- one tab icon per slot
  maxSlots           = 9,
  maxItemsPerSlot    = 1000,
  twoPi              = 2 * math.pi,
  goldenAngle        = math.pi * (3 - math.sqrt(5)),
  -- per density 1-5
  circleItems        = { 9, 18, 27, 36, 45 },
  squareSides        = { 3, 5, 7, 10, 12 },
  hexagonItems       = { 9, 18, 27, 36, 45 },
  spherePoints       = { 26, 62, 122, 242, 482 },
  logoItems          = { 60, 90, 120, 150, 180 },
  defaultMine        = "weapon_gen_mine_03",
  defaultTower       = "ship_gen_xs_lasertower_01_a",
  defaults           = {
    shape = 1, planeOrientation = 0, density = 1,
    concentricShapesCount = 0, concentricShapesSpacing = 2000, radius = 2000,
    parallelLayersCount = 0, parallelLayersSpacing = 500,
    offsetDirection = 0, offsetDistance = 2000, threshold = 5,
  },
}

local KIND_MINE, KIND_TOWER = 1, 2

local SLOT_FIELDS = {
  "shape", "planeOrientation", "density", "concentricShapesCount", "concentricShapesSpacing", "radius",
  "parallelLayersCount", "parallelLayersSpacing", "offsetDirection", "offsetDistance", "threshold",
}

---@type table<string, any>
local sm = {
  menu = nil,
  debugLevel = "none",
  -- config requests in arrival order; the first one is shown
  requests = {},
  configFrame = nil,
}

-- *** logging ***

local function format(fmt, ...)
  if select("#", ...) > 0 then fmt = string.format(fmt, ...) end
  return "SmartMinelayer: " .. fmt
end

function sm.Error(fmt, ...) UIError(format(fmt, ...)) end
function sm.Debug(fmt, ...) if sm.debugLevel ~= "none" then UIDebug(format(fmt, ...)) end end
function sm.Trace(fmt, ...) if sm.debugLevel == "trace" then UITrace(format(fmt, ...)) end end

function sm.ReadConfig()
  local playerId = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
  if playerId == 0 then return end
  local cfg = GetNPCBlackboard(playerId, config.configBlackboard)
  sm.debugLevel = (type(cfg) == "table" and cfg.debugLevel) and tostring(cfg.debugLevel) or "none"
end

-- build inputs per production run; script properties do not give them for equipment
local function wareInputs(wareId)
  local resources, runAmount = GetWareData(wareId, "resources", "productionamount")
  local inputs = {}
  for _, r in ipairs(resources or {}) do inputs[#inputs + 1] = { ware = r.ware, amount = r.amount } end
  return { runAmount = runAmount or 1, wares = inputs }
end

-- build inputs of every deployable by macro, so the order can decompose the ones it does not use
function sm.publishDeployables()
  local playerId = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
  if playerId == 0 then return end
  local byMacro, count = {}, 0
  for _, tag in ipairs({ "mine", "lasertower", "satellite", "navbeacon", "resourceprobe" }) do
    local n = C.GetNumWares(tag, false, "", "")
    local buf = ffi.new("const char*[?]", n)
    n = C.GetWares(buf, n, tag, false, "", "")
    for i = 0, n - 1 do
      local wareId = ffi.string(buf[i])
      local macro = GetWareData(wareId, "component")
      if macro and macro ~= "" and not byMacro[macro] then
        byMacro[macro] = wareInputs(wareId)
        count = count + 1
      end
    end
  end
  SetNPCBlackboard(playerId, config.deployablesVar, byMacro)
  sm.Debug("published the build inputs of %d deployables", count)
end

-- *** geometry ***

local function vec(x, y, z) return { x = x, y = y, z = z } end
local function negate(v) return vec(-v.x, -v.y, -v.z) end

-- pattern axes u, v and the offset direction w, from the object's rotation
local function orientedBasis(rot, direction)
  local fwd, right, up = rot.forward, rot.right, rot.up
  if direction == 1 then return right, up, fwd end
  if direction == 2 then return negate(right), up, negate(fwd) end
  if direction == 3 then return negate(fwd), up, right end
  if direction == 4 then return fwd, up, negate(right) end
  if direction == 5 then return right, negate(fwd), up end
  if direction == 6 then return right, fwd, negate(up) end
end

local function planeTransform(cx, cy, cz, orientation, u, v)
  if u then
    return function(a, b) return vec(cx + a * u.x + b * v.x, cy + a * u.y + b * v.y, cz + a * u.z + b * v.z) end
  end
  if orientation == 1 then return function(a, b) return vec(cx + a, cy + b, cz) end end
  if orientation == 2 then return function(a, b) return vec(cx, cy + b, cz + a) end end
  return function(a, b) return vec(cx + a, cy, cz + b) end
end

local function spaceTransform(cx, cy, cz, u, v, w)
  if u then
    return function(a, b, c)
      return vec(cx + a * u.x + b * v.x + c * w.x, cy + a * u.y + b * v.y + c * w.y, cz + a * u.z + b * v.z + c * w.z)
    end
  end
  return function(a, b, c) return vec(cx + a, cy + b, cz + c) end
end

-- the normal along which parallel layers are stacked
local function planeNormal(orientation, w)
  if w then return w end
  if orientation == 1 then return vec(0, 0, 1) end
  if orientation == 2 then return vec(1, 0, 0) end
  return vec(0, 1, 0)
end

local function circle(out, transform, items, r, layer)
  local step = config.twoPi / items
  local offset = layer * step * 0.5
  for i = 0, items - 1 do
    local angle = i * step + offset
    out[#out + 1] = transform(r * math.cos(angle), r * math.sin(angle))
  end
end

local function square(out, transform, side, half, fill)
  local step = (side > 1) and (2 * half / (side - 1)) or 0
  for i = 0, side - 1 do
    for j = 0, side - 1 do
      if fill or i == 0 or j == 0 or i == side - 1 or j == side - 1 then
        out[#out + 1] = transform(-half + i * step, -half + j * step)
      end
    end
  end
end

-- evenly spaced along the perimeter; a side is as long as the circumradius
local function hexagon(out, transform, items, r, layer)
  local rotation = (layer % 2) * math.pi / 6
  local corners = {}
  for k = 0, 6 do
    local angle = k * math.pi / 3 + rotation
    corners[k + 1] = { r * math.cos(angle), r * math.sin(angle) }
  end
  for i = 0, items - 1 do
    local s = i * 6 / items
    local side = math.floor(s)
    local t = s - side
    local a, b = corners[side + 1], corners[side + 2]
    out[#out + 1] = transform(a[1] + t * (b[1] - a[1]), a[2] + t * (b[2] - a[2]))
  end
end

local function sphere(out, cx, cy, cz, n, r, layer)
  local phiOffset = layer * config.goldenAngle
  for i = 1, n do
    local theta = math.acos(1 - 2 * (i - 0.5) / n)
    local phi = config.goldenAngle * i + phiOffset
    local sinTheta = math.sin(theta)
    out[#out + 1] = vec(cx + r * sinTheta * math.cos(phi), cy + r * math.cos(theta), cz + r * sinTheta * math.sin(phi))
  end
end

local function cube(out, transform, side, half, fill)
  local step = (side > 1) and (2 * half / (side - 1)) or 0
  for i = 0, side - 1 do
    for j = 0, side - 1 do
      for k = 0, side - 1 do
        if fill or i == 0 or j == 0 or k == 0 or i == side - 1 or j == side - 1 or k == side - 1 then
          out[#out + 1] = transform(-half + i * step, -half + j * step, -half + k * step)
        end
      end
    end
  end
end

-- unit outline, scaled by the layer distance
local LOGO_X = {
  { 0.516287193, 0.188186137 }, { 0.159563925, -0.148662042 }, { 0.496531219, -0.683845391 },
  { -0.018830525, -0.683845391 }, { -0.167492567, -0.46580773 }, { -0.405351833, -0.683845391 },
  { -0.960356789, -0.683845391 }, { -0.385530228, -0.128840436 }, { -0.742319128, 0.436075322 },
  { -0.217046581, 0.436075322 }, { -0.058473736, 0.186323092 }, { 0.219028741, 0.436075322 },
  { 0.424893643, 0.435001800 },
}
local LOGO_CIRCLE = { 0.699702676, 0.396432111, 0.277502478 }
-- the stem is split at the crossbar so the junction is one shared point
local LOGO_FOUR = {
  { 0.749256690, 0.559960357, 0.555996036, 0.376610505 },
  { 0.555996036, 0.376610505, 0.783944500, 0.376610505 },
  { 0.783944500, 0.436075322, 0.783944500, 0.376610505 },
  { 0.783944500, 0.376610505, 0.783944500, 0.272547076 },
}

-- the X's open ends sit on the ring at these angles; the ring is two arcs between them, ends owned by the X
local LOGO_ARC_START, LOGO_ARC_INNER = 3.002152597, 0.988151328
local LOGO_LENGTH
do
  LOGO_LENGTH = config.twoPi * LOGO_CIRCLE[3]
  for i = 1, #LOGO_X - 1 do
    LOGO_LENGTH = LOGO_LENGTH + math.sqrt((LOGO_X[i + 1][1] - LOGO_X[i][1]) ^ 2 + (LOGO_X[i + 1][2] - LOGO_X[i][2]) ^ 2)
  end
  for _, s in ipairs(LOGO_FOUR) do
    LOGO_LENGTH = LOGO_LENGTH + math.sqrt((s[3] - s[1]) ^ 2 + (s[4] - s[2]) ^ 2)
  end
end

-- about `items` points evenly spaced along the outline
local function logo(out, transform, scale, items)
  local spacing = LOGO_LENGTH / items
  local function line(x1, y1, x2, y2)
    local steps = math.max(1, math.floor(math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) / spacing + 0.5))
    for i = 0, steps do
      local t = i / steps
      out[#out + 1] = transform((x1 + (x2 - x1) * t) * scale, (y1 + (y2 - y1) * t) * scale)
    end
  end
  local lx, ly, lr = LOGO_CIRCLE[1], LOGO_CIRCLE[2], LOGO_CIRCLE[3]
  local function arc(start, span)
    local steps = math.max(1, math.floor(span * lr / spacing + 0.5))
    for i = 1, steps - 1 do
      local angle = start + span * i / steps
      out[#out + 1] = transform((lx + lr * math.cos(angle)) * scale, (ly + lr * math.sin(angle)) * scale)
    end
  end
  for i = 1, #LOGO_X - 1 do
    line(LOGO_X[i][1], LOGO_X[i][2], LOGO_X[i + 1][1], LOGO_X[i + 1][2])
  end
  arc(LOGO_ARC_START, LOGO_ARC_INNER)
  arc(LOGO_ARC_START + LOGO_ARC_INNER, config.twoPi - LOGO_ARC_INNER)
  for _, s in ipairs(LOGO_FOUR) do
    line(s[1], s[2], s[3], s[4])
  end
end

-- drops points within 10 cm of an earlier one: shared corners, line ends and overlapping layers
local function dedupe(points)
  local seen, out = {}, {}
  for _, p in ipairs(points) do
    local key = string.format("%d:%d:%d", math.floor(p.x * 10 + 0.5), math.floor(p.y * 10 + 0.5), math.floor(p.z * 10 + 0.5))
    if not seen[key] then
      seen[key] = true
      out[#out + 1] = p
    end
  end
  return out
end

-- greedy nearest-neighbour walk from the first point, O(n^2)
local function sortNearestNeighbor(positions)
  local n = #positions
  if n <= 2 then return positions end
  local sorted, visited = { positions[1] }, { [1] = true }
  for _ = 2, n do
    local cur = sorted[#sorted]
    local bestIdx, bestDist = nil, math.huge
    for j = 1, n do
      if not visited[j] then
        local p = positions[j]
        local dx, dy, dz = p.x - cur.x, p.y - cur.y, p.z - cur.z
        local d2 = dx * dx + dy * dy + dz * dz
        if d2 < bestDist then
          bestDist, bestIdx = d2, j
        end
      end
    end
    visited[bestIdx] = true
    sorted[#sorted + 1] = positions[bestIdx]
  end
  return sorted
end

-- the positions of the slot cfg describes; sorted for the flight path only when they will be laid
function sm.computePositions(cfg, sorted)
  local cx, cy, cz = 0, 0, 0
  local rot
  if cfg.targetObjectPosition then
    local p = cfg.targetObjectPosition
    cx, cy, cz = p.x or 0, p.y or 0, p.z or 0
    local r = cfg.targetObjectRotation
    if r then
      rot = {
        forward = vec(r.fwdX or 0, r.fwdY or 0, r.fwdZ or 0),
        right   = vec(r.rgtX or 0, r.rgtY or 0, r.rgtZ or 0),
        up      = vec(r.upX or 0, r.upY or 0, r.upZ or 0),
      }
    end
  elseif cfg.targetPosition and type(cfg.targetPosition[2]) == "table" then
    local p = cfg.targetPosition[2]
    cx, cy, cz = p.x or 0, p.y or 0, p.z or 0
  end

  local u, v, w
  if rot and cfg.targetObject and cfg.offsetDirection > 0 then
    u, v, w = orientedBasis(rot, cfg.offsetDirection)
    cx, cy, cz = cx + w.x * cfg.offsetDistance, cy + w.y * cfg.offsetDistance, cz + w.z * cfg.offsetDistance
  end

  local shape, density = cfg.shape, cfg.density
  local onObject = cfg.targetObject ~= nil
  -- around an object the centre is taken, so only a free position fills its grid
  local fill = not onObject
  local planar = shape == 1 or shape == 2 or shape == 3 or shape == 6
  local planes = (planar and cfg.parallelLayersCount > 0 and (w or not onObject)) and (cfg.parallelLayersCount + 1) or 1
  local planeOrder = {}
  do
    local center = math.floor((planes - 1) / 2)
    planeOrder[1] = center
    local l, r = center - 1, center + 1
    while l >= 0 or r < planes do
      if l >= 0 then planeOrder[#planeOrder + 1] = l; l = l - 1 end
      if r < planes then planeOrder[#planeOrder + 1] = r; r = r + 1 end
    end
  end
  local normal = planeNormal(cfg.planeOrientation, w)
  local transform2 = planeTransform(cx, cy, cz, cfg.planeOrientation, u, v)
  local transform3 = spaceTransform(cx, cy, cz, u, v, w)

  local positions = {}
  for layer = 0, cfg.concentricShapesCount do
    local dist = cfg.radius + layer * cfg.concentricShapesSpacing
    local base = {}
    if shape == 1 then
      circle(base, transform2, config.circleItems[density], dist, layer)
    elseif shape == 2 then
      square(base, transform2, config.squareSides[density], dist, fill and layer == 0)
    elseif shape == 3 then
      hexagon(base, transform2, config.hexagonItems[density], dist, layer)
    elseif shape == 4 then
      sphere(base, cx, cy, cz, config.spherePoints[density], dist, layer)
    elseif shape == 5 then
      cube(base, transform3, config.squareSides[density], dist, fill and layer == 0)
    else
      logo(base, transform2, dist, config.logoItems[density])
    end
    for _, plane in ipairs(planeOrder) do
      local d = (plane - (planes - 1) / 2) * cfg.parallelLayersSpacing
      local group = {}
      for _, p in ipairs(base) do
        group[#group + 1] = vec(p.x + d * normal.x, p.y + d * normal.y, p.z + d * normal.z)
      end
      if sorted then group = sortNearestNeighbor(group) end
      for _, p in ipairs(group) do positions[#positions + 1] = p end
    end
  end
  return dedupe(positions)
end

-- *** config state ***

local function samePositions(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    local dx, dy, dz = a[i].x - b[i].x, a[i].y - b[i].y, a[i].z - b[i].z
    if dx * dx + dy * dy + dz * dz > 1 then return false end
  end
  return true
end

-- per old point the new point within 1 m that replaces it, or 0; each new point is taken once
local function remapPositions(old, new)
  local cell = 10
  local function cellKey(x, y, z) return x .. ":" .. y .. ":" .. z end
  local grid = {}
  for j, p in ipairs(new) do
    local k = cellKey(math.floor(p.x / cell), math.floor(p.y / cell), math.floor(p.z / cell))
    grid[k] = grid[k] or {}
    table.insert(grid[k], j)
  end
  local used, remap = {}, {}
  for i, p in ipairs(old) do
    local cx, cy, cz = math.floor(p.x / cell), math.floor(p.y / cell), math.floor(p.z / cell)
    local best, bestD = 0, 1
    for dx = -1, 1 do
      for dy = -1, 1 do
        for dz = -1, 1 do
          for _, j in ipairs(grid[cellKey(cx + dx, cy + dy, cz + dz)] or {}) do
            local q = new[j]
            local ex, ey, ez = q.x - p.x, q.y - p.y, q.z - p.z
            local d = ex * ex + ey * ey + ez * ez
            if not used[j] and d <= bestD then best, bestD = j, d end
          end
        end
      end
    end
    if best > 0 then used[best] = true end
    remap[i] = best
  end
  return remap
end

function sm.oldSlotPositions(cfg, index)
  local list = cfg.slotPositions[index]
  return (type(list) == "table") and list or {}
end

-- Configure: the slot on this tab becomes the one the window edits
function sm.loadSlot(cfg, index)
  local slot = cfg.slotList[index] ---@type any
  cfg.originalValues = {}
  for _, field in ipairs(SLOT_FIELDS) do
    cfg[field] = slot[field] or config.defaults[field]
    cfg.originalValues[field] = cfg[field]
  end
  cfg.sector               = slot.sector or (slot.targetPosition and slot.targetPosition[1])
  cfg.targetObject         = slot.targetObject
  cfg.targetObjectPosition = slot.targetObjectPosition
  cfg.targetObjectRotation = slot.targetObjectRotation
  cfg.targetPosition       = slot.targetPosition
  cfg.restockNpc           = cfg.originalRestockNpc
  cfg.editingSlotIndex, cfg.editingTabIndex, cfg.activeTab = index, index, index
  cfg.deleteArmedTab       = nil
  cfg.deleteCollect        = false
end

function sm.isDirty(cfg)
  if not cfg.originalValues then return false end
  if cfg.restockNpc ~= cfg.originalRestockNpc then return true end
  for _, field in ipairs(SLOT_FIELDS) do
    if cfg[field] ~= cfg.originalValues[field] then return true end
  end
  return false
end

-- a mine carries its library entry (damage, friend/foe, tracking, trigger range), package size and follow range
local function wareOption(wareId, macro, wareName, kind)
  local icon = GetMacroData(macro, "icon") or ""
  local package, follow
  if kind == KIND_MINE and ExtraUI then package, follow = ExtraUI.GetMacroDataEx(macro, "minecounter", "minefollowrange") end
  return {
    id = wareId, macro = macro, icon = "",
    text = (icon ~= "" and ("\027[" .. icon .. "] ") or "") .. (wareName or wareId),
    displayremoveoption = false,
    kind = kind,
    mine = (kind == KIND_MINE) and GetLibraryEntry("mines", macro) or nil,
    package = package, follow = follow,
  }
end

function sm.getDeployableWareOptions(cfg, shipId64, shipMacro, shipClass, equipmentStations)
  if cfg.existingDeployableMacro then
    local macro = cfg.existingDeployableMacro
    local wareId = GetMacroData(macro, "ware") or ""
    local wareName = (wareId ~= "") and GetWareData(wareId, "name") or macro
    cfg.allWareOptions = { wareOption(wareId, macro, wareName, IsMacroClass(macro, "mine") and KIND_MINE or KIND_TOWER) }
    return
  end

  local result = {}
  for kind, tag in ipairs({ "mine", "lasertower" }) do
    local n = C.GetNumWares(tag, false, "", "")
    local buf = ffi.new("const char*[?]", n)
    n = C.GetWares(buf, n, tag, false, "", "")
    for i = 0, n - 1 do
      local wareId = ffi.string(buf[i])
      local wareName, macro = GetWareData(wareId, "name", "component")
      if macro and wareName and (shipId64 == 0 or C.IsDeployableMacroCompatible(shipId64, shipMacro, macro)) then
        local opt = wareOption(wareId, macro, wareName, kind)
        -- one launch must be one mine (an unknown package size counts as a package);
        -- any mine but a friend/foe one can hit its own minelayer while it is placed
        if kind == KIND_MINE and opt.package ~= 1 then
          sm.Debug("mine %s left out: package size %s", wareId, tostring(opt.package))
        elseif kind == KIND_MINE and not (opt.mine and opt.mine.isfriendfoe) then
          sm.Debug("mine %s left out: not friend/foe", wareId)
        else
          result[#result + 1] = opt
        end
      end
    end
  end
  table.sort(result, function(a, b) return a.text < b.text end)

  -- only what a reachable equipment dock sells
  if type(equipmentStations) == "table" and #equipmentStations > 0 then
    local unsold = {}
    for _, opt in ipairs(result) do unsold[opt.id] = true end
    for _, station in ipairs(equipmentStations) do
      local station64 = ConvertIDTo64Bit(station)
      local count = C.GetNumAvailableEquipment(station64, shipClass)
      local equipment = ffi.new("EquipmentWareInfo[?]", count)
      count = C.GetAvailableEquipment(equipment, count, station64, shipClass)
      for j = 0, count - 1 do
        local ware = equipment[j].ware and ffi.string(equipment[j].ware) or ""
        unsold[ware] = nil
      end
      if next(unsold) == nil then break end
    end
    for i = #result, 1, -1 do
      if unsold[result[i].id] then
        sm.Trace("ware %s is sold at no reachable equipment dock", result[i].id)
        table.remove(result, i)
      end
    end
  end

  cfg.allWareOptions = result
end

-- the dropdown's items: the chosen kind
function sm.filterWareOptions(cfg)
  local list, keep = {}, nil
  for _, opt in ipairs(cfg.allWareOptions or {}) do
    if opt.kind == cfg.kind then
      list[#list + 1] = opt
      if opt.id == cfg.ware then keep = opt end
    end
  end
  if not keep then
    local default = (cfg.kind == KIND_MINE) and config.defaultMine or config.defaultTower
    for _, opt in ipairs(list) do
      if opt.id == default then keep = opt; break end
    end
    keep = keep or list[1]
  end
  cfg.deployableWareOptions = list
  cfg.ware, cfg.wareMacro = keep and keep.id or "", keep and keep.macro or ""
end

function sm.selectedWareOption(cfg)
  for _, opt in ipairs(cfg.allWareOptions or {}) do
    if opt.id == cfg.ware then return opt end
  end
end

function sm.newConfigState(request)
  local req, handle = request.req, request.handle
  local cfg = {}
  for _, field in ipairs(SLOT_FIELDS) do cfg[field] = config.defaults[field] end
  cfg.sector               = req.sector
  cfg.targetObject         = req.targetObject
  cfg.targetObjectPosition = req.targetObjectPosition
  cfg.targetObjectRotation = req.targetObjectRotation
  cfg.targetPosition       = req.targetPosition
  cfg.fromConfigure        = req.fromConfigure

  -- the order's copy of the ship's slots in tab order: uid, config, positions
  ---@type table<string, any>[]
  local slotList = {}
  local slotIds, slotPositions = {}, {}
  for _, slot in ipairs(type(req.slots) == "table" and req.slots or {}) do
    if type(slot) == "table" and type(slot.config) == "table" and slot.uid then
      local n = #slotList + 1
      slotList[n], slotIds[n], slotPositions[n] = slot.config, tostring(slot.uid), slot.positions
    end
  end
  cfg.slotList, cfg.slotIds, cfg.slotPositions = slotList, slotIds, slotPositions
  local existingMacro = GetNPCBlackboard(handle, config.deployableMacroVar)
  cfg.existingDeployableMacro = (type(existingMacro) == "string" and existingMacro ~= "") and existingMacro or nil
  -- per order; a new order starts with the value last confirmed in any window
  local restockNpc = GetNPCBlackboard(handle, config.restockNpcVar)
  if restockNpc == nil then
    local playerCfg = GetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), config.configBlackboard)
    restockNpc = (type(playerCfg) == "table") and playerCfg.restockNpc or 0
  end
  cfg.restockNpc = (restockNpc == 1 or restockNpc == true)
  cfg.originalRestockNpc = cfg.restockNpc

  local ship = ConvertIDTo64Bit(request.callbackObject) or 0
  local shipMacro = (ship ~= 0) and (GetComponentData(ship, "macro") or "") or ""
  local shipClass = (ship ~= 0) and ffi.string(C.GetComponentClass(ship)) or ""
  sm.getDeployableWareOptions(cfg, ship, shipMacro, shipClass, req.equipmentStations)
  -- an order's existing ware fixes the kind
  cfg.kind = KIND_TOWER
  for _, opt in ipairs(cfg.allWareOptions) do
    if opt.kind == KIND_MINE then cfg.kind = KIND_MINE; break end
  end
  if cfg.existingDeployableMacro then
    cfg.ware = cfg.allWareOptions[1].id
  end
  sm.filterWareOptions(cfg)

  -- Configure edits or deletes one saved slot per Confirm; any other request only adds one
  cfg.configure = cfg.fromConfigure or #cfg.slotList >= config.maxSlots
  if not cfg.configure then
    cfg.editingTabIndex = #cfg.slotList + 1
    cfg.activeTab       = cfg.editingTabIndex
    if not cfg.targetObject then cfg.offsetDirection = 0 end
  elseif #cfg.slotList > 0 then
    sm.loadSlot(cfg, 1)
  else
    cfg.editingTabIndex, cfg.activeTab = 0, 1
  end
  return cfg
end

-- *** requests ***

-- raised by the order (and every 5 s while it waits) and by the context menu, with the pilot
function sm.onConfigure(_, handle)
  if not handle then return end
  local handle64 = ConvertStringTo64Bit(tostring(handle))
  local req = GetNPCBlackboard(handle64, config.requestVar)
  if type(req) ~= "table" then
    sm.Debug("config request of %s has no data", tostring(handle64))
    return
  end
  req.fromConfigure = (req.fromConfigure == true or req.fromConfigure == 1)
  local key = tostring(handle64)
  for i, request in ipairs(sm.requests) do
    if request.key == key then
      if request.req.fromConfigure and not req.fromConfigure then
        request.req, request.callbackObject, request.cfg = req, req.callbackObject, nil
        if i == 1 then sm.dropWindow() end
        sm.Debug("Configure window of %s replaced by its config request", key)
      end
      return
    end
  end
  -- a request new to Lua has no window; a marker it carries came from a save
  SetNPCBlackboard(handle64, config.configPositionVar, nil)
  sm.requests[#sm.requests + 1] = { key = key, handle = handle64, callbackObject = req.callbackObject, req = req }
  sm.Debug("config request of %s queued, %d waiting", key, #sm.requests)
end

function sm.openRequest(request)
  if not request.req.fromConfigure and type(GetNPCBlackboard(request.handle, config.requestVar)) ~= "table" then
    sm.Debug("config request of %s was withdrawn", request.key)
    table.remove(sm.requests, 1)
    return
  end
  local menu = sm.menu
  local ship = ConvertIDTo64Bit(request.callbackObject) or 0
  if not request.cfg then
    request.cfg = sm.newConfigState(request)
    menu.selectedcomponents = {}
    menu.addSelectedComponent(ship, true, true)
    menu.setSelectedMapComponents()
  end
  -- the ship goes to the map centre, the window beside it
  if ship ~= 0 then
    C.SetFocusMapComponent(menu.holomap, ship, true)
  end
  sm.showConfigWindow()
end

-- a cleared frame sends no mouse-out, so the map would keep object picking off (as vanilla's closeContextMenu)
function sm.clearConfigFrame()
  local menu = sm.menu
  local frame = menu.frames and menu.frames[config.frameLayer]
  local over = menu.currentMouseOverTable
  if over and frame and frame ~= 0 and IsValidWidgetElement(frame) then
    for _, t in ipairs({ GetChildren(frame) }) do
      if t == over then
        menu.currentMouseOverTable = nil
        menu.picking = true
        break
      end
    end
  end
  sm.configFrame = nil
  Helper.clearFrame(menu, config.frameLayer)
end

-- the frame is gone (map closed, or a request replaced); the request stays queued and is shown again
function sm.dropWindow()
  if sm.configFrame then
    sm.clearConfigFrame()
  end
  local request = sm.requests[1]
  if request then
    SetNPCBlackboard(request.handle, config.configPositionVar, nil)
  end
end

function sm.finishRequest()
  local request = sm.requests[1]
  sm.dropWindow()
  table.remove(sm.requests, 1)
  if request and request.req.fromConfigure then
    SetNPCBlackboard(request.handle, config.requestVar, nil)
  end
  return request
end

function sm.onConfigOK()
  local request = sm.requests[1]
  local cfg = request and request.cfg
  if not cfg then return end
  local positions = sm.computePositions(cfg, true)
  if #positions == 0 or #positions > config.maxItemsPerSlot or cfg.wareMacro == "" then return end

  local slotEntry = {
    targetObject         = cfg.targetObject,
    targetObjectPosition = cfg.targetObjectPosition,
    targetObjectRotation = cfg.targetObjectRotation,
    targetPosition       = cfg.targetPosition,
    sector               = cfg.sector,
  }
  for _, field in ipairs(SLOT_FIELDS) do slotEntry[field] = cfg[field] end

  local op = { op = "add", slot = slotEntry, positions = positions }
  local edited = cfg.editingSlotIndex
  if edited then
    -- moved = 0 keeps every laid item; a move keeps those the remap places and collects the rest
    local oldPositions = sm.oldSlotPositions(cfg, edited)
    local same = samePositions(oldPositions, positions)
    op.op, op.uid, op.moved = "edit", cfg.slotIds[edited], same and 0 or 1
    if not same then
      op.remap = remapPositions(oldPositions, positions)
      local kept = 0
      for _, j in ipairs(op.remap) do if j > 0 then kept = kept + 1 end end
      sm.Debug("slot %s moved: %d of %d old points kept", op.uid, kept, #oldPositions)
    end
  end
  sm.Debug("%s slot %s of %s: %d positions, macro %s", op.op, tostring(op.uid or (#cfg.slotList + 1)), request.key, #positions, cfg.wareMacro)

  SetNPCBlackboard(request.handle, config.opVar, op)
  SetNPCBlackboard(request.handle, config.deployableMacroVar, cfg.wareMacro)
  SetNPCBlackboard(request.handle, config.deployableInputsVar, wareInputs(cfg.ware))
  SetNPCBlackboard(request.handle, config.restockNpcVar, cfg.restockNpc and 1 or 0)
  local opt = (cfg.kind == KIND_MINE) and sm.selectedWareOption(cfg) or {}
  local mine = opt.mine
  SetNPCBlackboard(request.handle, config.lowAttentionVar, mine and 1 or 0)
  -- the scanner's damage and reach for this mine
  SetNPCBlackboard(request.handle, config.mineStatsVar, mine and {
    tracking = mine.istracking and 1 or 0, range = mine.proximityrange or 0, follow = opt.follow,
    damage = mine.explosiondamage or 0, hull = mine.hullexplosiondamage or 0, shield = mine.shieldexplosiondamage or 0,
  } or nil)
  -- a cancelled first slot left a failure record; no MD action removes one
  local ship = ConvertIDTo64Bit(request.callbackObject) or 0
  local failure = ffi.new("OrderFailure")
  if ship ~= 0 and C.GetDefaultOrderFailure(failure, ship) and ffi.string(failure.orderdef) == "SmartMinelayer" then
    C.RemoveDefaultOrderFailure(ship)
    sm.Debug("default order failure of %s removed", request.key)
  end
  sm.finishRequest()
  AddUITriggeredEvent("SmartMinelayer", "ConfigReady", request.callbackObject)
end

-- drops a saved slot; an edit open in the window is dropped with it
function sm.onConfigDelete(deleted)
  local request = sm.requests[1]
  local cfg = request and request.cfg
  if not (cfg and cfg.slotIds[deleted]) then return end
  sm.Debug("slot %d (%s) of %s deleted, collect %s, %d slots left", deleted, cfg.slotIds[deleted], request.key, tostring(cfg.deleteCollect == true), #cfg.slotList - 1)
  SetNPCBlackboard(request.handle, config.opVar, { op = "delete", uid = cfg.slotIds[deleted], collect = cfg.deleteCollect and 1 or 0 })
  sm.finishRequest()
  AddUITriggeredEvent("SmartMinelayer", "ConfigReady", request.callbackObject)
end

function sm.onConfigCancel()
  local request = sm.finishRequest()
  if request and not request.req.fromConfigure then
    sm.Debug("config of %s cancelled", request.key)
    AddUITriggeredEvent("SmartMinelayer", "ConfigCancelled", request.callbackObject)
  end
end

function sm.onConfigReset()
  local cfg = sm.requests[1] and sm.requests[1].cfg
  if not (cfg and cfg.originalValues) then return end
  for _, field in ipairs(SLOT_FIELDS) do cfg[field] = cfg.originalValues[field] end
  cfg.restockNpc = cfg.originalRestockNpc
  sm.filterWareOptions(cfg)
  cfg.activeTab = cfg.editingTabIndex
  sm.showConfigWindow()
end

-- menu.getObjectColor exists from 9.00 on
function sm.getObjectColor(object64)
  local menu = sm.menu
  if config.isV9 then
    return menu.getObjectColor(object64)
  end
  local isplayerowned, isonlineobject, isenemy, ishostile = GetComponentData(object64, "isplayerowned", "isonlineobject", "isenemy", "ishostile")
  local color = Color["text_normal"]
  if isplayerowned then
    color = menu.holomapcolor.playercolor
    if object64 == C.GetPlayerObjectID() then
      color = menu.holomapcolor.currentplayershipcolor
    end
  elseif isonlineobject and menu.getFilterOption("layer_other", false) and menu.getFilterOption("think_diplomacy_highlightvisitor", false) then
    color = menu.holomapcolor.visitorcolor
  elseif ishostile then
    color = menu.holomapcolor.hostilecolor
  elseif isenemy then
    color = menu.holomapcolor.enemycolor
  end
  return color
end

-- *** window ***

local function message(t, text)
  local r = t:addRow(false, { fixed = true })
  r[1]:setColSpan(3):createText(text, { halign = "center", color = Color["text_warning"], wordwrap = true })
end

function sm.showConfigWindow()
  local request = sm.requests[1]
  local cfg = request and request.cfg
  local menu = sm.menu
  if not cfg then return end
  if sm.configFrame then
    sm.clearConfigFrame()
  end

  local frameW = menu.infoTableWidth
  local labelW = Helper.scaleX(200)
  local rowH = Helper.standardTextHeight
  -- bottom-left corner next to the ship in the map centre, kept inside vanilla's panel area
  local shipGap = Helper.scaleX(config.shipGap)
  local minY = (menu.infoTable2OffsetY or menu.infoTableOffsetY) - Helper.standardContainerOffset
  local frameX = math.min(Helper.viewWidth / 2 + shipGap, Helper.viewWidth - menu.infoTableOffsetX - frameW)
  sm.configFrame = Helper.createFrameHandle(menu, {
    layer                 = config.frameLayer,
    width                 = frameW,
    x                     = frameX,
    y                     = minY,
    standardButtons       = {},
    autoFrameHeight       = true,
    closeOnUnhandledClick = false,
  })
  sm.configFrame:setBackground("solid", { color = Color["frame_background_semitransparent"] })

  -- *** tabs: one per slot, plus the add tab when this request adds one ***
  local sideBarWidth = menu.sideBarWidth
  local slotList = cfg.slotList
  local activeTab = cfg.activeTab
  local showAddTab = cfg.editingTabIndex == #slotList + 1
  local numTabCols = math.max(1, #slotList + (showAddTab and 1 or 0))
  local tabT = sm.configFrame:addTable(numTabCols, {
    tabOrder = 1, x = Helper.borderSize, y = Helper.borderSize,
    width = numTabCols * (sideBarWidth + Helper.borderSize) - Helper.borderSize,
    reserveScrollBar = false,
  })
  for col = 1, numTabCols do tabT:setColWidth(col, sideBarWidth, false) end
  local tabRow = tabT:addRow("sm_tabs", { fixed = true })
  local dirty = cfg.configure and sm.isDirty(cfg)
  for i = 1, #slotList + (showAddTab and 1 or 0) do
    local isAdd = i > #slotList
    local locked = dirty and i ~= activeTab
    tabRow[i]:createButton({
      active        = not locked,
      width         = sideBarWidth,
      height        = sideBarWidth,
      bgColor       = (activeTab == i) and Color["row_background_selected"] or Color["row_background_unselectable"],
      mouseOverText = locked and ReadText(PAGE, 34) or (isAdd and ReadText(PAGE, 30) or (ReadText(PAGE, 1) .. " " .. i)),
      scaling       = false,
    }):setIcon(isAdd and "sml_tab_icon_add" or ("sml_tab_icon_" .. i), { color = locked and Color["icon_inactive"] or Color["icon_normal"] })
    tabRow[i].handlers.onClick = function()
      if i == cfg.activeTab then return end
      if cfg.configure then
        sm.loadSlot(cfg, i)
      else
        cfg.activeTab = i
      end
      sm.showConfigWindow()
    end
  end

  -- *** values: live on the editing tab, saved on the others ***
  local isEditingTab = activeTab == cfg.editingTabIndex
  local viewSlot = (not isEditingTab) and slotList[activeTab] or nil
  local disp = {}
  for _, field in ipairs(SLOT_FIELDS) do
    disp[field] = isEditingTab and cfg[field] or ((viewSlot and viewSlot[field]) or config.defaults[field])
  end
  local dispSector, dispTargetObject, dispTargetObjPos, dispTargetPosition
  if isEditingTab then
    dispSector, dispTargetObject, dispTargetObjPos, dispTargetPosition = cfg.sector, cfg.targetObject, cfg.targetObjectPosition, cfg.targetPosition
  elseif viewSlot then
    dispSector = viewSlot.sector or (viewSlot.targetPosition and viewSlot.targetPosition[1])
    dispTargetObject, dispTargetObjPos, dispTargetPosition = viewSlot.targetObject, viewSlot.targetObjectPosition, viewSlot.targetPosition
  end
  local itemCount
  if isEditingTab then
    itemCount = #sm.computePositions(cfg, false)
  elseif viewSlot then
    itemCount = #sm.oldSlotPositions(cfg, activeTab)
  end

  -- the order shows this point as its map marker while the window is open
  local px, py, pz
  if dispTargetObjPos then
    px, py, pz = dispTargetObjPos.x or 0, dispTargetObjPos.y or 0, dispTargetObjPos.z or 0
  elseif dispTargetPosition and type(dispTargetPosition[2]) == "table" then
    local c = dispTargetPosition[2]
    px, py, pz = c.x or 0, c.y or 0, c.z or 0
  end
  if px and dispSector then
    SetNPCBlackboard(request.handle, config.configPositionVar, { x = px, y = py, z = pz, radius = disp.radius, sector = dispSector })
  else
    SetNPCBlackboard(request.handle, config.configPositionVar, nil)
  end

  local isPlanar = disp.shape ~= 4 and disp.shape ~= 5
  local hasTargetObject = dispTargetObject ~= nil

  local t = sm.configFrame:addTable(3, {
    tabOrder = 2, x = Helper.borderSize, y = tabT.properties.y + tabT:getFullHeight() + Helper.borderSize,
    width = frameW - 2 * Helper.borderSize, defaultInteractiveObject = true,
  })
  t:setColWidth(1, labelW, false)

  local r = t:addRow(false, { fixed = true })
  r[1]:setColSpan(3):createText(ReadText(PAGE, 1), Helper.headerRowCenteredProperties)
  t:addEmptyRow(Helper.borderSize)

  local function section(textId)
    local row = t:addRow(false, { fixed = true })
    row[1]:setColSpan(3):createText(ReadText(PAGE, textId), { halign = "center", titleColor = Color["row_title"] })
  end
  local function slider(textId, field, props, enabled)
    local row = t:addRow(true, { fixed = true })
    row[1]:createText(ReadText(PAGE, textId), { halign = "left" })
    props.height, props.bgColor, props.start = rowH, Color["slider_background_transparent"], disp[field]
    props.minSelect, props.maxSelect = props.min, props.max
    props.readOnly = not enabled
    props.valueColor = (not enabled) and Color["slider_value_inactive"] or nil
    row[2]:setColSpan(2):createSliderCell(props)
    row[2].handlers.onSliderCellActivated = function() if enabled then menu.noupdate = true end end
    row[2].handlers.onSliderCellDeactivated = function() menu.noupdate = false; sm.showConfigWindow() end
    row[2].handlers.onSliderCellChanged = function(_, val) if enabled then cfg[field] = val end end
    return row
  end
  local function dropdown(textId, field, options, enabled)
    local row = t:addRow(true, { fixed = true })
    row[1]:createText(ReadText(PAGE, textId), { halign = "left" })
    row[2]:setColSpan(2):createDropDown(options, { startOption = disp[field], active = enabled })
    row[2].handlers.onDropDownActivated = function() if enabled then menu.noupdate = true end end
    row[2].handlers.onDropDownConfirmed = function(_, id)
      menu.noupdate = false
      if enabled then cfg[field] = tonumber(id) end
      sm.showConfigWindow()
    end
  end
  local function options(firstText, count, firstId)
    local list = {}
    for i = 0, count - 1 do
      list[#list + 1] = { id = firstId + i, icon = "", text = ReadText(PAGE, firstText + i), displayremoveoption = false }
    end
    return list
  end

  -- *** target ***
  section(100)
  local sector64 = dispSector and ConvertIDTo64Bit(dispSector) or 0
  r = t:addRow(false, { fixed = true, bgColor = Color["row_background_unselectable"] })
  r[1]:createText(ReadText(PAGE, 110), { halign = "left" })
  r[2]:setColSpan(2):createText((sector64 ~= 0) and (GetComponentData(sector64, "name") or "---") or "---",
    { halign = "left", color = (sector64 ~= 0) and sm.getObjectColor(sector64) or nil })
  local targetLabelId, targetText, targetColor = 10, "---", nil
  if dispTargetObject then
    local target64 = ConvertIDTo64Bit(dispTargetObject)
    local name, idcode = GetComponentData(target64, "name", "idcode")
    targetLabelId = 20
    targetText = idcode and ((name or "---") .. " (" .. idcode .. ")") or (name or "---")
    targetColor = sm.getObjectColor(target64)
  elseif px then
    targetText = string.format("%.0f / %.0f / %.0f", px, py, pz)
  end
  r = t:addRow(false, { fixed = true, bgColor = Color["row_background_unselectable"] })
  r[1]:createText(ReadText(PAGE, targetLabelId), { halign = "left" })
  r[2]:setColSpan(2):createText(targetText, { halign = "left", color = targetColor })
  t:addEmptyRow(Helper.borderSize)

  -- *** deployable: one ware per ship ***
  section(200)
  local kindOptions = {
    { id = KIND_MINE, icon = "", text = ReadText(1001, 1326), displayremoveoption = false },
    { id = KIND_TOWER, icon = "", text = ReadText(1001, 1333), displayremoveoption = false },
  }
  r = t:addRow(true, { fixed = true })
  r[1]:createText(ReadText(1001, 6400), { halign = "left" })
  r[2]:setColSpan(2):createDropDown(kindOptions, { startOption = cfg.kind, active = isEditingTab and not cfg.existingDeployableMacro })
  r[2].handlers.onDropDownActivated = function() menu.noupdate = true end
  r[2].handlers.onDropDownConfirmed = function(_, id)
    menu.noupdate = false
    cfg.kind = tonumber(id) or KIND_MINE
    sm.filterWareOptions(cfg)
    sm.showConfigWindow()
  end
  local wareOptions = cfg.deployableWareOptions or {}
  local wareMacroByWare = {}
  for _, opt in ipairs(wareOptions) do wareMacroByWare[opt.id] = opt.macro end
  r = t:addRow(true, { fixed = true })
  r[1]:createText(ReadText(PAGE, 210), { halign = "left" })
  r[2]:setColSpan(2):createDropDown(wareOptions, { startOption = cfg.ware, active = isEditingTab and #wareOptions > 0 and not cfg.existingDeployableMacro })
  r[2].handlers.onDropDownActivated = function() menu.noupdate = true end
  r[2].handlers.onDropDownConfirmed = function(_, id)
    menu.noupdate = false
    cfg.ware, cfg.wareMacro = id, wareMacroByWare[id] or ""
    sm.showConfigWindow()
  end

  -- *** shape ***
  t:addEmptyRow(Helper.borderSize)
  section(300)
  dropdown(310, "shape", options(311, 6, 1), isEditingTab)
  local radiusRow = slider(320, "radius", { min = 500, max = 30000, step = 500 }, isEditingTab)
  radiusRow[2].handlers.onSliderCellChanged = function(_, val)
    if not isEditingTab then return end
    cfg.radius = val
    local pos = GetNPCBlackboard(request.handle, config.configPositionVar)
    if type(pos) == "table" then
      pos.radius = val
      SetNPCBlackboard(request.handle, config.configPositionVar, pos)
    end
  end
  dropdown(330, "density", options(331, 5, 1), isEditingTab)
  dropdown(340, "planeOrientation", options(341, 3, 0), isEditingTab and isPlanar)

  -- *** concentric shapes and parallel layers ***
  t:addEmptyRow(Helper.borderSize)
  section(400)
  slider(410, "concentricShapesCount", { min = 0, max = 4, step = 1 }, isEditingTab)
  slider(420, "concentricShapesSpacing", { min = 200, max = 10000, step = 200 }, isEditingTab)
  t:addEmptyRow(Helper.borderSize)
  section(500)
  slider(510, "parallelLayersCount", { min = 0, max = 4, step = 1 }, isEditingTab and isPlanar)
  slider(520, "parallelLayersSpacing", { min = 200, max = 5000, step = 100 }, isEditingTab and isPlanar)

  -- *** offset from the target object ***
  t:addEmptyRow(Helper.borderSize)
  section(600)
  dropdown(610, "offsetDirection", options(611, 7, 0), isEditingTab and hasTargetObject)
  slider(620, "offsetDistance", { min = 200, max = 50000, step = 200 }, isEditingTab and hasTargetObject and disp.offsetDirection > 0)

  -- *** maintenance ***
  t:addEmptyRow(Helper.borderSize)
  section(700)
  slider(710, "threshold", { min = 0, max = 100, step = 5 }, isEditingTab)
  -- the whole order's setting, shown on every tab
  r = t:addRow(true, { fixed = true })
  r[1]:createText(ReadText(PAGE, 720), { halign = "left", mouseOverText = ReadText(PAGE, 721) })
  r[2]:createCheckBox(cfg.restockNpc, { active = isEditingTab, width = rowH, height = rowH, mouseOverText = ReadText(PAGE, 721) })
  r[2].handlers.onClick = function(_, checked)
    cfg.restockNpc = checked
    if cfg.configure then sm.showConfigWindow() end
  end
  r = t:addRow(false, { fixed = true, bgColor = Color["row_background_unselectable"] })
  r[1]:createText(ReadText(PAGE, 350), { halign = "left" })
  r[2]:setColSpan(2):createText(itemCount and tostring(itemCount) or "---", { halign = "left" })

  local tooMany = isEditingTab and itemCount > config.maxItemsPerSlot
  if isEditingTab and #wareOptions == 0 then message(t, ReadText(PAGE, 10007)) end
  if tooMany then message(t, string.format(tostring(ReadText(PAGE, 10019)), itemCount, config.maxItemsPerSlot)) end
  t:addEmptyRow(rowH / 2)

  -- *** Configure on a saved slot: the Delete box, and once it is ticked the Collect box ***
  local editsSaved = cfg.configure and cfg.slotIds[activeTab] ~= nil
  local armed = editsSaved and cfg.deleteArmedTab == activeTab
  local btnY = t.properties.y + t:getFullHeight() + Helper.borderSize
  if editsSaved then
    local dt = sm.configFrame:addTable(4, {
      tabOrder = 3, x = Helper.borderSize, y = btnY, width = frameW - 2 * Helper.borderSize,
    })
    dt:setColWidth(1, rowH, false)
    dt:setColWidth(3, rowH, false)
    local delRow = dt:addRow(true, { fixed = true })
    delRow[1]:createCheckBox(armed, { width = rowH, height = rowH, mouseOverText = ReadText(PAGE, 32) })
    delRow[1].handlers.onClick = function(_, checked)
      cfg.deleteArmedTab = checked and activeTab or nil
      cfg.deleteCollect = false
      sm.showConfigWindow()
    end
    delRow[2]:createText(ReadText(PAGE, 35), { halign = "left", mouseOverText = ReadText(PAGE, 32) })
    if armed then
      delRow[3]:createCheckBox(cfg.deleteCollect == true, { width = rowH, height = rowH, mouseOverText = ReadText(PAGE, 37) })
      delRow[3].handlers.onClick = function(_, checked)
        cfg.deleteCollect = checked
        sm.showConfigWindow()
      end
      delRow[4]:createText(ReadText(PAGE, 36), { halign = "left", mouseOverText = ReadText(PAGE, 37) })
    end
    dt:addEmptyRow(Helper.borderSize)
    btnY = dt.properties.y + dt:getFullHeight()
  end

  -- *** buttons: Configure has Confirm, Reset, Delete, Close; an add has Confirm, Cancel ***
  local btnH = Helper.standardButtonHeight
  local bt = sm.configFrame:addTable(editsSaved and 4 or 12, {
    tabOrder = editsSaved and 4 or 3, x = Helper.borderSize, y = btnY,
    width = frameW - 2 * Helper.borderSize,
  })
  local btnRow = bt:addRow("sm_buttons", { fixed = true })
  local canConfirm = isEditingTab and cfg.wareMacro ~= "" and itemCount > 0 and not tooMany and (dirty or not cfg.configure)
  local wide = editsSaved and 1 or 4
  btnRow[1]:setColSpan(wide):createButton({ height = btnH, active = canConfirm }):setText(ReadText(1001, 2821), { halign = "center" })
  btnRow[1].handlers.onClick = sm.onConfigOK
  if editsSaved then
    btnRow[2]:createButton({ height = btnH, active = dirty }):setText(ReadText(PAGE, 31), { halign = "center" })
    btnRow[2].handlers.onClick = sm.onConfigReset
    btnRow[3]:createButton({ height = btnH, active = armed, mouseOverText = ReadText(PAGE, cfg.deleteCollect and 38 or 33) }):setText(ReadText(1001, 8931), { halign = "center" })
    btnRow[3].handlers.onClick = function() sm.onConfigDelete(activeTab) end
  end
  local closeCol = editsSaved and 4 or 9
  btnRow[closeCol]:setColSpan(wide):createButton({ height = btnH }):setText(ReadText(1001, cfg.configure and 2670 or 64), { halign = "center" })
  btnRow[closeCol].handlers.onClick = sm.onConfigCancel
  bt:addEmptyRow(Helper.borderSize)

  local frameH = bt.properties.y + bt:getFullHeight() + Helper.borderSize
  sm.configFrame.properties.y = math.max(minY, Helper.viewHeight / 2 - shipGap - frameH)
  sm.configFrame:display()
end

-- *** map hooks ***

local function hookMap(menu)
  local onUpdate = menu.onUpdate
  menu.onUpdate = function(...)
    onUpdate(...)
    local request = sm.requests[1]
    if request and not sm.configFrame and menu.shown and menu.holomap and menu.holomap ~= 0 then
      local ok, err = pcall(sm.openRequest, request)
      if not ok then
        sm.Error("config window of %s failed: %s", request.key, tostring(err))
        sm.onConfigCancel()
      end
    end
  end
  local cleanup = menu.cleanup
  menu.cleanup = function(...)
    sm.dropWindow()
    return cleanup(...)
  end
  -- Escape cancels the window, unless a vanilla context menu is open above it
  local onCloseElement = menu.onCloseElement
  menu.onCloseElement = function(dueToClose, ...)
    if sm.configFrame and dueToClose == "back" and not menu.contextMenuMode then
      sm.onConfigCancel()
      return
    end
    return onCloseElement(dueToClose, ...)
  end
end

local function Init()
  sm.menu = Helper.getMenu("MapMenu")
  sm.ReadConfig()
  sm.publishDeployables()
  RegisterEvent("SmartMinelayer.Configure", sm.onConfigure)
  RegisterEvent("SmartMinelayer.ConfigChanged", sm.ReadConfig)
  if sm.menu then
    hookMap(sm.menu)
  else
    sm.Error("MapMenu not found, the config window cannot open")
  end
  sm.Debug("initialised")
end

Register_OnLoad_Init(Init)
