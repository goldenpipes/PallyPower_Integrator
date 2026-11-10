# PallyPower Integration

WoW Forever addon that lets a paladin pick and cast PallyPower blessings straight from EllesmereUI unit frames.

Hover your EUI player, party or raid frame, then:

- **Mouse wheel** picks the blessing for that player. The pick becomes your PallyPower individual assignment and syncs to the other paladins.
- **Middle-click** casts it. You can change the cast click (mouse button 4 or 5, or Shift, Ctrl or Alt with a click) and require a modifier while scrolling.

An icon on the hovered frame shows the current pick. This works in combat. If raid slots shuffle mid-fight, the choices catch up when combat ends.

## Requirements

- [PallyPower](https://github.com/AznamirWoW/PallyPower) (Forever version)
- EllesmereUI with its Unit Frames and/or Raid Frames modules

## Settings

`/ppe` opens the plugin's page in the EllesmereUI options panel (sidebar section **PallyPower**). It has a live preview built from your EUI player frame. The settings:

- **Unit frames:** turn unit-frame blessings on or off, and hide PallyPower's own bar.
- **Bindings:** the click that casts (middle-click, mouse button 4 or 5, or Shift, Ctrl or Alt with a left, right or middle click), and a modifier to hold while scrolling (none, Shift, Ctrl or Alt).
- **Visibility:** EllesmereUI's own visibility checklist. Never, Always or Mouseover (the hovered frame only), plus conditions such as in combat, in a raid or party, in a dungeon or instance, mounted, resting or with a target, each with a Show and a Hide box, matched all together or any one. You can also choose to always show the icon on the hovered frame.
- **Position:** over the portrait, inside or outside the frame, with X/Y offset and size.
- **Style:** border size and color, and a border color for players missing your blessing.
- **Cooldown:** an EUI-style swipe and timer for your blessing's remaining time on that player. You can set the swipe opacity, reverse the swipe, show the timer only under a number of minutes, and set the text size, position, color and offset.

`/ppe assign` (or `/pp blessings`) opens PallyPower's blessing assignment window. EllesmereUI skins that window. You can turn the skin off under Blizzard Skins+ > Window Skins > Third-Party Addons.

## Notes

- If EllesmereUI's own click-casting is turned on, it can conflict with this addon's cast click and mouse-wheel bindings. Pick a different cast click or scroll modifier under Bindings if it does.
- You can't cast Blessing of Sacrifice on yourself, so it never appears in your own list.
