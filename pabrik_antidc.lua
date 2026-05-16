-- [[ ADAM BY GHOST PABRIK SCRIPT PREMIUM - MERGED v2.0 ]]
-- Best Pabrik script versions, dengan semua fix & improvements

-- =========================================================
-- 0) EDIT WAJIB - CONFIGURATION
-- =========================================================
local farm_world = "miya-ko-:krida"

local SEED_ITEM_ID  = 6
local INV_SEED_TYPE = InventoryItemType.seed

local INV_THRESHOLD = 10

-- Seed drop/save config
local SAVE_SEED_THRESHOLD_MIN = 50
local SAVE_SEED_THRESHOLD_MAX = 100
local SAVE_HALF_ENABLED       = true
local SEED_STORE_POINT        = Vector2i.new(12, 47)

-- PNB (Place & Break) Configuration
local PNB_CONFIG = {
    itemid      = 6,
    hits        = 4,
    start_point = Vector2i.new(4, 47),
    offsets = {
        Vector2i.new(0,  1),
        Vector2i.new(-1, 1),
        Vector2i.new(1,  1),
        Vector2i.new(-2, 1),
        Vector2i.new(2,  1),
    },
    hit_delay     = { min = 120, max = 200 },
    place_delay   = { min = 250, max = 350 },
    collect       = true,
    collect_delay = { min = 250, max = 320 },
    log           = true,
}

local WEBHOOK_URL = "https://discord.com/api/webhooks/1467420069490458808/jBlPjNam-T3UPsGPstoHF-vqze2C2PihbBFmwxwU-OQQBHk5c1pIh2tzYI7Dcs1P8JJ_"

-- =========================================================
-- 1) AREA & TIMING
-- =========================================================
local xMin, xMax   = 1, 78
local min_y, max_y = 39, 45

local T_MOVE_EXTRA                = 15
local T_HARVEST_HIT               = 150
local T_PLACE                     = 100
local T_PLANT                     = 110
local T_COLLECT                   = 30
local T_CYCLE                     = 1500
local T_RECONNECT_WAIT_AFTER_WARP = 3500
local T_DISCONNECT_WAIT           = 2000

-- =========================================================
-- 2) STATE
-- =========================================================
local client               = getClient()
local world                = nil
local isDisconnected       = false
local hasWarpedToFarmWorld = false
local currentAction        = "idle"
local webhookCycleCounter  = 0
local webhookUpdateCycles  = 20

local function safeSetStatus(icon)
    pcall(function() client:setStatus(icon) end)
end

local function getWorld()
    world = client:world()
    return world
end

local function getSeedCount()
    return client:inventory():count(SEED_ITEM_ID, INV_SEED_TYPE)
end

local function getTargetCount()
    return client:inventory():count(PNB_CONFIG.itemid, InventoryItemType.block)
end

local function totalInvSeedPlusTarget()
    return getSeedCount() + getTargetCount()
end

-- =========================================================
-- 3) HELPERS
-- =========================================================
local function webhook_send(payload)
    if not WEBHOOK_URL or WEBHOOK_URL == "" or WEBHOOK_URL == "YOUR_WEBHOOK_URL_HERE" then
        print("[WEBHOOK] Webhook URL tidak valid!")
        return false
    end
    pcall(function()
        webhook(WEBHOOK_URL, {
            username = "Adam Pabrik Farm Bot",
            embeds   = { payload }
        })
    end)
    print("[WEBHOOK] Webhook dikirim!")
    return true
end

local function webhook_update()
    local seedCount   = getSeedCount()
    local targetCount = getTargetCount()
    local totalInv    = totalInvSeedPlusTarget()
    local w           = getWorld()
    local worldName   = w and w.name or "Loading..."
    local connected   = client:connected() and "Terhubung" or "Terputus"

    local embed = {
        title       = "Adam Pabrik Farm Bot",
        description = "Bot ID: " .. tostring(client.id or "Unknown"),
        color       = isDisconnected and 16711680 or 65280,
        fields      = {
            { name = "STATUS BOT", value = connected,             inline = true },
            { name = "DUNIA",      value = worldName,             inline = true },
            { name = "BENIH",      value = tostring(seedCount),   inline = true },
            { name = "BLOK",       value = tostring(targetCount), inline = true },
            { name = "TOTAL ITEM", value = tostring(totalInv),    inline = true },
            { name = "AKSI",       value = string.upper(currentAction), inline = true },
        },
        footer = {
            text = "Adam Pabrik | " .. (isDisconnected and "Terputus" or "Berjalan")
        }
    }
    webhook_send(embed)
