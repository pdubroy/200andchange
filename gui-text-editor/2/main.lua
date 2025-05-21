-- tested with LÖVE versions 11.4, 11.5 and 12.0
local edit = {}

local I = {}  -- for internal names, so I can refer to them before defining them
local _  -- for unused variables

-- some constants people might like to tweak
local Text_color = {0, 0, 0}
local Cursor_color = {1, 0, 0}

local Font_height = 20
local Line_height = 26

local Margin_left, Margin_right = 25, 25  -- relative to window dimension
local Margin_top = 15

local Editor  -- most data will be here

local Cursor_time = 0  -- for blinking cursor

function love.load(arg)
  love.keyboard.setKeyRepeat(true)
  love.graphics.setBackgroundColor(1,1,1)
  love.graphics.setFont(love.graphics.newFont(Font_height))
  local screen_width, screen_height = love.window.getMode()
  Editor = edit.new(Margin_top, Margin_left, screen_width-Margin_right, screen_height-Margin_top)
end

function edit.new(top, left, right, bottom)
  local result = {
    top=top, left=left, right=right, bottom=bottom,
    width = right-left,

    -- The editor is for editing an array of lines.
    -- The array of lines can never be empty; there must be at least one line for positioning a cursor at.
    lines = {''},  -- array of strings

    -- We need to track a couple of _locations_:
    cursor = {line=1, pos=1},  -- location where editing will occur
  }
  return result
end

function love.draw()
  local y = Editor.top
  for line_index = 1, #Editor.lines do
    local loc = {line=line_index, pos=1}
    local rect = I.get_rect(Editor, loc, Editor.bottom - y)
    for _,s in ipairs(rect.screen_line_rects) do
      for _,c in ipairs(s.char_rects) do
        love.graphics.setColor(Text_color)
        love.graphics.print(c.data, Editor.left+c.x, y+c.y)
        if line_index == Editor.cursor.line and c.pos == Editor.cursor.pos then
          I.draw_text_cursor(Editor, Editor.left+c.x, y+c.y, c.dy)
        end
      end
    end
    y = y + rect.dy
    if y + Line_height > Editor.bottom then
      break
    end
  end
end

function love.update(dt)
  Cursor_time = Cursor_time + dt
end

function love.mousepressed(mx,my, mouse_button)
  Cursor_time = 0  -- ensure cursor is visible immediately after it moves
  Editor.cursor = I.loc_at_mouse(Editor)
end

---- keyboard handling

function love.keyreleased(key)
  Cursor_time = 0  -- ensure cursor is visible immediately after it moves
end

function love.textinput(t)
  Cursor_time = 0  -- ensure cursor is visible immediately after it moves
  if love.mouse.isDown(1) then return end
  I.insert_text_at_cursor(Editor, t)
end

function love.keypressed(key)
  Cursor_time = 0  -- ensure cursor is visible immediately after it moves
  if key == 'return' then
    local before_line = Editor.cursor.line
    I.insert_return_at_cursor(Editor)
  elseif key == 'tab' then
    I.insert_text_at_cursor(Editor, '\t')
  elseif key == 'backspace' then
    local before
    if Editor.cursor.pos > 1 then
      local line = Editor.lines[Editor.cursor.line]
      Editor.lines[Editor.cursor.line] = line:sub(1, Editor.cursor.pos-2)..line:sub(Editor.cursor.pos)
      Editor.cursor.pos = Editor.cursor.pos-1
    elseif Editor.cursor.line > 1 then
      -- join lines
      local prev = Editor.lines[Editor.cursor.line-1]
      local curr = Editor.lines[Editor.cursor.line]
      Editor.cursor.pos = #prev+1
      Editor.lines[Editor.cursor.line-1] = prev..curr
      table.remove(Editor.lines, Editor.cursor.line)
      Editor.cursor.line = Editor.cursor.line-1
    end
  elseif key == 'delete' then
    -- cursor in text line
    if Editor.cursor.pos <= #Editor.lines[Editor.cursor.line] then
      local line = Editor.lines[Editor.cursor.line]
      Editor.lines[Editor.cursor.line] = line:sub(1, Editor.cursor.pos-1)..line:sub(Editor.cursor.pos+1)
      -- no change to Editor.cursor.pos
    elseif Editor.cursor.line < #Editor.lines then
      -- join lines
      Editor.lines[Editor.cursor.line] = Editor.lines[Editor.cursor.line]..Editor.lines[Editor.cursor.line+1]
      table.remove(Editor.lines, Editor.cursor.line+1)
    end
  end
end

function I.draw_text_cursor(editor, x, y, dy)
  -- blink every 0.5s
  if math.floor(Cursor_time*2)%2 == 0 then
    love.graphics.setColor(Cursor_color)
    love.graphics.rectangle('fill', x,y, 3,dy)
  end
end

function I.insert_text_at_cursor(editor, t)
  local line = editor.lines[editor.cursor.line]
  local p = editor.cursor.pos
  editor.lines[editor.cursor.line] = line:sub(1, p-1)..t..line:sub(p)
  editor.cursor.pos = p+1
end

function I.insert_return_at_cursor(editor)
  local line = editor.lines[editor.cursor.line]
  local p = editor.cursor.pos
  table.insert(editor.lines, editor.cursor.line+1, line:sub(p))
  editor.lines[editor.cursor.line] = line:sub(1, p-1)
  editor.cursor = {line=editor.cursor.line+1, pos=1}
