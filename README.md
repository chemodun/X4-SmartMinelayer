# Smart Minelayer

Laying a minefield by hand means placing every mine yourself and coming back whenever the field thins out, and while you are away the game leaves the mines inert. This extension adds the **Smart Minelayer** order: the ship lays mines or laser towers in a pattern you design on the map, refills the losses on its own, restocks itself when it runs out, and its friend/foe mines keep fighting while you are far away.

## Features

- **Patterns**: circle, square, hexagon, sphere, cube or the X4 logo, around a point in space or around a station or gate, with a radius, a density and a plane orientation. Concentric shapes, parallel layers and an offset from the target build larger fields from one pattern.
- **Up to nine fields per ship**: each field, called a slot, has its own target, sector, pattern and item count (up to 1000 items). Changing one slot leaves the items of the others in place.
- **Friend/foe mines or laser towers**: any friend/foe mine or laser tower the ship can carry. Package mines that release a whole cluster at once, such as the Cluster Mine, are left out.
- **Active while you are away**: the mines detonate on enemy ships while you are far from the field, where the game otherwise leaves them inert. A mine reaches as far as its trigger range, a tracking mine as far as it follows a target.
- **Automatic refill**: when a slot's losses reach its replacement threshold, the ship flies out and lays the missing items again.
- **Own restock**: when the ship runs out of items, it buys them on its own. It looks for your own supply ships and stations first, free of charge, near its sector before farther away. With **Restock at Other Factions' Stations** it may also buy at other factions' stations, at their price and only as many as you can pay for.
- **Experience for kills**: when the mines or laser towers of the ship or its wingmen destroy an enemy ship, the pilot and service crew of the ship and of every wingman gain experience, as they would from the game's attack order.
- **Wingmen**: ships assigned to the minelayer with the **Assist** order lay, refill and restock the same fields together with it.
- **Waiting**: between refills the ship docks at the nearest station in the field's sector that lets it, or waits in open space a few kilometres off the field's edge.

## Limitations

- S, M and L ships only: XL ships are not offered the order.
- One kind of item per ship: once the order holds a mine or laser tower, the window keeps it. To lay another kind, give the ship a new order.
- Only friend/foe mines: any other mine could hit the minelayer itself while it lays the field.
- While you are away, a mine hits the first enemy ship within its reach; there is no hit chance.
- When you change a slot's pattern, the items already laid for it stay in space but are no longer refilled.
- A restock that fails five times in a row stops the order with a message. A trip cut short by your own edit of the order or by another order does not count.
- The extension patches two game AI scripts, `order.assist.xml` and `interrupt.attacked.xml`, and one mission script, `notifications.xml`. The patches are small, but another mod that patches or replaces the same scripts can still conflict with it.

## Requirements