end

local function webhook_keren(state, seedCount, targetCount, totalInv, extra)
    local emoji = "🧱"
    local color = 3447003
    if state == "terputus" then emoji = "⚠️";  color = 16711680 end
    if state == "berjalan" then emoji = "🟢";  color = 65280    end
    if state == "tanam"    then emoji = "🌱";  color = 65535    end
    if state == "panen"    then emoji = "🌾";  color = 16776960 end
    if state == "pnb"      then emoji = "🛠️"; color = 255      end
    if state == "simpan"   then emoji = "📦";  color = 16711680 end
    if state == "pecah"    then emoji = "🔥";  color = 16711680 end

    local embed = {
        title       = emoji .. " Zenith Farm",
        description = "Status: " .. state,
        color       = color,
        fields      = {
            { name = "BENIH", value = tostring(seedCount  or 0), inline = true },
            { name = "BLOK",  value = tostring(targetCount or 0), inline = true },
            { name = "TOTAL", value = tostring(totalInv   or 0), inline = true },
        },
        footer = { text = extra or "Farm Status" }
    }
    webhook_send(embed)
end

local function inArea(tile)
    local p = tile:point()
    if p then
        return p.x >= xMin and p.x <= xMax and p.y >= min_y and p.y <= max_y
    end
    return false
end

local function goToPoint(pt)
    if isDisconnected then return false end

    local cp = client:point()
    if not cp:equals(pt) then
        if PNB_CONFIG.log then
            print(string.format("[PNB] [MOVE] Moving to (%d, %d)...", pt.x, pt.y))
        end

        local ok = pcall(function() return client:findPath(pt) end)
        if ok then
            sleep(200)
            local waitCount = 0
            while client:pathfinding() and waitCount < 100 do
                sleep(T_MOVE_EXTRA)
                waitCount = waitCount + 1
                if isDisconnected then
                    print("[PNB] [MOVE] Disconnect during pathfinding!")
                    return false
                end
            end
        else
            if PNB_CONFIG.log then
                print("[PNB] [MOVE] Pathfinding failed, using setPoint fallback...")
            end
            pcall(function() client:setPoint(pt, false) end)
            sleep(300)
        end

        if PNB_CONFIG.log then
            print(string.format("[PNB] [MOVE] Arrived at (%d, %d)", pt.x, pt.y))
        end

        sleep(100)
    end
    return true
end

local function hasBlock(tilePoint)
    local w = getWorld()
    if not w then return false end
    local tile = w:tile(tilePoint)
    return tile and tile.foreground and tile.foreground > 0
end

-- =========================================================
-- COLLECT - TETAP DI TEMPAT, TIDAK TERBANG
-- =========================================================
local function collectAtPoint(tilePoint)
    if not PNB_CONFIG.collect then return end
    local w = getWorld()
    if not w then return end

    local collectedCount = 0
    print("[PNB] [COLLECT] Scanning area around (" .. tilePoint.x .. "," .. tilePoint.y .. ")...")

    for _, col in pairs(w.collectables) do
        if col ~= nil then
            local p = col:point()
            if p then
                local dx = math.abs(p.x - tilePoint.x)
                local dy = math.abs(p.y - tilePoint.y)
                if dx <= 1 and dy <= 1 then
                    pcall(function()
                        sleep(math.random(PNB_CONFIG.collect_delay.min, PNB_CONFIG.collect_delay.max))
                        local success = client:collect(col.id)
                        if success ~= false then
                            collectedCount = collectedCount + 1
                            print("[PNB] [COLLECT] Collected item " .. collectedCount .. " at (" .. p.x .. "," .. p.y .. ")")
                            sleep(100)
                        end
                    end)
                end
            end
        end
    end

    if collectedCount > 0 then
        print("[PNB] [COLLECT] Total collected: " .. collectedCount .. " items")
    else
        print("[PNB] [COLLECT] No items found to collect")
    end

    sleep(350)