end

---- helpers for keyboard handling

function I.shift_down()
  return love.keyboard.isDown('lshift') or love.keyboard.isDown('rshift')
end

function I.is_cursor_movement(key)
  for _, x in ipairs{'left', 'right', 'up', 'down', 'home', 'end', 'pageup', 'pagedown'} do
    if key == x then
      return true
    end
  end
  return false
end

-- return the location corresponding to a pixel
function I.to_loc(editor, mx,my)
  if my < editor.top then
    return {line=1, pos=1}
  end
  local x, y, maxy = mx - editor.left, my - editor.top, editor.bottom - editor.top
  local rect
  for line_index = 1, #editor.lines do
    if maxy < Line_height then
      break
    end
    rect = I.get_rect(editor, {line=line_index, pos=1})
    if y < rect.dy then
      local s = I.find_y(rect.screen_line_rects, y)
      local char_rect = I.find_xy(s.char_rects, x, y)
      assert(char_rect)
      return {line=line_index, pos=char_rect.pos}
    end
    y = y - rect.dy
    maxy = maxy - rect.dy
    if y <= 0 then
      break
    end
  end
  -- below all lines; return final rect on screen
  local s = rect.screen_line_rects
  local c = s[#s].char_rects
  return {line=rect.line_index, pos=c[#c].pos}
end

-- generate rects for each screen line in it and the range [pos,pos+dpos-1] associated with each
-- within each screen line generate rects for each byte and the pos associated with each.
--
-- Each rect is a rectangle on screen, as defined by its x, y, dx (width) and
-- dy (height). A rect will also usually contain some data that is
-- claimed/made to live within that rectangle on screen.
--
-- Example line containing 3 screen lines after word wrapping:
--  {x=0, y=0, dx=100, dy=30,  -- line is 100px wide and 30px tall
--    screen_line_rects = {
--      {x=0, y=0, dx=100, dy=10,  -- first screen line of line
--        ...  -- see below for what's inside a screen line
--      },
--      {x=0, y=10, dx=100, dy=10,  -- second screen line of line starts at y=10
--        ...
--      },
--      {x=0, y=20, dx=100, dy=10,  -- third screen line of line starts at y=20
--        ...
--      },
--    },
--  }
--
-- Example screen line:
--  {x=0, y=0, dx=100, dy=10,
--    pos=1, dpos=10,  -- will render 10 characters from the line starting at position 1 (start of line)
--    char_rects = {
--      {x=0, y=0, dx=10, dy=10, pos=1, data='a'},  -- the first character is drawn at 0,0; clicking anywhere in this rect focuses cursor before this character
--      ...
--    }
--  }
function I.get_rect(editor, loc, available_height)
  if available_height == nil then
    available_height = editor.bottom - editor.top
  end
  local line = editor.lines[loc.line]
  local screen_lines = {}
  local curr_screen_line = {}
  local spos = 1
  local x, y = 0, 0
  for pos = loc.pos,#line do
    local char = line:sub(pos,pos)
    local w = love.graphics.getFont():getWidth(char)
    if x+w > editor.width then
      assert(pos > 1)
      table.insert(curr_screen_line, {x=x, y=y, dx=editor.width-x, dy=Line_height, pos=pos, data=''})  -- filler
      table.insert(screen_lines, {x=0, y=y, dx=editor.width, dy=Line_height, pos=spos, dpos=(pos-1)-spos+1, char_rects=curr_screen_line})
      curr_screen_line = {}
      spos = pos
      x = 0
      y = y + Line_height
      if y + Line_height > available_height then
        return {x=0, y=0, dx=editor.width, dy=y, screen_line_rects=screen_lines}
      end
    end
    table.insert(curr_screen_line, {x=x, y=y, dx=w, dy=Line_height, pos=pos, data=char})
    x = x + w
  end
  table.insert(curr_screen_line, {x=x, y=y, dx=editor.width-x, dy=Line_height, pos=#line+1, data=''})  -- filler
  table.insert(screen_lines, {x=0, y=y, dx=editor.width, dy=Line_height, pos=spos, dpos=#line+1-spos+1, char_rects=curr_screen_line})
  y = y + Line_height
  return {x=0, y=0, dx=editor.width, dy=y, line_index=loc.line, screen_line_rects=screen_lines}
end

function I.find_xy(rects, x, y)
  if x < 0 then return rects[1] end
  for _, rect in ipairs(rects) do
    if I.within_rect(rect, x, y) then
      return rect
    end
  end
  return rects[#rects]
end

function I.find_x(rects, x)
  if x < 0 then return rects[1] end
  for _, rect in ipairs(rects) do
    if I.within(x, rect.x, rect.x+rect.dx) then
      return rect
    end
  end
  return rects[#rects]
end

function I.find_y(rects, y)
  if y < 0 then return rects[1] end
  for _, rect in ipairs(rects) do
    if I.within(y, rect.y, rect.y+rect.dy) then
      return rect
    end
  end
  return rects[#rects]
end

function I.within_rect(rect, x,y)
  return I.within(x, rect.x, rect.x+rect.dx)
    and I.within(y, rect.y, rect.y+rect.dy)
end

function I.within(a, lo, hi)
  return a >= lo and a < hi
end

-- helpers for selecting portions of text

function I.loc_at_mouse(editor)
  local mx,my = love.mouse.getPosition()
  return I.to_loc(editor, mx, my)
end
