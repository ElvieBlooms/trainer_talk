local voice = {}

--- Wires up every voice-line trigger, options row, and dev-logging
-- hook for the mod. Called once by the engine per boot (see
-- main.lua), never invoked directly by anything in this file.
-- Purpose: single entry point the loader calls into; everything else
--   in this file is a local defined inside its closure so it can
--   close over `mod` without passing it to every helper explicitly.
-- Inputs:
--   mod (table) -- the sandboxed mod handle the engine hands every
--     mod's entry chunk (assets, options, events, hooks, log,
--     fetch/postLog under the declared permissions, etc).
-- Outputs: none.
function voice.init(mod)
    math.randomseed(os.time())

    -- ---- Session ID ----
    -- One per boot, not persisted -- generated fresh here every time
    -- voice.init runs, so it rotates on its own each session as long
    -- as nothing overrides it (see the SESSION ID options row below).
    local SESSION_ID_CHARS = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"

    --- Builds a short, human-shareable session identifier.
    -- Purpose: lets a tester read one string off-screen (options
    --   menu) and match it against the same string tagging every
    --   uploaded log line, so one session's logs can be picked out
    --   of a shared Drive file without cross-referencing timestamps.
    -- Inputs: none.
    -- Outputs:
    --   string -- 6 characters from an unambiguous charset (no
    --     0/O, 1/I/L, so it reads cleanly when relayed verbally or
    --     typed into a bug report).
    local function generateSessionId()
      local chars = {}
      for i = 1, 6 do
        local idx = math.random(1, #SESSION_ID_CHARS)
        chars[i] = SESSION_ID_CHARS:sub(idx, idx)
      end
      return table.concat(chars)
    end
    local SESSION_ID = generateSessionId()

    -- ================================================================
    -- FRAMEWORK -- settings, shared state, and the helpers everything
    -- below actually calls into. Nothing in here fires on its own.
    -- ================================================================

    -- ---- Voice pack discovery ----
    -- Scans assets/characters/ and assets/milestones/ for subfolders
    -- and builds CHARACTER/MILESTONE VOICE's choices from whatever's
    -- actually there -- same trick Crystal's kris.lua uses for its
    -- sprite picker. Drop a folder in with an optional meta.json
    -- ({ "label": "..." }) and it just shows up, no code changes.
    local Json = require("src.link.Json")

    --- Reads a voice pack's optional meta.json for its display label.
    -- Purpose: lets a dropped-in pack folder carry a human-readable
    --   name (e.g. "KRIS") instead of showing its raw folder key in
    --   the CHARACTER/MILESTONE VOICE options rows.
    -- Inputs:
    --   dir (string) -- "assets/characters" or "assets/milestones".
    --   key (string) -- the pack's folder name under dir.
    -- Outputs:
    --   table -- decoded meta.json contents, or {} if the file is
    --     missing or fails to parse (a pack with no meta is not an
    --     error, just unlabeled).
    local function readPackMeta(dir, key)
      local metaPath = dir .. "/" .. key .. "/meta.json"
      local ok1, info = pcall(function() return mod.assets:info(metaPath) end)
      if ok1 and info then
        local ok2, decoded = pcall(function() return Json.decode(mod:read(metaPath)) end)
        if ok2 and type(decoded) == "table" then return decoded end
      end
      return {}
    end

    --- Scans a voice-pack directory and builds an options-row choice
    -- list from whatever subfolders actually exist -- same trick
    -- Crystal's kris.lua uses for its sprite picker. Drop a folder in
    -- with an optional meta.json and it shows up with no code changes.
    -- Purpose: keeps CHARACTER/MILESTONE VOICE in sync with installed
    --   asset packs instead of a hardcoded choice list that drifts.
    -- Inputs:
    --   dir (string) -- directory to scan, e.g. "assets/characters".
    --   preferredDefault (string) -- pack key to default to if present.
    --   fallbackLabel (string) -- label to show if the scan finds
    --     nothing at all (a settings row should never end up with
    --     zero options).
    -- Outputs:
    --   choicePairs (table) -- array of { label, key } pairs, sorted
    --     alphabetically by label, ready to hand to a "choice" options
    --     row's `choices` field.
    --   defaultKey (string) -- preferredDefault if it was found among
    --     the scanned packs, otherwise whichever pack sorted first.
    local function discoverPacks(dir, preferredDefault, fallbackLabel)
      local found = {}
      local ok, list = pcall(function() return mod.assets:list(dir) end)
      if ok and list then
        for _, key in ipairs(list) do
          local ok2, info = pcall(function() return mod.assets:info(dir .. "/" .. key) end)
          if ok2 and info and info.type == "directory" then
            local meta = readPackMeta(dir, key)
            local label = meta.label or key:upper()
            table.insert(found, { label = label, key = key })
          end
        end
      end
      if #found == 0 then
        table.insert(found, { label = fallbackLabel, key = preferredDefault })
      end
      table.sort(found, function(a, b) return a.label < b.label end)
      local choicePairs = {}
      local defaultKey, sawPreferred = found[1].key, false
      for _, entry in ipairs(found) do
        table.insert(choicePairs, { entry.label, entry.key })
        if entry.key == preferredDefault then sawPreferred = true end
      end
      if sawPreferred then defaultKey = preferredDefault end
      return choicePairs, defaultKey
    end

    local characterChoices, characterDefault =
      discoverPacks("assets/characters", "kris", "KRIS")
    local milestoneChoices, milestoneDefault =
      discoverPacks("assets/milestones", "leaders", "GYM LEADER VOICES")

    mod.options:define({
      -- global controls
      { key = "voice_lines", type = "toggle", label = "VOICE LINES", default = true },
      { key = "voice_vol", type = "number", label = "VOICE VOL",
        min = 0, max = 7, step = 1, default = 7 },
      -- 0 also means "no ducking" -- see duckSeconds() below
      { key = "duck_seconds", type = "number", label = "DUCK TIME",
        min = 0, max = 5, step = 0.5, default = 2.5 },
      { key = "character", type = "choice", label = "CHARACTER",
        choices = characterChoices,
        default = characterDefault },
      -- Independent of CHARACTER -- who voices gym/E4/Champion wins,
      -- not who's escorting the player everywhere else.
      { key = "milestone_voice", type = "choice", label = "MILESTONE VOICE",
        choices = milestoneChoices,
        default = milestoneDefault },

      -- per-category on/off. VOICE LINES/VOICE VOL above still gate
      -- everything regardless of these.
      { key = "cat_game_start", type = "toggle", label = "GAME START", default = true },
      -- OFF here is just a 0x multiplier, so this one row covers both
      -- on/off and frequency. A multiplier (not a raw percent) so
      -- BATTLE STATUS stays rarer than BATTLE HITS at every tier.
      { key = "freq_battle_barks", type = "choice", label = "BATTLE BARKS",
        choices = {
          { "OFF", 0 },
          { "RARE", 0.5 },
          { "NORMAL", 1 },
          { "FREQUENT", 2 },
        },
        default = 1 },
      { key = "freq_day_night", type = "choice", label = "DAY/NIGHT",
        choices = {
          { "OFF", 0 },
          { "RARE", 0.5 },
          { "NORMAL", 1 },
          { "FREQUENT", 2 },
        },
        default = 1 },
      -- same multiplier shape as BATTLE BARKS/DAY-NIGHT above -- each
      -- reaction (hit_crit, move_miss, catch_fail, run_success/fail)
      -- keeps its own base percentage, scaled by this.
      { key = "freq_reactions", type = "choice", label = "REACTIONS",
        choices = {
          { "OFF", 0 },
          { "RARE", 0.5 },
          { "NORMAL", 1 },
          { "FREQUENT", 2 },
        },
        default = 1 },
      -- a different shape on purpose -- faints are a bigger moment
      -- than a miss or a failed catch, so this starts at guaranteed
      -- and steps down, rather than starting at a baseline and
      -- multiplying up/down the way the dial above does. Stores the
      -- actual percent directly, not a multiplier.
      { key = "freq_faint", type = "choice", label = "FAINT REACTIONS",
        choices = {
          { "OFF", 0 },
          { "SOMETIMES", 30 },
          { "OFTEN", 60 },
          { "ALWAYS", 100 },
        },
        default = 100 },
      { key = "cat_moments", type = "toggle", label = "MOMENTS", default = true },
      { key = "cat_gym_badges", type = "toggle", label = "GYM BADGES", default = true },
      { key = "cat_elite_four", type = "toggle", label = "ELITE FOUR", default = true },
      { key = "cat_champion", type = "toggle", label = "CHAMPION", default = true },
      -- Off by default, safe to leave shipped -- uses the real mod.log
      -- API (auto-prefixed with the mod id, routed through the
      -- engine's own Logger), not print() or anything that writes
      -- outside the sandbox. An env-var-based flag (POKEPORT_DEV=1)
      -- was the original idea, but os.getenv is deliberately absent
      -- from the mod sandbox (confirmed in src/mods/Sandbox.lua's own
      -- comment: a past exploit used it to find the user's home
      -- directory), so a toggle here is the actual supported
      -- equivalent for a mod, not a workaround.
      { key = "dev_logging", type = "toggle", label = "DEV LOGGING", default = false },
      -- Only shown once DEV LOGGING is on (visible_if -- a real engine
      -- mechanism, src/mods/ManagerState.lua, not a fake indent). Kept
      -- as its own opt-in rather than folded into dev_logging above:
      -- watching the log on-screen via the mod manager is local and
      -- free, but this one leaves the device over the network, so it
      -- gets its own explicit consent and stays off by default even
      -- while you're debugging.
      { key = "dev_log_upload", type = "toggle", label = "SEND LOGS",
        default = false,
        visible_if = { key = "dev_logging", equals = true } },
      -- "choice" with exactly one entry, not "text" -- stepping left
      -- or right just clamps back to the same single choice (see
      -- ManagerState.lua's step handler: clampIndex against #choices,
      -- which is 1), so there's no adjacent value to land on and no
      -- confirm screen to trigger. Genuinely can't be edited into
      -- something else, unlike the text-row approach this replaces.
      -- The stored value (0) is meaningless -- only the label is read.
      { key = "session_id_display", type = "choice", label = "SESSION ID",
        choices = { { SESSION_ID, 0 } },
        default = 0,
        visible_if = { key = "dev_logging", equals = true } },
    })

    -- ---- Dev log capture + upload ----
    -- input.step runs every frame (see the hook below), so this bounds
    -- how often we actually hit the network to once every 30s.
    local LOG_FLUSH_INTERVAL = 30
    local logBuffer = {}
    local lastLogFlushAt = -math.huge

    --- Logs a formatted dev-diagnostic line, and buffers it for
    -- upload if the player has separately opted into that.
    -- Every prior "if dev_logging then mod.log:info(...) end" call
    -- site in this file goes through here instead, so the lines shown
    -- on-screen (mod manager log view) and the lines uploaded are
    -- always identical -- one source of truth, not two paths that
    -- can drift apart.
    -- Purpose: centralizes dev logging so DEV LOGGING alone stays
    --   local/free (on-screen only) while SEND LOGS is a separate,
    --   explicit opt-in for anything that leaves the device.
    -- Inputs:
    --   fmt (string) -- a string.format pattern.
    --   ... -- values to fill fmt's placeholders.
    -- Outputs: none.
    local function devLog(fmt, ...)
      if not mod.options:get("dev_logging") then return end
      local line = string.format("[%s] " .. fmt, SESSION_ID, ...)
      mod.log:info(line)
      if mod.options:get("dev_log_upload") then
        table.insert(logBuffer, os.date("%H:%M:%S") .. "  " .. line)
      end
    end

    --- Sends whatever's currently buffered to the engine's own
    -- mod:postLog (not a custom transport -- see manifest.json's
    -- log_url). Fire-and-forget: the response body is never handed
    -- back, so a failed upload is only ever detected here if
    -- mod:postLog itself rejects the call up front (missing
    -- permission/log_url, empty body, body over the engine's 512 KiB
    -- ceiling, or too many uploads already in flight).
    -- Purpose: batches devLog output into periodic uploads instead of
    --   one network call per line (see LOG_FLUSH_INTERVAL below).
    -- Inputs: none (reads the closed-over logBuffer).
    -- Outputs: none.
    local function flushLogBuffer()
      if #logBuffer == 0 then return end
      if not mod.options:get("dev_log_upload") then
        -- Toggled off since these lines were captured -- drop them
        -- rather than sending on a consent that's no longer current.
        logBuffer = {}
        return
      end
      local chunk = table.concat(logBuffer, "\n") .. "\n"
      logBuffer = {}
      local ok, handleOrErr = pcall(function() return mod:postLog(chunk) end)
      if not ok or not handleOrErr then
        mod.log:warn("postLog: upload failed (%s) -- check log_url is set "
          .. "in manifest.json and the Apps Script is deployed",
          tostring(handleOrErr))
      end
    end

    -- ---- Playback core ----
    local duckUntil = 0

    --- Purpose: current voice volume, options-driven with a safe
    -- default if unset.
    -- Inputs: none. Outputs: number, 0-7.
    local function voiceVolume()
      return mod.options:get("voice_vol") or 7
    end

    --- Purpose: current music-ducking duration, options-driven.
    -- Inputs: none. Outputs: number, seconds (0 disables ducking).
    local function duckSeconds()
      return mod.options:get("duck_seconds") or 2.5
    end

    --- Purpose: whether voice lines should play at all right now.
    -- Both the toggle AND volume > 0 have to hold, so muting never
    -- clobbers the player's saved volume number.
    -- Inputs: none. Outputs: boolean.
    local function voiceLinesOn()
      return mod.options:get("voice_lines") and voiceVolume() > 0
    end

    --- Purpose: resolves the CHARACTER option to an asset subpath.
    -- Inputs: none.
    -- Outputs: string -- "characters/<key>", so every call site that
    --   builds "assets/" .. folder .. "/file.ogg" resolves correctly
    --   without change if the option value changes.
    local function characterFolder()
      return "characters/" .. (mod.options:get("character") or characterDefault)
    end

    --- Purpose: resolves the MILESTONE VOICE option to an asset
    -- subpath. Same shape as characterFolder, independent option.
    -- Inputs: none. Outputs: string -- "milestones/<key>".
    local function milestoneFolder()
      return "milestones/" .. (mod.options:get("milestone_voice") or milestoneDefault)
    end

    --- Plays a single voice line if voice lines are currently on.
    -- Purpose: the one place actual playback happens, so ducking,
    --   volume, and dev logging are applied consistently everywhere
    --   else in this file calls into it rather than touching
    --   love.audio directly.
    -- Inputs:
    --   path (string) -- resolved asset path to an .ogg file.
    -- Outputs: none. A missing/failed file stays silent (pcall)
    --   rather than crashing the mod.
    local function playSound(path)
      if not voiceLinesOn() then
        devLog("playSound: SKIPPED (voice lines off) path=%s", path)
        return
      end
      local ok, src = pcall(love.audio.newSource, path, "static")
      devLog("playSound: %s path=%s",
        (ok and src) and "PLAYING" or "MISSING/FAILED", path)
      if ok and src then
        src:setVolume(voiceVolume() / 7)
        duckUntil = love.timer.getTime() + duckSeconds()
        src:play()
      end
    end

    --- Purpose: picks one line at random from a pool and plays it --
    -- the common case everywhere a category has multiple takes.
    -- Inputs: paths (table) -- array of asset path strings.
    -- Outputs: none (delegates to playSound).
    local function playRandom(paths)
      playSound(paths[math.random(#paths)])
    end

    -- ---- Music ducking ----
    mod.hooks:wrap("music.volume", function(next, vol, ctx)
      vol = next(vol, ctx)
      if love.timer.getTime() < duckUntil then
        return vol * 0.3
      end
      return vol
    end)

    -- ---- Frequency & chance ----
    --- Purpose: a single dice roll every probability check in this
    -- file shares, so the odds language ("chance(50 * ...)") stays
    -- consistent throughout.
    -- Inputs: percent (number) -- 0-100.
    -- Outputs: boolean -- true with the given probability.
    local function chance(percent)
      return math.random(100) <= percent
    end

    --- Purpose: reads a freq_* choice option as a multiplier, with a
    -- safe 1x fallback if unset.
    -- Inputs: key (string) -- an options key, e.g. "freq_reactions".
    -- Outputs: number -- 0 (off), 0.5, 1, or 2 per the choice rows
    --   defined above.
    local function frequencyMultiplier(key)
      return mod.options:get(key) or 1
    end

    -- ---- Universal voice line gap & delay queue ----
    -- Shared across EVERY category -- barks, reactions, faints, and
    -- moments all check and update this same timestamp, so nothing
    -- can ever land on top of anything else regardless of which
    -- queue it came from. Originally bark-only (moments deliberately
    -- bypassed it), changed to universal and bidirectional after
    -- real playtesting turned up a moment firing right on top of an
    -- unrelated bark's overlapping audio.
    local VOICE_LINE_GAP = 5
    local lastVoiceLineAt = -math.huge

    --- Plays one line from a pool immediately, unless the universal
    -- gap hasn't cleared since the last voice line from ANY category.
    -- Purpose: the synchronous half of the bark system -- for
    --   reactions that don't need the queued delay scheduleBark
    --   provides (crit/miss/catch/run already fire after their own
    --   animation, so no extra beat is needed).
    -- Inputs: pool (table) -- array of candidate asset paths.
    -- Outputs: none. Drops the line (does not queue it) if the gap
    --   hasn't cleared -- see scheduleBark for the queued version.
    local function attemptBark(pool)
      local now = love.timer.getTime()
      if now - lastVoiceLineAt < VOICE_LINE_GAP then
        devLog("attemptBark: DROPPED (cooldown, %.1fs remaining)",
          VOICE_LINE_GAP - (now - lastVoiceLineAt))
        return
      end
      lastVoiceLineAt = now
      playRandom(pool)
    end

    -- damage_dealt fires before the hit animation plays, so we queue
    -- the bark and let it go off a beat later instead of talking over
    -- the animation.
    local pendingBarks = {}

    --- Queues a bark to fire after a fixed delay (checked in the
    -- input.step hook below) rather than immediately.
    -- Purpose: lets a bark wait out its own animation/text (e.g. a
    --   hit landing) before speaking, instead of talking over it the
    --   way an immediate attemptBark would.
    -- Inputs:
    --   pool (table) -- array of candidate asset paths.
    --   delay (number) -- seconds to wait before attempting to play.
    -- Outputs: none.
    local function scheduleBark(pool, delay)
      devLog("scheduleBark: QUEUED, fires in %.1fs", delay)
      table.insert(pendingBarks, { at = love.timer.getTime() + delay, pool = pool })
    end

    -- Own delay on top of the universal gap above, not instead of it
    -- -- a moment still waits for its own timing (OUTCOME_DELAY,
    -- blackout's extra beat), but once that elapses it ALSO has to
    -- clear the same universal gap every other category respects
    -- before it's allowed to actually play. If the gap hasn't cleared
    -- yet, it keeps waiting rather than firing on top of whatever
    -- just played.
    local pendingMoments = {}

    --- Queues a single, specific voice line (not a random pool) to
    -- fire after a fixed delay.
    -- Purpose: for one-off "moments" (evolutions, milestone outros,
    --   blackouts) that need their own pacing distinct from the
    --   bark system's shared timing.
    -- Inputs:
    --   path (string) -- resolved asset path to play.
    --   delay (number) -- seconds to wait before attempting to play.
    -- Outputs: none.
    local function scheduleMoment(path, delay)
      devLog("scheduleMoment: QUEUED path=%s, own delay %.1fs", path, delay)
      table.insert(pendingMoments, { at = love.timer.getTime() + delay, path = path })
    end

    mod.hooks:wrap("input.step", function(next, ...)
      local now = love.timer.getTime()
      if now - lastLogFlushAt >= LOG_FLUSH_INTERVAL then
        lastLogFlushAt = now
        flushLogBuffer()
      end
      for i = #pendingBarks, 1, -1 do
        if now >= pendingBarks[i].at then
          local entry = table.remove(pendingBarks, i)
          attemptBark(entry.pool)
        end
      end
      for i = #pendingMoments, 1, -1 do
        if now >= pendingMoments[i].at then
          if now - lastVoiceLineAt >= VOICE_LINE_GAP then
            local entry = table.remove(pendingMoments, i)
            lastVoiceLineAt = now
            playSound(entry.path)
          elseif not pendingMoments[i].deferredLogged then
            -- only announced once per entry, not every frame it keeps
            -- waiting -- input.step runs every frame, and the gap can
            -- take several seconds to clear, so logging unconditionally
            -- here would flood the log for the entire wait
            pendingMoments[i].deferredLogged = true
            devLog("moment DEFERRED (own delay elapsed, universal gap not clear yet) path=%s",
              pendingMoments[i].path)
          end
          -- else: own delay has elapsed but the universal gap hasn't
          -- -- leave it queued and check again next frame instead of
          -- firing on top of whatever just played.
        end
      end
      return next(...)
    end)

    -- ================================================================
    -- EVENTS -- wires the framework above into actual game moments.
    -- ================================================================

    -- ---- Game start (New Game / Continue) ----
    mod.events:once("intro.oak_speech.finished", function()
      if not mod.options:get("cat_game_start") then return end
      local folder = characterFolder()
      playSound(mod.assets:path("assets/" .. folder .. "/new_game.ogg"))
    end)

    mod.events:once("save.loaded", function()
      if not mod.options:get("cat_game_start") then return end
      local folder = characterFolder()
      playRandom({
        mod.assets:path("assets/" .. folder .. "/continue1.ogg"),
        mod.assets:path("assets/" .. folder .. "/continue2.ogg"),
        mod.assets:path("assets/" .. folder .. "/continue3.ogg"),
        mod.assets:path("assets/" .. folder .. "/continue4.ogg"),
        mod.assets:path("assets/" .. folder .. "/continue5.ogg"),
      })
    end)

    --- Determines whether a battler/mon belongs to the player.
    -- Purpose: Gen 1's user/target/battler objects carry an explicit
    --   isPlayer flag, but Gen 2's engine works on the raw party-mon
    --   table directly, which has none -- every .isPlayer check in
    --   this file would silently read nil (falsy) for BOTH sides on
    --   Gen 2 without this fallback. Confirmed against real source
    --   (src/battle/gen2/Battle.lua's own header comment); Gen 2's
    --   equivalent is Battle:sideRecord, an identity check against
    --   the battle's own .player table.
    -- Inputs:
    --   mon (table|nil) -- a battler/target/user object from an
    --     event or hook payload.
    --   battle (table) -- the event/hook's battle field, required for
    --     the Gen 2 fallback. Every call site here is confirmed to
    --     carry one.
    -- Outputs: boolean.
    local function isPlayerSide(mon, battle)
      if mon == nil then return false end
      if mon.isPlayer ~= nil then return mon.isPlayer end
      if battle and battle.player ~= nil then return mon == battle.player end
      return false
    end

    -- ---- General diagnostics (not Trainer Talk's own triggers) ----
    -- Broader engine/game-state events, subscribed here purely so a
    -- bug report's surrounding context (what screen, what kind of
    -- battle, was this a link session) shows up next to Trainer
    -- Talk's own lines without the tester having to describe what
    -- they were doing by hand.
    --
    -- Deliberately NOT logged, even though the engine hands it to
    -- every listener: save contents (save.created/loading/loaded's
    -- `save` payload -- trainer name, party, badges) and a link
    -- partner's own display name (link.connected's `remote.name`,
    -- confirmed against src/link/LinkState.lua). Both are player-
    -- authored, personally identifying, and add nothing a tester
    -- would need over just knowing the event fired -- logging them
    -- would cut against the "as anonymous as possible" goal these
    -- logs exist under. Only structural fields (screen ids, battle
    -- kind, link role/fatal-ness) get logged below.
    mod.events:on("game.ready", function()
      devLog("game.ready: trainer_talk v%s", tostring(mod.version))
    end)

    mod.events:on("save.created", function() devLog("save.created") end)
    mod.events:on("save.loading", function() devLog("save.loading") end)
    mod.events:on("save.loaded", function() devLog("save.loaded") end)

    -- Same screenId-only pattern already used for Hall of Fame
    -- detection further down -- never the raw `state` object.
    mod.events:on("screen.pushed", function(ev)
      devLog("screen.pushed: screenId=%s", tostring(ev.state and ev.state.screenId))
    end)
    mod.events:on("screen.popped", function(ev)
      devLog("screen.popped: screenId=%s", tostring(ev.state and ev.state.screenId))
    end)

    mod.events:on("battle.started", function(ev)
      devLog("battle.started: kind=%s trainerId=%s species=%s",
        tostring(ev.kind), tostring(ev.trainerId), tostring(ev.species))
    end)

    mod.events:on("checkpoint.restored", function(ev)
      devLog("checkpoint.restored: kind=%s", tostring(ev.kind))
    end)

    -- role/mode/fingerprint are connection metadata, not identity --
    -- remote.name (the peer's own display name) is intentionally
    -- excluded, see the block comment above.
    mod.events:on("link.connected", function(ev)
      devLog("link.connected: role=%s mode=%s", tostring(ev.role),
        tostring(ev.remote and ev.remote.mode))
    end)
    mod.events:on("link.desync", function(ev)
      devLog("link.desync: turn=%s component=%s fatal=%s",
        tostring(ev.turn), tostring(ev.component), tostring(ev.fatal))
    end)
    mod.events:on("link.ended", function(ev)
      devLog("link.ended: reason=%s", tostring(ev.reason))
    end)

    -- ---- Battle barks (hit / status) ----
    mod.events:on("battle.damage_dealt", function(ev)
      -- user.isPlayer confirmed against the real event reference --
      -- this fires for either side landing a hit, so without this
      -- check an enemy's hit would trigger the same pleased bark a
      -- player hit does. Deliberately player-only for now, not split
      -- into a matching enemy/player pair the way status is.
      if not isPlayerSide(ev.user, ev.battle) then return end
      if not chance(15 * frequencyMultiplier("freq_battle_barks")) then return end
      local folder = characterFolder()
      scheduleBark({
        mod.assets:path("assets/" .. folder .. "/hit1.ogg"),
        mod.assets:path("assets/" .. folder .. "/hit2.ogg"),
        mod.assets:path("assets/" .. folder .. "/hit3.ogg"),
      }, 1.5)
    end)

    mod.events:on("battle.status_inflicted", function(ev)
      if not chance(10 * frequencyMultiplier("freq_battle_barks")) then return end
      local folder = characterFolder()
      -- target.isPlayer confirmed against real source on Gen 1
      -- (StatusRegistry.lua's own displayName(b) uses b.isPlayer on
      -- this exact target object) -- this fires for a status landing
      -- on EITHER side, not just the opponent, so it needs the same
      -- direction check battle.fainted already uses. Gen 2's raw
      -- party-mon target has no such field, hence isPlayerSide's
      -- fallback rather than a direct .isPlayer read here.
      if isPlayerSide(ev.target, ev.battle) then
        attemptBark({
          mod.assets:path("assets/" .. folder .. "/status_player.ogg"),
          mod.assets:path("assets/" .. folder .. "/status_player2.ogg"),
        })
      else
        attemptBark({
          mod.assets:path("assets/" .. folder .. "/status_enemy.ogg"),
          mod.assets:path("assets/" .. folder .. "/status_enemy2.ogg"),
        })
      end
    end)

    -- ---- Day/Night ambient lines ----
    -- Gen 1 has no real day/night clock, so this mostly only fires on
    -- Gold saves.
    mod.events:on("world.tod_changed", function(ev)
      if not chance(5 * frequencyMultiplier("freq_day_night")) then return end
      local period = tostring(ev.daytime or ev.tod or ""):upper()
      local folder = characterFolder()
      if period == "NITE" or period == "DARK" or period:find("NIGHT") then
        playRandom({
          mod.assets:path("assets/" .. folder .. "/night1.ogg"),
          mod.assets:path("assets/" .. folder .. "/night2.ogg"),
          mod.assets:path("assets/" .. folder .. "/night3.ogg"),
        })
      elseif period == "MORN" or period:find("MORNING") then
        playRandom({
          mod.assets:path("assets/" .. folder .. "/morning1.ogg"),
          mod.assets:path("assets/" .. folder .. "/morning2.ogg"),
        })
      end
    end)

    -- ---- Reactions ----
    -- Small, wordless battle nuance: crits, misses, catches, escapes,
    -- faints.

    mod.events:on("battle.damage_dealt", function(ev)
      if not ev.crit then return end
      -- same isPlayerSide check as the hit1/2/3 pool above -- a crit
      -- landed BY the enemy shouldn't play the same pleased bark.
      if not isPlayerSide(ev.user, ev.battle) then return end
      if not chance(50 * frequencyMultiplier("freq_reactions")) then return end
      local folder = characterFolder()
      -- same delay as hit1/2/3 above and for the same reason -- lands
      -- after the hit animation/text instead of before it.
      scheduleBark({
        mod.assets:path("assets/" .. folder .. "/hit_crit.ogg"),
        mod.assets:path("assets/" .. folder .. "/hit_crit2.ogg"),
      }, 1.5)
    end)

    -- battle.accuracy is a hook, not an event -- nothing fires on a
    -- miss otherwise.
    mod.hooks:wrap("battle.accuracy", function(next, ctx)
      local hit = next(ctx)
      -- isPlayerSide confirmed against the real hook reference --
      -- this wraps EITHER side's accuracy roll, so without this check
      -- an enemy's miss would trigger the same disappointed bark a
      -- player's miss does.
      local isPlayerMove = isPlayerSide(ctx.user, ctx.battle)
      if not hit and isPlayerMove and chance(20 * frequencyMultiplier("freq_reactions")) then
        local folder = characterFolder()
        -- same delay as hit1/2/3 above -- lands after the miss
        -- animation/text instead of before it.
        scheduleBark({
          mod.assets:path("assets/" .. folder .. "/move_miss.ogg"),
          mod.assets:path("assets/" .. folder .. "/move_miss2.ogg"),
        }, 1.5)
      end
      return hit
    end)

    -- same deal for a failed catch -- pokemon.caught only fires on
    -- success.
    mod.hooks:wrap("catch.rate", function(next, ball, mon, def, opts)
      local caught, shakes = next(ball, mon, def, opts)
      if not caught and chance(25 * frequencyMultiplier("freq_reactions")) then
        local folder = characterFolder()
        attemptBark({
          mod.assets:path("assets/" .. folder .. "/catch_fail.ogg"),
          mod.assets:path("assets/" .. folder .. "/catch_fail2.ogg"),
        })
      end
      return caught, shakes
    end)

    mod.hooks:wrap("battle.run", function(next, ctx)
      local escaped = next(ctx)
      if chance(25 * frequencyMultiplier("freq_reactions")) then
        local folder = characterFolder()
        if escaped then
          attemptBark({
            mod.assets:path("assets/" .. folder .. "/run_success.ogg"),
            mod.assets:path("assets/" .. folder .. "/run_success2.ogg"),
          })
        else
          attemptBark({
            mod.assets:path("assets/" .. folder .. "/run_fail.ogg"),
            mod.assets:path("assets/" .. folder .. "/run_fail2.ogg"),
          })
        end
      end
      return escaped
    end)

    -- own dial (freq_faint), not freq_reactions -- a faint is a
    -- bigger deal than a miss or a failed catch, defaults to firing
    -- every time rather than sharing the others' baseline.
    -- scheduleBark (not attemptBark) -- 1.5s delay so the line lands
    -- after the faint animation/sound plays out, same reasoning as
    -- the damage_dealt hit bark above rather than talking over it.
    mod.events:on("battle.fainted", function(ev)
      if not chance(mod.options:get("freq_faint") or 100) then return end
      local folder = characterFolder()
      if isPlayerSide(ev.battler, ev.battle) then
        scheduleBark({
          mod.assets:path("assets/" .. folder .. "/faint_player.ogg"),
          mod.assets:path("assets/" .. folder .. "/faint_player2.ogg"),
        }, 1.5)
      else
        scheduleBark({
          mod.assets:path("assets/" .. folder .. "/faint_enemy.ogg"),
          mod.assets:path("assets/" .. folder .. "/faint_enemy2.ogg"),
        }, 1.5)
      end
    end)

    -- ---- Moments ----
    -- Bigger, rarer beats -- evolving, a first catch, blacking out.
    -- No chance-gating needed, these are already rare on their own.
    -- (Ordinary trainer win/loss shares this toggle too, but the
    -- handler for it lives down with Gym Badges/Elite Four, since
    -- it's the same battle.ended listener.)

    mod.events:on("pokemon.evolved", function(ev)
      if not mod.options:get("cat_moments") then return end
      local folder = characterFolder()
      playSound(mod.assets:path("assets/" .. folder .. "/evolved.ogg"))
    end)

    mod.events:on("pokemon.caught", function(ev)
      if not mod.options:get("cat_moments") then return end
      if not ev.isNew then return end
      local folder = characterFolder()
      playRandom({
        mod.assets:path("assets/" .. folder .. "/new_catch.ogg"),
        mod.assets:path("assets/" .. folder .. "/new_catch2.ogg"),
      })
    end)

    -- Delayed so it lands after the loss reaction and the warp back
    -- to a Pokemon Center, rather than stacked on top of either.
    mod.events:on("world.blacked_out", function(ev)
      if not mod.options:get("cat_moments") then return end
      local folder = characterFolder()
      local blackoutPaths = {
        mod.assets:path("assets/" .. folder .. "/blackout.ogg"),
        mod.assets:path("assets/" .. folder .. "/blackout2.ogg"),
      }
      scheduleMoment(blackoutPaths[math.random(#blackoutPaths)], 3)
    end)

    -- ---- Gym Badges & Elite Four ----
    -- Two voice sources: CHARACTER reacts to walking into the room;
    -- MILESTONE VOICE handles both the per-trainer challenge line
    -- (on engaging that specific leader) and the win, since both are
    -- really about the leader, not about who's escorting the player.

    -- Trainer class -> base name, shared by both _intro (on engage,
    -- below) and _outro (on win, in battle.ended further down).
    --
    -- Gen 2 support added here directly into the same tables, not as
    -- a parallel set -- confirmed safe against real decoded Gold/
    -- Silver/Crystal data (data/generated/trainers.lua from an actual
    -- install, all three games checked, identical indices in each).
    -- Gen 1's trainerClass is always a STRING ("OPP_BROCK"); Gen 2's
    -- is always a NUMBER (17 for the same Brock, post-game). Lua
    -- never coerces between the two for table lookups, so a string
    -- key and a number key can never collide here even sitting in
    -- the same table -- no generation check needed at all, the type
    -- difference does it for free.
    --
    -- Several Gen 2 entries deliberately point at Gen 1's EXISTING
    -- base names rather than new ones: Gen 2's Kanto post-game
    -- rematches are the literal same characters (confirmed via the
    -- same decoded data -- Brock is trainer class 17 there, Misty 18,
    -- etc.), so they reuse brock_intro.ogg/brock_outro.ogg rather than
    -- needing duplicate recordings of the same person. Bruno (Gen 1
    -- Elite Four AND Gen 2 Elite Four, same character) and Koga (Gen 1
    -- gym leader AND Gen 2 Elite Four, same character, confirmed via
    -- his Gen 2 trainer class literally being named "KOGA" with
    -- display name "ELITE FOUR") work the same way. Only genuinely
    -- new characters (Falkner through Clair, Will, Karen, Janine,
    -- Blue) need their own new base names and new recordings.
    local GYM_LEADERS = {
      OPP_BROCK = "brock",
      OPP_MISTY = "misty",
      OPP_LT_SURGE = "surge",
      OPP_ERIKA = "erika",
      OPP_KOGA = "koga",
      OPP_SABRINA = "sabrina",
      OPP_BLAINE = "blaine",
      OPP_GIOVANNI = "giovanni",
      -- Gen 2 Johto (new characters, new base names)
      [1] = "falkner",
      [2] = "whitney",
      [3] = "bugsy",
      [4] = "morty",
      [5] = "pryce",
      [6] = "jasmine",
      [7] = "chuck",
      [8] = "clair",
      -- Gen 2 Kanto post-game (same characters as Gen 1 above, reuses
      -- their existing base names -- no new recordings needed)
      [17] = "brock",
      [18] = "misty",
      [19] = "surge",
      [21] = "erika",
      [35] = "sabrina",
      [46] = "blaine",
      -- Gen 2 Kanto post-game (genuinely new -- Janine replaces Koga
      -- at Fuchsia, since Koga moved to the Elite Four; Blue replaces
      -- Giovanni at Viridian, since Giovanni has no Gen 2 trainer
      -- class at all)
      [26] = "janine",
      [64] = "blue",
    }
    local ELITE_FOUR = {
      OPP_LORELEI = "lorelei",
      OPP_BRUNO = "bruno",
      OPP_AGATHA = "agatha",
      OPP_LANCE = "lance",
      -- Gen 2 -- Bruno (13) is the same character as Gen 1's, reuses
      -- his existing base name; Will/Karen (11/14) are new; Koga (15)
      -- reuses his existing GYM_LEADERS recording above, since it's
      -- the same voice regardless of which table currently employs
      -- him
      [11] = "will",
      [13] = "bruno",
      [14] = "karen",
      [15] = "koga",
    }

    -- Map IDs, for map.entered below -- a different identifier space
    -- from the trainer classes above. Map IDs are always strings on
    -- both generations, but Gen 2's Kanto post-game reuses Gen 1's
    -- EXACT SAME map ID strings for the same physical locations
    -- (confirmed against real decoded data -- PEWTER_GYM is spelled
    -- identically in both) -- correct and intentional, not a
    -- collision, since it's genuinely the same room and the same
    -- entrance reaction is exactly what should play either way. Only
    -- Johto's own new locations need adding here.
    local GYM_MAPS = {
      PEWTER_GYM = true, CERULEAN_GYM = true, VERMILION_GYM = true,
      CELADON_GYM = true, FUCHSIA_GYM = true, SAFFRON_GYM = true,
      CINNABAR_GYM = true, VIRIDIAN_GYM = true,
      -- Gen 2 Johto
      VIOLET_GYM = true, GOLDENROD_GYM = true, AZALEA_GYM = true,
      ECRUTEAK_GYM = true, MAHOGANY_GYM = true, OLIVINE_GYM = true,
      CIANWOOD_GYM = true,
      -- Clair's battle trigger is confirmed on the 1st floor, not the
      -- 2nd, via her actual NPC script in the decoded map data
      BLACKTHORN_GYM_1F = true,
      -- Blaine's Kanto post-game rematch is NOT at CINNABAR_GYM --
      -- confirmed via his actual battle-trigger NPC script sitting in
      -- a different map entirely. Matches the game's own lore: the
      -- Cinnabar volcano erupts between generations, and he relocates
      -- to a cave on the Seafoam Islands instead. Missing this would
      -- have silently broken his Kanto rematch entrance reaction
      -- despite his milestone audio (which correctly still reuses
      -- Gen 1's blaine_intro.ogg/blaine_outro.ogg, since it's still
      -- the same character) being completely fine.
      SEAFOAM_GYM = true,
    }
    local E4_MAPS = {
      LORELEIS_ROOM = true, BRUNOS_ROOM = true,
      AGATHAS_ROOM = true, LANCES_ROOM = true,
      -- Gen 2 -- BRUNOS_ROOM already covers Bruno's Gen 2 room too
      -- (confirmed identical string), only Will/Koga/Karen's rooms
      -- are new
      WILLS_ROOM = true, KOGAS_ROOM = true, KARENS_ROOM = true,
    }

    -- Confirmed against real source (data/scripts/story.lua): the
    -- Gen 1 Champion battle is always OPP_RIVAL3 (distinct from the
    -- earlier OPP_RIVAL1/OPP_RIVAL2 rival fights), fought in a real,
    -- confirmed map, CHAMPIONS_ROOM. Long treated as unconfirmed/
    -- impossible to detect -- it isn't, it just needed tracing
    -- properly.
    --
    -- Gen 2 is structurally different, confirmed against real decoded
    -- data: Lance has his own dedicated CHAMPION trainer class (index
    -- 16), entirely separate from Gen 2's own RIVAL1/RIVAL2 classes
    -- (9/42) -- no OPP_RIVAL3-style disambiguation needed, since the
    -- Champion genuinely isn't your rival in these games. Fought in
    -- LANCES_ROOM, a different map ID from Gen 1's generic
    -- CHAMPIONS_ROOM.
    local CHAMPION_TRAINER = "OPP_RIVAL3"
    local CHAMPION_TRAINER_GEN2 = 16

    -- Just the character's own reaction to the room -- fires every
    -- time it's entered, not suppressed after the first visit, since
    -- that's rare enough in practice not to need it. The leader's own
    -- challenge line comes later, in world.trainer_engaged below, once
    -- the battle actually starts rather than as soon as you walk in.
    mod.events:on("map.entered", function(ev)
      devLog("map.entered: mapId=%s -> gym=%s e4=%s champion=%s",
        tostring(ev.mapId), tostring(GYM_MAPS[ev.mapId] or false),
        tostring(E4_MAPS[ev.mapId] or false),
        tostring(ev.mapId == "CHAMPIONS_ROOM" or ev.mapId == "LANCES_ROOM"))
      if GYM_MAPS[ev.mapId] then
        if not mod.options:get("cat_gym_badges") then return end
        local charFolder = characterFolder()
        playRandom({
          mod.assets:path("assets/" .. charFolder .. "/gym_enter.ogg"),
          mod.assets:path("assets/" .. charFolder .. "/gym_enter2.ogg"),
          mod.assets:path("assets/" .. charFolder .. "/gym_enter3.ogg"),
        })
      elseif E4_MAPS[ev.mapId] then
        if not mod.options:get("cat_elite_four") then return end
        local charFolder = characterFolder()
        playRandom({
          mod.assets:path("assets/" .. charFolder .. "/e4_enter.ogg"),
          mod.assets:path("assets/" .. charFolder .. "/e4_enter2.ogg"),
        })
      elseif ev.mapId == "CHAMPIONS_ROOM" or ev.mapId == "LANCES_ROOM" then
        if not mod.options:get("cat_champion") then return end
        local charFolder = characterFolder()
        playRandom({
          mod.assets:path("assets/" .. charFolder .. "/champion_enter.ogg"),
          mod.assets:path("assets/" .. charFolder .. "/champion_enter2.ogg"),
        })
      end
    end)

    -- Tracks who's about to be fought (for the outcome below) AND
    -- plays that specific leader's own challenge line right now, e.g.
    -- brock_intro.ogg. Same pattern for the Champion (CHAMPION_TRAINER
    -- / CHAMPION_TRAINER_GEN2) as for a gym leader or E4 member, just
    -- a single trainer instead of a lookup table.
    local pendingTrainerClass = nil
    mod.events:on("world.trainer_engaged", function(ev)
      pendingTrainerClass = ev.trainerClass
      local gymBase = GYM_LEADERS[ev.trainerClass]
      local e4Base = ELITE_FOUR[ev.trainerClass]
      local isChampion = (ev.trainerClass == CHAMPION_TRAINER or ev.trainerClass == CHAMPION_TRAINER_GEN2)
      devLog("world.trainer_engaged: trainerClass=%s (%s) -> gym=%s e4=%s champion=%s",
        tostring(ev.trainerClass), type(ev.trainerClass),
        tostring(gymBase), tostring(e4Base), tostring(isChampion))
      if gymBase and mod.options:get("cat_gym_badges") then
        local folder = milestoneFolder()
        playSound(mod.assets:path("assets/" .. folder .. "/" .. gymBase .. "_intro.ogg"))
      elseif e4Base and mod.options:get("cat_elite_four") then
        local folder = milestoneFolder()
        playSound(mod.assets:path("assets/" .. folder .. "/" .. e4Base .. "_intro.ogg"))
      elseif isChampion and mod.options:get("cat_champion") then
        local folder = milestoneFolder()
        playSound(mod.assets:path("assets/" .. folder .. "/champion_intro.ogg"))
      end
    end)

    -- Delayed so it doesn't land on top of a faint bark from the
    -- finishing blow. Originally 1.5s -- reduced after real
    -- playtesting showed the actual battle-end-to-overworld transition
    -- is faster than that, so the line was landing as a noticeable
    -- beat of silence after the player was already back on the map.
    local OUTCOME_DELAY = 0.8

    mod.events:on("battle.ended", function(ev)
      local trainerClass = pendingTrainerClass
      pendingTrainerClass = nil
      if ev.result == "win" then
        local gymBase = GYM_LEADERS[trainerClass]
        local e4Base = ELITE_FOUR[trainerClass]
        if gymBase then
          if not mod.options:get("cat_gym_badges") then return end
          local folder = milestoneFolder()
          scheduleMoment(mod.assets:path("assets/" .. folder .. "/" .. gymBase .. "_outro.ogg"), OUTCOME_DELAY)
        elseif e4Base then
          if not mod.options:get("cat_elite_four") then return end
          local folder = milestoneFolder()
          scheduleMoment(mod.assets:path("assets/" .. folder .. "/" .. e4Base .. "_outro.ogg"), OUTCOME_DELAY)
        else
          -- Champion is deliberately excluded here, not just falling
          -- through to the generic case -- its real outro plays via
          -- screen.pushed below (the confirmed Hall of Fame signal),
          -- and used to double up with this generic line before
          -- CHAMPION_TRAINER existed to tell the two apart. Gen 2's
          -- CHAMPION_TRAINER_GEN2 excluded the same way, for the same
          -- reason -- its real outro plays via screen.pushed below too.
          if trainerClass == CHAMPION_TRAINER or trainerClass == CHAMPION_TRAINER_GEN2 then return end
          if not mod.options:get("cat_moments") then return end
          local folder = characterFolder()
          local winPaths = {
            mod.assets:path("assets/" .. folder .. "/battle_win.ogg"),
            mod.assets:path("assets/" .. folder .. "/battle_win2.ogg"),
          }
          scheduleMoment(winPaths[math.random(#winPaths)], OUTCOME_DELAY)
        end
      elseif ev.result == "lose" then
        if not mod.options:get("cat_moments") then return end
        local folder = characterFolder()
        local lossPaths = {
          mod.assets:path("assets/" .. folder .. "/battle_loss.ogg"),
          mod.assets:path("assets/" .. folder .. "/battle_loss2.ogg"),
        }
        scheduleMoment(lossPaths[math.random(#lossPaths)], OUTCOME_DELAY)
      end
    end)

    -- ---- Champion ----
    -- Beating the Champion pushes a "HallOfFame" screen on Gen 1 --
    -- confirmed against real engine source (src/ui/Screens.lua). Gen 2
    -- is a genuinely separate screen id, not the same one reused:
    -- confirmed in that same source file, which documents a "Gen2"
    -- prefix convention for any Gen 2 screen sharing a module name
    -- with a Gen 1 one (HallOfFame explicitly listed among them) --
    -- Gen 2's actual id is "Gen2HallOfFame". Missing this would have
    -- silently broken the Gen 2 Champion outro entirely despite
    -- everything else being correct, since the check would simply
    -- never have matched. This is the outro; the challenge line
    -- (champion_intro.ogg) lives up in world.trainer_engaged above.
    mod.events:on("screen.pushed", function(ev)
      if not mod.options:get("cat_champion") then return end
      if not (ev.state and (ev.state.screenId == "HallOfFame" or ev.state.screenId == "Gen2HallOfFame")) then return end
      local folder = milestoneFolder()
      scheduleMoment(mod.assets:path("assets/" .. folder .. "/champion_outro.ogg"), OUTCOME_DELAY)
    end)

end

return voice
