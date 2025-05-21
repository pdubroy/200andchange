-- single-line text editor with line wrap

Cursor = {line=1, pos=1}

Font_height = 20
Line_height = 26

Margin_left, Margin_right = 15, 415  -- absolute
Margin_top = 15

W, H = nil

Rects = {}  -- global but recreated every frame

function love.load()
  love.keyboard.setKeyRepeat(true)
  love.graphics.setBackgroundColor(1,1,1)
  love.graphics.setColor(0,0,0)
  love.graphics.setFont(love.graphics.newFont(Font_height))
  W, H = love.window.getMode()
end

function love.draw()
  compute_rects()
  for _, rect in ipairs(Rects) do
    if Cursor.line == rect.line and Cursor.pos == rect.pos then
      love.graphics.rectangle('fill', rect.x, rect.y, 3, Line_height)
    end
    love.graphics.print(rect.data, rect.x,rect.y)
  end
end

function compute_rects()
  Rects = {}
  local x,y, line = Margin_left,Margin_top, 1
  for j=1,#Text do
    local c = Text:sub(j,j)
    local w = love.graphics.getFont():getWidth(c)
    if x+w > Margin_right then
      x, y = Margin_left, y + Line_height
      if y + Line_height > H then
        break
      end
    end
    table.insert(Rects, {x=x, y=y, w=w, h=Line_height, line=line, pos=j, data=c})
    x = x + w
  end
end

function love.mousepressed(x, y)
  for _, rect in ipairs(Rects) do
    if within(rect, x, y) then
      Cursor = {line=rect.line, pos=rect.pos}
    end
  end
end

function within(rect, x,y)
  return rect.x <= x and x < rect.x+rect.w
    and rect.y <= y and y < rect.y+rect.h
end

function love.textinput(t)
  -- mutate Text, never Rects
  Text = Text:sub(1, Cursor.pos-1) .. t .. Text:sub(Cursor.pos)
  Cursor.pos = Cursor.pos+1
end

Text = [[Call me Ishmael.  Some years ago--never mind how long precisely--having little or no money in my purse, and nothing particular to interest me on shore, I thought I would sail about a little and see the watery part of the world.  It is a way I have of driving off the spleen and regulating the circulation.  Whenever I find myself growing grim about the mouth; whenever it is a damp, drizzly November in my soul; whenever I find myself involuntarily pausing before coffin warehouses, and bringing up the rear of every funeral I meet; and especially whenever my hypos get such an upper hand of me, that it requires a strong moral principle to prevent me from deliberately stepping into the street, and methodically knocking people's hats off--then, I account it high time to get to sea as soon as I can.  This is my substitute for pistol and ball.  With a philosophical flourish Cato throws himself upon his sword; I quietly take to the ship.  There is nothing surprising in this.  If they but knew it, almost all men in their degree, some time or other, cherish very nearly the same feelings towards the ocean with me.]]
