# Trainer Talk

> **Beta build (0.5.6-beta.1).** This build is a playtest of two things: voice lines that now wait for the battle text before they play (faints, catches, crits, misses, status effects and running away), and the first Ruby, Sapphire and Emerald support. DEV LOGGING is on by default so the playtest records what the battle text says. Logs stay on your device unless you turn on SEND LOGS. If a line plays too early, too late or not at all, please tell me which game, what happened and your SESSION ID.

A companion who actually talks to you.

Trainer Talk adds a voice to your Pokémon adventure — someone in your corner who reacts to what's actually happening as you play. She gets excited when you start a new save. She cheers when you land a good hit. She's there when you win, and she's there when you lose. Small moments, but they add up to a game that feels a little less like you're playing alone.

Built to pair naturally with [Crystal](https://github.com/dburton95/crystal), the player-sprite mod — if you're already using Crystal to look the part, Trainer Talk gives her a voice to match. It works just as well on its own, too, with no other mods required.

## What she'll react to

- **Starting a new game, or picking up where you left off** — a real hello every time
- **Landing hits, inflicting status effects, critical hits, misses, close calls** — the little ups and downs of a battle, not just the big moments
- **Catching a Pokémon for the first time, evolutions, day and night** — the quieter beats of the adventure get noticed too
- **Winning or losing a battle** — she's in it with you either way
- **Walking into a Gym or the Elite Four's chambers** — a real moment of "here we go" the second you step in, the leader's own challenge once you actually reach them, and their own congratulations if you win (their voice throughout, or a stadium announcer, your choice)
- **Becoming Champion** — the biggest moment in the game gets treated like one

A growing roster of voices is included — see the full list and status of each below. Pick whichever fits the adventure you want to have; the game remembers your choice.

## Where things stand right now

Everything above is live and fully voiced, including the personalized moment when you beat a Gym Leader or Elite Four member, they give you their own congratulations. Champion is complete too, on both ends of the fight.

This now carries all the way through Gen 2 (Gold, Silver, Crystal) — the Johto gym leaders, their own Elite Four, and Kanto's returning leaders in the post-game all have their own milestone lines, not just Gen 1. Gen 3 support is in progress: FireRed and LeafGreen are in, and Hoenn (Ruby, Sapphire and Emerald) is being added. See Installation below for exactly what that currently covers.

## Voices
 
| Character | Status |
|---|---|
| Kris | Live, Updated with Packager Recipe |
| Jessie | Live, Updated with Packager Recipe |
| James | Live, Updated with Packager Recipe |
| Rocket Trio (James, Jessie & Meowth combined) | Live, Updated with Packager Recipe |
| Leaf | Live, Updated with Packager Recipe |
| Ash | Live, Updated with Packager Recipe |
| Giovanni | Live, under review |
| Rocket Grunt (Male) | Live, under review |
| Rocket Grunt (Female) | Live, under review |
| Dawn | Live, Updated with Packager Recipe |
| Blue | Live, under review |
 
More on the way: Red, Misty, May, and more to come after that.
 
*"Under review" means the lines were assigned to events based on transcription and tone analysis rather than a full listening pass yet. Still playable, just expect the occasional rough edge until that review is finished.*

## Settings

Everything below lives in the in-game **Mods** menu — no files to edit, no digging required.

| Setting | What it does |
|---|---|
| **VOICE LINES** | Turn all voice lines on or off |
| **VOICE VOL** | How loud the voice lines play, on the same scale as your music and sound effect volume |
| **DUCK TIME** | How long the music quiets down under a voice line, so you never miss a word |
| **CHARACTER** | Choose your companion's voice — Kris, Jessie, or any others that get added down the line |
| **MILESTONE VOICE** | Choose who voices the big Gym/Elite Four/Champion moments — a Gym Leader's own voice, or a stadium announcer |
| **BATTLE BARKS** / **DAY-NIGHT** / **REACTIONS** | How often those specific reactions happen — off, rare, normal, or frequent, whatever feels right to you |
| **FAINT REACTIONS** | How often she reacts to a Pokémon fainting specifically, on its own dial — off, sometimes, often, or always. Timed to land just after the KO plays out, not on top of it. |
| **VOICE DELAY** | How long faint, failed-catch and win/loss lines wait so they don't give away the result before the game shows it — shorter, normal, longer, or longest. The battle animations run at their own pace, so raise it if a line still lands too early. |
| **GAME START**, **MOMENTS**, **GYM BADGES**, **ELITE FOUR**, **CHAMPION** | Turn any single category on or off, if you'd rather hear some moments and not others |
| **DEV LOGGING** | Off by default in full releases, and on in beta builds like this one. Turns on detailed diagnostic messages, useful if something sounds wrong and you want to help track down why. Most players will never need this. |
| **SEND LOGS** | Only shows up once DEV LOGGING is on. A separate, explicit opt-in — turning on DEV LOGGING alone keeps everything on your device; this additionally uploads diagnostic logs to help troubleshoot an issue you're reporting. Off by default even while debugging. |
| **SESSION ID** | Only shows up once DEV LOGGING is on. A short code (e.g. `K7XPQR`) unique to your current play session — share it when reporting an issue so your logs can be found without digging through timestamps. Just a display; the value itself doesn't do anything if changed. |

Not sure where to start? The defaults are tuned to feel natural without being chatty — try it as-is for a while before you go tweaking.

## Installation

1. Download the latest release `.zip` from the [Releases](../../releases) page.
2. In-game: **MODS → Import mod .zip** — or, if you'd rather do it by hand, extract the zip into your Gen1Recomp `mods/` folder:
   - Windows: `%APPDATA%\love\pokemon-love2d\mods\`
   - macOS: `~/Library/Application Support/LOVE/pokemon-love2d/mods/`
   - Linux: `~/.local/share/love/pokemon-love2d/mods/`
3. Restart the game.
4. Open the **MODS** panel, select **Trainer Talk**, and make sure it shows as `ENABLED`. All the settings above live on that same screen.

Works on Gen 1 (Red/Blue/Yellow), Gen 2 (Gold/Silver/Crystal), and — new, still being tested — Gen 3 (FireRed/LeafGreen). Everything carries through on all three. FireRed/LeafGreen support is newer than the rest of this mod, so treat it as the least battle-tested of the three for now. Hoenn (Ruby, Sapphire and Emerald) is wired in but has not been played through yet, and its gym leaders, Elite Four and Champions have no milestone audio so far. Everyday lines work from any voice pack, and a milestone with no audio file stays silent.

## Credits

- Built to pair with [Crystal](https://github.com/dburton95/crystal) by dburton95
- Obviously all of this is possible because of [gen1recomp](https://github.com/bryanthaboi/gen1recomp) by bryanthaboi

## Want to build your own voice pack?

Trainer Talk is designed so anyone can add a new voice — your own character, a favorite performer, whatever you'd like to hear in your playthrough. No coding required, just audio files in a folder. See `BUILD_YOUR_OWN_VOICE_PACK.txt` for a plain-English guide to what to record/source and where it goes, or use the [Trainer Talk Packager](https://github.com/ElvieBlooms/trainer_talk_packager) to do it the easy way — feed it a zip of audio clips and it transcribes, matches, and exports a ready-to-drop-in pack for you.

**Starting with the Hoenn release, this mod will ship without bundled voice packs** — building your own (by hand or with the packager) will be the way to get one. `BUILD_YOUR_OWN_VOICE_PACK.txt` has a pointer to where people commonly source raw game audio for this kind of thing.

If you're a fellow mod author looking to understand how this one's actually built, the full technical documentation (every event, every design decision, and why) lives alongside this README in the repo. *(Work in progress — being kept current, not a finished reference yet.)*

## Contributing

Forks and collaboration are welcome — new voice packs, new reactions, bug reports, all of it. Feel free to open a PR or an issue.

## License

MIT — see [LICENSE](LICENSE).

## Disclaimer

This is an unofficial fan-made mod for Gen1Recomp. It is not affiliated with or endorsed by Nintendo, Game Freak, The Pokémon Company, or the Gen1Recomp maintainers. No Pokémon ROM is included.
