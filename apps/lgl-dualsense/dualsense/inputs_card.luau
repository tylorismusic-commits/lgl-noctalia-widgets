--!nonstrict
-- Live gamepad input display for the Noctalia desktop.
--
-- Renders buttons, D-pad, both sticks and both triggers as they are pressed and
-- moved. State comes from the plugin's "listener" service, which reads the
-- kernel evdev node of the pad (see code/ds_inputs_daemon.py).

local STALE_AFTER = 20 -- seconds without a daemon heartbeat
local DEADZONE = 0.08  -- stick jitter below this is drawn as centered

local settings = {
  accent_color = noctalia.getConfig("accent_color") or "primary",
  text_color = noctalia.getConfig("text_color") or "on_surface",
  muted_text_color = noctalia.getConfig("muted_text_color") or "on_surface_variant",
  show_battery = noctalia.getConfig("show_battery"),
  illustration_color = noctalia.getConfig("illustration_color") or "#e8ebef",
  controller_body_color = noctalia.getConfig("controller_body_color") or "#2c3035",
  controller_body_opacity = tonumber(noctalia.getConfig("controller_body_opacity")) or 1.0,
  controller_stroke_width = tonumber(noctalia.getConfig("controller_stroke_width")) or 2.8,
}
if settings.accent_color == "" then
  settings.accent_color = "primary"
end
if settings.text_color == "" then
  settings.text_color = "on_surface"
end
if settings.muted_text_color == "" then
  settings.muted_text_color = "on_surface_variant"
end
if settings.show_battery == nil then
  settings.show_battery = true
end

local SHAPE = {
  triangle = "#6fe3a2",
  circle = "#ff7a90",
  square = "#ff9ad5",
  cross = "#8ab4ff",
}

-- Xbox-style face letters, in the physical positions used by the 8BitDo pad:
-- Y top, B right, A bottom, X left.
local XBOX = {
  y = "#f2c94c",
  b = "#ef5350",
  a = "#66bb6a",
  x = "#4a90e2",
}

local STICK = 52
local CELL = 16
local GAP = 8
local CARD_W = STICK * 4 + GAP * 3
local DOT = 7

local current_state = nil
local render

local function valid_hex(color)
  return type(color) == "string" and (
    string.match(color, "^#%x%x%x$")
    or string.match(color, "^#%x%x%x%x$")
    or string.match(color, "^#%x%x%x%x%x%x$")
    or string.match(color, "^#%x%x%x%x%x%x%x%x$")
  ) ~= nil
end

local function resolve_color(value, fallback)
  if value == nil or value == "" then
    return fallback
  end
  if string.sub(value, 1, 1) == "#" then
    return value
  end
  if type(noctalia.getColor) == "function" then
    return noctalia.getColor(value) or fallback
  end
  return fallback
end

-- Palette role tokens take "/alpha", hex colours need an #RRGGBBAA suffix.
local function with_alpha(color, alpha)
  if type(color) ~= "string" then
    return color
  end
  local suffix = string.format("%02x", math.floor(alpha * 255 + 0.5))
  if string.sub(color, 1, 1) == "#" then
    local hex = string.gsub(color, "#", "")
    if #hex == 6 or #hex == 8 then
      return "#" .. string.sub(hex, 1, 6) .. suffix
    end
    return color
  end
  return color .. "/" .. string.format("%.2f", alpha)
end

local function color_key(color)
  return string.gsub(tostring(color), "[^%w]", "")
end

-- ui.image cannot tint, so the controller art is generated from an SVG
-- template per model and written into the plugin data directory. The template
-- changes with the active pad: DualSense/Edge, DualShock 4, or Xbox/8BitDo.
local ART = {
  dualsense = { template = "assets/controller-template.svg", fallback = "assets/controller.svg" },
  edge = { template = "assets/controller-template.svg", fallback = "assets/controller.svg" },
  ds4 = { template = "assets/ds4-template.svg", fallback = "assets/ds4.svg" },
  ["8bitdo"] = { template = "assets/xbox-template.svg", fallback = "assets/xbox.svg" },
  xinput = { template = "assets/xbox-template.svg", fallback = "assets/xbox.svg" },
}

