-- tested with LÖVE versions 11.4, 11.5 and 12.0
local edit = {}

local I = {}  -- for internal names, so I can refer to them before defining them
local _  -- for unused variables

-- some constants people might like to tweak
local Text_color = {0, 0, 0}
local Cursor_color = {1, 0, 0}
local Highlight_color = {0.7, 0.7, 0.9, --[[alpha]] 0.4}  -- for selected text

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
    screen_top = {line=1, pos=1},  -- location at top of screen, to start drawing from
    cursor = {line=1, pos=1},  -- location where editing will occur
    selection = {},
  }
  return result
end

function love.draw()
  local y = Editor.top
  for line_index = Editor.screen_top.line, #Editor.lines do
    local loc
    if line_index == Editor.screen_top.line then
      loc = Editor.screen_top
    else
      loc = {line=line_index, pos=1}
    end
    local rect = I.get_rect(Editor, loc, Editor.bottom - y)
    for _,s in ipairs(rect.screen_line_rects) do
      for _,c in ipairs(s.char_rects) do
        if I.in_selection(Editor, line_index, c.pos, Editor.cursor) then
          love.graphics.setColor(Highlight_color)
          love.graphics.rectangle('fill', Editor.left+c.x, y+c.y, c.dx,c.dy)
        end
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

function love.mousepressed(mx,my, mouse_button)
  Cursor_time = 0  -- ensure cursor is visible immediately after it moves
  if I.shift_down() then
    -- only set selection on first press with shift down
    if Editor.selection.line == nil then
      Editor.selection = Editor.cursor
    end
  else
    Editor.selection = I.loc_at_mouse(Editor)
  end
end

function love.update(dt)
  Cursor_time = Cursor_time + dt
  if love.mouse.isDown(1) then
    Editor.cursor = I.loc_at_mouse(Editor)
  end
end

function edit.mouse_release(mx,my, mouse_button)
  Cursor_time = 0  -- ensure cursor is visible immediately after it moves
end

---- keyboard handling

function love.keyreleased(key)
  Cursor_time = 0  -- ensure cursor is visible immediately after it moves
end

function love.textinput(t)
  Cursor_time = 0  -- ensure cursor is visible immediately after it moves
  if love.mouse.isDown(1) then return end
  if I.to_coord(Editor, Editor.cursor) == nil then return end  -- cursor is off screen
  I.insert_text_at_cursor(Editor, t)
  I.maybe_snap_cursor_to_bottom_of_screen(Editor)
end

