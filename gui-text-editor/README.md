A few draft versions of a text editor supporting a proportional font (so no
grid of characters) and line wrapping.

They're built in the [LÖVE](https://love2d.org) but should be easy to port to
other platforms that provide a canvas to draw pixels on and can draw fonts on
it. Primitives used:

* `love.graphics.print`  -- print text in some font at a specific x,y
* `love.graphics.setColor` -- for later drawing operations
* `love.graphics.getMode` -- get window dimensions
* `love.graphics.rectangle`  -- draw a filled rectangle
* `love.mouse.getPosition`
* `love.mouse.isDown`  -- detect mouse click/drag
* `love.keyboard.isDown`  -- detect keypress
* `love.system.setClipboardText` and `love.system.getClipboardText`  -- clipboard integration
* `font:getWidth`  -- compute width of text in a given font