local art_cache = {}

local function controller_art(model)
  local key = type(model) == "string" and model or "dualsense"
  local entry = ART[key] or ART.dualsense
  local line = resolve_color(settings.illustration_color, "#e8ebef")
  local body = resolve_color(settings.controller_body_color, "#2c3035")
  local lightbar = resolve_color(settings.accent_color, "#4a90e2")
  if not valid_hex(line) then
    line = "#e8ebef"
  end
  if not valid_hex(body) then
    body = "#2c3035"
  end
  if not valid_hex(lightbar) then
    lightbar = "#4a90e2"
  end
  local stroke = settings.controller_stroke_width
  if type(stroke) ~= "number" or stroke <= 0 then
    stroke = 2.8
  end
  local opacity = settings.controller_body_opacity
  if type(opacity) ~= "number" then
    opacity = 1.0
  end
  opacity = math.max(0, math.min(1, opacity))
  local stroke_text = string.format("%.2f", stroke)
  local grip_text = string.format("%.2f", stroke * 0.625)
  local opacity_text = string.format("%.2f", opacity)

  local dir = noctalia.pluginDataDir()
  if not dir then
    return nil
  end
  local path = dir .. "/controller-" .. color_key(key)
    .. "-" .. color_key(line) .. "-" .. color_key(body)
    .. "-" .. color_key(lightbar) .. "-" .. color_key(stroke_text)
    .. "-" .. color_key(opacity_text) .. ".svg"
  if art_cache[key] == path and noctalia.fileExists(path) then
    return path
  end
  local template = noctalia.readFile(entry.template)
  if not template then
    return entry.fallback
  end
  local svg = string.gsub(template, "{{BODY}}", body)
  svg = string.gsub(svg, "{{BODY_OPACITY}}", opacity_text)
  svg = string.gsub(svg, "{{COLOR}}", line)
  svg = string.gsub(svg, "{{LIGHTBAR}}", lightbar)
  svg = string.gsub(svg, "{{STROKE_BODY}}", stroke_text)
  svg = string.gsub(svg, "{{STROKE_GRIP}}", grip_text)
  if not noctalia.writeFile(path, svg) then
    return entry.fallback
  end
  art_cache[key] = path
  return path
end

local function fresh()
  if type(current_state) ~= "table" then
    return false
  end
  local ts = tonumber(current_state.ts)
  if not ts then
    return false
  end
  return os.time() - ts <= STALE_AFTER
end

local function full_state()
  if not fresh() or current_state.connected ~= true then
    return nil
  end
  return current_state
end

local function button(name)
  local s = full_state()
  if type(s) ~= "table" or type(s.buttons) ~= "table" then
    return false
  end
  return s.buttons[name] == true
end

local function axis(table_name, key)
  local s = full_state()
  if type(s) ~= "table" or type(s[table_name]) ~= "table" then
    return 0
  end
  return tonumber(s[table_name][key]) or 0
end

local function dpad(key)
  local s = full_state()
  if type(s) ~= "table" or type(s.dpad) ~= "table" then
    return 0
  end
  return tonumber(s.dpad[key]) or 0
end

local function weight(value)
  if not value or value < 0 then
    return 0.001
  end
  return math.max(0.001, value)
end

local function stick_position(value)
  if math.abs(value) < DEADZONE then
    return 0.5
  end
  return math.max(0, math.min(1, (value + 1) / 2))
end

