# Trainer Talk

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

Two full voices are included: **Kris** (cause she's the best) and **Jessie**, everyone's favorite member of Team Rocket. Pick whichever fits the adventure you want to have — the game remembers your choice.

## Where things stand right now

Everything above is live and fully voiced, including the personalized moment when you beat a Gym Leader or Elite Four member, they give you their own congratulations. Champion is complete too, on both ends of the fight.

Gen 2 (Gold & Silver) is still catching up on that specific piece — see Installation below for the details on what does and doesn't carry over yet.

## Voices
 
| Character | Status |
|---|---|
| Kris | Live |
| Jessie | Live |
| James | Live |
| Rocket Trio (James, Jessie & Meowth combined) | Live |
| Dawn | Live, under review |
| Leaf | Live, under review |
 
More on the way: Rocket Grunt (Male), Rocket Grunt (Female), Giovanni, Blue, Ash, Red, Misty, May, and more to come after that.
 
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
| **FAINT REACTIONS** | How often she reacts to a Pokémon fainting specifically, on its own dial — off, sometimes, often, or always |
| **GAME START**, **MOMENTS**, **GYM BADGES**, **ELITE FOUR**, **CHAMPION** | Turn any single category on or off, if you'd rather hear some moments and not others |

Not sure where to start? The defaults are tuned to feel natural without being chatty — try it as-is for a while before you go tweaking.

## Installation

1. Download the latest release `.zip` from the [Releases](../../releases) page.
2. In-game: **MODS → Import mod .zip** — or, if you'd rather do it by hand, extract the zip into your Gen1Recomp `mods/` folder:
   - Windows: `%APPDATA%\love\pokemon-love2d\mods\`
   - macOS: `~/Library/Application Support/LOVE/pokemon-love2d/mods/`
   - Linux: `~/.local/share/love/pokemon-love2d/mods/`
3. Restart the game.
4. Open the **MODS** panel, select **Trainer Talk**, and make sure it shows as `ENABLED`. All the settings above live on that same screen.

Works on Gen 1 (Red/Blue/Yellow) and Gen 2 (Gold) — on Gold, everything works except Gym Badges, Elite Four, and Champion specifically, which are Gen 1-only for now.

## Credits

- Built to pair with [Crystal](https://github.com/dburton95/crystal) by dburton95
- Obviously all of this is possible because of [gen1recomp](https://github.com/bryanthaboi/gen1recomp) by bryanthaboi

## Want to build your own voice pack?

Trainer Talk is designed so anyone can add a new voice — your own character, a favorite performer, whatever you'd like to hear in your playthrough. No coding required, just audio files in a folder. See `BUILD_YOUR_OWN_VOICE_PACK.txt` for a plain-English guide to what to record/source and where it goes.

If you're a fellow mod author looking to understand how this one's actually built, the full technical documentation (every event, every design decision, and why) will lives alongside this README in the repo. (Work in Progress)

## Contributing

Forks and collaboration are welcome — new voice packs, new reactions, bug reports, all of it. Feel free to open a PR or an issue.

## License

MIT — see [LICENSE](LICENSE).

## Disclaimer

This is an unofficial fan-made mod for Gen1Recomp. It is not affiliated with or endorsed by Nintendo, Game Freak, The Pokémon Company, or the Gen1Recomp maintainers. No Pokémon ROM is included.
