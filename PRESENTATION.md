Export to PDF.


One single video. Pause frames are stretched out to 1s.

Check video location on every frame.
If we're in a pause area, pause the video.
If we're in a loop area, reset video to previous point.

Commands:
  Pause.
  Unpause.
  Play forwards.
  Play backwards.
  Skip forwards to next pause frame.
  Skip backwards to prev pause frame.
  Step forwards one frame.
  Step backwards one frame.

Playing backwards requires two videos. Can we switch video while in fullscreen?
Yes, at least in FF. Might be a good idea not to depend on this.
Instead: Concatenate the two videos, one forward and one backwards.

Types of frames:
  Pause
  Repeat
  Reverse

elm
  fps and frame indexes as flags.