-- A round stick well with a dot offset by the live axis values. `ui.*` has no
-- absolute positioning, so the offset comes from weighted spacers around the
-- dot: flexGrow x : (1 - x) puts it at the right fraction of the well.
local function stick_node(key, x_value, y_value, pressed)
  local fx = stick_position(x_value)
  local fy = stick_position(y_value)
  local border = pressed and settings.accent_color or with_alpha(resolve_color(settings.muted_text_color, "#8b9096"), 0.55)
  return ui.column({
    key = key,
    width = STICK,
    height = STICK,
    radius = STICK / 2,
    fill = "surface/0.55",
    border = border,
    borderWidth = pressed and 2 or 1,
    padding = 7,
    align = "stretch",
  }, {
    ui.spacer({ key = key .. "-up", flexGrow = weight(fy) }),
    ui.row({ key = key .. "-row", height = DOT, align = "center", justify = "start" }, {
      ui.spacer({ key = key .. "-left", flexGrow = weight(fx) }),
      ui.column({
        key = key .. "-dot",
        width = DOT,
        height = DOT,
        radius = DOT / 2,
        fill = settings.accent_color,
        opacity = pressed and 1 or 0.9,
      }),
      ui.spacer({ key = key .. "-right", flexGrow = weight(1 - fx) }),
    }),
    ui.spacer({ key = key .. "-down", flexGrow = weight(1 - fy) }),
  })
end

local function shape_button(key, glyph, color, lit)
  return ui.column({
    key = key,
    width = CELL,
    height = CELL,
    radius = 5,
    align = "center",
    justify = "center",
    fill = lit and with_alpha(color, 0.3) or "surface/0.55",
    border = lit and color or "outline/0.55",
    borderWidth = lit and 2 or 1,
  }, {
    ui.glyph({ key = key .. "-glyph", name = glyph, size = 10, color = color, opacity = lit and 1 or 0.55 }),
  })
end

local function letter_button(key, letter, color, lit)
  return ui.column({
    key = key,
    width = CELL,
    height = CELL,
    radius = 5,
    align = "center",
    justify = "center",
    fill = lit and with_alpha(color, 0.3) or "surface/0.55",
    border = lit and color or "outline/0.55",
    borderWidth = lit and 2 or 1,
  }, {
    ui.label({
      key = key .. "-letter",
      text = letter,
      fontSize = 10,
      fontWeight = "bold",
      color = lit and "#ffffff" or color,
      opacity = lit and 1 or 0.7,
    }),
  })
end

local function mini_button(key, glyph, lit)
  return ui.column({
    key = key,
    width = CELL,
    height = CELL,
    radius = 5,
    align = "center",
    justify = "center",
    fill = lit and with_alpha(settings.accent_color, 0.35) or "surface/0.55",
    border = lit and settings.accent_color or "outline/0.55",
    borderWidth = lit and 2 or 1,
  }, {
    ui.glyph({
      key = key .. "-glyph",
      name = glyph,
      size = 9,
      color = lit and settings.accent_color or settings.muted_text_color,
      opacity = lit and 1 or 0.75,
    }),
  })
end

local function dpad_cell(key, glyph, lit)
  return ui.column({
    key = key,
    width = CELL,
    height = CELL,
    radius = 4,
    align = "center",
    justify = "center",
    fill = lit and with_alpha(settings.accent_color, 0.35) or "surface/0.55",
    border = lit and settings.accent_color or "outline/0.55",
    borderWidth = lit and 2 or 1,
  }, {
    ui.glyph({
      key = key .. "-glyph",
      name = glyph,
      size = 10,
      color = lit and settings.accent_color or settings.muted_text_color,
      opacity = lit and 1 or 0.7,
    }),
  })
end

