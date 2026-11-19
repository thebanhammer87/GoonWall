# GoonWall

Shared guild chat for **&lt;Goon Squad&gt;** and its alt guilds on **World of Warcraft: Forever**.

Members of Goon Squad and every alt guild see one `/g`. A line typed in any of them shows up in all
of them, tagged with the guild it came from:

    [Guild] [Nil Goat]: <GoonSquab> anyone up for Deadmines?

GoonWall is a fork of [GreenWall](https://github.com/AIE-Guild/GreenWall) by Mark Rogaski, rebuilt
for the Forever client (interface `16001`). It doesn't talk to stock GreenWall, GuildLink, or the
streamer forks.

## Installation

1. **Remove GreenWall, GuildLink and any other guild-bridge addon.** Running two bridges at once
   doubles every line.
2. Put the `GoonWall` folder in the Forever client's `Interface\AddOns\` folder.
   The folder must be named `GoonWall` and contain `GoonWall.toc`.
3. Enable **GoonWall** on the character select screen's AddOns list and log in.

After login you'll see `GoonWall: v2.0.2 loaded.` About 30 seconds later you'll see
`Connected to confederation on channel N.` That's all a member needs to do.

## Setting it up (officers)

See [GUILD_QUICKSTART.md](GUILD_QUICKSTART.md). In short, paste the same block into the
**Guild Information** text of every guild.

## Options

`/gw` or `/goonwall`, or Esc → Options → AddOns → GoonWall.

| Command | Default | What it does |
|---|---|---|
| `/gw tag on\|off` | on | Prefix bridged lines with the sender's guild tag, for example `<GoonSquab>`. |
| `/gw roster on\|off` | on | Show online, offline, join and leave notices from the other guilds. |
| `/gw mode account\|character` | account | Share settings across your characters, or keep them per character. |
| `/gw joindelay <seconds>` | 30 | How long to wait after login before joining the bridge channel. |
| `/gw status` | | Connection status. |
| `/gw reload` | | Re-read the Guild Information config. |
| `/gw reset` | | Leave and rejoin the bridge, and reload the config. |
| `/gw version` | | Addon, client and Lua versions. |
| `/gw dump` | | Print all settings and state, for bug reports. |
| `/gw debug <0-5>`, `/gw verbose on\|off` | 0, off | Debug output in chat. |
| `/gw log on\|off`, `/gw logsize <n>` | off, 2048 | Keep debug output in the SavedVariables file. |
| `/gw redact on\|off` | on | Hide the channel name and password in debug output. |

Officer chat is **not** bridged.

## Reporting problems

Open an issue on [GitHub](https://github.com/thebanhammer87/GoonWall/issues). Please include:
- the output of `/gw version` and `/gw status`;
- any BugSack error text;
- if you can, the lines printed after `/gw debug 5` and `/gw verbose on`, then `/reload`.

`redact` is on by default, so the channel password isn't printed.

## Credits and license

GoonWall is based on GreenWall, Copyright (c) 2010-2025 Mark Rogaski, released under the MIT License.
The fork keeps that license; see [LICENSE](LICENSE). GreenWall is dedicated to the memory of
Roger Keith White (1962-2017), known to Alea Iacta Est as Ralff.

The addon message API for other addons is documented in [API.md](API.md).