end

-- =========================================================
-- 4) FARMING
-- =========================================================
local function scanAreaTiles()
    local w = getWorld()
    if not w then return {}, {} end

    if not w.tiles or #w.tiles == 0 then return {}, {} end

    local harvest = {}
    local plant   = {}

    for _, tile in pairs(w.tiles) do
        if inArea(tile) then
            local tree = tile:tree()
            if tree ~= nil and tree.ready ~= nil and tree:ready() then
                table.insert(harvest, tile)
            elseif tree == nil then
                -- Hanya masuk plant jika tile BENAR-BENAR kosong
                table.insert(plant, tile)
            end
            -- tree ada tapi belum ready = abaikan
        end
    end

    table.sort(harvest, function(a, b)
        local pa, pb = a:point(), b:point()
        if pa.y == pb.y then return pa.x < pb.x end
        return pa.y < pb.y
    end)

    table.sort(plant, function(a, b)
        local pa, pb = a:point(), b:point()
        if pa.y == pb.y then return pa.x < pb.x end
        return pa.y < pb.y
    end)

    return harvest, plant
end

-- =========================================================
-- HARVEST & PLANT COMBINED
-- =========================================================
local function harvestAndPlantTile(tile)
    if isDisconnected then return false end
    currentAction = "harvest_plant"

    local currentSeeds = getSeedCount()
    if currentSeeds <= 0 then
        print("[DEBUG] No seeds! Aborting harvest.")
        return false
    end

    if not goToPoint(tile:point()) then return false end

    local tree = tile:tree()
    if not tree or not tree:ready() then
        return false
    end

    local coordStr = string.format("(%d, %d)", tile:point().x, tile:point().y)
    if PNB_CONFIG.log then
        print("[PNB] [HARVEST+PLANT] Start di " .. coordStr)
    end

    if isDisconnected then return false end

    pcall(function() client:hit(tile:point()) end)
    sleep(T_HARVEST_HIT)
    pcall(function() client:hit(tile:point()) end)
    sleep(T_HARVEST_HIT)
    pcall(function() client:hit(tile:point()) end)
    sleep(T_HARVEST_HIT)
    pcall(function() client:hit(tile:point()) end)
    sleep(T_HARVEST_HIT)
    pcall(function() client:hit(tile:point()) end)
    sleep(T_HARVEST_HIT)

    sleep(1500)

    local w = getWorld()
    if not w then
        print("[PNB] [HARVEST+PLANT] World is nil, attempting plant anyway...")
    else
        local fresh_tile = w:tile(tile:point())
        if fresh_tile then
            local still_has_tree = fresh_tile:tree() ~= nil
            if still_has_tree then
                print("[PNB] [HARVEST+PLANT] Tree still detected, attempting plant anyway...")
            end
        end
    end

    if PNB_CONFIG.log then
        print("[PNB] [HARVEST+PLANT] Planting seed di " .. coordStr)
    end

    local plant_success = pcall(function()
        client:place(tile:point(), SEED_ITEM_ID, INV_SEED_TYPE)
    end)

    if not plant_success then
        print("[DEBUG] Plant failed at " .. coordStr)
        currentAction = "idle"
        return false
    end

    sleep(T_PLACE + 300)

    local embed = { title = "Panen+Tanam", description = "[HARVEST+PLANT] Panen & Tanam di " .. coordStr, color = 16776960 }
    webhook_send(embed)

    if PNB_CONFIG.log then
        print("[PNB] [HARVEST+PLANT] Complete di " .. coordStr)
    end

    currentAction = "idle"
    return true
end

local function harvestTile(tile)
    return harvestAndPlantTile(tile)
end

