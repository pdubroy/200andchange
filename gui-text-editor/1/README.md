This version demonstrates rendering wrapped text to screen and positioning the
cursor using the mouse.

It does this by saving the rectangle area (_rect_) corresponding to each
character printed.

The key idea is to recompute the rects while drawing every frame, and make
them available to mouse events in the same frame. It's better on balance to
use CPU inefficiently (but in a bounded manner) while limiting memory usage.

Limitations:

* Single line of text (that can wrap)
* No scrolling (single line of text can't overflow window)
* No special keys, arrows, etc. Just type. Mouse click to move cursor.
* You have to click on a character. Left or right of a line won't work.