local function dpad_node()
  local x = dpad("x")
  local y = dpad("y")
  local function row(key, children)
    return ui.row({ key = key, gap = 2, align = "center", justify = "center" }, children)
  end
  local function empty(key)
    return ui.column({ key = key, width = CELL, height = CELL })
  end
  return ui.column({ key = "dpad", gap = 2, align = "center", justify = "center", width = STICK, height = STICK }, {
    row("dpad-up-row", {
      empty("dpad-empty-tl"),
      dpad_cell("dpad-up", "chevron-up", y < 0),
      empty("dpad-empty-tr"),
    }),
    row("dpad-mid-row", {
      dpad_cell("dpad-left", "chevron-left", x < 0),
      ui.column({ key = "dpad-center", width = CELL, height = CELL, align = "center", justify = "center" }, {
        ui.column({ key = "dpad-center-dot", width = 6, height = 6, radius = 3, fill = "outline/0.5" }),
      }),
      dpad_cell("dpad-right", "chevron-right", x > 0),
    }),
    row("dpad-down-row", {
      empty("dpad-empty-bl"),
      dpad_cell("dpad-down", "chevron-down", y > 0),
      empty("dpad-empty-br"),
    }),
  })
end

local function face_node()
  local s = full_state()
  local xbox = type(s) == "table" and (s.model == "8bitdo" or s.model == "xinput")
  local function face(key, glyph, color, lit, letter, xbox_color)
    if xbox then
      return letter_button(key, letter, xbox_color or color, lit)
    end
    return shape_button(key, glyph, color, lit)
  end
  local function row(key, children)
    return ui.row({ key = key, gap = 2, align = "center", justify = "center" }, children)
  end
  local function empty(key)
    return ui.column({ key = key, width = CELL, height = CELL })
  end
  return ui.column({ key = "face", gap = 2, align = "center", justify = "center", width = STICK, height = STICK }, {
    row("face-top-row", {
      empty("face-empty-tl"),
      face("face-triangle", "triangle", SHAPE.triangle, button("triangle"), "Y", XBOX.y),
      empty("face-empty-tr"),
    }),
    row("face-mid-row", {
      face("face-square", "square", SHAPE.square, button("square"), "X", XBOX.x),
      ui.column({ key = "face-center", width = CELL, height = CELL }),
      face("face-circle", "circle", SHAPE.circle, button("circle"), "B", XBOX.b),
    }),
    row("face-bottom-row", {
      empty("face-empty-bl"),
      face("face-cross", "x", SHAPE.cross, button("cross"), "A", XBOX.a),
      empty("face-empty-br"),
    }),
  })
end

local function pill(key, text, lit)
  return ui.column({
    key = key,
    width = 26,
    height = CELL,
    radius = 5,
    align = "center",
    justify = "center",
    fill = lit and with_alpha(settings.accent_color, 0.35) or "surface/0.55",
    border = lit and settings.accent_color or "outline/0.55",
    borderWidth = lit and 2 or 1,
  }, {
    ui.label({
      key = key .. "-label",
      text = text,
      fontSize = 8,
      fontWeight = "medium",
      color = lit and settings.accent_color or settings.muted_text_color,
    }),
  })
end

local function trigger_column(key, text, value, align_end)
  return ui.column({
    key = key,
    width = 44,
    gap = 3,
    align = align_end and "end" or "start",
  }, {
    ui.label({
      key = key .. "-label",
      text = text,
      fontSize = 8,
      color = settings.muted_text_color,
      opacity = value > 0.02 and 1 or 0.7,
    }),
    ui.progress({
      key = key .. "-bar",
      progress = value,
      width = 44,
      height = 4,
      radius = 2,
      fill = settings.accent_color,
      track = "outline/0.35",
    }),
  })
end

local function battery_label(s)
  if not settings.show_battery then
    return nil
  end
  local pct = tonumber(s.battery_pct) or -1
  if pct < 0 then
    return nil
  end
  return ui.row({ key = "battery", gap = 3, align = "center" }, {
    ui.glyph({
      key = "battery-glyph",
      name = s.charging and "battery-charging" or "battery",
      size = 11,
      color = s.charging and settings.accent_color or settings.muted_text_color,
    }),
    ui.label({
      key = "battery-text",
      text = tostring(math.floor(pct + 0.5)) .. "%",
      fontSize = 10,
      color = settings.muted_text_color,
    }),
  })
end