- **X4: Foundations**: Version **8.00** or higher on Windows, or **9.00** on the native Linux version.
- **Mod Support APIs**: Version **1.95** or higher by [SirNukes](https://next.nexusmods.com/profile/sirnukes?gameId=2659).
  - Available on Steam: [SirNukes Mod Support APIs](https://steamcommunity.com/sharedfiles/filedetails/?id=2042901274)
  - Available on Nexus Mods: [Mod Support APIs](https://www.nexusmods.com/x4foundations/mods/503)
- **Options Helper**: Version **1.10** or higher by [Chem O`Dun](https://next.nexusmods.com/profile/ChemODun/mods?gameId=2659).
  - Available on Steam: [Options Helper](https://steamcommunity.com/sharedfiles/filedetails/?id=3715253556)
  - Available on Nexus Mods: [Options Helper](https://www.nexusmods.com/x4foundations/mods/2089)
- **Print Extension List**: Version **1.00** or higher by [Chem O`Dun](https://next.nexusmods.com/profile/ChemODun/mods?gameId=2659).
  - Available on Steam: [Print Extension List](https://steamcommunity.com/sharedfiles/filedetails/?id=3770927339)
  - Available on Nexus Mods: [Print Extension List](https://www.nexusmods.com/x4foundations/mods/2191)
- **Lua Log API**: Version **1.00** or higher by [Chem O`Dun](https://next.nexusmods.com/profile/ChemODun/mods?gameId=2659).
  - Available on Steam: [Lua Log API](https://steamcommunity.com/sharedfiles/filedetails/?id=3823580916)
  - Available on Nexus Mods: [Lua Log API](https://www.nexusmods.com/x4foundations/mods/2473)
- **Extra UI API**: Version **1.05** or higher by [Chem O`Dun](https://next.nexusmods.com/profile/ChemODun/mods?gameId=2659), which tells which mines come as a package and how far a tracking mine follows its target.
  - Available on Steam: [Extra UI API](https://steamcommunity.com/sharedfiles/filedetails/?id=3839783822)
  - Available on Nexus Mods: [Extra UI API](https://www.nexusmods.com/x4foundations/mods/2602)

## Installation

You can download the latest version via Steam client - [Smart Minelayer](https://steamcommunity.com/sharedfiles/filedetails/?id=3843065392)
Or you can do it via the Nexus Mods - [Smart Minelayer](https://www.nexusmods.com/x4foundations/mods/0)

## Save state

**No** (removing the extension does not break saves).

## Usage

Select a ship that carries mines or laser towers, open its **Behaviour** on the map and choose **Smart Minelayer**. Set **Target Position** to a point in space, or **Target Object** to a station or gate, and confirm. The configuration window for the first slot opens on the map.

![Behaviour: Smart Minelayer](docs/images/behaviour.png)

In the **Deployable** section pick the type, **Mines** or **Laser Towers**, and the item.

In **Shape**, **Concentric Shapes**, **Parallel Layers** and **Offset** design the field. The window shows how many items the slot needs.

In **Maintenance** set the **Replacement Threshold**: the share of a slot's items that must be lost before the ship refills it, 0 for at once. **Restock at Other Factions' Stations** lets the ship buy at stations that are not yours; a new order starts with your last choice.

![Configuration window](docs/images/config_window.png)

Confirm, and the ship flies to the field and lays it. For another field, select the ship, right-click a spot in space, a station or a gate and choose **Add Minelayer Position**; up to nine slots, one tab each in the window. Picking the target of an existing slot opens that slot for a change. A new target in its **Behaviour** adds no slot. The tab of a saved slot shows **Delete** in place of **Reset**: tick the box beside it first. The deleted slot's items stay in space and are no longer replaced. Deleting the last slot clears the order's target too; the ship stands by until **Add Minelayer Position** gives it a new one.

A few fields on the map, one slot each:

![Three concentric circles of 54 Friend/Foe Mines](docs/images/map_concentric_circles.png)

![Two concentric hexagons of 54 Friend/Foe Mines](docs/images/map_hexagons.png)

![A sphere of 62 Friend/Foe Mines](docs/images/map_sphere.png)

![A filled cube inside a hollow one, 53 Friend/Foe Mines, seen from above](docs/images/map_cube.png)

To look at a ship's slots, right-click it with no other object selected and choose **Configure Smart Minelayer** under **Orders**. If the window of its first slot was closed without a slot, the same item opens it again.

![Context menu: Configure Smart Minelayer](docs/images/context_menu.png)

## Options

An options page is available via the `Extension Options` menu. **Keep Slots of a Destroyed Minelayer** sets how many game hours (0 to 24, default 4) the slots of a minelayer destroyed without wingmen are kept before they are dropped; its friend/foe mines keep working either way. **Debug Level** sets the detail of the extension's log.

![Options](docs/images/options.png)

## Credits

- Author: Chem O`Dun, on [Nexus Mods](https://next.nexusmods.com/profile/ChemODun/mods?gameId=2659) and [Steam Workshop](https://steamcommunity.com/id/chemodun/myworkshopfiles/?appid=392160)
- *"X4: Foundations"* is a trademark of [Egosoft](https://www.egosoft.com).

## Acknowledgements

- [EGOSOFT](https://www.egosoft.com) - for the X series.
- [SirNukes](https://next.nexusmods.com/profile/sirnukes?gameId=2659) - for the Mod Support APIs that power the UI hooks.

## Changelog

### [1.00] - unreleased

- **Added**
  - Initial public version
