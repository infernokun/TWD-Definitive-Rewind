# TODO

## Season 3 rewind: verify and validate (WIP)

Season 3 has the Rewind entry in its More Options popup, the rewind list and the picture strip, but it
has not been played through and checked the way Season 4 has.

- [ ] Rewind to a scene point in each Season 3 episode (1-5) and check the episode starts in that scene.
- [ ] Check the choices made before that point are kept, and the ones after it are gone.
- [ ] Rewind a second time in the same episode (the list should again show every earlier point).
- [ ] Check the "Saved" points and "From the beginning".
- [ ] Find a way to run the mod inside Season 3 episodes. They don't load it yet (Season 4 uses the
      `GameOverrides.lua` wrapper; no equivalent has been found for Season 3), so a scene point's act
      number and "entered" flags are not applied when the scene starts.
- [ ] Check the picture strip follows the highlighted row on every page of the list.

## Season 4 picture view

- [x] Rewind opens straight onto the latest point's picture, with Previous / Next / Rewind here.
- [ ] Controller: LB / RB browse, Y opens the numbered list, B closes (not confirmed yet).
- [ ] Possible later: the game has a carousel menu (`Menu_carousel.lua`: an image display with
      shoulder buttons and arrows) that might make a real gallery screen.

## Other

- [ ] Run the screenshot tour once as an add-on (`tools/capture-tour`) in the game. It worked when its
      code was inside `TWDRewind.lua`, but has not been run since it was moved out.