local function plantTile(tile)
    if isDisconnected then return false end

    local currentSeeds = getSeedCount()
    if currentSeeds <= 0 then
        print("[DEBUG] No seeds in inventory! Aborting plant.")
        return false
    end

    currentAction = "plant"

    if not goToPoint(tile:point()) then return false end

    local tree = tile:tree()
    if tree ~= nil then
        return false
    end

    local coordStr = string.format("(%d, %d)", tile:point().x, tile:point().y)
    if PNB_CONFIG.log then
        print("[PNB] [PLANT] Plant di " .. coordStr)
    end

    local success = pcall(function()
        client:place(tile:point(), SEED_ITEM_ID, INV_SEED_TYPE)
    end)

    if not success then
        print("[DEBUG] Plant failed at " .. coordStr)
        return false
    end

    sleep(T_PLANT + 200)
    currentAction = "idle"
    return true
end

-- =========================================================
-- 5) PNB - PHASE 2 COLLECT PAKAI setPoint BUKAN goToPoint
--    AGAR TIDAK TERBANG LAMA DAN KENA DC
-- =========================================================
local function pnbPlaceAndBreak()
    if isDisconnected then return false end
    currentAction = "pnb"

    local startPos = PNB_CONFIG.start_point
    if not goToPoint(startPos) then
        return false
    end

    print("[PNB] ===== STARTING PNB CYCLE =====")

    -- Phase 1: Break semua block
    print("[PNB] PHASE 1: Breaking all blocks...")
    for i = 1, #PNB_CONFIG.offsets do
        if isDisconnected then
            print("[DEBUG] Disconnect during PNB break phase!")
            return false
        end
        local offset = PNB_CONFIG.offsets[i]
        local target = Vector2i.new(startPos.x + offset.x, startPos.y + offset.y)

        if PNB_CONFIG.log then
            print(string.format("[PNB] Break target %d/%d: (%d,%d)", i, #PNB_CONFIG.offsets, target.x, target.y))
        end

        if hasBlock(target) then
            for j = 1, PNB_CONFIG.hits do
                if isDisconnected then return false end
                pcall(function() client:hit(target) end)
                sleep(math.random(PNB_CONFIG.hit_delay.min, PNB_CONFIG.hit_delay.max))
            end
            print(string.format("[PNB] Broke block %d/%d", i, #PNB_CONFIG.offsets))
        else
            print(string.format("[PNB] No block at %d/%d - skipping", i, #PNB_CONFIG.offsets))
        end
    end

    print("[PNB] PHASE 1 Complete: All blocks broken")
    sleep(1200)
    print("[PNB] Waiting for items to settle...")
    sleep(600)

    -- =========================================================
    -- Phase 2: Collect - PERBAIKAN ANTI DC
    -- Gunakan setPoint langsung, jangan goToPoint (pathfinding)
    -- karena pathfinding bisa terbang lama = DC
    -- =========================================================
    print("[PNB] PHASE 2: Collecting all drops...")

    -- Collect dari CENTER (tidak perlu gerak)
    print("[PNB] [COLLECT] Center collect...")
    collectAtPoint(startPos)
    sleep(math.random(200, 350)) -- jeda natural

    -- Gerak ke KIRI pakai setPoint (langsung, tidak terbang)
    local leftPos = Vector2i.new(startPos.x - 1, startPos.y + 1)
    print("[PNB] [COLLECT] Moving LEFT...")
    pcall(function() client:setPoint(leftPos, false) end)
    sleep(math.random(300, 500)) -- tunggu karakter mendarat
    collectAtPoint(leftPos)
    sleep(math.random(200, 350))

    -- Gerak ke KANAN pakai setPoint (langsung, tidak terbang)
    local rightPos = Vector2i.new(startPos.x + 1, startPos.y + 1)
    print("[PNB] [COLLECT] Moving RIGHT...")
    pcall(function() client:setPoint(rightPos, false) end)
    sleep(math.random(300, 500)) -- tunggu karakter mendarat
    collectAtPoint(rightPos)
    sleep(math.random(200, 350))

    -- Kembali ke center pakai setPoint
    print("[PNB] [COLLECT] Returning to center...")
    pcall(function() client:setPoint(startPos, false) end)
    sleep(math.random(300, 500)) -- tunggu karakter mendarat

    print("[PNB] PHASE 2 Complete: Collected all drops")

    -- Phase 3: Place semua block
    print("[PNB] PHASE 3: Placing all blocks back...")
    for i = 1, #PNB_CONFIG.offsets do
        if isDisconnected then
            print("[DEBUG] Disconnect during PNB place phase!")
            return false
        end
        local offset = PNB_CONFIG.offsets[i]
        local target = Vector2i.new(startPos.x + offset.x, startPos.y + offset.y)

        pcall(function() client:place(target, PNB_CONFIG.itemid, InventoryItemType.block) end)
        sleep(math.random(PNB_CONFIG.place_delay.min, PNB_CONFIG.place_delay.max))

        print(string.format("[PNB] Placed block %d/%d at (%d,%d)", i, #PNB_CONFIG.offsets, target.x, target.y))
    end

    print("[PNB] PHASE 3 Complete: All blocks placed back")
    print("[PNB] ===== PNB CYCLE DONE =====")
    currentAction = "idle"
    return true
end

-- =========================================================
-- 6) SAVE SEED HALF
-- =========================================================
local function saveSeedHalfIfNeeded()
    if not SAVE_HALF_ENABLED then return false end
    if isDisconnected then return false end

    if not SEED_STORE_POINT or SEED_STORE_POINT.x == nil or SEED_STORE_POINT.y == nil then
        print("[DEBUG] SEED_STORE_POINT tidak valid, skip save seed")
        return false
    end

    local seedCount = getSeedCount()
    if seedCount < SAVE_SEED_THRESHOLD_MIN then return false end

    local half = math.floor(seedCount / 2)
    if half <= 0 then return false end

    currentAction = "drop"

    if not goToPoint(SEED_STORE_POINT) then
        print("[DEBUG] Failed to go to SEED_STORE_POINT")
        return false
    end

    sleep(300)

    pcall(function()
        client:drop(SEED_ITEM_ID, INV_SEED_TYPE, half)
    end)

    sleep(800)

    local dropCoord = string.format("(%d, %d)", SEED_STORE_POINT.x, SEED_STORE_POINT.y)
    print("[PNB] [DROP] Dropped " .. half .. " seeds di " .. dropCoord)
    local embed = { title = "Simpan Benih", description = "[SIMPAN] Menyimpan " .. half .. " benih di " .. dropCoord, color = 16711680 }
    webhook_send(embed)

    print("[DEBUG] [SAVE] Kembali ke start point...")
    sleep(500)
    pcall(function()
        goToPoint(PNB_CONFIG.start_point)
    end)

    currentAction = "idle"
    return true
end

-- =========================================================
-- 7) RECONNECT / WARP
-- =========================================================
local function reconnectIfNeeded()
    if client:connected() then return end

    print("[DEBUG] Starting reconnect sequence...")
    pcall(function() client:connect() end)

    local tries = 0
    while not client:connected() and tries < 15 do
        sleep(1000)
        tries = tries + 1
        print(string.format("[DEBUG] Reconnect attempt %d/15", tries))
    end

    if client:connected() then
        print("[DEBUG] Reconnect SUCCESS!")
        return true
    else
        print("[DEBUG] Reconnect FAILED after 15 attempts")
        return false
    end
end

local function warpToFarmWorld()
    if isDisconnected then return false end

    local w = client:world()
    if not w then
        if PNB_CONFIG.log then
            print("[PNB] [WARP] World is nil, waiting...")
        end
        sleep(1000)
        return false
    end

    local maxWaitCount = 0
    while (not w.tiles or #w.tiles == 0) and maxWaitCount < 30 do
        sleep(200)
        w = client:world()
        maxWaitCount = maxWaitCount + 1
    end

    local worldName = w.name
    if worldName == farm_world then
        if PNB_CONFIG.log then
            print("[PNB] Already in " .. farm_world)
        end
        return true
    end

    if PNB_CONFIG.log then
        print("[PNB] [WARP] Current: " .. tostring(worldName) .. " -> Warping to " .. farm_world)
    end

    pcall(function() client:warp(farm_world) end)
    sleep(T_RECONNECT_WAIT_AFTER_WARP + 2000)

    local waitCount = 0
    w = client:world()
    while (not w or not w.tiles or #w.tiles == 0) and waitCount < 30 do
        sleep(200)
        w = client:world()
        waitCount = waitCount + 1
    end

    if isDisconnected then
        print("[PNB] [WARP] Disconnect during warp!")
        return false
    end

    if PNB_CONFIG.log then
        print("[PNB] [WARP] Moving to start point...")
    end

    local moved = goToPoint(PNB_CONFIG.start_point)

    if not moved then
        if PNB_CONFIG.log then
            print("[PNB] [WARP] Pathfinding failed, using setPoint as fallback...")
        end
        pcall(function() client:setPoint(PNB_CONFIG.start_point, false) end)
        sleep(500)
    end

    sleep(500)
    local embed = { title = "Teleport Berhasil", description = "[WARP] Teleport ke " .. farm_world .. " berhasil", color = 65280 }
    webhook_send(embed)
    if PNB_CONFIG.log then
        print("[PNB] [WARP] Warp complete")
    end

    world = nil
    return true
end

-- =========================================================
-- 8) EVENT HANDLER
-- =========================================================
client:on("disconnect", function()
    isDisconnected = true
    currentAction  = "disconnected"
    safeSetStatus(StatusIconType.none)
    print("[DEBUG] DISCONNECT EVENT TRIGGERED!")
    local embed = { title = "Bot Terputus", description = "Bot terputus! Akan terhubung kembali dalam 3 detik...", color = 16711680 }
    webhook_send(embed)

    runThread(function()
        sleep(3000)
        print("[DEBUG] Attempting reconnect...")

        if not client:connected() then
            pcall(function() client:connect() end)
            local tries = 0
            while not client:connected() and tries < 15 do
                sleep(1000)
                tries = tries + 1
                print(string.format("[DEBUG] Reconnect attempt %d...", tries))
            end
        end

        if client:connected() then
            sleep(1000)
            isDisconnected       = false
            safeSetStatus(StatusIconType.typing)
            local embed = { title = "Bot Terhubung", description = "Bot terhubung kembali! Teleport ke dunia farm...", color = 65280 }
            webhook_send(embed)
            hasWarpedToFarmWorld = false
        else
            print("[DEBUG] Reconnect FAILED!")
            local embed = { title = "Reconnect Gagal", description = "Gagal terhubung kembali! Butuh intervensi manual.", color = 16711680 }
            webhook_send(embed)
        end
    end)
end)

client:on("connect", function()
    isDisconnected = false
    currentAction  = "connected"
    safeSetStatus(StatusIconType.typing)
end)

-- =========================================================
-- 9) MAIN LOOP
-- =========================================================
runThread(function()
    sleep(1000)

    print("[DEBUG] ===== BOT STARTED =====")

    if not client:connected() then
        print("[DEBUG] Client not connected, attempting reconnect...")
        reconnectIfNeeded()
    end

    if not hasWarpedToFarmWorld then
        print("[DEBUG] First time: Warping to farm world...")
        local warped = warpToFarmWorld()
        if warped then
            hasWarpedToFarmWorld = true
            print("[DEBUG] First warp SUCCESS, hasWarpedToFarmWorld=TRUE")
        else
            print("[DEBUG] First warp FAILED")
        end
    end

    local startCoord = string.format("(%d, %d)", PNB_CONFIG.start_point.x, PNB_CONFIG.start_point.y)
    local dropCoord  = string.format("(%d, %d)", SEED_STORE_POINT.x, SEED_STORE_POINT.y)
    local embed = {
        title       = "Bot Mulai Farming",
        description = "Bot mulai farming!",
        color       = 65280,
        fields      = {
            { name = "Posisi Start",  value = startCoord, inline = true },
            { name = "Posisi Simpan", value = dropCoord,  inline = true }
        }
    }
    webhook_send(embed)
    if PNB_CONFIG.log then
        print("Bot dimulai dengan Start: " .. startCoord .. " | Drop Seed: " .. dropCoord)
    end

    while true do
        if isDisconnected then
            currentAction = "disconnected"
            print("[DEBUG] Disconnected, waiting...")
            sleep(T_DISCONNECT_WAIT)
        else
            if not hasWarpedToFarmWorld then
                print("[DEBUG] Retrying warp... hasWarpedToFarmWorld=" .. tostring(hasWarpedToFarmWorld))
                local warped = warpToFarmWorld()
                print("[DEBUG] Warp result: " .. tostring(warped))
                if warped then
                    hasWarpedToFarmWorld = true
                    print("[DEBUG] hasWarpedToFarmWorld SET TO TRUE")
                end
                sleep(2000)
            else
                local seedCount   = getSeedCount()
                local targetCount = getTargetCount()
                local totalInv    = totalInvSeedPlusTarget()

                local harvestTiles, plantTiles = scanAreaTiles()

                print(string.format("[DEBUG] Seeds: %d, Blocks: %d, Total: %d | Harvest: %d, Plant: %d",
                    seedCount, targetCount, totalInv, #harvestTiles, #plantTiles))

                -- Prioritas 1: PNB
                if targetCount >= 1 and not isDisconnected then
                    print("[DEBUG] PNB TRIGGERED! Blocks: " .. targetCount .. " (threshold=" .. INV_THRESHOLD .. ")")

                    while getTargetCount() > 0 do
                        if isDisconnected then
                            print("[DEBUG] Disconnect during PNB loop!")
                            break
                        end

                        local blocksBefore = getTargetCount()
                        print("[DEBUG] PNB cycle: " .. blocksBefore .. " blocks remaining")

                        local pnbSuccess = pnbPlaceAndBreak()
                        print("[DEBUG] PNB result: " .. tostring(pnbSuccess))

                        sleep(500)

                        local blocksAfter = getTargetCount()
                        print("[DEBUG] After PNB: " .. blocksAfter .. " blocks remaining")

                        if blocksAfter >= blocksBefore then
                            print("[DEBUG] Blocks tidak berkurang! Stopping PNB.")
                            break
                        end
                    end

                    print("[DEBUG] PNB selesai!")

                -- Prioritas 1.5: Save seed jika melebihi threshold
                elseif seedCount > SAVE_SEED_THRESHOLD_MAX and SAVE_HALF_ENABLED then
                    print("[DEBUG] SEED MELEBIHI " .. SAVE_SEED_THRESHOLD_MAX .. "! Menyimpan seed...")
                    saveSeedHalfIfNeeded()
                    sleep(1000)

                -- Prioritas 2: Harvest
                elseif #harvestTiles > 0 then
                    print("[DEBUG] Harvesting & Planting tiles...")
                    for _, tile in ipairs(harvestTiles) do
                        if isDisconnected then
                            print("[DEBUG] Disconnect detected, stopping harvest loop")
                            break
                        end
                        if not harvestAndPlantTile(tile) then
                            print("[DEBUG] Harvest+Plant failed, continuing...")
                        end
                        sleep(100)
                    end
                    sleep(500)

                -- Prioritas 3: Plant
                elseif seedCount > 0 and #plantTiles > 0 then
                    print("[DEBUG] Planting on empty tiles...")
                    for _, tile in ipairs(plantTiles) do
                        if isDisconnected then
                            print("[DEBUG] Disconnect detected, stopping plant loop")
                            break
                        end
                        local currentSeeds = getSeedCount()
                        if currentSeeds <= 0 then
                            print("[DEBUG] Seed count = 0, stopping plant loop!")
                            break
                        end
                        if not plantTile(tile) then
                            print("[DEBUG] Plant failed at tile, skipping...")
                        end
                        sleep(100)
                    end
                    sleep(500)

                -- Prioritas 4: Save seed
                else
                    if not isDisconnected then
                        saveSeedHalfIfNeeded()
                    end
                end
            end

            webhookCycleCounter = webhookCycleCounter + 1
            if webhookCycleCounter >= webhookUpdateCycles then
                webhook_update()
                webhookCycleCounter = 0
            end

            sleep(T_CYCLE)
        end
    end
end)