local function header(s)
  local title = "DualSense"
  if s.model == "edge" then
    title = "DualSense Edge"
  elseif s.model == "ds4" then
    title = "DualShock 4"
  elseif s.model == "8bitdo" then
    title = "8BitDo"
  elseif s.model == "xinput" then
    title = "Xbox Controller"
  end

  local children = {}
  local art = controller_art(s.model)
  if art then
    table.insert(children, ui.image({
      key = "controller-art",
      path = art,
      width = 76,
      height = 57,
      fit = "contain",
    }))
  end

  local status = {}
  local battery = battery_label(s)
  if battery then
    table.insert(status, battery)
  end
  if s.connection == "usb" then
    table.insert(status, ui.glyph({ key = "header-link", name = "usb", size = 11, color = settings.muted_text_color }))
  elseif s.connection == "bluetooth" then
    table.insert(status, ui.glyph({ key = "header-link", name = "bluetooth", size = 11, color = settings.muted_text_color }))
  end

  table.insert(children, ui.column({
    key = "header-info",
    gap = 4,
    align = "center",
  }, {
    ui.row({ key = "header-title-row", gap = 5, align = "center", justify = "center" }, {
      ui.label({
        key = "header-title",
        text = title,
        fontSize = 10,
        fontWeight = "semibold",
        color = settings.text_color,
      }),
    }),
    ui.row({ key = "header-status-row", gap = 6, align = "center", justify = "center" }, status),
  }))

  return ui.row({ key = "header", gap = 8, width = CARD_W, align = "center", justify = "center" }, children)
end

local function shoulders(s)
  return ui.row({ key = "shoulders", width = CARD_W, gap = 6, align = "center" }, {
    trigger_column("l2", "L2", axis("triggers", "l2"), false),
    pill("l1", "L1", button("l1")),
    ui.spacer({ key = "shoulder-gap-l", flexGrow = 1 }),
    mini_button("create", "menu-2", button("create")),
    mini_button("ps", "circle-dot", button("ps")),
    mini_button("mute", "microphone-off", button("mute")),
    ui.spacer({ key = "shoulder-gap-r", flexGrow = 1 }),
    pill("r1", "R1", button("r1")),
    trigger_column("r2", "R2", axis("triggers", "r2"), true),
  })
end

local function body()
  return ui.row({ key = "body", width = CARD_W, gap = GAP, align = "center", justify = "center" }, {
    stick_node("stick-l", axis("sticks", "lx"), axis("sticks", "ly"), button("l3")),
    dpad_node(),
    face_node(),
    stick_node("stick-r", axis("sticks", "rx"), axis("sticks", "ry"), button("r3")),
  })
end

local function placeholder()
  local s = type(current_state) == "table" and current_state or {}
  local text = noctalia.tr("inputs.waiting")
  if s.error == "python3" then
    text = noctalia.tr("status.no_python")
  end
  return ui.column({ key = "placeholder", width = CARD_W, gap = 4, align = "center", paddingV = 10 }, {
    ui.glyph({ key = "placeholder-glyph", name = "device-gamepad-2", size = 22, color = settings.muted_text_color, opacity = 0.7 }),
    ui.label({
      key = "placeholder-text",
      text = text,
      fontSize = 10,
      color = settings.muted_text_color,
    }),
    ui.label({
      key = "placeholder-hint",
      text = noctalia.tr("inputs.hint"),
      fontSize = 9,
      color = settings.muted_text_color,
      opacity = 0.7,
    }),
  })
end

render = function()
  local s = full_state()

  local children
  if s then
    children = { header(s), shoulders(s), body() }
  else
    children = { placeholder() }
  end
  desktopWidget.render(ui.column({
    key = "inputs-card",
    gap = 6,
    align = "center",
    padding = 2,
  }, children))
end

current_state = noctalia.state.get("inputs")
noctalia.setUpdateInterval(1000)
noctalia.state.watch("inputs", function(value)
  current_state = value
  render()
end)

function update()
  render()
end

render()