function love.keypressed(key)
  Cursor_time = 0  -- ensure cursor is visible immediately after it moves
  if I.to_coord(Editor, Editor.cursor) == nil then return end  -- cursor is off screen
  if Editor.selection.line and
      -- printable character created using shift key => delete selection
      -- (we're not creating any ctrl-shift- or alt-shift- combinations using regular/printable keys)
      (not I.shift_down() or #key == 1) and
      key ~= 'backspace' and key ~= 'delete' and not I.is_cursor_movement(key) then
    I.delete_selection(Editor)
  end
  if chord == 'C-c' then
    local s = I.selection(editor)
    if s then
      love.system.setClipboardText(s)
    end
  elseif chord == 'C-x' then
    local s = I.cut_selection(editor, editor.left, editor.right)
    if s then
      love.system.setClipboardText(s)
    end
  elseif chord == 'C-v' then
    local clipboard_data = love.system.getClipboardText()
    for _,code in utf8.codes(clipboard_data) do
      local c = utf8.char(code)
      if c == '\n' then
        I.insert_return_at_cursor(editor)
      else
        I.insert_text_at_cursor(editor, c)
      end
    end
    I.maybe_snap_cursor_to_bottom_of_screen(editor)
  --== shortcuts that mutate text
  elseif key == 'return' then
    local before_line = Editor.cursor.line
    I.insert_return_at_cursor(Editor)
    I.maybe_snap_cursor_to_bottom_of_screen(Editor)
  elseif key == 'tab' then
    I.insert_text_at_cursor(Editor, '\t')
    I.maybe_snap_cursor_to_bottom_of_screen(Editor)
  elseif key == 'backspace' then
    if Editor.selection.line then
      I.delete_selection(Editor)
      return
    end
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
    if Editor.screen_top.line > #Editor.lines then
      Editor.screen_top = I.loc_down(Editor, Editor.cursor, 0)
    elseif I.loc_lt(Editor.cursor, Editor.screen_top) then
      I.maybe_snap_cursor_to_top_of_screen(Editor)
    end
    assert(I.loc_le(Editor.screen_top, Editor.cursor), ('screen_top (line=%d,pos=%d) is below cursor (line=%d,pos=%d)'):format(Editor.screen_top.line, Editor.screen_top.pos or -1, Editor.cursor.line, Editor.cursor.pos or -1))
  elseif key == 'delete' then
    -- cursor in text line
    if Editor.selection.line then
      I.delete_selection(Editor)
      return
    end
    local before
    if Editor.cursor.pos <= #Editor.lines[Editor.cursor.line] then
      local line = Editor.lines[Editor.cursor.line]
      Editor.lines[Editor.cursor.line] = line:sub(1, Editor.cursor.pos-1)..line:sub(Editor.cursor.pos+1)
      -- no change to Editor.cursor.pos
    elseif Editor.cursor.line < #Editor.lines then
      -- join lines
      Editor.lines[Editor.cursor.line] = Editor.lines[Editor.cursor.line]..Editor.lines[Editor.cursor.line+1]
      table.remove(Editor.lines, Editor.cursor.line+1)
    end
  --== shortcuts that move the cursor
  elseif I.is_cursor_movement(key) then
    if I.shift_down() then
      if Editor.selection.line == nil then
        Editor.selection = {line=Editor.cursor.line, pos=Editor.cursor.pos}
      end
    else
      Editor.selection = {}
    end
    if key == 'left' then I.left_arrow(Editor)
    elseif key == 'right' then I.right_arrow(Editor)
    elseif key == 'down' then I.down_arrow(Editor)
    elseif key == 'up' then I.up_arrow(Editor)
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
  I.maybe_snap_cursor_to_bottom_of_screen(editor)
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

---- moving around the editor in terms of locations (loc)
--
-- locations within text lines look like this:
--   {line=, pos=}
--
-- all movements are built primarily using the following primitives, defined
-- further down:
--   - to_loc: (x, y) -> loc
--     identify the location at pixel coordinates (x,y) on screen
--     returns nil if (x,y) is not on screen
--   - to_coord: loc -> x, y
--     identify the top-left coordinate on screen of location loc
--     returns nil if loc is not on screen
--   - loc_down: loc, dy -> loc
--     find the location at the start of a screen line dy pixels down from loc
--     returns nil if dy is taller than the screen
--     returns bottom of file if we hit it
--   - loc_up: loc, dy -> loc
--     find the location at the start of a screen line dy pixels up from loc
--     returns nil if dy is taller than the screen
--     returns top of file if we hit it
--   - loc_hor: loc, x -> loc
--     find the location at x=x0 on the same screen line as loc
--
-- I have tried to make these definitions as clear as possible while being fast enough.
-- My mental model for trading off performance for clarity:
--   - any computation limited to the number of characters a screen can show
--     will be an order of magnitude faster than it needs to be to draw 30
--     frames per second.
--     So I don't mind doing up to 5 scans per interactive operation if that
--     makes the code clearer.
--   - no caching across frames; it makes the code less clear and has also
--     caused bugs.
--   - short-lived memory allocations that live within a single frame are cheap
--
-- This API is independent of the data structures the editor uses, whether
-- arrays as here or ropes or gap buffers.

function I.up_arrow(editor)
  local x, _ = I.to_coord(editor, editor.cursor)  -- scan
  editor.cursor = I.loc_up(editor, editor.cursor, 1 --[[px]])  -- scan
  assert(editor.cursor)
  editor.cursor = I.loc_hor(editor, editor.cursor, x)  -- 0-1 scan
  assert(editor.cursor)
  I.maybe_snap_cursor_to_top_of_screen(editor)  -- 1-2 scans
end  -- 3-5 scans

function I.down_arrow(editor)
  local x, _ = I.to_coord(editor, editor.cursor)  -- scan
  editor.cursor = I.loc_down(editor, editor.cursor, Line_height)  -- scan
  assert(editor.cursor)
  editor.cursor = I.loc_hor(editor, editor.cursor, x)  -- 0-1 scan
  assert(editor.cursor)
  I.maybe_snap_cursor_to_bottom_of_screen(editor)  -- 0-2 scans
end  -- 2-5 scans

function I.left_arrow(editor)
  if editor.cursor.pos and editor.cursor.pos > 1 then
    editor.cursor.pos = editor.cursor.pos-1
  elseif editor.cursor.line > 1 then
    editor.cursor = I.loc_up(editor, editor.cursor, 1 --[[px]])  -- scan
    assert(editor.cursor)
    editor.cursor = I.loc_hor(editor, editor.cursor, editor.right)  -- 0-1 scan
    assert(editor.cursor)
  end
  I.maybe_snap_cursor_to_top_of_screen(editor)  -- 1-2 scans
end  -- 1-4 scans

function I.right_arrow(editor)
  if editor.cursor.pos and editor.cursor.pos <= #editor.lines[editor.cursor.line] then
    editor.cursor.pos = editor.cursor.pos+1
  else
    local _, y = I.to_coord(editor, editor.cursor)  -- scan
    local new_cursor = I.loc_down(editor, editor.cursor, Line_height)  -- scan
    if I.loc_lt(editor.cursor, new_cursor) then  -- there's further down to go
      editor.cursor = new_cursor
    end
  end
  I.maybe_snap_cursor_to_bottom_of_screen(editor)  -- 0-2 scans
end  -- 0-4 scans

function I.maybe_snap_cursor_to_top_of_screen(editor)
  local _, y = I.to_coord(editor, editor.cursor)  -- scan
  if y == nil then
    editor.screen_top = I.loc_hor(editor, editor.cursor, editor.left)  -- scan
    assert(editor.screen_top)
  end
end  -- 1-2 scans

function I.maybe_snap_cursor_to_bottom_of_screen(editor)
  local _, y = I.to_coord(editor, editor.cursor)  -- scan
  if y == nil or y > editor.bottom - editor.top - Line_height then
    editor.screen_top = I.loc_up_whole_screen_lines(editor, editor.cursor, editor.bottom - editor.top - Line_height)  -- scan
    assert(editor.screen_top)
  else
    -- no need to scroll
    return
  end
end  -- 1-2 scans

---- helpers for moving around the editor
-- These simulate drawing on screen without actually doing so.
--
-- These _do_ depend on the data structures the editor uses (see get_rect).

-- return the location corresponding to a pixel
function I.to_loc(editor, mx,my)
  if my < editor.top then
    return I.deepcopy(editor.screen_top)
  end
  local x, y, maxy = mx - editor.left, my - editor.top, editor.bottom - editor.top
  local rect
  for line_index = editor.screen_top.line, #editor.lines do
    if maxy < Line_height then
      break
    end
    if line_index == editor.screen_top.line then
      rect = I.get_rect(editor, editor.screen_top)
    else
      rect = I.get_rect(editor, {line=line_index, pos=1})
    end
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

function I.to_coord(editor, loc)  -- scans
  if I.loc_lt(loc, editor.screen_top) then return end
  local y = editor.top
  for line_index = editor.screen_top.line, #editor.lines do
    local line = editor.lines[line_index]
    local rect
    if line_index == editor.screen_top.line then
      rect = I.get_rect(editor, editor.screen_top)
    else
      rect = I.get_rect(editor, {line=line_index, pos=1})
    end
    if line_index == loc.line then
      for _,s in ipairs(rect.screen_line_rects) do
        for _,c in ipairs(s.char_rects) do
          if c.pos == loc.pos and (c.data or c.pos == #line+1) then
            return editor.left + c.x, y + c.y
          end
        end
      end
      assert(false, 'to_coord: invalid pos in text loc')
    end
    y = y + rect.dy
    if y > editor.bottom then
      break
    end
  end
end  -- 1 scan

-- find the location at the start of a screen line dy pixels down from loc
-- return nil if dy is more than screen height away
-- return bottommost screen line in file if we hit it
function I.loc_down(editor, loc, dy)  -- scans
  local y = 0
  local prevloc = loc
  for line_index = loc.line, #editor.lines do
    local rect = I.get_rect(editor, {line=line_index, pos=1})
    for _,s in ipairs(rect.screen_line_rects) do
      if line_index > loc.line or loc.pos < s.pos+s.dpos then
        local currloc = {line=line_index, pos=s.pos}
        if y + s.dy > dy then
          return currloc
        end
        y = y + s.dy
        prevloc = currloc
      end
    end
  end
  return prevloc
end  -- 1 scan

-- find the location at the start of a screen line dy pixels up from loc
-- return nil if dy is more than screen height away
-- return topmost screen line in file if we hit it
function I.loc_up(editor, loc, dy)  -- scans
  local y = 0
  -- special handling for loc's line
  local rect = I.get_rect(editor, {line=loc.line, pos=1})
  local found = false
  for is = #rect.screen_line_rects,1,-1 do
    local s = rect.screen_line_rects[is]
    if not found and I.within(loc.pos, s.pos, s.pos+s.dpos) then
      found = true
    elseif found then
      if y + s.dy > dy then
        return {line=loc.line, pos=s.pos}
      end
      y = y + s.dy
    else
      -- below loc's screen line; skip
    end
  end
  for line_index = loc.line-1,1,-1 do
    local line = editor.lines[line_index]
    local rect = I.get_rect(editor, {line=line_index, pos=1})
    for is = #rect.screen_line_rects,1,-1 do
      local s = rect.screen_line_rects[is]
      if y + s.dy > dy then
        return {line=line_index, pos=s.pos}
      end
      y = y + s.dy
    end
  end
  return {line=1, pos=1}
end  -- 1 scan

-- find the location at the start of a screen line up to dy pixels up from loc, but count only whole screen lines.
-- So the result will be at or below dy pixels above loc.
function I.loc_up_whole_screen_lines(editor, loc, dy)  -- scans
  local prevloc = loc  -- bug: not at start of screen line
  local y = 0
  -- special handling for loc's line
  local rect = I.get_rect(editor, {line=loc.line, pos=1})
  local found = false
  for is = #rect.screen_line_rects,1,-1 do
    local s = rect.screen_line_rects[is]
    if not found and I.within(loc.pos, s.pos, s.pos+s.dpos) then
      found = true
    elseif found then
      local currloc = {line=loc.line, pos=s.pos}
      if y + s.dy > dy then
        return prevloc
      end
      y = y + s.dy
      prevloc = currloc
    else
      -- below loc's screen line; skip
    end
  end
  for line_index = loc.line-1,1,-1 do
    local line = editor.lines[line_index]
    local rect = I.get_rect(editor, {line=line_index, pos=1})
    for is = #rect.screen_line_rects,1,-1 do
      local s = rect.screen_line_rects[is]
      local currloc = {line=line_index, pos=s.pos}
      if y + s.dy > dy then
        return prevloc
      end
      y = y + s.dy
      prevloc = currloc
    end
  end
  return {line=1, pos=1}
end  -- 1 scan

-- find the location at x=x0 on the same screen line as loc
function I.loc_hor(editor, loc, x0)  -- scans line
  local rect = I.get_rect(editor, {line=loc.line, pos=1})
  x0 = x0 - editor.left
  assert(rect.screen_line_rects)
  for i,sc in ipairs(rect.screen_line_rects) do
    if loc.pos >= sc.pos and loc.pos < sc.pos+sc.dpos then
      local prevx = nil
      for _,c in ipairs(sc.char_rects) do
        if (prevx == nil or x0 >= (prevx+c.x)/2) and x0 < c.x+c.dx/2 then
          return {line=loc.line, pos=c.pos}
        end
        prevx = c.x
      end
      return {line=loc.line, pos=sc.pos+sc.dpos-1}
    end
  end
end  -- 0-1 scans

function I.loc_eq(a, b)
  return a.line == b.line and a.pos == b.pos
end

function I.loc_lt(a, b)
  if a.line < b.line then return true end
  if a.line > b.line then return false end
  return a.pos < b.pos
end

function I.loc_le(a, b)
  return I.loc_eq(a, b) or I.loc_lt(a, b)
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

function I.delete_selection(editor)
  if editor.selection.line == nil then return end
  -- min,max = sorted(editor.selection,editor.cursor)
  local minl,minp = editor.selection.line,editor.selection.pos
  local maxl,maxp = editor.cursor.line,editor.cursor.pos
  if minl > maxl then
    minl,maxl = maxl,minl
    minp,maxp = maxp,minp
  elseif minl == maxl then
    if minp > maxp then
      minp,maxp = maxp,minp
    end
  end
  -- update editor.cursor and editor.selection
  editor.cursor.line = minl
  editor.cursor.pos = minp
  if I.loc_lt(editor.cursor, editor.screen_top) then
    editor.screen_top = I.loc_hor(editor, editor.cursor, editor.left)
  end
  editor.selection = {}
  -- delete everything between min (inclusive) and max (exclusive)
  if minl == maxl then
    editor.lines[minl] = editor.lines[minl]:sub(1, minp-1)..editor.lines[minl]:sub(maxp)
    return
  end
  assert(minl < maxl, ('minl %d not < maxl %d'):format(minl, maxl))
  local rhs = editor.lines[maxl]:sub(maxp)
  for i=maxl,minl+1,-1 do
    table.remove(editor.lines, i)
  end
  editor.lines[minl] = editor.lines[minl]:sub(1, minp-1)..rhs
end

function I.in_selection(editor, line_index, pos, cursor)
  if editor.selection.line == nil then return false end
  local curr = {line=line_index, pos=pos}
  if I.loc_eq(cursor, editor.selection) then
    return false
  elseif I.loc_lt(cursor, editor.selection) then
    return I.loc_le(cursor, curr) and I.loc_lt(curr, editor.selection)
  elseif I.loc_lt(editor.selection, cursor) then
    return I.loc_le(editor.selection, curr) and I.loc_lt(curr, cursor)
  end
end
