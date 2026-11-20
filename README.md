# Smart Minelayer

Laying a minefield by hand means placing every mine yourself and coming back whenever the field thins out, and while you are away the game leaves the mines inert. This extension adds the **Smart Minelayer** order: the ship lays mines or laser towers in a pattern you design on the map, refills the losses on its own, restocks itself when it runs out, and its friend/foe mines keep fighting while you are far away.

## Features

- **Patterns**: circle, square, hexagon, sphere, cube or the X4 logo, around a point in space or around a station or gate, with a radius, a density and a plane orientation. Concentric shapes, parallel layers and an offset from the target build larger fields from one pattern.
- **Up to nine fields per ship**: each field, called a slot, has its own target, sector, pattern and item count (up to 1000 items). Changing one slot leaves the items of the others in place.
- **Mines or laser towers**: any mine or laser tower the ship can carry. Package mines that release a whole cluster at once, such as the Cluster Mine, are left out.
- **Active While You Are Away**: with this option, friend/foe mines detonate on enemy ships while you are far from the field, where the game otherwise leaves them inert. A mine reaches as far as its trigger range, a tracking mine as far as it follows a target.
- **Automatic refill**: when a slot's losses reach its replacement threshold, the ship flies out and lays the missing items again.
- **Own restock**: when the ship runs out of items, it buys them on its own. It looks for your own supply ships and stations first, free of charge, near its sector before farther away. With **Restock at Other Factions' Stations** it may also buy at other factions' stations, at their price and only as many as you can pay for.
- **Experience for kills**: when the mines or laser towers of the ship or its wingmen destroy an enemy ship, the pilot and service crew of the ship and of every wingman gain experience, as they would from the game's attack order.
- **Wingmen**: ships assigned to the minelayer with the **Assist** order lay, refill and restock the same fields together with it.
- **Waiting**: between refills the ship docks at the nearest station in the field's sector that lets it, or waits in open space a few kilometres off the field's edge.

## Limitations

- S, M and L ships only: XL ships are not offered the order.
- One kind of item per ship: once the order holds a mine or laser tower, the window keeps it. To lay another kind, give the ship a new order.
- Without **Active While You Are Away**, mines behave as in the game: they act only while you are near the field. Only friend/foe mines can be chosen with the option on.
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

Select a ship that carries mines or laser towers, open its **Behaviour** on the map and choose **Smart Minelayer**. Set **Target Position** to a point in space, or **Target Object** to a station or gate, turn on **Add Position** and confirm. The configuration window opens on the map.

![Behaviour: Smart Minelayer](docs/images/behaviour.png)

In the **Deployable** section pick the type, **Mines** or **Laser Towers**, and the item. With **Mines**, **Active While You Are Away** is on by default and offers only friend/foe mines; turn it off to choose any mine.

In **Shape**, **Concentric Shapes**, **Parallel Layers** and **Offset** design the field. The window shows how many items the slot needs.

In **Maintenance** set the **Replacement Threshold**: the share of a slot's items that must be lost before the ship refills it, 0 for at once. **Restock at Other Factions' Stations** lets the ship buy at stations that are not yours; a new order starts with your last choice.

![Configuration window](docs/images/config_window.png)

Confirm, and the ship flies to the field and lays it. For another field, set a new target and turn on **Add Position** again; up to nine slots, one tab each in the window. Picking the target of an existing slot opens that slot for a change.

![An X4 Logo of 120 Friend/Foe Mines on the map](docs/images/map_x4_logo.png)

To look at a ship's slots, choose **Configure Smart Minelayer** in its context menu; with UI Extensions installed it is under **Smart Minelayer** in **Custom Actions**.

![Context menu: Configure Smart Minelayer](docs/images/context_menu.png)

## Options

An options page is available via the `Extension Options` menu: it sets the debug level of the extension's log.

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
