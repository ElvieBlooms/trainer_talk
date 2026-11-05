-- Trainer Talk: voice lines for gen1recomp
--
-- Plays a character's voice line on game events: new game, hits, faints,
-- catches, gym and Elite Four rooms, the Champion. Hooks into the engine
-- through mod.events, mod.hooks:wrap and mod.options. Works on Gen 1, Gen 2
-- and FireRed/LeafGreen. Leaves the game's own music and sound effects
-- alone, apart from quieting the music under a line (music.volume).
-- ------------------

local voice = {}

function voice.init(mod)
    math.randomseed(os.time())

    -- ---- Session ID ----
    -- A new 6-character code every boot, shown in the options and on every
    -- log line so a tester can quote it in a report. The charset drops
    -- 0/O and 1/I/L so it survives being read aloud.
    local SESSION_ID_CHARS = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
    local function generateSessionId()
      local chars = {}
      for i = 1, 6 do
        local idx = math.random(1, #SESSION_ID_CHARS)
        chars[i] = SESSION_ID_CHARS:sub(idx, idx)
      end
      return table.concat(chars)
    end
    local SESSION_ID = generateSessionId()

    -- ------------------
    -- FRAMEWORK: settings, shared state and the helpers the events use.
    -- Nothing in this half fires on its own.
    -- ------------------

    -- ---- Voice pack discovery ----
    -- Builds the CHARACTER and MILESTONE VOICE choices from the folders in
    -- assets/characters/ and assets/milestones/, so a new pack shows up
    -- without a code change. An optional meta.json ({ "label": "..." })
    -- sets the name shown in game.
    local Json = require("src.link.Json")

    local function readPackMeta(dir, key)
      local metaPath = dir .. "/" .. key .. "/meta.json"
      local ok1, info = pcall(function() return mod.assets:info(metaPath) end)
      if ok1 and info then
        local ok2, decoded = pcall(function() return Json.decode(mod:read(metaPath)) end)
        if ok2 and type(decoded) == "table" then return decoded end
      end
      return {}
    end

    -- An options row can't have zero choices, so an empty scan falls back
    -- to one hardcoded entry.
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
      -- 0 means no ducking, see duckSeconds()
      { key = "duck_seconds", type = "number", label = "DUCK TIME",
        min = 0, max = 5, step = 0.5, default = 2.5 },
      { key = "character", type = "choice", label = "CHARACTER",
        choices = characterChoices,
        default = characterDefault },
      -- Separate from CHARACTER: who voices the gym, Elite Four and
      -- Champion lines.
      { key = "milestone_voice", type = "choice", label = "MILESTONE VOICE",
        choices = milestoneChoices,
        default = milestoneDefault },

      -- Per-category switches. VOICE LINES and VOICE VOL still gate all of
      -- them.
      { key = "cat_game_start", type = "toggle", label = "GAME START", default = true },
      -- The frequency rows store a multiplier, not a percent, so BATTLE
      -- STATUS stays rarer than BATTLE HITS at every setting. OFF is 0x.
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
      -- Each reaction (crit, miss, failed catch, run) keeps its own base
      -- percent and this scales it.
      { key = "freq_reactions", type = "choice", label = "REACTIONS",
        choices = {
          { "OFF", 0 },
          { "RARE", 0.5 },
          { "NORMAL", 1 },
          { "FREQUENT", 2 },
        },
        default = 1 },
      -- A faint is a bigger moment than a miss, so this row starts at
      -- guaranteed and steps down. It stores the percent itself.
      { key = "freq_faint", type = "choice", label = "FAINT REACTIONS",
        choices = {
          { "OFF", 0 },
          { "SOMETIMES", 30 },
          { "OFTEN", 60 },
          { "ALWAYS", 100 },
        },
        default = 100 },
      -- How long faint, failed-catch and win/loss lines wait for the game
      -- to show the result first. The battle animations run on their own
      -- frame counts, so no single delay suits every setup. Raise it if a
      -- line still gives away the result.
      { key = "voice_delay", type = "choice", label = "VOICE DELAY",
        choices = {
          { "SHORTER", 0.6 },
          { "NORMAL", 1 },
          { "LONGER", 1.5 },
          { "LONGEST", 2.2 },
        },
        default = 1 },
      { key = "cat_moments", type = "toggle", label = "MOMENTS", default = true },
      { key = "cat_gym_badges", type = "toggle", label = "GYM BADGES", default = true },
      { key = "cat_elite_four", type = "toggle", label = "ELITE FOUR", default = true },
      { key = "cat_champion", type = "toggle", label = "CHAMPION", default = true },
      -- Off by default. Logs through mod.log, since the sandbox has no
      -- os.getenv to read a debug flag from.
      { key = "dev_logging", type = "toggle", label = "DEV LOGGING", default = false },
      -- Shown only while DEV LOGGING is on (visible_if). Its own opt-in
      -- because this is the one setting that sends anything off the
      -- device. Off by default even while debugging.
      { key = "dev_log_upload", type = "toggle", label = "SEND LOGS",
        default = false,
        visible_if = { key = "dev_logging", equals = true } },
      -- A "choice" with a single entry, so the ID can be read but not
      -- changed: ManagerState clamps stepping to that one entry, and a
      -- "text" row would open the rename screen. The stored 0 means
      -- nothing, only the label is read.
      { key = "session_id_display", type = "choice", label = "SESSION ID",
        choices = { { SESSION_ID, 0 } },
        default = 0,
        visible_if = { key = "dev_logging", equals = true } },
    })

    -- ---- Dev log capture and upload ----
    -- The upload check runs in the input.step hook below, so it costs one
    -- timestamp comparison per frame and hits the network once every 30s.
    local LOG_FLUSH_INTERVAL = 30
    local logBuffer = {}
    local lastLogFlushAt = -math.huge

    -- Every dev log line goes through here, so the mod manager's log view
    -- and the upload carry the same lines. Only SEND LOGS buffers for
    -- upload. DEV LOGGING alone stays on the device.
    local function devLog(fmt, ...)
      if not mod.options:get("dev_logging") then return end
      local line = string.format("[%s] " .. fmt, SESSION_ID, ...)
      mod.log:info(line)
      if mod.options:get("dev_log_upload") then
        table.insert(logBuffer, os.date("%H:%M:%S") .. "  " .. line)
      end
    end

    -- Handles from mod:postLog that haven't finished yet. Each one has to
    -- be polled and released or the engine keeps it for the whole session.
    local uploads = {}

    -- Releases finished uploads and warns about the ones that failed. The
    -- server's reply is never returned, so "ok" only means it was sent.
    local function reapUploads()
      for i = #uploads, 1, -1 do
        local okPoll, st = pcall(function() return mod.fetch:poll(uploads[i]) end)
        if not okPoll or not st then
          table.remove(uploads, i)
        elseif st.status ~= "pending" then
          if st.status == "error" then
            mod.log:warn("postLog: upload failed (%s)", tostring(st.err))
          end
          pcall(function() mod.fetch:release(uploads[i]) end)
          table.remove(uploads, i)
        end
      end
    end

    -- Sends the buffer with the engine's mod:postLog, which posts to the
    -- log_url in manifest.json (needs the "network" permission). It
    -- refuses up front for a missing permission or log_url, an empty or
    -- oversize body (512 KiB), or four uploads already in flight.
    local function flushLogBuffer()
      if #logBuffer == 0 then return end
      if not mod.options:get("dev_log_upload") then
        -- SEND LOGS was switched off after these lines were captured, so
        -- they are dropped instead of sent.
        logBuffer = {}
        return
      end
      local chunk = table.concat(logBuffer, "\n") .. "\n"
      logBuffer = {}
      local ok, handle, reason = pcall(mod.postLog, mod, chunk)
      if not ok then
        mod.log:warn("postLog: refused (%s) -- check log_url and the network "
          .. "permission in manifest.json", tostring(handle))
      elseif not handle then
        mod.log:warn("postLog: not sent (%s)", tostring(reason))
      else
        table.insert(uploads, handle)
      end
    end

    -- ---- Playback core ----
    local duckUntil = 0

    local function voiceVolume()
      return mod.options:get("voice_vol") or 7
    end

    local function duckSeconds()
      return mod.options:get("duck_seconds") or 2.5
    end

    -- The toggle and the volume both have to allow it, so muting with
    -- volume 0 never overwrites the saved volume.
    local function voiceLinesOn()
      return mod.options:get("voice_lines") and voiceVolume() > 0
    end

    -- Returns "characters/<key>" so "assets/" .. folder .. "/x.ogg" works
    -- at every call site.
    local function characterFolder()
      return "characters/" .. (mod.options:get("character") or characterDefault)
    end

    local function milestoneFolder()
      return "milestones/" .. (mod.options:get("milestone_voice") or milestoneDefault)
    end

    -- pcall on the load, so a pack missing a file stays quiet instead of
    -- erroring.
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

    -- ---- Frequency and chance ----
    local function chance(percent)
      return math.random(100) <= percent
    end

    local function frequencyMultiplier(key)
      return mod.options:get(key) or 1
    end

    -- Base waits before a line that would give away a result, scaled by
    -- the VOICE DELAY row. The events fire when the move or throw is
    -- decided, before the game plays any of it:
    --   faint: battle.fainted fires before the HP bar drains and the
    --          faint animation and text.
    --   catch: the catch.rate hook runs at the throw, before the ball
    --          toss, the shakes and the result text.
    --   outcome: battle.ended fires as the battle screen closes.
    -- These are estimates from the engine's animation order. They have not
    -- been timed in game yet.
    local FAINT_DELAY = 2.5
    local CAUGHT_FALLBACK_DELAY = 3
    local CATCH_FAIL_BASE = 1.8
    local CATCH_FAIL_PER_SHAKE = 0.8
    local OUTCOME_DELAY = 0.8

    local function delayScale()
      return mod.options:get("voice_delay") or 1
    end

    local function outcomeDelay()
      return OUTCOME_DELAY * delayScale()
    end

    -- ---- Voice line gap and delay queues ----
    -- One timestamp shared by barks, reactions, faints and moments, so no
    -- line lands on top of another. Moments used to skip it, until a
    -- playtest had one firing over a bark.
    local VOICE_LINE_GAP = 5
    local lastVoiceLineAt = -math.huge

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

    -- battle.damage_dealt fires before the hit animation, so the bark is
    -- queued and goes off a beat later.
    --
    -- A bark can also name text to wait for. The hooks and events fire when
    -- the game decides an outcome, well before the player reads it, so a
    -- line tied to result text waits until mod.battle:snapshot() shows that
    -- text on screen. The timed delay is only the fallback. It is used when
    -- there is no snapshot, and a hard cap stops a line waiting forever if
    -- the text never matches, for example on a translated ROM.
    local TEXT_POLL_INTERVAL = 0.1
    local TEXT_CAP_EXTRA = 4
    -- A beat after the text shows, so the voice lands with the reader and
    -- not on the first letter.
    local TEXT_TAIL = 0.25
    local lastTextPollAt = -math.huge
    local lastText = nil

    -- Returns the lowercased text now in the battle box, "" when the box is
    -- empty, or nil when there is no battle snapshot to read. The snapshot is
    -- copied, so this is polled and shared by every waiting line.
    local function shownText(force)
      local now = love.timer.getTime()
      if force or now - lastTextPollAt >= TEXT_POLL_INTERVAL then
        lastTextPollAt = now
        local ok, snap = pcall(function()
          return mod.battle and mod.battle:snapshot() or nil
        end)
        if ok and type(snap) == "table" then
          lastText = type(snap.message) == "table"
            and table.concat(snap.message, " "):lower() or ""
        else
          lastText = nil
        end
      end
      return lastText
    end

    local function textMatches(text, patterns)
      for _, pattern in ipairs(patterns) do
        if text:find(pattern, 1, true) then return true end
      end
      return false
    end

    -- Result text in all three generations. Lowercase and accent-free.
    local FAINT_TEXT = { "fainted" }
    local CAUGHT_TEXT = { "was caught" }
    local CATCH_FAIL_TEXT = {
      "broke free", "appeared to be caught", "almost had it",
      "so close", "missed the",
    }

    local pendingBarks = {}
    -- opts.direct plays the line without the shared gap, as the catch line
    -- always has. opts.allowStale lets text that is already showing count,
    -- for events that fire after their text.
    local function scheduleBark(pool, delay, patterns, opts)
      devLog("scheduleBark: QUEUED, fires in %.1fs%s", delay,
        patterns and " (or when its text shows)" or "")
      local entry = { at = love.timer.getTime() + delay, pool = pool, opts = opts or {} }
      if patterns then
        entry.patterns = patterns
        entry.baseline = shownText(true)
      end
      table.insert(pendingBarks, entry)
    end

    -- A moment waits for its own delay and then for the shared gap. If
    -- the gap hasn't cleared it stays queued instead of talking over
    -- whatever just played.
    local pendingMoments = {}
    local function scheduleMoment(path, delay)
      devLog("scheduleMoment: QUEUED path=%s, own delay %.1fs", path, delay)
      table.insert(pendingMoments, { at = love.timer.getTime() + delay, path = path })
    end

    mod.hooks:wrap("input.step", function(next, ...)
      local now = love.timer.getTime()
      if now - lastLogFlushAt >= LOG_FLUSH_INTERVAL then
        lastLogFlushAt = now
        reapUploads()
        flushLogBuffer()
      end
      for i = #pendingBarks, 1, -1 do
        local entry = pendingBarks[i]
        local ready
        if entry.patterns then
          local text = shownText()
          if text == nil then
            ready = now >= entry.at
          else
            if not entry.releaseAt
                and (text ~= entry.baseline or entry.opts.allowStale)
                and textMatches(text, entry.patterns) then
              entry.releaseAt = now + TEXT_TAIL
            end
            ready = (entry.releaseAt and now >= entry.releaseAt)
              or now >= entry.at + TEXT_CAP_EXTRA
          end
        else
          ready = now >= entry.at
        end
        if ready then
          table.remove(pendingBarks, i)
          if entry.opts.direct then
            playRandom(entry.pool)
          else
            attemptBark(entry.pool)
          end
        end
      end
      for i = #pendingMoments, 1, -1 do
        if now >= pendingMoments[i].at then
          if now - lastVoiceLineAt >= VOICE_LINE_GAP then
            local entry = table.remove(pendingMoments, i)
            lastVoiceLineAt = now
            playSound(entry.path)
          elseif not pendingMoments[i].deferredLogged then
            -- Logged once per entry. This runs every frame and the gap can
            -- last seconds.
            pendingMoments[i].deferredLogged = true
            devLog("moment DEFERRED (own delay elapsed, universal gap not clear yet) path=%s",
              pendingMoments[i].path)
          end
        end
      end
      return next(...)
    end)

    -- ------------------
    -- EVENTS: ties the framework above to game moments.
    -- ------------------

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

    -- Which side a battler is on. Each generation hands over a different
    -- shape:
    --   Gen 1: a wrapper with isPlayer.
    --   Gen 3: the battler's own .side string ("player"), the same field
    --          battle.fainted reports as sideName
    --          (src/core/game3/battle/adapter.lua).
    --   Gen 2: the raw party mon with neither field, so it is compared
    --          against battle.player (src/battle/gen2/Battle.lua).
    -- Every event used with this carries a `battle` field for that last case.
    local function isPlayerSide(mon, battle)
      if mon == nil then return false end
      if mon.isPlayer ~= nil then return mon.isPlayer end
      if mon.side ~= nil then return mon.side == "player" end
      if battle and battle.player ~= nil then return mon == battle.player end
      return false
    end

    -- ---- Battle barks (hit / status) ----
    mod.events:on("battle.damage_dealt", function(ev)
      -- Fires for either side's hit, so an enemy hit would otherwise
      -- trigger the pleased bark. Player hits only, with no enemy pair
      -- the way status has.
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
      -- A status can land on either side, so the lines are split by who
      -- got it.
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
    -- Gen 1 has no day/night clock, so in practice this is Gold and
    -- Crystal.
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
    -- Small wordless beats in a battle: crits, misses, catches, escapes,
    -- faints.

    mod.events:on("battle.damage_dealt", function(ev)
      if not ev.crit then return end
      -- Player crits only, same as the hit pool above.
      if not isPlayerSide(ev.user, ev.battle) then return end
      if not chance(50 * frequencyMultiplier("freq_reactions")) then return end
      local folder = characterFolder()
      -- Same 1.5s delay as the hit pool, so it lands after the hit text.
      scheduleBark({
        mod.assets:path("assets/" .. folder .. "/hit_crit.ogg"),
        mod.assets:path("assets/" .. folder .. "/hit_crit2.ogg"),
      }, 1.5)
    end)

    -- A miss has no event, so this wraps the battle.accuracy hook. It
    -- runs for both sides' rolls, hence the player check.
    mod.hooks:wrap("battle.accuracy", function(next, ctx)
      local hit = next(ctx)
      local isPlayerMove = isPlayerSide(ctx.user, ctx.battle)
      if not hit and isPlayerMove and chance(20 * frequencyMultiplier("freq_reactions")) then
        local folder = characterFolder()
        -- Delayed like the hit pool, so it lands after the miss text.
        scheduleBark({
          mod.assets:path("assets/" .. folder .. "/move_miss.ogg"),
          mod.assets:path("assets/" .. folder .. "/move_miss2.ogg"),
        }, 1.5)
      end
      return hit
    end)

    -- pokemon.caught only fires on success, so a failed catch is read
    -- from the catch.rate hook. The hook runs at the throw, so the line
    -- waits for the result text to show. The toss and one stretch per
    -- shake, which the hook also returns, are the fallback delay.
    mod.hooks:wrap("catch.rate", function(next, ball, mon, def, opts)
      local caught, shakes = next(ball, mon, def, opts)
      if not caught and chance(25 * frequencyMultiplier("freq_reactions")) then
        local folder = characterFolder()
        -- Gen 2 can hand back a value far above three, so clamp it.
        local wait = CATCH_FAIL_BASE
          + CATCH_FAIL_PER_SHAKE * math.min(tonumber(shakes) or 0, 3)
        scheduleBark({
          mod.assets:path("assets/" .. folder .. "/catch_fail.ogg"),
          mod.assets:path("assets/" .. folder .. "/catch_fail2.ogg"),
        }, wait * delayScale(), CATCH_FAIL_TEXT)
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

    -- Faints have their own dial (freq_faint) and default to every time.
    -- The line waits for the fainted text. FAINT_DELAY is the fallback.
    mod.events:on("battle.fainted", function(ev)
      if not chance(mod.options:get("freq_faint") or 100) then return end
      local folder = characterFolder()
      if isPlayerSide(ev.battler, ev.battle) then
        scheduleBark({
          mod.assets:path("assets/" .. folder .. "/faint_player.ogg"),
          mod.assets:path("assets/" .. folder .. "/faint_player2.ogg"),
        }, FAINT_DELAY * delayScale(), FAINT_TEXT)
      else
        scheduleBark({
          mod.assets:path("assets/" .. folder .. "/faint_enemy.ogg"),
          mod.assets:path("assets/" .. folder .. "/faint_enemy2.ogg"),
        }, FAINT_DELAY * delayScale(), FAINT_TEXT)
      end
    end)

    -- ---- Moments ----
    -- Rarer, bigger beats: evolving, a first catch, blacking out. Already
    -- rare, so no chance roll. Ordinary trainer win and loss lines use the
    -- same MOMENTS toggle but live with the battle.ended handler below.

    mod.events:on("pokemon.evolved", function(ev)
      if not mod.options:get("cat_moments") then return end
      local folder = characterFolder()
      playSound(mod.assets:path("assets/" .. folder .. "/evolved.ogg"))
    end)

    -- Gen 2 fires pokemon.caught at the throw, Gen 1 and 3 after the caught
    -- text. The line waits for "was caught" either way. The text can already
    -- be showing by then, so stale text counts.
    mod.events:on("pokemon.caught", function(ev)
      if not mod.options:get("cat_moments") then return end
      if not ev.isNew then return end
      local folder = characterFolder()
      scheduleBark({
        mod.assets:path("assets/" .. folder .. "/new_catch.ogg"),
        mod.assets:path("assets/" .. folder .. "/new_catch2.ogg"),
      }, CAUGHT_FALLBACK_DELAY * delayScale(), CAUGHT_TEXT,
      { direct = true, allowStale = true })
    end)

    -- 3s delay, so it lands after the loss line and the warp back to the
    -- Pokemon Center.
    mod.events:on("world.blacked_out", function(ev)
      if not mod.options:get("cat_moments") then return end
      local folder = characterFolder()
      local blackoutPaths = {
        mod.assets:path("assets/" .. folder .. "/blackout.ogg"),
        mod.assets:path("assets/" .. folder .. "/blackout2.ogg"),
      }
      scheduleMoment(blackoutPaths[math.random(#blackoutPaths)], 3)
    end)

    -- ---- Gym Badges and Elite Four ----
    -- Two voices. CHARACTER reacts to walking into the room. MILESTONE
    -- VOICE does the leader's challenge line and the win line, since both
    -- are about the leader.

    -- Trainer class to file name, shared by the _intro line (on engage)
    -- and the _outro line (on win, in battle.ended below).
    --
    -- Gen 1 classes are strings (OPP_BROCK) and Gen 2 classes are numbers,
    -- so they can share one table without colliding. Gen 2's Kanto
    -- rematches are the same people, so they reuse Gen 1's file names
    -- (class 17 is Brock, 18 Misty). Bruno and Koga work the same way:
    -- Koga is a Gen 1 gym leader and a Gen 2 Elite Four member, so he
    -- appears in both tables with one recording. Only the new characters
    -- (Falkner to Clair, Will, Karen, Janine, Blue) have their own names.
    -- Numbers come from the decoded Gold, Silver and Crystal trainer data,
    -- which use the same indices in all three.
    local GYM_LEADERS = {
      OPP_BROCK = "brock",
      OPP_MISTY = "misty",
      OPP_LT_SURGE = "surge",
      OPP_ERIKA = "erika",
      OPP_KOGA = "koga",
      OPP_SABRINA = "sabrina",
      OPP_BLAINE = "blaine",
      OPP_GIOVANNI = "giovanni",
      -- Gen 2 Johto
      [1] = "falkner",
      [2] = "whitney",
      [3] = "bugsy",
      [4] = "morty",
      [5] = "pryce",
      [6] = "jasmine",
      [7] = "chuck",
      [8] = "clair",
      -- Gen 2 Kanto post-game, reusing the Gen 1 recordings
      [17] = "brock",
      [18] = "misty",
      [19] = "surge",
      [21] = "erika",
      [35] = "sabrina",
      [46] = "blaine",
      -- Janine runs Fuchsia now that Koga is in the Elite Four, and Blue
      -- runs Viridian because Giovanni has no Gen 2 trainer class.
      [26] = "janine",
      [64] = "blue",
    }

    -- FireRed and LeafGreen key on trainerId, not trainerClass. Every
    -- leader there shares the one "LEADER" class, so the class can't say
    -- which leader it is. world.trainer_engaged carries both fields. Both
    -- games have identical trainer tables in this engine, so one table
    -- covers them.
    local GEN3_GYM_LEADERS = {
      [414] = "brock", [415] = "misty", [416] = "surge", [417] = "erika",
      [418] = "koga", [419] = "blaine", [420] = "sabrina",
      -- Giovanni's gym fight only. Ids 348 and 349 are his Rocket Hideout
      -- and Silph Co. fights, which are not the gym milestone.
      [350] = "giovanni",
    }
    local ELITE_FOUR = {
      OPP_LORELEI = "lorelei",
      OPP_BRUNO = "bruno",
      OPP_AGATHA = "agatha",
      OPP_LANCE = "lance",
      -- Gen 2. Bruno and Koga reuse their existing recordings, Will and
      -- Karen are new.
      [11] = "will",
      [13] = "bruno",
      [14] = "karen",
      [15] = "koga",
    }
    -- FireRed and LeafGreen Elite Four, keyed on trainerId like the gym
    -- table. 410-413 is the first run and 735-738 the Sevii Islands
    -- rematch. Same four people, same audio.
    local GEN3_ELITE_FOUR = {
      [410] = "lorelei", [411] = "bruno", [412] = "agatha", [413] = "lance",
      [735] = "lorelei", [736] = "bruno", [737] = "agatha", [738] = "lance",
    }

    -- Map ids for map.entered. These are strings in every generation, and
    -- Gen 2's Kanto post-game uses Gen 1's exact strings for the same
    -- rooms (PEWTER_GYM, BRUNOS_ROOM), so the one entry covers both. Only
    -- Johto's rooms and the Gen 3 names are added.
    local GYM_MAPS = {
      PEWTER_GYM = true, CERULEAN_GYM = true, VERMILION_GYM = true,
      CELADON_GYM = true, FUCHSIA_GYM = true, SAFFRON_GYM = true,
      CINNABAR_GYM = true, VIRIDIAN_GYM = true,
      -- Gen 2 Johto
      VIOLET_GYM = true, GOLDENROD_GYM = true, AZALEA_GYM = true,
      ECRUTEAK_GYM = true, MAHOGANY_GYM = true, OLIVINE_GYM = true,
      CIANWOOD_GYM = true,
      -- Clair's fight triggers on the 1st floor, not the 2nd.
      BLACKTHORN_GYM_1F = true,
      -- Blaine's Kanto rematch is in the Seafoam Islands, not Cinnabar
      -- (the volcano erupted). His audio is still blaine_intro and
      -- blaine_outro from Gen 1.
      SEAFOAM_GYM = true,
      -- FireRed and LeafGreen use different strings from Gen 1, and not
      -- only by prefix: Cinnabar is FR_CINNABAR_ISLAND_GYM.
      FR_PEWTER_CITY_GYM = true, FR_CERULEAN_CITY_GYM = true,
      FR_VERMILION_CITY_GYM = true, FR_CELADON_CITY_GYM = true,
      FR_FUCHSIA_CITY_GYM = true, FR_SAFFRON_CITY_GYM = true,
      FR_CINNABAR_ISLAND_GYM = true, FR_VIRIDIAN_CITY_GYM = true,
    }
    local E4_MAPS = {
      LORELEIS_ROOM = true, BRUNOS_ROOM = true,
      AGATHAS_ROOM = true, LANCES_ROOM = true,
      -- Gen 2. Bruno's room is the same string as Gen 1, so only Will,
      -- Koga and Karen are added.
      WILLS_ROOM = true, KOGAS_ROOM = true, KARENS_ROOM = true,
      -- FireRed and LeafGreen
      FR_POKEMON_LEAGUE_LORELEIS_ROOM = true,
      FR_POKEMON_LEAGUE_BRUNOS_ROOM = true,
      FR_POKEMON_LEAGUE_AGATHAS_ROOM = true,
      FR_POKEMON_LEAGUE_LANCES_ROOM = true,
    }

    -- The Champion, per generation:
    --   Gen 1: the rival's third fight, OPP_RIVAL3 (RIVAL1 and RIVAL2 are
    --          the earlier fights), in CHAMPIONS_ROOM.
    --   Gen 2: Lance has his own CHAMPION class, index 16, separate from
    --          the rival classes (9 and 42). The room is LANCES_ROOM.
    --   Gen 3: trainer id 38, class CHAMPION. Its name is empty in the
    --          trainer table because the rival is named by the player.
    --          Ids 438 and 439 are a different, optional level 63 rematch.
    local CHAMPION_TRAINER = "OPP_RIVAL3"
    local CHAMPION_TRAINER_GEN2 = 16
    local CHAMPION_TRAINER_GEN3 = 38

    -- CHARACTER's reaction to the room itself. Plays on every entry, since
    -- re-entering is rare. The leader's own challenge line waits for
    -- world.trainer_engaged below.
    mod.events:on("map.entered", function(ev)
      devLog("map.entered: mapId=%s -> gym=%s e4=%s champion=%s",
        tostring(ev.mapId), tostring(GYM_MAPS[ev.mapId] or false),
        tostring(E4_MAPS[ev.mapId] or false),
        tostring(ev.mapId == "CHAMPIONS_ROOM" or ev.mapId == "LANCES_ROOM"
          or ev.mapId == "FR_POKEMON_LEAGUE_CHAMPIONS_ROOM"))
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
      elseif ev.mapId == "CHAMPIONS_ROOM" or ev.mapId == "LANCES_ROOM"
          or ev.mapId == "FR_POKEMON_LEAGUE_CHAMPIONS_ROOM" then
        if not mod.options:get("cat_champion") then return end
        local charFolder = characterFolder()
        playRandom({
          mod.assets:path("assets/" .. charFolder .. "/champion_enter.ogg"),
          mod.assets:path("assets/" .. charFolder .. "/champion_enter2.ogg"),
        })
      end
    end)

    -- Remembers who is being fought, for battle.ended, and plays that
    -- leader's own challenge line (brock_intro.ogg). The Champion works
    -- the same way with a single trainer in place of a table.
    -- The Gen 3 tables are checked on ev.trainerId next to the
    -- ev.trainerClass tables, because trainerClass can't tell FireRed's
    -- leaders apart (src/core/game3/trainer_sight.lua emits both).
    local pendingTrainerClass = nil
    local pendingTrainerId = nil
    mod.events:on("world.trainer_engaged", function(ev)
      pendingTrainerClass = ev.trainerClass
      pendingTrainerId = ev.trainerId
      local gymBase = GYM_LEADERS[ev.trainerClass] or GEN3_GYM_LEADERS[ev.trainerId]
      local e4Base = ELITE_FOUR[ev.trainerClass] or GEN3_ELITE_FOUR[ev.trainerId]
      local isChampion = (ev.trainerClass == CHAMPION_TRAINER
        or ev.trainerClass == CHAMPION_TRAINER_GEN2
        or ev.trainerId == CHAMPION_TRAINER_GEN3)
      devLog("world.trainer_engaged: trainerClass=%s (%s) trainerId=%s -> gym=%s e4=%s champion=%s",
        tostring(ev.trainerClass), type(ev.trainerClass), tostring(ev.trainerId),
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

    mod.events:on("battle.ended", function(ev)
      local trainerClass = pendingTrainerClass
      local trainerId = pendingTrainerId
      pendingTrainerClass = nil
      pendingTrainerId = nil
      if ev.result == "win" then
        local gymBase = GYM_LEADERS[trainerClass] or GEN3_GYM_LEADERS[trainerId]
        local e4Base = ELITE_FOUR[trainerClass] or GEN3_ELITE_FOUR[trainerId]
        if gymBase then
          if not mod.options:get("cat_gym_badges") then return end
          local folder = milestoneFolder()
          scheduleMoment(mod.assets:path("assets/" .. folder .. "/" .. gymBase .. "_outro.ogg"), outcomeDelay())
        elseif e4Base then
          if not mod.options:get("cat_elite_four") then return end
          local folder = milestoneFolder()
          scheduleMoment(mod.assets:path("assets/" .. folder .. "/" .. e4Base .. "_outro.ogg"), outcomeDelay())
        elseif trainerId == CHAMPION_TRAINER_GEN3 then
          -- FireRed and LeafGreen play the Champion outro straight off
          -- battle.ended. Their screen stack (src/ui/game3/stack.lua)
          -- never emits screen.pushed, so the Hall of Fame signal that
          -- Gen 1 and 2 wait for below doesn't exist here. If the game
          -- runs a scripted scene between the fight and Hall of Fame,
          -- the line lands before it. That is untested, and the simpler
          -- timing was a deliberate choice.
          if not mod.options:get("cat_champion") then return end
          local folder = milestoneFolder()
          scheduleMoment(mod.assets:path("assets/" .. folder .. "/champion_outro.ogg"), outcomeDelay())
        else
          -- Gen 1 and 2 Champion wins are skipped here because their real
          -- outro plays from screen.pushed below. Without this check the
          -- generic win line would double up with it.
          if trainerClass == CHAMPION_TRAINER or trainerClass == CHAMPION_TRAINER_GEN2 then return end
          if not mod.options:get("cat_moments") then return end
          local folder = characterFolder()
          local winPaths = {
            mod.assets:path("assets/" .. folder .. "/battle_win.ogg"),
            mod.assets:path("assets/" .. folder .. "/battle_win2.ogg"),
          }
          scheduleMoment(winPaths[math.random(#winPaths)], outcomeDelay())
        end
      elseif ev.result == "lose" then
        if not mod.options:get("cat_moments") then return end
        local folder = characterFolder()
        local lossPaths = {
          mod.assets:path("assets/" .. folder .. "/battle_loss.ogg"),
          mod.assets:path("assets/" .. folder .. "/battle_loss2.ogg"),
        }
        scheduleMoment(lossPaths[math.random(#lossPaths)], outcomeDelay())
      end
    end)

    -- ---- Champion ----
    -- Beating the Champion pushes the Hall of Fame screen, which is the
    -- signal for the outro (champion_intro.ogg is up in
    -- world.trainer_engaged). Gen 1's screen id is "HallOfFame" and Gen 2
    -- builds "Gen2HallOfFame" (Screens.GEN2_IDS in src/ui/Screens.lua), so
    -- both are matched.
    mod.events:on("screen.pushed", function(ev)
      if not mod.options:get("cat_champion") then return end
      if not (ev.state and (ev.state.screenId == "HallOfFame" or ev.state.screenId == "Gen2HallOfFame")) then return end
      local folder = milestoneFolder()
      scheduleMoment(mod.assets:path("assets/" .. folder .. "/champion_outro.ogg"), outcomeDelay())
    end)

end

return voice
