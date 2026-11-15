# GoonWall officer quickstart

GoonWall reads its config from each guild's **Guild Information** text (Guild window `J`,
then the **Info** tab). It needs the "Edit Guild Info" permission. Members need no setup.

## 1. Pick a channel and a tag for each guild

- **Channel name and password:** one pair, shared by every guild. Use letters and digits only, no
  spaces or colons. Anyone in any of the guilds can read the Guild Information, so the password only
  keeps out people who aren't in a guild.
- **Tag:** a short label for each guild, shown in front of bridged lines. **Every guild needs a
  different tag.** If two guilds share a tag, they drop each other's messages, and GoonWall prints
  `tag "X" is used by both ...` at login.

## 2. Paste the same block into every guild

Use the same block, line for line, in Goon Squad and in every alt guild. List **every** guild,
including the one you're editing:

    GWc:goonbridge:CHANGEME
    GWp:Goon Squad:Goon
    GWp:Goon Squab:GoonSquab

Adding an alt guild means adding one `GWp` line, **in every guild's** Guild Information:

    GWp:<exact guild name>:<unique tag>

Guild names must match exactly, including spaces. Capitalisation doesn't matter. Don't add a realm
to the name: Forever realm names are shard labels and change.

Other text in Guild Information is fine. GoonWall only reads lines that start with `GW`.

## 3. Check it

On a character in each guild:

1. `/gw reload`, or log out and back in.
2. `/gw status` should show `configured=true` and `guild bridge: connected=true`. The connection
   waits about 30 seconds after login.
3. Say something in `/g`. It should appear in the other guild's `/g`, prefixed with your tag.

## Optional lines

    GWv:2.0.0

Tells members with an older GoonWall to update.

    GWs:Goon Squad:G
    GWp:$G:Goon

Defines a substitution, `$G`, for long names. See [CONFIGURATION_FORMAT.md](CONFIGURATION_FORMAT.md).

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `/gw status` shows `configured=false` | The guild's own `GWp` line is missing or misspelled. |
| `tag "X" is used by both ...` | Two `GWp` lines share a tag. Make the tags unique. |
| Lines only cross one way | The blocks aren't identical in every guild. |
| Every line shows twice | GreenWall, GuildLink or another bridge is still installed. |
