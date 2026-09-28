--// Weather + Skybox extracted from the original script
--// Required before this block: Config, Tabs, Toggles, Options and a LinoriaLib Library.
--// These service locals make the Weather implementation portable.

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

Config = Config or {}
Toggles = Toggles or {}
Options = Options or {}

local Weather = {}
;(function()
    local SoundService = game:GetService("SoundService")
    local TweenService = game:GetService("TweenService")
    local function cfg(key, default)
        local v = Config[key]
        if v == nil then return default end
        return v
    end
    local function iAmt()
        return math.clamp(cfg("WeatherIntensity", 1), 0.15, 2)
    end
    local function iRate(I, kLo, kHi)
        if I < 1 then
            return math.exp(kLo * (I - 1))
        end
        return math.exp(kHi * (I - 1))
    end
    local function evRate(key)
        return math.clamp(cfg(key, 1), 0.25, 3)
    end
    local IR = {
        Snow      = { lo = 1.75, hi = 0.85, acc = 0.45, sz = 0.08, alp = 0.35, gst = 0.30 },
        Petals    = { lo = 1.75, hi = 0.85, acc = 0.40, sz = 0.08, alp = 0.30, gst = 0.30 },
        Autumn    = { lo = 1.75, hi = 0.85, acc = 0.40, sz = 0.08, alp = 0.30, gst = 0.30 },
        Mist      = { lo = 1.35, hi = 1.10, acc = 0.30, sz = 0.25, alp = 0.75, gst = 0.20 },
        Ash       = { lo = 1.45, hi = 1.05, acc = 0.35, sz = 0.15, alp = 0.55, gst = 0.20 },
        Sandstorm = { lo = 1.35, hi = 1.60, acc = 0.45, sz = 0.30, alp = 0.75, gst = 0.20 },
        Embers    = { lo = 1.45, hi = 1.05, acc = 0.30, sz = 0.10, alp = 0.25, gst = 0.20 },
        Fireflies = { lo = 1.45, hi = 1.00, acc = 0.10, sz = 0.08, alp = 0.20, gst = 0.15 },
    }
    local IR_DEF = { lo = 1.6, hi = 0.9, acc = 0.3, sz = 0.10, alp = 0.25, gst = 0.25 }
    local SET_LO, SET_HI = 0.75, 0.45
    local Vec   = Vector3.new
    local WHITE = Color3.new(1, 1, 1)
    local TX_SOFT  = "rbxasset://textures/particles/smoke_main.dds"
    local TX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
    local TX_FLAKE    = "rbxassetid://101749163393113"
    local TX_SNOWSOFT = "rbxassetid://78582616787441"
    local TX_PUFF     = "rbxassetid://77935321198144"
    local TX_PETAL    = "rbxassetid://243344623"
    local TX_LEAFA    = "rbxassetid://8590047664"
    local TX_LEAFB    = "rbxassetid://5970677338"
    local TX_LEAFC    = "rbxassetid://9239040931"
    local TX_DUST     = "rbxassetid://341828512"
    local _curType = nil
    local Wind = { x = 0, z = 0 }
    ;(function()
        local baseAng = math.random() * 6.283
        local gustT0, gustDur, gustAmp = 0, 1, 0
        local nextGustT = math.huge
        local cbs = {}
        function Wind.onGust(fn)
            cbs[#cbs + 1] = fn
        end
        function Wind.reset(now)
            nextGustT = now + 8 + math.random() * 17
            gustT0, gustAmp = 0, 0
            Wind.x, Wind.z = 0, 0
        end
        function Wind.update(now)
            if now >= nextGustT then
                gustT0 = now
                gustDur = 2 + math.random() * 2
                gustAmp = 1 + math.random()
                nextGustT = now + 8 + math.random() * 17
                for i = 1, #cbs do
                    pcall(cbs[i], gustDur, 1 + gustAmp)
                end
            end
            local ang = baseAng + 0.6 * math.sin(now * 0.013) + 0.9 * math.sin(now * 0.031 + 2.6)
            local str = 1 + 0.35 * math.sin(now * 0.17) + 0.22 * math.sin(now * 0.41 + 1.3)
                          + 0.15 * math.sin(now * 0.07 + 4.1)
            local ga = (now - gustT0) / gustDur
            if gustAmp > 0 and ga < 1 then
                str = str * (1 + gustAmp * math.sin(ga * math.pi))
            end
            Wind.x = math.cos(ang) * str
            Wind.z = math.sin(ang) * str
        end
        function Wind.vec()
            return Vec(Wind.x, 0, Wind.z)
        end
    end)()
    local _folder = nil
    local function getFolder()
        if _folder and _folder.Parent then return _folder end
        local f = Instance.new("Folder"); f.Name = "_wx"; f:SetAttribute("WX_Custom", true)
        f.Parent = Workspace
        _folder = f; return f
    end
    local _rain = { drops = {}, conn = nil, folder = nil, dir = nil, applied = nil }
    local RAIN_DIR      = Vec(-0.16, -1, 0.05).Unit
    local RAIN_LEAN_K   = 0.12
    local RAIN_LEAN_MAX = 0.2126
    local RAIN_RADIUS = 70
    local RAIN_TOP    = 70
    local RAIN_BOT    = -28
    local RAIN_MAX    = 420
    local function rainFolder()
        if _rain.folder and _rain.folder.Parent then return _rain.folder end
        local f = Instance.new("Folder"); f.Name = "_wxRain"; f:SetAttribute("WX_Custom", true)
        f.Parent = getFolder()
        _rain.folder = f; return f
    end
    local function makeDrop(parent, streakLen, width, color, glow, transp)
        local part = Instance.new("Part")
        part.Anchored = true; part.CanCollide = false; part.CanQuery = false; part.CanTouch = false
        part.CastShadow = false; part.Massless = true; part.Transparency = 1; part.Size = Vec(0.05,0.05,0.05)
        part:SetAttribute("WX_Custom", true)
        local a0 = Instance.new("Attachment"); a0.Parent = part
        local a1 = Instance.new("Attachment"); a1.Position = _rain.dir * streakLen; a1.Parent = part
        local beam = Instance.new("Beam")
        beam.Attachment0 = a0; beam.Attachment1 = a1
        beam.Segments = 1; beam.FaceCamera = true
        beam.Width0 = width; beam.Width1 = width * 0.55
        local emission = 0.35
        if glow then
            emission = 1
        end
        beam.LightEmission = emission
        beam.LightInfluence = 0
        beam.Color = ColorSequence.new(color)
        beam.Transparency = NumberSequence.new(transp)
        beam.Parent = part
        part.Parent = parent
        return part, a1, beam
    end
    local function seedDrop(d, camPos)
        local ang = math.random() * math.pi * 2
        local rad = math.sqrt(math.random()) * RAIN_RADIUS
        local y   = camPos.Y + RAIN_TOP - math.random() * (RAIN_TOP - RAIN_BOT)
        d.pos = Vec(camPos.X + math.cos(ang) * rad, y, camPos.Z + math.sin(ang) * rad)
    end
    local function newDrop(folder, i, camPos)
        local base, width, color, transp, spd0
        if (i % 3) ~= 0 then
            base, width, transp = 5 + math.random() * 3, 0.10, 0.22
            spd0 = 150 + math.random() * 30
            color = Color3.fromRGB(180, 202, 232)
        else
            base, width, transp = 3 + math.random() * 2, 0.06, 0.55
            spd0 = 120 + math.random() * 30
            color = Color3.fromRGB(158, 182, 214)
        end
        local part, a1, beam = makeDrop(folder, base, width, color, false, transp)
        local d = { part = part, a1 = a1, beam = beam, base = base, len = base,
                    w0 = width, t0 = transp, spd0 = spd0, spd = spd0 }
        seedDrop(d, camPos)
        part.CFrame = CFrame.new(d.pos)
        return d
    end
    local function tuneRain()
        local folder = rainFolder()
        local I = iAmt()
        local n = math.clamp(math.floor(150 * iRate(I, 1.75, 0.85)), 16, RAIN_MAX)
        local drops = _rain.drops
        local camPos = Vec(0, 0, 0)
        if Camera then
            camPos = Camera.CFrame.Position
        end
        for i = #drops, n + 1, -1 do
            drops[i].part:Destroy()
            drops[i] = nil
        end
        for i = #drops + 1, n do
            drops[i] = newDrop(folder, i, camPos)
        end
        local sm = 0.55 + 0.45 * I
        local wm = 0.85 + 0.15 * I
        local am = 0.78 + 0.22 * I
        local dir = _rain.applied or _rain.dir or RAIN_DIR
        for i = 1, n do
            local d = drops[i]
            d.spd = d.spd0 * sm
            d.len = d.base * sm
            d.a1.Position = dir * d.len
            local w = d.w0 * wm
            d.beam.Width0 = w
            d.beam.Width1 = w * 0.55
            d.beam.Transparency = NumberSequence.new(math.clamp(1 - (1 - d.t0) * am, 0.02, 1))
        end
    end
    local function buildRain()
        if _rain.folder then pcall(function() _rain.folder:Destroy() end); _rain.folder = nil end
        table.clear(_rain.drops)
        if not _rain.dir then _rain.dir = RAIN_DIR end
        _rain.applied = _rain.dir
        tuneRain()
    end
    local function startRain()
        if _rain.conn then return end
        _rain.conn = RunService.Heartbeat:Connect(function(dt)
            if not Config.Weather or _curType ~= "Rain" then return end
            local cam = Camera; if not cam then return end
            local camPos = cam.CFrame.Position
            local lx, lz = Wind.x * RAIN_LEAN_K, Wind.z * RAIN_LEAN_K
            local lm = math.sqrt(lx * lx + lz * lz)
            if lm > RAIN_LEAN_MAX then
                local s = RAIN_LEAN_MAX / lm
                lx, lz = lx * s, lz * s
            end
            local step = _rain.dir:Lerp(Vec(lx, -1, lz).Unit, math.min(dt * 2, 1)).Unit
            _rain.dir = step
            if (step - _rain.applied).Magnitude > 0.015 then
                _rain.applied = step
                for i = 1, #_rain.drops do
                    local d = _rain.drops[i]
                    d.a1.Position = step * d.len
                end
            end
            local r2 = RAIN_RADIUS * RAIN_RADIUS
            for i = 1, #_rain.drops do
                local d = _rain.drops[i]
                local p = d.pos + step * (d.spd * dt)
                local relX, relY, relZ = p.X - camPos.X, p.Y - camPos.Y, p.Z - camPos.Z
                if relY < RAIN_BOT or (relX * relX + relZ * relZ) > r2 then
                    seedDrop(d, camPos)
                    p = d.pos
                end
                d.pos = p
                if d.part then d.part.CFrame = CFrame.new(p) end
            end
        end)
    end
    local function stopRain()
        if _rain.conn then _rain.conn:Disconnect(); _rain.conn = nil end
        if _rain.folder then pcall(function() _rain.folder:Destroy() end); _rain.folder = nil end
        table.clear(_rain.drops)
        _rain.dir = nil; _rain.applied = nil
    end
    local ND = Enum.NormalId
    local function flutterSeq(lo, hi, n, env, flip)
        local kps = table.create(n + 1)
        for i = 0, n do
            local v = lo
            if (i + flip) % 2 == 1 then
                v = hi
            end
            kps[i + 1] = NumberSequenceKeypoint.new(i / n, v, env)
        end
        return NumberSequence.new(kps)
    end
    local PRESETS = {
        Snow = {
            { size=Vec(22,4,22), oy=5, tex=TX_FLAKE, color=WHITE,
              skeys={{0,1.7,0.35},{1,1.35,0.3}}, squash=-0.12, transp0=0.18,transp1=0.55,
              rate=0.7, speed={0.8,1.6}, life={5,7}, spread=28, rot={-60,60}, rotSpd=26,
              accel=Vec(0,-2.4,0), drag=2.2, glow=0.2, dir=ND.Bottom,
              gust={ax=1.8,az=1.2,wx=0.4,wz=0.31,ph=0.5} },
            { size=Vec(46,4,46), oy=10, tex=TX_SNOWSOFT, color=WHITE,
              skeys={{0,0.48,0.15},{1,0.38,0.10}}, squash=-0.05, transp0=0.7,transp1=0.92,
              rate=12, speed={1.5,3}, life={5,8}, spread=45, rot={-180,180}, rotSpd=10,
              accel=Vec(0,-3.5,0), drag=1.8, glow=0.12, dir=ND.Bottom,
              gust={ax=2.5,az=1.6,wx=0.37,wz=0.29,ph=0} },
            { size=Vec(140,4,140), oy=20, tex=TX_FLAKE, color=Color3.fromRGB(242,248,255),
              skeys={{0,0.5,0.2},{1,0.38,0.14}}, squash=-0.08, transp0=0.08,transp1=0.5,
              rate=190, speed={2,4}, life={7,10}, spread=50, rot={-180,180}, rotSpd=42,
              accel=Vec(0,-5,0), drag=1.7, glow=0.35, dir=ND.Bottom,
              gust={ax=2.2,az=1.4,wx=0.33,wz=0.26,ph=1.9} },
            { size=Vec(220,4,220), oy=32, tex=TX_SNOWSOFT, color=Color3.fromRGB(214,231,255),
              skeys={{0,0.3,0.08},{1,0.22,0.06}}, transp0=0.5,transp1=0.85,
              rate=265, speed={2,4}, life={8,11}, spread=55, rot={-30,30}, rotSpd=12,
              accel=Vec(0,-5.5,0), drag=1.5, glow=0.3, dir=ND.Bottom,
              gust={ax=1.5,az=1,wx=0.29,wz=0.25,ph=3.8} },
            { size=Vec(100,4,100), oy=12, tex=TX_SPARK, color=WHITE,
              skeys={{0,0.4,0.12},{1,0.32,0.1}},
              tkeys={{0,1},{0.2,0.5},{0.45,0.78},{0.62,0.42},{0.85,0.78},{1,1}},
              rate=10, speed={2,4}, life={5,8}, spread=45, rot={-180,180}, rotSpd=60,
              accel=Vec(0,-4.5,0), drag=1.6, glow=0.7, dir=ND.Bottom,
              gust={ax=2.2,az=1.4,wx=0.35,wz=0.27,ph=1} },
        },
        Mist = {
            { size=Vec(150,8,150), oy=0, tex=TX_SOFT, color=Color3.fromRGB(210,216,226),
              size0=26,size1=44, transp0=0.68,transp1=0.94,
              rate=16, speed={0.8,2.2}, life={9,13}, spread=20, rot={-5,5}, rotSpd=3,
              accel=Vec(2.2,0.25,1.2), drag=0.8, dir=ND.Top },
            { size=Vec(110,6,110), oy=1, tex=TX_SOFT, color=Color3.fromRGB(228,232,240),
              size0=12,size1=22, transp0=0.75,transp1=0.95,
              rate=10, speed={1.5,3}, life={6,9}, spread=25, rot={-8,8}, rotSpd=5,
              accel=Vec(3,0.4,1.6), drag=0.8, dir=ND.Top },
        },
        Embers = {
            { size=Vec(90,28,90), oy=2, tex=TX_SOFT, color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0,   Color3.fromRGB(255,170,60)),
                  ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255,95,25)),
                  ColorSequenceKeypoint.new(1,   Color3.fromRGB(165,35,12)) }),
              size0=0.85,size1=0.3, transp0=0.05,transp1=0.85,
              rate=80, speed={3,7}, life={3,5}, spread=40, rot={-60,60}, rotSpd=90,
              accel=Vec(1.5,9,1), drag=1.6, glow=0.35, dir=ND.Top },
            { size=Vec(120,30,120), oy=6, tex=TX_SPARK, color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0, Color3.fromRGB(255,220,140)),
                  ColorSequenceKeypoint.new(1, Color3.fromRGB(255,110,40)) }),
              size0=0.3,size1=0.08, transp0=0.05,transp1=0.9,
              rate=55, speed={2,5}, life={2.5,4}, spread=55, rot={-40,40}, rotSpd=60,
              accel=Vec(1,7,0.8), drag=1.4, glow=0.9, dir=ND.Top },
        },
        Fireflies = {
            { size=Vec(70,8,70), oy=-2, tex=TX_SNOWSOFT, color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0,   Color3.fromRGB(220,255,130)),
                  ColorSequenceKeypoint.new(0.5, Color3.fromRGB(205,245,100)),
                  ColorSequenceKeypoint.new(1,   Color3.fromRGB(255,200,80)) }),
              skeys={{0,0.1},{0.08,0.62,0.15},{0.45,0.5,0.1},{1,0.08}},
              tkeys={{0,1},{0.08,0.08},{0.4,0.45},{0.75,0.85},{1,1}},
              rate=18, speed={0.5,1.6}, life={2.5,4}, spread=180, rot={0,0}, rotSpd=0,
              accel=Vec(0,0.3,0), drag=2.5, glow=0.95, dir=ND.Top },
            { size=Vec(140,14,140), oy=-1, tex=TX_SNOWSOFT, color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0, Color3.fromRGB(175,225,95)),
                  ColorSequenceKeypoint.new(1, Color3.fromRGB(200,190,70)) }),
              skeys={{0,0.06},{0.1,0.32,0.08},{0.5,0.26},{1,0.05}},
              tkeys={{0,1},{0.1,0.3},{0.5,0.6},{1,1}},
              rate=18, speed={0.4,1.2}, life={3,5}, spread=180, rot={0,0}, rotSpd=0,
              accel=Vec(0,0.3,0), drag=2.5, glow=0.95, dir=ND.Top },
            { size=Vec(120,4,120), oy=-4, tex=TX_PUFF, color=Color3.fromRGB(148,158,178),
              size0=13,size1=22, tkeys={{0,1},{0.2,0.8},{0.7,0.89},{1,1}},
              rate=8, speed={0.5,1.5}, life={8,12}, spread=14, rot={-180,180}, rotSpd=4,
              accel=Vec(1.2,0.12,0.7), drag=0.7, glow=0, dir=ND.Top,
              gust={ax=1.2,az=0.8,wx=0.23,wz=0.19,ph=2.2} },
        },
        Petals = {
            { size=Vec(26,6,26), oy=3, tex=TX_SNOWSOFT, zoff=3, color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0, Color3.fromRGB(255,222,232)),
                  ColorSequenceKeypoint.new(1, Color3.fromRGB(250,205,220)) }),
              skeys={{0,1.75,0.5},{1,1.4,0.3}}, transp0=0.78,transp1=0.92,
              rate=7, speed={0.4,1.1}, life={5,7}, spread=30, rot={-180,180}, rotSpd=22,
              accel=Vec(0,-3,0), drag=1.7, glow=0.04, dir=ND.Bottom,
              gust={ax=2.2,az=1.5,wx=0.43,wz=0.33,ph=1.4} },
            { size=Vec(64,12,64), oy=5, tex=TX_PETAL, color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0,    Color3.fromRGB(255,222,234)),
                  ColorSequenceKeypoint.new(0.55, Color3.fromRGB(248,178,206)),
                  ColorSequenceKeypoint.new(1,    Color3.fromRGB(226,132,176)) }),
              skeys={{0,2.05,0.5},{1,1.7,0.35}}, qseq=flutterSeq(-0.88, 0.08, 14, 0.12, 0),
              transp0=0.1,transp1=0.38,
              rate=13, speed={0.6,1.4}, life={6,8}, spread=35, rot={-180,180}, rotSpd=95,
              accel=Vec(0,-3.5,0), drag=1.6, glow=0.08, dir=ND.Bottom,
              gust={ax=2.6,az=1.8,wx=0.4,wz=0.31,ph=0.5} },
            { size=Vec(76,12,76), oy=7, tex=TX_PETAL, color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0,    Color3.fromRGB(250,224,200)),
                  ColorSequenceKeypoint.new(0.55, Color3.fromRGB(244,203,178)),
                  ColorSequenceKeypoint.new(1,    Color3.fromRGB(230,176,150)) }),
              skeys={{0,1.55,0.4},{1,1.28,0.28}}, qseq=flutterSeq(-0.8, 0.15, 12, 0.15, 1),
              transp0=0.14,transp1=0.44,
              rate=12, speed={0.8,1.8}, life={6,8.5}, spread=42, rot={-180,180}, rotSpd=140,
              accel=Vec(0,-3.2,0), drag=1.55, glow=0.05, dir=ND.Bottom,
              gust={ax=3,az=2,wx=0.37,wz=0.29,ph=2.1} },
            { size=Vec(130,6,130), oy=15, tex=TX_PETAL, color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0, Color3.fromRGB(255,222,234)),
                  ColorSequenceKeypoint.new(1, Color3.fromRGB(246,178,204)) }),
              skeys={{0,0.85,0.26},{1,0.68,0.18}}, qseq=flutterSeq(-0.7, 0.1, 8, 0.2, 0),
              transp0=0.06,transp1=0.44,
              rate=120, speed={1.4,3}, life={7,9}, spread=48, rot={-180,180}, rotSpd=170,
              accel=Vec(0,-5.2,0), drag=1.5, glow=0.1, dir=ND.Bottom,
              gust={ax=3.2,az=2.2,wx=0.33,wz=0.26,ph=1.9} },
            { size=Vec(240,6,240), oy=26, tex=TX_PETAL, color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0, Color3.fromRGB(250,214,228)),
                  ColorSequenceKeypoint.new(1, Color3.fromRGB(238,190,210)) }),
              skeys={{0,0.3,0.09},{1,0.24,0.06}}, squash=-0.5, transp0=0.42,transp1=0.8,
              rate=170, speed={1.5,3.2}, life={8,11}, spread=55, rot={-180,180}, rotSpd=90,
              accel=Vec(0,-6,0), drag=1.35, glow=0.08, dir=ND.Bottom,
              gust={ax=2.4,az=1.6,wx=0.29,wz=0.25,ph=3.8} },
            { size=Vec(56,1.2,56), oy=-3.7, tex=TX_PETAL, tag="settle",
              color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0, Color3.fromRGB(255,214,228)),
                  ColorSequenceKeypoint.new(1, Color3.fromRGB(240,178,204)) }),
              skeys={{0,1.1,0.3},{1,0.95,0.2}}, qseq=flutterSeq(-0.92, -0.2, 10, 0.1, 0),
              transp0=0.05,transp1=0.42,
              rate=34, speed={0.05,0.5}, life={14,20}, spread=90, rot={-180,180}, rotSpd=25,
              accel=Vec(0,-0.15,0), drag=2.6, glow=0.08, dir=ND.Bottom,
              gust={ax=3.6,az=3,wx=0.5,wz=0.44,ph=0.9} },
        },
        Autumn = {
            { size=Vec(20,6,20), oy=13, uw=8, tex=TX_LEAFA, color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0,    Color3.fromRGB(226,190,128)),
                  ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255,246,200)),
                  ColorSequenceKeypoint.new(1,    Color3.fromRGB(190,132,62)) }),
              skeys={{0,0.62,0.14},{1,0.54,0.10}}, qseq=flutterSeq(-0.60, 0.14, 13, 0.10, 0),
              transp0=0.08,transp1=0.42,
              rate=14, speed={0.6,1.6}, life={7,9}, spread=34, rot={-180,180}, rotSpd=130,
              accel=Vec(0,-5,0), drag=1.5, glow=0.62, dir=ND.Bottom,
              gust={ax=3.4,az=2.2,wx=0.41,wz=0.3,ph=0.5} },
            { size=Vec(22,6,22), oy=15, uw=8, tex=TX_LEAFB, color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0, Color3.fromRGB(156,74,255)),
                  ColorSequenceKeypoint.new(1, Color3.fromRGB(106,46,200)) }),
              skeys={{0,0.60,0.14},{1,0.52,0.10}}, qseq=flutterSeq(-0.56, 0.20, 11, 0.14, 1),
              transp0=0.12,transp1=0.46,
              rate=9, speed={0.8,1.9}, life={7,9}, spread=40, rot={-180,180}, rotSpd=185,
              accel=Vec(0,-5.6,0), drag=1.5, glow=0.07, dir=ND.Bottom,
              gust={ax=3.9,az=2.6,wx=0.36,wz=0.27,ph=2.1} },
            { size=Vec(150,8,150), oy=16, uw=26, tex=TX_LEAFA, color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0,    Color3.fromRGB(226,190,128)),
                  ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255,246,200)),
                  ColorSequenceKeypoint.new(1,    Color3.fromRGB(190,132,62)) }),
              skeys={{0,0.56,0.16},{1,0.44,0.11}}, qseq=flutterSeq(-0.50, 0.10, 8, 0.16, 0),
              transp0=0.08,transp1=0.50,
              rate=24, speed={1.4,3}, life={7,9}, spread=54, rot={-180,180}, rotSpd=210,
              accel=Vec(0,-7,0), drag=1.45, glow=0.62, dir=ND.Bottom,
              gust={ax=4.2,az=2.8,wx=0.33,wz=0.24,ph=1.9} },
            { size=Vec(150,8,150), oy=16, uw=26, tex=TX_LEAFB, color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0, Color3.fromRGB(160,80,52)),
                  ColorSequenceKeypoint.new(1, Color3.fromRGB(104,44,30)) }),
              skeys={{0,0.54,0.16},{1,0.42,0.11}}, qseq=flutterSeq(-0.54, 0.14, 9, 0.16, 1),
              transp0=0.10,transp1=0.50,
              rate=21, speed={1.4,3.1}, life={7,9}, spread=54, rot={-180,180}, rotSpd=200,
              accel=Vec(0,-7.2,0), drag=1.45, glow=0.07, dir=ND.Bottom,
              gust={ax=4,az=2.7,wx=0.31,wz=0.26,ph=3.3} },
            { size=Vec(150,8,150), oy=16, uw=26, tex=TX_LEAFA, color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0,   Color3.fromRGB(230,222,176)),
                  ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255,254,228)),
                  ColorSequenceKeypoint.new(1,   Color3.fromRGB(200,180,122)) }),
              skeys={{0,0.52,0.15},{1,0.41,0.10}}, qseq=flutterSeq(-0.52, 0.12, 10, 0.16, 1),
              transp0=0.10,transp1=0.52,
              rate=17, speed={1.3,2.9}, life={7,9}, spread=52, rot={-180,180}, rotSpd=190,
              accel=Vec(0,-6.8,0), drag=1.45, glow=0.60, dir=ND.Bottom,
              gust={ax=4.1,az=2.7,wx=0.35,wz=0.28,ph=2.7} },
            { size=Vec(150,8,150), oy=16, uw=26, tex=TX_LEAFB, color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0, Color3.fromRGB(156,74,255)),
                  ColorSequenceKeypoint.new(1, Color3.fromRGB(106,46,200)) }),
              skeys={{0,0.53,0.16},{1,0.42,0.11}}, qseq=flutterSeq(-0.52, 0.16, 9, 0.16, 0),
              transp0=0.10,transp1=0.50,
              rate=12, speed={1.4,3.1}, life={7,9}, spread=54, rot={-180,180}, rotSpd=220,
              accel=Vec(0,-7.1,0), drag=1.45, glow=0.07, dir=ND.Bottom,
              gust={ax=4,az=2.7,wx=0.3,wz=0.25,ph=5.1} },
            { size=Vec(150,8,150), oy=16, uw=20, tex=TX_LEAFC, color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0, Color3.fromRGB(196,156,112)),
                  ColorSequenceKeypoint.new(1, Color3.fromRGB(146,110,74)) }),
              skeys={{0,0.50,0.15},{1,0.40,0.10}}, qseq=flutterSeq(-0.52, 0.10, 7, 0.16, 0),
              transp0=0.14,transp1=0.55,
              rate=11, speed={1.5,3.2}, life={7,9}, spread=56, rot={-180,180}, rotSpd=240,
              accel=Vec(0,-7.6,0), drag=1.45, glow=0.08, dir=ND.Bottom,
              gust={ax=3.8,az=2.6,wx=0.29,wz=0.23,ph=0.9} },
            { size=Vec(150,8,150), oy=16, uw=26, tex=TX_LEAFA, color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0, Color3.fromRGB(152,255,255)),
                  ColorSequenceKeypoint.new(1, Color3.fromRGB(118,214,240)) }),
              skeys={{0,0.52,0.15},{1,0.41,0.10}}, qseq=flutterSeq(-0.50, 0.14, 8, 0.16, 1),
              transp0=0.12,transp1=0.52,
              rate=10, speed={1.4,3}, life={7,9}, spread=54, rot={-180,180}, rotSpd=195,
              accel=Vec(0,-7,0), drag=1.45, glow=0.16, dir=ND.Bottom,
              gust={ax=4.1,az=2.7,wx=0.34,wz=0.27,ph=4.2} },
            { size=Vec(300,30,300), oy=30, uw=60, tex=TX_LEAFA, color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0,    Color3.fromRGB(226,190,128)),
                  ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255,246,200)),
                  ColorSequenceKeypoint.new(1,    Color3.fromRGB(190,132,62)) }),
              skeys={{0,0.24,0.06},{1,0.18,0.04}}, squash=-0.35, transp0=0.68,transp1=0.92,
              rate=30, speed={1.5,3.2}, life={8,11}, spread=55, rot={-180,180}, rotSpd=110,
              accel=Vec(0,-8,0), drag=1.35, glow=0.55, dir=ND.Bottom,
              gust={ax=3.1,az=2.1,wx=0.27,wz=0.24,ph=1.2} },
            { size=Vec(300,30,300), oy=30, uw=60, tex=TX_LEAFB, color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0, Color3.fromRGB(160,80,52)),
                  ColorSequenceKeypoint.new(1, Color3.fromRGB(104,44,30)) }),
              skeys={{0,0.23,0.06},{1,0.17,0.04}}, squash=-0.35, transp0=0.70,transp1=0.93,
              rate=24, speed={1.5,3.2}, life={8,11}, spread=55, rot={-180,180}, rotSpd=120,
              accel=Vec(0,-8,0), drag=1.35, glow=0.07, dir=ND.Bottom,
              gust={ax=3,az=2,wx=0.29,wz=0.22,ph=3.8} },
            { size=Vec(120,16,120), oy=6, tex=TX_LEAFA, tag="streak", aim=true,
              orient=Enum.ParticleOrientation.VelocityParallel,
              color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0,    Color3.fromRGB(226,190,128)),
                  ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255,246,200)),
                  ColorSequenceKeypoint.new(1,    Color3.fromRGB(190,132,62)) }),
              skeys={{0,0.66,0.16},{1,0.46,0.10}}, squash=-0.55,
              tkeys={{0,1},{0.08,0.06},{0.72,0.34},{1,1}},
              rate=0, speed={16,26}, life={1,1.9}, spread=13, rot={-180,180}, rotSpd=300,
              accel=Vec(0,-3.4,0), drag=2.6, glow=0.62, dir=ND.Front,
              gust={ax=5,az=4,wx=0.4,wz=0.35,ph=0} },
            { size=Vec(120,16,120), oy=5, tex=TX_LEAFB, tag="streak", aim=true,
              orient=Enum.ParticleOrientation.VelocityParallel,
              color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0, Color3.fromRGB(160,80,52)),
                  ColorSequenceKeypoint.new(1, Color3.fromRGB(104,44,30)) }),
              skeys={{0,0.62,0.16},{1,0.44,0.10}}, squash=-0.55,
              tkeys={{0,1},{0.08,0.08},{0.72,0.38},{1,1}},
              rate=0, speed={15,24}, life={1,1.8}, spread=14, rot={-180,180}, rotSpd=280,
              accel=Vec(0,-3.6,0), drag=2.6, glow=0.07, dir=ND.Front,
              gust={ax=5,az=4,wx=0.37,wz=0.33,ph=1.7} },
            { size=Vec(96,0.9,96), oy=-3.9, tex=TX_LEAFA, tag="settle",
              color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0,   Color3.fromRGB(200,150,86)),
                  ColorSequenceKeypoint.new(0.5, Color3.fromRGB(168,110,58)),
                  ColorSequenceKeypoint.new(1,   Color3.fromRGB(130,80,44)) }),
              skeys={{0,0.50,0.14},{1,0.44,0.10}}, qseq=flutterSeq(-0.62, -0.05, 10, 0.1, 0),
              transp0=0.06,transp1=0.46,
              rate=34, speed={0.8,3.2}, life={10,16}, spread=90, rot={-180,180}, rotSpd=90,
              accel=Vec(0,-0.15,0), drag=3.2, glow=0.32, dir=ND.Bottom,
              gust={ax=9,az=8,wx=0.5,wz=0.44,ph=0.9} },
            { size=Vec(70,0.8,70), oy=-3.85, tex=TX_LEAFB, tag="settle",
              color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0, Color3.fromRGB(160,80,52)),
                  ColorSequenceKeypoint.new(1, Color3.fromRGB(104,44,30)) }),
              skeys={{0,0.54,0.12},{1,0.46,0.08}}, qseq=flutterSeq(-0.66, 0.26, 16, 0.06, 0),
              transp0=0.05,transp1=0.44,
              rate=14, speed={0.6,2.2}, life={3,5}, spread=70, rot={-180,180}, rotSpd=340,
              accel=Vec(0,-1.2,0), drag=1.9, glow=0.10, dir=ND.Top,
              gust={ax=8,az=7,wx=0.62,wz=0.55,ph=2.4} },
            { size=Vec(74,0.6,74), oy=-3.95, tex=TX_LEAFC, tag="settle",
              orient=Enum.ParticleOrientation.VelocityPerpendicular,
              color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0, Color3.fromRGB(190,146,96)),
                  ColorSequenceKeypoint.new(1, Color3.fromRGB(150,110,72)) }),
              skeys={{0,0.76,0.16},{1,0.72,0.12}}, squash=0, transp0=0.04,transp1=0.30,
              rate=42, speed={0.04,0.1}, life={20,28}, spread=90, rot={-180,180}, rotSpd=3,
              accel=Vec(0,-0.12,0), drag=4, glow=0.22, dir=ND.Bottom },
            { size=Vec(80,0.8,80), oy=-4, tex=TX_DUST, tag="dust",
              color=ColorSequence.new({
                  ColorSequenceKeypoint.new(0, Color3.fromRGB(206,180,140)),
                  ColorSequenceKeypoint.new(1, Color3.fromRGB(150,124,92)) }),
              skeys={{0,1.1,0.35},{1,3.4,0.5}}, tkeys={{0,1},{0.18,0.84},{0.7,0.93},{1,1}},
              rate=0, speed={2,6}, life={1.1,2}, spread=85, rot={-180,180}, rotSpd=22,
              accel=Vec(0,0.6,0), drag=2.4, glow=0.06, dir=ND.Top,
              gust={ax=8,az=7,wx=0.4,wz=0.35,ph=0} },
        },
        Ash = {
            { size=Vec(110,4,110), oy=16, tex=TX_SOFT, color=Color3.fromRGB(96,90,86),
              size0=0.4,size1=0.3, transp0=0.05,transp1=0.5,
              rate=140, speed={2,4}, life={6,9}, spread=45, rot={-60,60}, rotSpd=45,
              accel=Vec(-3.5,-5,2), drag=1.6, glow=0, dir=ND.Bottom },
            { size=Vec(170,4,170), oy=26, tex=TX_SPARK, color=Color3.fromRGB(255,140,70),
              size0=0.14,size1=0.05, transp0=0.15,transp1=0.9,
              rate=26, speed={1.5,3.5}, life={4,7}, spread=60, rot={-40,40}, rotSpd=70,
              accel=Vec(-2.5,-2,1.5), drag=1.5, glow=0.9, dir=ND.Bottom },
        },
        Sandstorm = {
            { size=Vec(160,20,160), oy=6, tex=TX_SOFT, color=Color3.fromRGB(194,168,120),
              size0=24,size1=38, transp0=0.58,transp1=0.93,
              rate=24, speed={8,15}, life={5,8}, spread=28, rot={-8,8}, rotSpd=6,
              accel=Vec(20,0.5,7), drag=0.6, dir=ND.Right },
        },
    }
    Weather.TypeOrder = { "Rain", "Snow", "Mist", "Embers", "Fireflies", "Petals", "Autumn",
                          "Ash", "Sandstorm", "BloodMoon" }
    local MOOD = {
        Rain      = { B=-0.03, C=0.08,  S=-0.12, tint=Color3.fromRGB(205,220,255) },
        Snow      = { B= 0.03, C=0.05,  S=-0.08, tint=Color3.fromRGB(226,240,255) },
        Mist      = { B=-0.01, C=-0.05, S=-0.20, tint=Color3.fromRGB(220,224,230) },
        Embers    = { B= 0.02, C=0.08,  S= 0.10, tint=Color3.fromRGB(255,238,220) },
        Fireflies = { B=-0.04, C=0.06,  S= 0.02, tint=Color3.fromRGB(238,228,205) },
        Petals    = { B= 0.00, C=0.09,  S= 0.05, tint=Color3.fromRGB(255,234,234) },
        Autumn    = { B= 0.005, C=0.08, S= 0.04, tint=Color3.fromRGB(253,244,232) },
        Ash       = { B=-0.04, C=0.06,  S=-0.25, tint=Color3.fromRGB(225,220,215) },
        Sandstorm = { B=-0.02, C=0.10,  S= 0.05, tint=Color3.fromRGB(224,196,150) },
        BloodMoon = { B=-0.05, C=0.12,  S=-0.20, tint=Color3.fromRGB(255,180,180) },
    }
    local SOUND = { Rain="rain", Snow="wind", Mist="wind", Embers="fire",
                    Fireflies="night", Petals="birds", Autumn="wind", Ash="wind",
                    Sandstorm="wind", BloodMoon="night" }
    local function ambientId(mood)
        local map = cfg("WeatherSoundIds", nil)
        if type(map) == "table" and map[mood] and map[mood] ~= "" then return map[mood] end
        return nil
    end
    local _partLayers = {}
    local _ambient  = nil
    local _moodCC   = nil
    local _moodTween = nil
    local FADE_TI = TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
    local MOOD_TI = TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
    local _followConn = nil
    local _lightFolder = nil
    local _rays = nil
    local _special = { moon = nil, shell = nil, sky = nil, cc = nil, atmo = nil, halo = nil, kind = nil }
    local _specialConn = nil
    local _clockConn = nil
    local function clearPartLayers()
        for _, L in _partLayers do
            if L.rateTween then L.rateTween:Cancel() end
            if L.host then pcall(function() L.host:Destroy() end) end
        end
        table.clear(_partLayers)
    end
    local _fadeLayers = {}
    local _fadeToken = 0
    local function killFade()
        _fadeToken = _fadeToken + 1
        for _, F in _fadeLayers do
            local host = F.host
            pcall(function() host:Destroy() end)
        end
        table.clear(_fadeLayers)
    end
    local function beginLayerFade()
        killFade()
        local maxLife = 0
        for _, L in _partLayers do
            if L.rateTween then L.rateTween:Cancel() end
            if L.emitter then
                TweenService:Create(L.emitter, FADE_TI, { Rate = 0 }):Play()
            end
            if L.life2 > maxLife then maxLife = L.life2 end
            _fadeLayers[#_fadeLayers + 1] = { host = L.host, oy = L.oy }
        end
        table.clear(_partLayers)
        local tok = _fadeToken
        task.delay(FADE_TI.Time + maxLife, function()
            if tok == _fadeToken then killFade() end
        end)
    end
    local _spectacles, _spectWeight, _spectNextT = {}, 0, 0
    local function registerSpectacle(name, weight, fn)
        _spectacles[#_spectacles + 1] = { name = name, weight = weight, fn = fn }
        _spectWeight = _spectWeight + weight
    end
    local _blizzT0, _blizzDur = 0, 1
    local function layerRate(L, I)
        if L.spec.tag == "settle" then
            return L.spec.rate * iRate(I, SET_LO, SET_HI)
        end
        return L.spec.rate * iRate(I, L.ir.lo, L.ir.hi)
    end
    local function tuneLayer(L, I)
        local spec, R, e = L.spec, L.ir, L.emitter
        local am = 1
        if spec.tag ~= "settle" then
            am = 1 - R.acc + R.acc * I
        end
        L.accel = spec.accel * am
        if not spec.gust then
            e.Acceleration = L.accel
        end
        e.Speed = NumberRange.new(spec.speed[1] * am, spec.speed[2] * am)
        if spec.gust then
            local gm = 1 - R.gst + R.gst * I
            L.gax, L.gaz = spec.gust.ax * gm, spec.gust.az * gm
        end
        local sm = 1 - R.sz + R.sz * I
        if spec.skeys then
            local ks = spec.skeys
            local kps = table.create(#ks)
            for i = 1, #ks do
                local k = ks[i]
                kps[i] = NumberSequenceKeypoint.new(k[1], k[2] * sm, (k[3] or 0) * sm)
            end
            e.Size = NumberSequence.new(kps)
        else
            e.Size = NumberSequence.new(spec.size0 * sm, spec.size1 * sm)
        end
        if not spec.tkeys then
            local om = 1 - R.alp + R.alp * I
            e.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0,    1),
                NumberSequenceKeypoint.new(0.12, math.clamp(1 - (1 - spec.transp0) * om, 0, 1)),
                NumberSequenceKeypoint.new(0.8,  math.clamp(1 - (1 - spec.transp1) * om, 0, 1)),
                NumberSequenceKeypoint.new(1,    1),
            })
        end
    end
    local function mkPartLayer(spec, ir, rampIn)
        local host = Instance.new("Part")
        host.Name = "_wxHost"; host.Anchored = true; host.CanCollide = false; host.CanQuery = false
        host.CanTouch = false; host.CastShadow = false; host.Transparency = 1; host.Massless = true
        host.Size = spec.size; host:SetAttribute("WX_Custom", true)
        host.Parent = getFolder()
        local e = Instance.new("ParticleEmitter")
        e:SetAttribute("WX_Custom", true)
        e.Texture = spec.tex
        local colorSeq = spec.color
        if typeof(colorSeq) ~= "ColorSequence" then
            colorSeq = ColorSequence.new(colorSeq)
        end
        e.Color = colorSeq
        local glow = spec.glow or 0
        e.LightEmission  = glow
        e.LightInfluence = 1 - math.min(glow, 1)
        e.Lifetime = NumberRange.new(spec.life[1], spec.life[2])
        e.SpreadAngle = Vector2.new(spec.spread, spec.spread)
        local rot0, rot1 = 0, 360
        if spec.rot then
            rot0, rot1 = spec.rot[1], spec.rot[2]
        end
        e.Rotation = NumberRange.new(rot0, rot1)
        e.RotSpeed = NumberRange.new(-(spec.rotSpd or 45), spec.rotSpd or 45)
        if spec.qseq then
            e.Squash = spec.qseq
        else
            e.Squash = NumberSequence.new(spec.squash or 0)
        end
        if spec.tkeys then
            local kps = table.create(#spec.tkeys)
            for i = 1, #spec.tkeys do kps[i] = NumberSequenceKeypoint.new(spec.tkeys[i][1], spec.tkeys[i][2]) end
            e.Transparency = NumberSequence.new(kps)
        end
        e.Drag = spec.drag or 0
        e.ZOffset = spec.zoff or 0
        e.EmissionDirection = spec.dir
        if spec.orient then
            e.Orientation = spec.orient
        end
        e.Parent = host
        local L = { host = host, oy = spec.oy, emitter = e, spec = spec, ir = ir,
                    accel = spec.accel, gust = spec.gust, tag = spec.tag,
                    gax = 0, gaz = 0, rateMul = 1,
                    uw = spec.uw, aim = spec.aim,
                    life2 = spec.life[2], rateTween = nil }
        local I = iAmt()
        tuneLayer(L, I)
        local targetRate = layerRate(L, I)
        if rampIn then
            e.Rate = 0
            L.rateTween = TweenService:Create(e, FADE_TI, { Rate = targetRate })
            L.rateTween:Play()
        else
            e.Rate = targetRate
        end
        _partLayers[#_partLayers + 1] = L
    end
    local function clearMood()
        if _moodTween then _moodTween:Cancel(); _moodTween = nil end
        if _moodCC then pcall(function() _moodCC:Destroy() end); _moodCC = nil end
    end
    local function applyMood(name)
        if not cfg("WeatherMood", true) then
            clearMood()
            return
        end
        local m = MOOD[name]
        if not m then
            clearMood()
            return
        end
        if _moodTween then _moodTween:Cancel(); _moodTween = nil end
        local g = 0.6 + 0.4 * iAmt()
        local cc = _moodCC
        if cc and cc.Parent then
            _moodTween = TweenService:Create(cc, MOOD_TI,
                { Brightness = m.B * g, Contrast = m.C * g, Saturation = m.S * g, TintColor = m.tint })
            _moodTween:Play()
            return
        end
        cc = Instance.new("ColorCorrectionEffect")
        cc.Name = "_wxMood"; cc:SetAttribute("WX_Custom", true)
        cc.Brightness = m.B * g; cc.Contrast = m.C * g; cc.Saturation = m.S * g; cc.TintColor = m.tint
        cc.Parent = Lighting
        _moodCC = cc
    end
    local function startAmbient(mood)
        if _ambient then pcall(function() _ambient:Destroy() end); _ambient = nil end
        local id = mood and ambientId(mood)
        if not id then return end
        local s = Instance.new("Sound")
        s.Name = "_wxAmb"; s:SetAttribute("WX_Custom", true)
        s.SoundId = id; s.Looped = true; s.Volume = cfg("WeatherSoundVolume", 0.35)
        s.Parent = SoundService
        pcall(function() s:Play() end)
        _ambient = s
    end
    local function oneShot(id, vol, pitch)
        if not id or id == "" then return end
        local s = Instance.new("Sound")
        s.Name = "_wxSfx"; s:SetAttribute("WX_Custom", true)
        s.SoundId = id; s.Volume = math.clamp(vol, 0, 10)
        if pitch then s.PlaybackSpeed = pitch end
        s.Parent = SoundService
        pcall(function() s:Play() end)
        Debris:AddItem(s, 8)
    end
    local function getLightFolder()
        if _lightFolder and _lightFolder.Parent then return _lightFolder end
        local f = Instance.new("Folder"); f.Name = "_wxBolts"; f:SetAttribute("WX_Custom", true)
        f.Parent = getFolder()
        _lightFolder = f; return f
    end
    local function mkBoltPart(color, transp, size, cf, parent)
        local p = Instance.new("Part")
        p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
        p.CastShadow = false; p.Massless = true; p.Material = Enum.Material.Neon
        p.Color = color; p.Transparency = transp; p:SetAttribute("WX_Custom", true)
        p.Size = size; p.CFrame = cf; p.Parent = parent
        return p
    end
    local startStorm, stopStormLoop, stopStorm, rescheduleStorm
    ;(function()
        local TX_BGLOW   = "rbxassetid://78582616787441"
        local TX_BSTREAK = "rbxassetid://102481842205398"
        local BOLT_CORE  = Color3.fromRGB(245, 242, 255)
        local BOLT_GLOW  = Color3.fromRGB(162, 145, 255)
        local BOLT_AFTER = Color3.fromRGB(126, 96, 228)
        local ROT90 = CFrame.Angles(0, math.rad(90), 0)
        local FLICK = 0.12
        local _stormConn, _stormNextT = nil, 0
        local _boltRp = RaycastParams.new()
        _boltRp.FilterType = Enum.RaycastFilterType.Exclude
        local function mkSeg(color, transp, dia, len, cf, parent)
            local p = Instance.new("Part")
            p.Shape = Enum.PartType.Cylinder
            p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
            p.CastShadow = false; p.Massless = true; p.Material = Enum.Material.Neon
            p.Color = color; p.Transparency = transp; p:SetAttribute("WX_Custom", true)
            p.Size = Vec(len, dia, dia); p.CFrame = cf * ROT90; p.Parent = parent
            return p
        end
        local function boltChannel(model, segs, top, bot, n, thick, jitter, layer3)
            local pts = { top }
            local prev = top
            local driftAng = math.random() * 6.283
            for i = 1, n do
                local t = i / n
                local point = top:Lerp(bot, t)
                if i < n then
                    driftAng = driftAng + (math.random() - 0.5) * 2.2
                    local j = jitter * (0.5 + 0.5 * (1 - t))
                    local off = j * (0.3 + math.random() * 0.7)
                    point = point + Vec(math.cos(driftAng) * off, (math.random() - 0.5) * j * 0.25, math.sin(driftAng) * off)
                end
                local len = math.max((point - prev).Magnitude, 0.1)
                local cf = CFrame.lookAt((point + prev) * 0.5, point)
                segs[#segs + 1] = { p = mkSeg(BOLT_CORE, 0.02, thick, len + thick * 1.6, cf, model), on = 0.02, fade = 0.16 }
                segs[#segs + 1] = { p = mkSeg(BOLT_GLOW, 0.78, thick * 5.5, len + thick * 1.8, cf, model), on = 0.78, fade = 0.38 }
                if layer3 then
                    segs[#segs + 1] = { p = mkSeg(BOLT_AFTER, 0.88, thick * 2.2, len + thick * 1.6, cf, model), on = 0.75, fade = 0.85 }
                end
                pts[#pts + 1] = point
                prev = point
            end
            return pts
        end
        local function boltBranch(model, segs, fromPts, groundY, thick, depth)
            local count = 1
            if depth == 1 then count = math.random(2, 4) end
            for _ = 1, count do
                local idx = math.random(math.floor(#fromPts * 0.2), math.floor(#fromPts * 0.7))
                local a = fromPts[math.max(idx, 2)]
                local ang = math.random() * 6.283
                local drop = (a.Y - groundY) * (0.3 + math.random() * 0.25)
                local outw = drop * (0.55 + math.random() * 0.4)
                local endp = a + Vec(math.cos(ang) * outw, -drop, math.sin(ang) * outw)
                local n = 5
                if depth == 1 then n = 8 end
                local blen = (endp - a).Magnitude
                local pts = boltChannel(model, segs, a, endp, n, thick, math.max(5, blen * 0.1) / depth, false)
                if depth < 3 and math.random() < 0.5 then
                    boltBranch(model, segs, pts, groundY, thick * 0.45, depth + 1)
                end
            end
        end
        local function preFlash(pos, scale)
            local host = mkBoltPart(BOLT_CORE, 1, Vec(2, 2, 2), CFrame.new(pos), getLightFolder())
            local e = Instance.new("ParticleEmitter")
            e:SetAttribute("WX_Custom", true)
            e.Texture = TX_BGLOW
            e.Color = ColorSequence.new(Color3.fromRGB(206, 192, 255))
            e.LightEmission = 0.85; e.LightInfluence = 0
            e.Size = NumberSequence.new(60 * scale, 85 * scale)
            e.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.55),
                NumberSequenceKeypoint.new(0.7, 0.75), NumberSequenceKeypoint.new(1, 1),
            })
            e.Lifetime = NumberRange.new(0.22, 0.3)
            e.Rate = 0; e.Speed = NumberRange.new(0, 0.5)
            e.Parent = host
            e:Emit(1)
            task.delay(0.09, function() pcall(function() e:Emit(1) end) end)
            Debris:AddItem(host, 1.2)
        end
        local function screenFlash()
            local cc = Instance.new("ColorCorrectionEffect")
            cc.Name = "_wxFlash"; cc:SetAttribute("WX_Custom", true); cc.Brightness = 0.35; cc.Parent = Lighting
            local pulseA = 0.3 + math.random() * 0.25
            local pulseB = -1
            if math.random() < 0.6 then pulseB = pulseA + 0.18 + math.random() * 0.12 end
            local st = tick(); local c2
            c2 = RunService.Heartbeat:Connect(function()
                if not cc.Parent then if c2 then c2:Disconnect() end return end
                local a = (tick() - st) / 0.45
                if a >= 1 then pcall(function() cc:Destroy() end); if c2 then c2:Disconnect() end return end
                local b = 0.35 * (1 - a)
                if a >= pulseA and a < pulseA + 0.14 then
                    b = b + 0.22 * (1 - (a - pulseA) / 0.14)
                elseif pulseB > 0 and a >= pulseB and a < pulseB + 0.14 then
                    b = b + 0.16 * (1 - (a - pulseB) / 0.14)
                end
                cc.Brightness = b
            end)
            Debris:AddItem(cc, 0.7)
        end
        local function igniteBolt(ground, top)
            local model = Instance.new("Model"); model.Name = "_bolt"; model:SetAttribute("WX_Custom", true)
            local segs = {}
            local mainPts = boltChannel(model, segs, top, ground, 18, 1.0, 14, true)
            boltBranch(model, segs, mainPts, ground.Y, 0.55, 1)
            local dome = mkBoltPart(Color3.fromRGB(228, 240, 255), 0.5, Vec(0.6, 5, 5),
                CFrame.new(ground + Vec(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), model)
            dome.Shape = Enum.PartType.Cylinder
            local fl = Instance.new("PointLight"); fl.Color = BOLT_GLOW; fl.Range = 150; fl.Brightness = 8; fl.Parent = dome
            TweenService:Create(dome, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { Size = Vec(0.6, 30, 30), Transparency = 1 }):Play()
            TweenService:Create(fl, TweenInfo.new(0.5), { Brightness = 0 }):Play()
            local cb = mkBoltPart(BOLT_CORE, 1, Vec(2, 2, 2), CFrame.new(ground + Vec(0, 1.5, 0)), model)
            local ce = Instance.new("ParticleEmitter")
            ce:SetAttribute("WX_Custom", true)
            ce.Texture = TX_BGLOW
            ce.Color = ColorSequence.new(Color3.fromRGB(235, 228, 255))
            ce.LightEmission = 1; ce.LightInfluence = 0
            ce.Size = NumberSequence.new(13, 17)
            ce.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1),
            })
            ce.Lifetime = NumberRange.new(0.3, 0.4)
            ce.Rate = 0; ce.Speed = NumberRange.new(0, 0.1)
            ce.Parent = cb
            local se = Instance.new("ParticleEmitter")
            se:SetAttribute("WX_Custom", true)
            se.Texture = TX_BSTREAK
            se.Color = ColorSequence.new(Color3.fromRGB(220, 205, 255))
            se.LightEmission = 1; se.LightInfluence = 0
            se.Size = NumberSequence.new(2, 3)
            se.Transparency = NumberSequence.new(0.25, 1)
            se.Lifetime = NumberRange.new(0.5, 0.9)
            se.Rate = 0; se.Speed = NumberRange.new(26, 44)
            se.SpreadAngle = Vector2.new(38, 38)
            se.Orientation = Enum.ParticleOrientation.VelocityParallel
            se.EmissionDirection = Enum.NormalId.Top
            se.Acceleration = Vec(0, -40, 0)
            se.Parent = cb
            ce:Emit(1)
            se:Emit(9)
            model.Parent = getLightFolder()
            preFlash(top + Vec(0, 10, 0), 1.5)
            local flickEnd = FLICK
            local restrikeAt = -1
            if math.random() < 0.3 then restrikeAt = FLICK + 0.08 + math.random() * 0.07 end
            local startT = tick(); local conn
            conn = RunService.Heartbeat:Connect(function()
                if not model.Parent then if conn then conn:Disconnect() end return end
                local a = tick() - startT
                if restrikeAt > 0 and a >= restrikeAt then
                    restrikeAt = -1
                    flickEnd = a + 0.1
                    fl.Brightness = 6
                    TweenService:Create(fl, TweenInfo.new(0.4), { Brightness = 0 }):Play()
                end
                if a < flickEnd then
                    local dim = 0
                    if math.random() < 0.28 then dim = 0.85 end
                    for i = 1, #segs do
                        local s = segs[i]
                        s.p.Transparency = s.on + (1 - s.on) * dim
                    end
                    return
                end
                local f = a - flickEnd
                if f >= 0.85 then
                    if conn then conn:Disconnect() end
                    pcall(function() model:Destroy() end)
                    return
                end
                for i = 1, #segs do
                    local s = segs[i]
                    local k = math.clamp(f / s.fade, 0, 1)
                    s.p.Transparency = s.on + (1 - s.on) * k
                end
            end)
            Debris:AddItem(model, 1.8)
            if cfg("WeatherStormFlash", true) then screenFlash() end
            local tid = cfg("WeatherThunderId", "")
            if tid ~= "" then
                local cam = Camera
                local dist = 120
                if cam then dist = (ground - cam.CFrame.Position).Magnitude end
                task.delay(dist * (3 / 343), function()
                    oneShot(tid, cfg("WeatherSoundVolume", 0.35) * 8 * (0.85 + math.random() * 0.3),
                        0.92 + math.random() * 0.16)
                end)
            end
        end
        local function spawnBolt()
            if not Config.Weather or not cfg("WeatherStorm", false) then return end
            local cam = Camera; if not cam then return end
            local base = cam.CFrame.Position
            local lv = cam.CFrame.LookVector
            local flat = Vec(lv.X, 0, lv.Z)
            if flat.Magnitude < 0.05 then flat = Vec(0, 0, -1) else flat = flat.Unit end
            local right = Vec(flat.Z, 0, -flat.X)
            local fwd  = 55 + math.random() * 95
            local side = (math.random() - 0.5) * 85
            local gx = base.X + flat.X * fwd + right.X * side
            local gz = base.Z + flat.Z * fwd + right.Z * side
            local ground = Vec(gx + (math.random() - 0.5) * 20, base.Y - 45, gz + (math.random() - 0.5) * 20)
            local ch = lp and lp.Character
            if ch then
                _boltRp.FilterDescendantsInstances = { getFolder(), ch }
            else
                _boltRp.FilterDescendantsInstances = { getFolder() }
            end
            local hit = Workspace:Raycast(Vec(gx, base.Y + 140, gz), Vec(0, -400, 0), _boltRp)
            if hit then ground = hit.Position end
            local top = Vec(gx + (math.random() - 0.5) * 90, base.Y + 280, gz + (math.random() - 0.5) * 90)
            preFlash(Vec(top.X, top.Y - 20, top.Z), 1)
            task.delay(0.1 + math.random() * 0.2, function()
                if not Config.Weather or not cfg("WeatherStorm", false) then return end
                pcall(function() igniteBolt(ground, top) end)
            end)
        end
        function startStorm()
            if _stormConn then return end
            _stormNextT = tick() + 2 + math.random() * 3
            _stormConn = RunService.Heartbeat:Connect(function()
                if not Config.Weather or not cfg("WeatherStorm", false) then return end
                local now = tick()
                if now >= _stormNextT then
                    _stormNextT = now + cfg("WeatherStormMin", 4)
                        + math.random() * cfg("WeatherStormVar", 8)
                    pcall(spawnBolt)
                end
            end)
        end
        function rescheduleStorm()
            if not _stormConn then
                return
            end
            local cap = tick() + cfg("WeatherStormMin", 4) + cfg("WeatherStormVar", 8)
            _stormNextT = math.min(_stormNextT, cap)
        end
        function stopStormLoop()
            if _stormConn then _stormConn:Disconnect(); _stormConn = nil end
        end
        function stopStorm()
            stopStormLoop()
            if _lightFolder then pcall(function() _lightFolder:Destroy() end); _lightFolder = nil end
        end
        registerSpectacle("StormBarrage", 1, function()
            if not Config.Weather or not cfg("WeatherStorm", false) then return end
            for i = 0, 2 do
                task.delay(i * (0.35 + math.random() * 0.3), function() pcall(spawnBolt) end)
            end
        end)
    end)()
    local function startFollow()
        if _followConn then return end
        local now0 = tick()
        Wind.reset(now0)
        _spectNextT = now0 + 120 + math.random() * 120
        _followConn = RunService.Heartbeat:Connect(function()
            if not Config.Weather then return end
            local now = tick()
            Wind.update(now)
            local amb = _ambient
            if amb then
                local vol = cfg("WeatherSoundVolume", 0.35)
                if amb.Volume ~= vol then amb.Volume = vol end
            end
            local cam = Camera; if not cam then return end
            local pos = cam.CFrame.Position
            if now >= _spectNextT then
                _spectNextT = now + 120 + math.random() * 120
                if _spectWeight > 0 then
                    local r = math.random() * _spectWeight
                    for i = 1, #_spectacles do
                        local s = _spectacles[i]
                        r = r - s.weight
                        if r <= 0 then
                            pcall(s.fn)
                            break
                        end
                    end
                end
            end
            local wgain = 1
            local bt = (now - _blizzT0) / _blizzDur
            if bt >= 0 and bt < 1 then
                wgain = 1 + 1.7 * math.sin(bt * math.pi)
            end
            local nwx, nwz = 1, 0
            local wl = math.sqrt(Wind.x * Wind.x + Wind.z * Wind.z)
            if wl > 0.05 then
                nwx = Wind.x / wl
                nwz = Wind.z / wl
            end
            for i = 1, #_partLayers do
                local L = _partLayers[i]
                if L.host and L.host.Parent then
                    local hx, hz = pos.X, pos.Z
                    if L.uw then
                        hx = hx - nwx * L.uw
                        hz = hz - nwz * L.uw
                    end
                    local hy = pos.Y + L.oy
                    if L.aim then
                        L.host.CFrame = CFrame.lookAt(Vec(hx, hy, hz), Vec(hx + nwx, hy, hz + nwz))
                    else
                        L.host.CFrame = CFrame.new(hx, hy, hz)
                    end
                    local g = L.gust
                    if g then
                        L.emitter.Acceleration = L.accel + Vec(
                            Wind.x * wgain * L.gax * (1 + 0.3 * math.sin(now * g.wx + g.ph)), 0,
                            Wind.z * wgain * L.gaz * (1 + 0.3 * math.cos(now * g.wz + g.ph)))
                    end
                end
            end
            for i = 1, #_fadeLayers do
                local F = _fadeLayers[i]
                if F.host and F.host.Parent then
                    F.host.CFrame = CFrame.new(pos.X, pos.Y + F.oy, pos.Z)
                end
            end
        end)
    end
    local function stopFollow()
        if _followConn then _followConn:Disconnect(); _followConn = nil end
    end
    do
        local SWELL_UP = TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
        local SWELL_DOWN = TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
        local function windSwell(kind, dur, rateMul)
            if not Config.Weather or _curType ~= kind then return end
            _blizzT0, _blizzDur = tick(), dur
            local surged = {}
            local I = iAmt()
            for _, L in _partLayers do
                if L.emitter and L.tag ~= "settle" then
                    if L.rateTween then L.rateTween:Cancel() end
                    L.rateMul = rateMul
                    local tw = TweenService:Create(L.emitter, SWELL_UP, { Rate = layerRate(L, I) * rateMul })
                    L.rateTween = tw
                    tw:Play()
                    surged[#surged + 1] = L
                end
            end
            task.delay(dur - 3, function()
                local I2 = iAmt()
                for _, L in surged do
                    local live = false
                    for _, cur in _partLayers do
                        if cur == L then live = true break end
                    end
                    if live and L.emitter and L.emitter.Parent then
                        if L.rateTween then L.rateTween:Cancel() end
                        L.rateMul = 1
                        local tw = TweenService:Create(L.emitter, SWELL_DOWN, { Rate = layerRate(L, I2) })
                        L.rateTween = tw
                        tw:Play()
                    end
                end
            end)
        end
        registerSpectacle("SnowBlizzard", 1, function()
            windSwell("Snow", 11 + math.random() * 3, 1.9)
        end)
        registerSpectacle("SakuraGale", 1, function()
            windSwell("Petals", 9 + math.random() * 4, 1.7)
        end)
    end
    do
        local GUST_UP   = TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
        local GUST_DOWN = TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
        local STREAK_BURST = { {0.3, 18}, {0.65, 14}, {1.05, 9} }
        Wind.onGust(function(dur)
            if not Config.Weather or _curType ~= "Autumn" then return end
            local I = iAmt()
            local em = iRate(I, IR.Autumn.lo, IR.Autumn.hi)
            local gm = 1 + 0.4 * I
            local surged = {}
            for _, L in _partLayers do
                if L.emitter and L.tag == "dust" then
                    local e = L.emitter
                    local n2 = math.max(1, math.floor(10 * em + 0.5))
                    e:Emit(math.max(1, math.floor(14 * em + 0.5)))
                    task.delay(0.4, function()
                        if e.Parent then e:Emit(n2) end
                    end)
                elseif L.emitter and L.tag == "streak" then
                    local e = L.emitter
                    e:Emit(math.max(1, math.floor(20 * em + 0.5)))
                    for _, b in STREAK_BURST do
                        local n = math.max(1, math.floor(b[2] * em + 0.5))
                        task.delay(b[1], function()
                            if e.Parent then e:Emit(n) end
                        end)
                    end
                elseif L.emitter and L.tag ~= "settle" then
                    if L.rateTween then L.rateTween:Cancel() end
                    L.rateMul = gm
                    local tw = TweenService:Create(L.emitter, GUST_UP, { Rate = layerRate(L, I) * gm })
                    L.rateTween = tw
                    tw:Play()
                    surged[#surged + 1] = L
                end
            end
            task.delay(dur, function()
                local I2 = iAmt()
                for _, L in surged do
                    local live = false
                    for _, cur in _partLayers do
                        if cur == L then live = true break end
                    end
                    if live and L.emitter and L.emitter.Parent then
                        if L.rateTween then L.rateTween:Cancel() end
                        L.rateMul = 1
                        local tw = TweenService:Create(L.emitter, GUST_DOWN, { Rate = layerRate(L, I2) })
                        L.rateTween = tw
                        tw:Play()
                    end
                end
            end)
        end)
    end
    local function clearSpecial()
        if _specialConn then _specialConn:Disconnect(); _specialConn = nil end
        if _special.moon  then pcall(function() _special.moon:Destroy() end);  _special.moon  = nil end
        if _special.shell then pcall(function() _special.shell:Destroy() end); _special.shell = nil end
        if _special.sky   then pcall(function() _special.sky:Destroy() end);   _special.sky   = nil end
        if _special.cc    then pcall(function() _special.cc:Destroy() end);    _special.cc    = nil end
        if _special.atmo  then pcall(function() _special.atmo:Destroy() end);  _special.atmo  = nil end
        _special.halo = nil
        _special.kind = nil
    end
    local function tuneBloodMoon(I)
        local ms = 0.72 + 0.28 * I
        local gr = 0.5 + 0.5 * I
        if _special.moon then
            _special.moon.Size = Vec(130, 130, 130) * ms
        end
        if _special.shell then
            _special.shell.Size = Vec(160, 160, 160) * ms
        end
        if _special.halo then
            _special.halo.Rate = 25 * iRate(I, 1.45, 1.05)
            _special.halo.Size = NumberSequence.new(330 * ms)
        end
        if _special.cc then
            _special.cc.Saturation = -0.15 * gr
            _special.cc.Brightness = -0.04 * gr
        end
        if _special.atmo then
            _special.atmo.Density = 0.12 + 0.18 * I
            _special.atmo.Haze    = 0.9 + 0.9 * I
            _special.atmo.Glare   = 0.4 + 0.4 * I
        end
        if _special.sky then
            _special.sky.StarCount = math.floor(4000 * (0.55 + 0.45 * I))
        end
    end
    local function buildBloodMoon()
        local folder = getFolder()
        local s = Instance.new("Sky"); s.Name = "_wxSkyBM"; s:SetAttribute("WX_Custom", true)
        s.SkyboxBk = "rbxassetid://159454299"; s.SkyboxDn = "rbxassetid://159454296"
        s.SkyboxFt = "rbxassetid://159454293"; s.SkyboxLf = "rbxassetid://159454286"
        s.SkyboxRt = "rbxassetid://159454300"; s.SkyboxUp = "rbxassetid://159454288"
        s.SunAngularSize = 0; s.MoonAngularSize = 0; s.StarCount = 4000
        s.Parent = Lighting; _special.sky = s
        local moon = Instance.new("Part")
        moon.Shape = Enum.PartType.Ball; moon.Size = Vec(130, 130, 130)
        moon.Material = Enum.Material.Neon; moon.Color = Color3.fromRGB(215, 45, 35)
        moon.Anchored = true; moon.CanCollide = false; moon.CanQuery = false; moon.CanTouch = false
        moon.CastShadow = false; moon.Massless = true; moon:SetAttribute("WX_Custom", true)
        local att = Instance.new("Attachment"); att.Parent = moon
        local halo = Instance.new("ParticleEmitter")
        halo.Texture = TX_SOFT; halo.Color = ColorSequence.new(Color3.fromRGB(255, 60, 42))
        halo.LightEmission = 1; halo.LightInfluence = 0
        halo.Rate = 25; halo.Lifetime = NumberRange.new(0.22, 0.28)
        halo.Speed = NumberRange.new(0, 0); halo.Size = NumberSequence.new(330)
        halo.Transparency = NumberSequence.new(0.72); halo.RotSpeed = NumberRange.new(0, 0)
        halo.Parent = att; _special.halo = halo
        moon.Parent = folder; _special.moon = moon
        local shell = Instance.new("Part")
        shell.Shape = Enum.PartType.Ball; shell.Size = Vec(160, 160, 160)
        shell.Material = Enum.Material.Neon; shell.Color = Color3.fromRGB(255, 60, 45); shell.Transparency = 0.7
        shell.Anchored = true; shell.CanCollide = false; shell.CanQuery = false; shell.CanTouch = false
        shell.CastShadow = false; shell.Massless = true; shell:SetAttribute("WX_Custom", true)
        shell.Parent = folder; _special.shell = shell
        local cc = Instance.new("ColorCorrectionEffect"); cc.Name = "_wxBM"; cc:SetAttribute("WX_Custom", true)
        cc.TintColor = Color3.fromRGB(255, 165, 160); cc.Saturation = -0.15; cc.Brightness = -0.04
        cc.Parent = Lighting; _special.cc = cc
        local at = Instance.new("Atmosphere"); at.Name = "_wxBMAtmo"; at:SetAttribute("WX_Custom", true)
        at.Density = 0.3; at.Color = Color3.fromRGB(125, 35, 35); at.Decay = Color3.fromRGB(190, 55, 50)
        at.Glare = 0.8; at.Haze = 1.8; at.Parent = Lighting; _special.atmo = at
        _special.kind = "BloodMoon"
        tuneBloodMoon(iAmt())
    end
    local function startSpecialAnim()
        if _specialConn then return end
        local accum = 0
        _specialConn = RunService.Heartbeat:Connect(function(dt)
            if not Config.Weather or not _special.kind then return end
            accum = accum + dt
            if accum < 0.1 then return end
            accum = 0
            local cam = Camera; if not cam then return end
            local pos = cam.CFrame.Position
            if _special.kind == "BloodMoon" and _special.moon then
                local cf = CFrame.new(pos + Vec(0.45, 0.62, -0.64).Unit * 700)
                _special.moon.CFrame = cf
                if _special.shell then _special.shell.CFrame = cf end
            end
        end)
    end
    local CSK, NSK = ColorSequenceKeypoint.new, NumberSequenceKeypoint.new
    local TX_MGLOW = "rbxassetid://78582616787441"
    local startMeteors, stopMeteors, rescheduleMeteors
    ;(function()
        local MET_TXS  = "rbxassetid://77935321198144"
        local MET_TXK  = "rbxassetid://102481842205398"
        local MET_TXD  = "rbxassetid://341828512"
        local MET_HAZE = Color3.fromRGB(128, 146, 176)
        local MET_GLOW = {
            { z = -0.80, size = 0.85, tr = 0.03, col = Color3.fromRGB(255, 246, 216), life = 0.09, rate = 34, b0 = 1.35, b1 = 2.1 },
            { z = -0.10, size = 1.75, tr = 0.55, col = Color3.fromRGB(255, 194, 106), life = 0.10, rate = 30, b0 = 0.85, b1 = 1.4 },
            { z =  1.30, size = 3.10, tr = 0.80, col = Color3.fromRGB(255, 124,  46), life = 0.11, rate = 26, b0 = 0.5, b1 = 0.8 },
            { z =  3.20, size = 5.20, tr = 0.92, col = Color3.fromRGB(224,  72,  26), life = 0.12, rate = 22, b0 = 0.4, b1 = 0.6 },
        }
        local MET_ROCK = {
            { 1.00, 0.74, 1.28,  0.00,  0.00,  0.00, 0.25, 0.40, 0.18, 58, 51, 47, 0.00, true },
            { 0.70, 0.60, 0.76,  0.40,  0.20,  0.12, 0.80, 0.50, 1.10, 47, 41, 39, 0.00, true },
            { 0.58, 0.48, 0.64, -0.38, -0.26,  0.34, 1.20, 0.90, 0.30, 36, 31, 30, 0.00, true },
            { 0.46, 0.40, 0.52,  0.06, -0.42, -0.24, 0.40, 1.30, 0.70, 52, 45, 42, 0.00, true },
            { 0.36, 0.30, 0.40, -0.32,  0.36, -0.08, 0.90, 0.20, 1.40, 42, 36, 34, 0.00, true },
            { 0.30, 0.26, 0.34,  0.22, -0.10,  0.46, 1.50, 0.70, 0.20, 38, 33, 32, 0.00, true },
            { 0.26, 0.34, 0.22, -0.20, -0.34, -0.02, 0.60, 1.10, 0.90, 33, 29, 28, 0.00, true },
            { 0.52, 0.40, 0.16,  0.10,  0.06, -0.56, 0.00, 0.00, 0.50, 255, 244, 214, 0.10, false },
            { 0.30, 0.46, 0.14, -0.30, -0.14, -0.44, 0.00, 0.00, -0.90, 255, 190, 104, 0.28, false },
            { 0.34, 0.20, 0.12,  0.16, -0.34, -0.40, 0.00, 0.00, 0.20, 255, 158,  66, 0.36, false },
            { 0.22, 0.16, 0.10, -0.10,  0.34, -0.38, 0.00, 0.00, 1.20, 255, 214, 150, 0.30, false },
        }
        local MET_ABL0 = 8
        local MET_ABLA = { 0.06, 0.20, 0.26, 0.22 }
        local MET_ABLK = { 0.20, 0.24, 0.26, 0.26 }
        local MET_UP, MET_DOWN = Vec(0, 300, 0), Vec(0, -800, 0)
        local _metConn = nil
        local _metNextFar, _metNextNear = 0, 0
        local _metFar, _metNear = 0, 0
        local _metLive = {}
        local _metRp = RaycastParams.new()
        _metRp.FilterType = Enum.RaycastFilterType.Exclude
        local function hz(c, k)
            return c:Lerp(MET_HAZE, k)
        end
        local function metPart(sx, sy, sz, cf)
            local p = Instance.new("Part")
            p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
            p.CastShadow = false; p.Massless = true
            p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
            p.Size = Vec(sx, sy, sz); p.CFrame = cf
            p:SetAttribute("WX_Custom", true)
            p.Parent = getLightFolder()
            return p
        end
        local function metFilter()
            local ch = nil
            if lp then ch = lp.Character end
            if ch then
                _metRp.FilterDescendantsInstances = { getFolder(), ch }
            else
                _metRp.FilterDescendantsInstances = { getFolder() }
            end
        end
        local function metSolveLand(base, out, tang)
            local d = 90 + math.random() * 110
            local lat = (math.random() - 0.5) * 160
            for _ = 1, 2 do
                local c = base + out * d + tang * lat
                local h = Workspace:Raycast(c + MET_UP, MET_DOWN, _metRp)
                if h then
                    return h.Position + Vec(0, 1.5, 0)
                end
                d = d * 0.5
                lat = lat * 0.5
            end
            return nil
        end
        local function metGlow(host, size, transp, color, life, rate)
            local g = Instance.new("ParticleEmitter")
            g:SetAttribute("WX_Custom", true)
            g.Texture = TX_MGLOW; g.Color = ColorSequence.new(color)
            g.LightEmission = 1; g.LightInfluence = 0
            g.Rate = rate; g.Lifetime = NumberRange.new(life, life)
            g.Size = NumberSequence.new(size); g.Transparency = NumberSequence.new(transp)
            g.Speed = NumberRange.new(0, 0); g.LockedToPart = true
            g.Parent = host
            return g
        end
        local function metRibbon(part, sep, c0, c1, a0, w1, life, emit, inf)
            local aT = Instance.new("Attachment"); aT.Position = Vec(0, sep * 0.5, 0); aT.Parent = part
            local aB = Instance.new("Attachment"); aB.Position = Vec(0, -sep * 0.5, 0); aB.Parent = part
            local tr = Instance.new("Trail")
            tr:SetAttribute("WX_Custom", true)
            tr.Attachment0 = aT; tr.Attachment1 = aB; tr.FaceCamera = true
            tr.Texture = TX_MGLOW; tr.TextureMode = Enum.TextureMode.Stretch; tr.TextureLength = 1
            tr.Color = ColorSequence.new(c0, c1)
            tr.Transparency = NumberSequence.new({ NSK(0, a0), NSK(0.6, a0 + (1 - a0) * 0.45), NSK(1, 1) })
            tr.WidthScale = NumberSequence.new({ NSK(0, 1), NSK(1, w1) })
            tr.Lifetime = life; tr.LightEmission = emit; tr.LightInfluence = inf
            tr.MinLength = 0.05
            tr.Parent = part
            return { t = tr, a = aT, b = aB, sep = sep }
        end
        local function metSmoke(host, sb, lo, hi, rate, aBase, drift, spread, k)
            local e = Instance.new("ParticleEmitter")
            e:SetAttribute("WX_Custom", true)
            e.Texture = MET_TXS
            e.Color = ColorSequence.new({
                CSK(0,   hz(Color3.fromRGB(178, 164, 152), k * 0.5)),
                CSK(0.2, hz(Color3.fromRGB(146, 142, 138), k * 0.5)),
                CSK(1,   hz(Color3.fromRGB(84, 82, 80), k * 0.5)) })
            e.LightEmission = 0.02; e.LightInfluence = 0.6
            e.Rate = rate; e.Lifetime = NumberRange.new(lo, hi)
            e.Size = NumberSequence.new({ NSK(0, sb), NSK(0.35, sb * 1.9), NSK(1, sb * 3) })
            e.Transparency = NumberSequence.new({
                NSK(0, 0.94), NSK(0.07, aBase + 0.16 * k), NSK(0.62, aBase + 0.16), NSK(1, 1) })
            e.Speed = NumberRange.new(0, spread); e.SpreadAngle = Vector2.new(60, 60)
            e.Drag = 0.5
            e.RotSpeed = NumberRange.new(-8, 8); e.Rotation = NumberRange.new(0, 360)
            e.Acceleration = Vec(Wind.x * drift, 0.35, Wind.z * drift)
            e.Parent = host
            return e
        end
        local function bez(p0, p1, p2, a)
            return p0:Lerp(p1, a):Lerp(p1:Lerp(p2, a), a)
        end
        local function metImpact(pos, sc)
            if Camera then
                sc = math.min(sc, math.max(0.85, (pos - Camera.CFrame.Position).Magnitude / 44))
            end
            local host = metPart(4 * sc, 4 * sc, 4 * sc, CFrame.new(pos))
            host.Shape = Enum.PartType.Ball; host.Material = Enum.Material.Neon
            host.Color = Color3.fromRGB(255, 240, 202); host.Transparency = 0.05
            local fl = Instance.new("PointLight")
            fl.Color = Color3.fromRGB(255, 176, 90); fl.Range = 150; fl.Brightness = 9; fl.Parent = host
            local glow = metPart(2, 2, 2, CFrame.new(pos + Vec(0, 3, 0)))
            glow.Transparency = 1
            local gl = Instance.new("PointLight")
            gl.Color = Color3.fromRGB(255, 148, 68); gl.Range = 120 * sc; gl.Brightness = 4; gl.Parent = glow
            local ring = metPart(12 * sc, 2 * sc, 12 * sc, CFrame.new(pos))
            ring.Shape = Enum.PartType.Ball; ring.Material = Enum.Material.Neon
            ring.Color = Color3.fromRGB(255, 150, 60); ring.Transparency = 0.35
            local scorch = metPart(15 * sc, 0.6, 15 * sc, CFrame.new(pos - Vec(0, 0.4, 0)))
            scorch.Shape = Enum.PartType.Ball; scorch.Material = Enum.Material.Neon
            scorch.Color = Color3.fromRGB(255, 104, 24); scorch.Transparency = 0.2
            local att = Instance.new("Attachment"); att.Parent = host
            local datt = Instance.new("Attachment"); datt.Orientation = Vec(0, 0, -90); datt.Parent = host
            local flash = Instance.new("ParticleEmitter")
            flash:SetAttribute("WX_Custom", true)
            flash.Texture = TX_MGLOW; flash.Rate = 0
            flash.Color = ColorSequence.new({
                CSK(0,    Color3.fromRGB(255, 246, 214)),
                CSK(0.45, Color3.fromRGB(255, 186, 96)),
                CSK(1,    Color3.fromRGB(226, 96, 34)) })
            flash.LightEmission = 1; flash.LightInfluence = 0
            flash.Lifetime = NumberRange.new(0.30, 0.30)
            flash.Size = NumberSequence.new({ NSK(0, 14 * sc), NSK(0.35, 34 * sc), NSK(1, 44 * sc) })
            flash.Transparency = NumberSequence.new({ NSK(0, 0.05), NSK(0.45, 0.42), NSK(1, 1) })
            flash.Speed = NumberRange.new(0, 0); flash.Rotation = NumberRange.new(0, 360)
            flash.Parent = att
            flash:Emit(2)
            local dust = Instance.new("ParticleEmitter")
            dust:SetAttribute("WX_Custom", true)
            dust.Texture = MET_TXD; dust.Rate = 0
            dust.Color = ColorSequence.new(Color3.fromRGB(198, 178, 152), Color3.fromRGB(120, 112, 104))
            dust.LightEmission = 0.05; dust.LightInfluence = 0.5
            dust.Lifetime = NumberRange.new(5.5, 9)
            dust.Size = NumberSequence.new({ NSK(0, 6 * sc), NSK(1, 22 * sc) })
            dust.Transparency = NumberSequence.new({ NSK(0, 0.6), NSK(0.1, 0.42), NSK(0.6, 0.68), NSK(1, 1) })
            dust.Speed = NumberRange.new(22, 38); dust.SpreadAngle = Vector2.new(0, 180)
            dust.Drag = 1.9; dust.EmissionDirection = ND.Top
            dust.RotSpeed = NumberRange.new(-16, 16); dust.Rotation = NumberRange.new(0, 360)
            dust.Acceleration = Vec(Wind.x * 6, 0.4, Wind.z * 6)
            dust.Parent = datt
            dust:Emit(math.floor(24 * sc))
            local fount = Instance.new("ParticleEmitter")
            fount:SetAttribute("WX_Custom", true)
            fount.Texture = MET_TXK; fount.Rate = 0
            fount.Color = ColorSequence.new(Color3.fromRGB(255, 200, 110), Color3.fromRGB(196, 52, 14))
            fount.LightEmission = 1; fount.LightInfluence = 0
            fount.Lifetime = NumberRange.new(1.1, 2.2)
            fount.Size = NumberSequence.new({ NSK(0, 1.7 * sc), NSK(1, 0.08) })
            fount.Transparency = NumberSequence.new({ NSK(0, 0), NSK(0.7, 0.35), NSK(1, 1) })
            fount.Orientation = Enum.ParticleOrientation.VelocityParallel
            fount.Speed = NumberRange.new(48, 96); fount.SpreadAngle = Vector2.new(30, 30)
            fount.Acceleration = Vec(0, -74, 0); fount.Drag = 0.35
            fount.EmissionDirection = ND.Top; fount.Parent = att
            fount:Emit(math.floor(52 * sc))
            local col = Instance.new("ParticleEmitter")
            col:SetAttribute("WX_Custom", true)
            col.Texture = TX_MGLOW; col.Rate = 0
            col.Color = ColorSequence.new({
                CSK(0,    Color3.fromRGB(255, 236, 180)),
                CSK(0.35, Color3.fromRGB(255, 130, 40)),
                CSK(1,    Color3.fromRGB(122, 40, 18)) })
            col.LightEmission = 0.9; col.LightInfluence = 0
            col.Lifetime = NumberRange.new(0.55, 1.05)
            col.Size = NumberSequence.new({ NSK(0, 5 * sc), NSK(1, 14 * sc) })
            col.Transparency = NumberSequence.new({ NSK(0, 0.12), NSK(0.6, 0.55), NSK(1, 1) })
            col.Speed = NumberRange.new(32, 62); col.SpreadAngle = Vector2.new(10, 10)
            col.EmissionDirection = ND.Top; col.Parent = att
            col:Emit(18)
            local pil = Instance.new("ParticleEmitter")
            pil:SetAttribute("WX_Custom", true)
            pil.Texture = MET_TXS; pil.Rate = 0
            pil.Color = ColorSequence.new({
                CSK(0,   Color3.fromRGB(186, 150, 118)),
                CSK(0.3, Color3.fromRGB(146, 140, 132)),
                CSK(1,   Color3.fromRGB(88, 85, 82)) })
            pil.LightEmission = 0.02; pil.LightInfluence = 0.5
            pil.Lifetime = NumberRange.new(4.5, 8)
            pil.Size = NumberSequence.new({ NSK(0, 4.5 * sc), NSK(1, 20 * sc) })
            pil.Transparency = NumberSequence.new({ NSK(0, 0.52), NSK(0.5, 0.68), NSK(1, 1) })
            pil.Speed = NumberRange.new(16, 30); pil.SpreadAngle = Vector2.new(9, 9)
            pil.Acceleration = Vec(Wind.x * 7, 2.6, Wind.z * 7); pil.Drag = 0.6
            pil.EmissionDirection = ND.Top
            pil.RotSpeed = NumberRange.new(-12, 12); pil.Rotation = NumberRange.new(0, 360)
            pil.Parent = att
            task.delay(0.12, function() if pil.Parent then pil:Emit(7) end end)
            task.delay(0.62, function() if pil.Parent then pil:Emit(5) end end)
            task.delay(1.30, function() if pil.Parent then pil:Emit(4) end end)
            local t0 = tick()
            local conn
            conn = RunService.Heartbeat:Connect(function()
                if not host.Parent then
                    conn:Disconnect()
                    return
                end
                local k = tick() - t0
                local f1 = math.clamp(k / 0.10, 0, 1)
                host.Size = Vec(1, 1, 1) * (4 + 6 * f1) * sc
                host.Transparency = 0.05 + 0.95 * f1
                fl.Brightness = 9 * (1 - math.clamp(k / 0.55, 0, 1))
                gl.Brightness = 4 * (1 - math.clamp(k / 5, 0, 1))
                local f2 = math.clamp(k / 0.55, 0, 1)
                ring.Size = Vec(12 + 52 * f2, 2 - 1.2 * f2, 12 + 52 * f2) * sc
                ring.Transparency = 0.35 + 0.65 * f2
                scorch.Transparency = 0.2 + 0.8 * math.clamp(k / 7, 0, 1)
                if k > 7.2 then
                    conn:Disconnect()
                end
            end)
            Debris:AddItem(ring, 1.1)
            Debris:AddItem(glow, 5.2)
            Debris:AddItem(scorch, 7.5)
            Debris:AddItem(host, 11)
        end
        local function launch(far, opts)
            local ang = math.random() * 6.28318
            local mul = 1
            local big = false
            if opts then
                if opts.ang then ang = opts.ang end
                if opts.scaleMul then mul = opts.scaleMul end
                big = opts.big == true
            end
            local tang = Vec(-math.sin(ang), 0, math.cos(ang))
            local out = Vec(math.cos(ang), 0, math.sin(ang))
            local sgn = 1
            if math.random() < 0.5 then sgn = -1 end
            local base = Camera.CFrame.Position
            local startP, endP, spd, rs, ws, k, doImpact, smk
            if far then
                local ctr = base + out * (1400 + math.random() * 1200)
                          + Vec(0, 820 + math.random() * 360, 0)
                local travel = 3000 + math.random() * 900
                local drop = 320 + math.random() * 200
                startP = ctr - tang * (travel * 0.5 * sgn) + Vec(0, drop * 0.5, 0)
                endP = ctr + tang * (travel * 0.5 * sgn) - Vec(0, drop * 0.5, 0)
                spd = 255 + math.random() * 70
                rs = 14 + math.random() * 5
                ws = 3.9 + math.random()
                k = 0.14 + math.random() * 0.10
                doImpact = false
                smk = 1.6
            else
                metFilter()
                local land = nil
                if opts and opts.land then
                    local h = Workspace:Raycast(opts.land + MET_UP, MET_DOWN, _metRp)
                    if h then land = h.Position + Vec(0, 1.5, 0) end
                end
                if not land then land = metSolveLand(base, out, tang) end
                doImpact = land ~= nil
                if not land then
                    land = base + out * 150 + Vec(0, 40, 0)
                end
                local travel = 1750 + math.random() * 450
                startP = land - tang * (travel * sgn) + out * (190 + math.random() * 190)
                         + Vec(0, 640 + math.random() * 160, 0)
                if opts and opts.start then startP = opts.start end
                endP = land
                spd = 175 + math.random() * 38
                rs = (7.0 + math.random() * 2.6) * mul
                ws = (1.3 + math.random() * 0.28) * mul
                k = 0
                smk = 1
            end
            if big then
                rs = rs * 1.7
                ws = ws * 1.5
                spd = spd * 0.92
            end
            local flare = far or (not doImpact)
            local splitAt = nil
            if big and not (opts and opts.noSplit) then
                splitAt = 0.42 + math.random() * 0.12
            end
            local mid = startP:Lerp(endP, 0.5) + Vec(0, (endP - startP).Magnitude * 0.075, 0)
            local dur = ((startP - mid).Magnitude + (mid - endP).Magnitude) / spd
            local cf0 = CFrame.lookAt(startP, endP)
            local root = metPart(0.2, 0.2, 0.2, cf0)
            root.Transparency = 1
            local a0 = Instance.new("Attachment"); a0.Parent = root
            local glows = table.create(4)
            for i, s in MET_GLOW do
                local hp = metPart(0.2, 0.2, 0.2, cf0)
                hp.Transparency = 1
                glows[i] = { p = hp, z = s.z * rs, b0 = s.b0, b1 = s.b1,
                    e = metGlow(hp, s.size * rs, math.min(0.97, s.tr + 0.18 * k),
                        hz(s.col, k * 0.55), s.life, s.rate) }
            end
            local chunks = table.create(#MET_ROCK)
            for i, r in MET_ROCK do
                local p = metPart(r[1] * rs, r[2] * rs, r[3] * rs, cf0)
                p.Transparency = r[13]
                if r[14] then
                    p.Material = Enum.Material.Slate
                    p.Color = Color3.fromRGB(r[10], r[11], r[12])
                else
                    p.Material = Enum.Material.Neon
                    p.Color = hz(Color3.fromRGB(r[10], r[11], r[12]), k * 0.4)
                end
                chunks[i] = { p = p, tumble = r[14],
                    off = CFrame.new(r[4] * rs, r[5] * rs, r[6] * rs) * CFrame.Angles(r[7], r[8], r[9]) }
            end
            local noseLight, bodyLight = nil, nil
            if not far then
                noseLight = Instance.new("PointLight")
                noseLight.Color = Color3.fromRGB(255, 186, 108)
                noseLight.Range = 4.2 * rs; noseLight.Brightness = 11
                noseLight.Parent = glows[1].p
                bodyLight = Instance.new("PointLight")
                bodyLight.Color = Color3.fromRGB(255, 150, 70)
                bodyLight.Range = 16 * rs; bodyLight.Brightness = 3
                bodyLight.Parent = root
            end
            local ha = 0.20 * k
            local ribbons = {
                metRibbon(root, 7.5 * ws, hz(Color3.fromRGB(255, 253, 248), k * 0.3),
                    hz(Color3.fromRGB(255, 226, 156), k * 0.6), ha, 0.45, 0.26, 1, 0),
                metRibbon(root, 14 * ws, hz(Color3.fromRGB(255, 222, 146), k * 0.5),
                    hz(Color3.fromRGB(255, 136, 40), k * 0.9), 0.06 + ha, 0.36, 0.72, 1, 0),
                metRibbon(root, 23 * ws, hz(Color3.fromRGB(255, 138, 42), k * 0.9),
                    hz(Color3.fromRGB(196, 50, 14), k), 0.22 + ha, 0.28, 1.85, 1, 0),
                metRibbon(root, 33 * ws, hz(Color3.fromRGB(196, 62, 18), k),
                    hz(Color3.fromRGB(88, 26, 14), k), 0.52 + ha, 0.30, 3.20, 0.55, 0.12),
            }
            local trainRate = math.clamp(spd / (17 * ws * 0.30 * smk), 6, 30)
            local train = metSmoke(a0, 17 * ws, 5, 7.5, trainRate, 0.56, 5.6, 3, k)
            local scarRate = math.clamp(spd / (50 * ws * 0.28 * smk), 1.6, 9)
            local scar = metSmoke(a0, 50 * ws, 20, 32, scarRate, 0.74, 7.8, 7, k)
            local sparks = nil
            if not far then
                sparks = Instance.new("ParticleEmitter")
                sparks:SetAttribute("WX_Custom", true)
                sparks.Texture = MET_TXK
                sparks.Color = ColorSequence.new(Color3.fromRGB(255, 172, 70), Color3.fromRGB(186, 44, 12))
                sparks.LightEmission = 1; sparks.LightInfluence = 0
                sparks.Rate = 60; sparks.Lifetime = NumberRange.new(0.6, 1.5)
                sparks.Size = NumberSequence.new({ NSK(0, 2.2 * ws), NSK(1, 0.06) })
                sparks.Transparency = NumberSequence.new({ NSK(0, 0.08), NSK(1, 1) })
                sparks.Orientation = Enum.ParticleOrientation.VelocityParallel
                sparks.Speed = NumberRange.new(6, 20); sparks.SpreadAngle = Vector2.new(32, 32)
                sparks.Acceleration = Vec(0, -12, 0); sparks.Drag = 0.6
                sparks.Parent = a0
            end
            if far then _metFar = _metFar + 1 else _metNear = _metNear + 1 end
            local rec = { root = root }
            _metLive[#_metLive + 1] = rec
            local t0 = tick()
            local ph = math.random() * 20
            local spinX, spinY, spinZ = (math.random() - 0.5) * 3, (math.random() - 0.5) * 3.4,
                0.6 + math.random() * 1.6
            local flareAt = 0.76 + math.random() * 0.10
            local shedAt = 0.25 + math.random() * 0.2
            local dead, endT = false, nil
            local conn
            local function retire()
                if dead then
                    return
                end
                dead = true
                if far then
                    _metFar = math.max(0, _metFar - 1)
                else
                    _metNear = math.max(0, _metNear - 1)
                end
                for i = #_metLive, 1, -1 do
                    if _metLive[i] == rec then table.remove(_metLive, i) end
                end
            end
            conn = RunService.Heartbeat:Connect(function()
                if not root.Parent then
                    conn:Disconnect()
                    retire()
                    return
                end
                local now = tick()
                local a = math.clamp((now - t0) / dur, 0, 1)
                local p = bez(startP, mid, endP, a)
                local d = (mid - startP) * (2 * (1 - a)) + (endP - mid) * (2 * a)
                if d.Magnitude < 1e-3 then d = endP - startP end
                local cf = CFrame.lookAt(p, p + d)
                local n = math.clamp(0.5 + 0.27 * math.sin(now * 41 + ph)
                    + 0.17 * math.sin(now * 67.3 + ph * 2.1)
                    + 0.09 * math.sin(now * 103.7 + ph * 0.7), 0, 1)
                local burn = 1
                if flare and a > flareAt then
                    local u = (a - flareAt) / (1 - flareAt)
                    burn = math.clamp((1 + 1.7 * math.exp(-((u - 0.14) ^ 2) / 0.011))
                        * (1 - u) ^ 1.5, 0, 3)
                end
                if endT then burn = burn * math.clamp(1 - (now - endT) / 0.4, 0, 1) end
                local bw = math.clamp(burn, 0, 1)
                if not endT then
                    root.CFrame = cf
                    for _, g in glows do
                        g.p.CFrame = cf * CFrame.new(0, 0, g.z)
                    end
                    local tum = CFrame.Angles(now * spinX, now * spinY, now * spinZ)
                    for _, c in chunks do
                        if c.tumble then
                            c.p.CFrame = cf * tum * c.off
                        else
                            c.p.CFrame = cf * c.off
                        end
                    end
                end
                for _, g in glows do
                    g.e.Brightness = (g.b0 + g.b1 * n) * burn
                end
                for i = 1, 4 do
                    local c = chunks[MET_ABL0 + i - 1]
                    c.p.Transparency = math.clamp(1 - (1 - (MET_ABLA[i] + MET_ABLK[i] * (1 - n))) * bw, 0, 1)
                end
                if noseLight then
                    noseLight.Brightness = (7 + 9 * n) * bw
                    bodyLight.Brightness = (2 + 3 * n) * bw
                end
                train.Rate = trainRate * bw
                scar.Rate = scarRate * bw
                if sparks then sparks.Rate = 60 * bw * (0.6 + 0.8 * n) end
                local pinch = (0.5 + 0.5 * bw) * (0.9 + 0.2 * n)
                for _, L in ribbons do
                    local h = L.sep * 0.5 * pinch
                    L.a.Position = Vec(0, h, 0)
                    L.b.Position = Vec(0, -h, 0)
                end
                if splitAt and a >= splitAt then
                    splitAt = nil
                    if sparks then sparks:Emit(30) end
                    for _ = 1, math.random(2, 3) do
                        launch(false, {
                            ang = ang,
                            noSplit = true,
                            scaleMul = 0.40 + math.random() * 0.14,
                            start = p + Vec((math.random() - 0.5) * 30, (math.random() - 0.5) * 20,
                                (math.random() - 0.5) * 30),
                            land = endP + Vec((math.random() - 0.5) * 110, 0, (math.random() - 0.5) * 110),
                        })
                    end
                end
                if (not far) and a > shedAt then
                    shedAt = 2
                    local fp = metPart(0.3 * rs, 0.24 * rs, 0.38 * rs, CFrame.new(p))
                    fp.Material = Enum.Material.Slate
                    fp.Color = Color3.fromRGB(40, 35, 33)
                    metRibbon(fp, 6, Color3.fromRGB(255, 220, 160), Color3.fromRGB(150, 34, 12),
                        0.12, 0.2, 0.8, 1, 0)
                    local fdir = (d.Unit * 0.65
                        + Vec(math.random() - 0.5, -0.5, math.random() - 0.5).Unit * 0.5).Unit
                    local fv, ft0 = fdir * spd * 0.6, tick()
                    local fc
                    fc = RunService.Heartbeat:Connect(function()
                        if not fp.Parent then
                            fc:Disconnect()
                            return
                        end
                        local age = tick() - ft0
                        if age > 2.4 then
                            fc:Disconnect()
                            fp:Destroy()
                            return
                        end
                        fv = fv + Vec(0, -0.88, 0)
                        fp.CFrame = CFrame.new(fp.Position + fv * 0.016)
                            * CFrame.Angles(age * 5, age * 3, age * 4)
                    end)
                end
                if not endT then
                    if a >= 1 then
                        endT = now
                        if doImpact then
                            metImpact(endP, rs * 0.215 + 0.6)
                            local tid = cfg("WeatherThunderId", "")
                            if tid ~= "" then
                                task.delay(0.15, function()
                                    oneShot(tid, cfg("WeatherSoundVolume", 0.35) * 6)
                                end)
                            end
                        end
                    elseif flare and burn < 0.02 and a > flareAt then
                        endT = now
                    end
                elseif now - endT >= 0.4 then
                    retire()
                    conn:Disconnect()
                    train.Enabled = false; scar.Enabled = false
                    if sparks then sparks.Enabled = false end
                    for _, g in glows do
                        g.e.Enabled = false
                        g.p:Destroy()
                    end
                    for _, L in ribbons do L.t.Enabled = false end
                    for _, c in chunks do c.p:Destroy() end
                    if noseLight then noseLight:Destroy(); bodyLight:Destroy() end
                    Debris:AddItem(root, 42)
                end
            end)
            Debris:AddItem(root, dur + 46)
        end
        local function spawnMeteor(far, opts)
            if not Config.Weather or not cfg("WeatherMeteors", false) then
                return
            end
            local r = evRate("WeatherMeteorRate")
            local capped
            if far then
                capped = _metFar >= math.clamp(math.floor(1 + 1.5 * r), 1, 4)
            elseif r >= 2.5 then
                capped = _metNear >= 3
            elseif r >= 1.5 then
                capped = _metNear >= 2
            else
                capped = _metNear >= 1
            end
            if capped then
                return
            end
            launch(far, opts)
        end
        startMeteors = function()
            if _metConn then
                return
            end
            local t = tick()
            _metNextFar = t + 1 + math.random() * 2
            _metNextNear = t + 5 + math.random() * 6
            _metConn = RunService.Heartbeat:Connect(function()
                if not Config.Weather or not cfg("WeatherMeteors", false) then
                    return
                end
                local now = tick()
                local r = evRate("WeatherMeteorRate")
                if now >= _metNextFar then
                    _metNextFar = now + (6 + math.random() * 5) / r
                    pcall(spawnMeteor, true)
                end
                if now >= _metNextNear then
                    _metNextNear = now + (14 + math.random() * 10) / r
                    pcall(spawnMeteor, false)
                end
            end)
        end
        rescheduleMeteors = function()
            if not _metConn then
                return
            end
            local now, r = tick(), evRate("WeatherMeteorRate")
            _metNextFar = math.min(_metNextFar, now + 11 / r)
            _metNextNear = math.min(_metNextNear, now + 24 / r)
        end
        stopMeteors = function()
            if _metConn then _metConn:Disconnect(); _metConn = nil end
            for _, rec in _metLive do
                pcall(function() rec.root:Destroy() end)
            end
            table.clear(_metLive)
        end
        registerSpectacle("MeteorBigOne", 1, function()
            if not Config.Weather or not cfg("WeatherMeteors", false) then
                return
            end
            launch(false, { big = true })
        end)
    end)()
    local startStars, stopStars, rescheduleStars
    ;(function()
        local TX_SGLOW = "rbxassetid://78582616787441"
        local TX_STAR4 = "rbxassetid://17726943419"
        local GLINT_C  = Color3.fromRGB(246, 250, 255)
        local MIN_SIN  = 0.3
        local FLOOR_H  = 60
        local PAL = {
            { WHITE, Color3.fromRGB(222, 234, 255), Color3.fromRGB(150, 184, 240) },
            { Color3.fromRGB(242, 250, 255), Color3.fromRGB(160, 206, 255), Color3.fromRGB(78, 138, 255) },
            { Color3.fromRGB(255, 246, 220), Color3.fromRGB(255, 205, 122), Color3.fromRGB(222, 140, 44) },
        }
        local CLS = {
            { 80, 55, 250, 105, 50, 28, 3.6 },
            { 145, 90, 158, 62, 76, 44, 5.4 },
            { 240, 150, 98, 46, 118, 62, 7.2 },
        }
        local TR_TRANSP  = NumberSequence.new({ NSK(0, 0.04), NSK(0.12, 0.12), NSK(0.45, 0.55), NSK(1, 1) })
        local TR_WIDTH   = NumberSequence.new({ NSK(0, 0.4), NSK(0.08, 1), NSK(1, 0.02) })
        local ION_TRANSP = NumberSequence.new({ NSK(0, 0.86), NSK(0.3, 0.9), NSK(1, 1) })
        local ION_WIDTH  = NumberSequence.new({ NSK(0, 0.5), NSK(0.25, 1), NSK(1, 0.35) })
        local HEAD_TR    = NumberSequence.new({ NSK(0, 1), NSK(0.05, 0), NSK(0.72, 0.06), NSK(1, 1) })
        local HALO_TR    = NumberSequence.new({ NSK(0, 1), NSK(0.07, 0.82), NSK(0.7, 0.88), NSK(1, 1) })
        local GLINT_TR   = NumberSequence.new({ NSK(0, 1), NSK(0.3, 0.12), NSK(0.55, 0.42), NSK(1, 1) })
        local _starConn, _starNextT = nil, 0
        local _starLive = {}
        local function mkSprite(parent, tex, col, sizeSeq, transpSeq, life, emit)
            local e = Instance.new("ParticleEmitter")
            e.Texture = tex
            e.Color = ColorSequence.new(col)
            e.Size = sizeSeq
            e.Transparency = transpSeq
            e.Lifetime = NumberRange.new(life)
            e.Rate = 0
            e.Speed = NumberRange.new(0, 0)
            e.SpreadAngle = Vector2.new(0, 0)
            e.LightEmission = emit
            e.LightInfluence = 0
            e.Drag = 0
            e.Parent = parent
            return e
        end
        local function spawnStreak(start, dir, ci, pi, floorY)
            if not Config.Weather or not cfg("WeatherShootingStars", false) then
                return
            end
            if #_starLive >= math.clamp(math.floor(4 + 2 * evRate("WeatherStarRate")), 4, 8) then
                return
            end
            local cls, pal = CLS[ci], PAL[pi]
            local dist = cls[1] + math.random() * cls[2]
            local spd  = cls[3] + math.random() * cls[4]
            local tail = cls[5] + math.random() * cls[6]
            if start.Y + dir.Y * dist < floorY then
                local ny = (floorY - start.Y) / dist
                local hl = math.sqrt(dir.X * dir.X + dir.Z * dir.Z)
                if hl > 1e-4 then
                    local k = math.sqrt(math.max(0, 1 - ny * ny)) / hl
                    dir = Vec(dir.X * k, ny, dir.Z * k)
                end
            end
            local dur  = dist / spd
            local life = math.min(tail / spd, dur * 0.9)
            local sep  = cls[7] * (0.85 + math.random() * 0.3)
            local glintD = 0.3 + math.random() * 0.3
            local cf0 = CFrame.lookAt(start, start + dir)
            local host = mkBoltPart(WHITE, 1, Vec(0.2, 0.2, 0.2), cf0, getLightFolder())
            local aT = Instance.new("Attachment"); aT.Position = Vec(0, sep * 0.5, 0); aT.Parent = host
            local aB = Instance.new("Attachment"); aB.Position = Vec(0, -sep * 0.5, 0); aB.Parent = host
            local tr = Instance.new("Trail")
            tr.Attachment0 = aT; tr.Attachment1 = aB
            tr.FaceCamera = true
            tr.Texture = TX_SGLOW; tr.TextureMode = Enum.TextureMode.Stretch; tr.TextureLength = 1
            tr.Color = ColorSequence.new({ CSK(0, pal[1]), CSK(0.24, pal[2]), CSK(1, pal[3]) })
            tr.Transparency = TR_TRANSP; tr.WidthScale = TR_WIDTH
            tr.Lifetime = life; tr.LightEmission = 1; tr.LightInfluence = 0
            tr.MinLength = 0.08; tr.Enabled = false
            tr.Parent = host
            local ion = nil
            if ci == 3 then
                ion = Instance.new("Trail")
                ion.Attachment0 = aT; ion.Attachment1 = aB
                ion.FaceCamera = true
                ion.Texture = TX_SGLOW; ion.TextureMode = Enum.TextureMode.Stretch; ion.TextureLength = 1
                ion.Color = ColorSequence.new({ CSK(0, pal[2]), CSK(1, pal[3]) })
                ion.Transparency = ION_TRANSP; ion.WidthScale = ION_WIDTH
                ion.Lifetime = life * 2.6; ion.LightEmission = 0.85; ion.LightInfluence = 0
                ion.MinLength = 0.1; ion.Enabled = false
                ion.Parent = host
            end
            local hub = Instance.new("Attachment"); hub.Parent = host
            local coreS = sep * 0.62
            local core = mkSprite(hub, TX_SGLOW, pal[1], NumberSequence.new({
                NSK(0, coreS * 0.55), NSK(0.1, coreS), NSK(1, coreS * 0.3) }), HEAD_TR, dur, 1)
            core.LockedToPart = true
            local haloS = sep * 1.7
            local halo = mkSprite(hub, TX_SGLOW, pal[2], NumberSequence.new({
                NSK(0, haloS * 0.5), NSK(0.12, haloS), NSK(1, haloS * 0.35) }), HALO_TR, dur, 1)
            halo.LockedToPart = true
            local gs = sep * 1.9
            local gl = mkSprite(hub, TX_STAR4, GLINT_C, NumberSequence.new({
                NSK(0, gs * 0.1), NSK(0.32, gs), NSK(1, gs * 0.14) }), GLINT_TR, glintD * 1.2, 0.55)
            gl.Rotation = NumberRange.new(0, 90)
            gl.RotSpeed = NumberRange.new(-16, 16)
            gl:Emit(1)
            table.insert(_starLive, {
                host = host, tr = tr, ion = ion, core = core, halo = halo, aT = aT, aB = aB,
                cf0 = cf0, dir = dir, dist = dist, dur = dur, sep = sep,
                t0 = tick() + glintD, started = false,
            })
            Debris:AddItem(host, glintD + dur + life * 2.8 + 0.6)
        end
        local function pickPal()
            local r = math.random()
            if r < 0.55 then
                return 1
            end
            if r < 0.92 then
                return 2
            end
            return 3
        end
        local function pickCls(pi)
            if pi == 3 then
                if math.random() < 0.6 then
                    return 3
                end
                return 2
            end
            local r = math.random()
            if r < 0.25 then
                return 1
            end
            if r < 0.7 then
                return 2
            end
            return 3
        end
        local function viewAz(cam)
            local lv = cam.CFrame.LookVector
            local az = math.atan2(lv.Z, lv.X)
            if math.random() < 0.35 then
                return math.random() * 6.283
            end
            return az
        end
        local function spawnSingle()
            local cam = Camera
            if not cam then
                return
            end
            local base = cam.CFrame.Position
            local az = viewAz(cam) + (math.random() - 0.5) * 1.5
            local el = math.rad(24 + math.random() * 30)
            local r  = 190 + math.random() * 130
            local ce = math.cos(el)
            local start = base + Vec(ce * math.cos(az) * r, math.sin(el) * r, ce * math.sin(az) * r)
            local hd = az + 1.5708 + (math.random() - 0.5) * 2.2
            local pi = pickPal()
            spawnStreak(start, Vec(math.cos(hd), -(0.05 + math.random() * 0.34), math.sin(hd)).Unit,
                pickCls(pi), pi, base.Y + FLOOR_H)
        end
        local function spawnShower()
            local cam = Camera
            if not cam then
                return
            end
            local base = cam.CFrame.Position
            local floorY = base.Y + FLOOR_H
            local raz = viewAz(cam) + (math.random() - 0.5) * 0.9
            local rel = math.rad(36 + math.random() * 16)
            local cr = math.cos(rel)
            local rv = Vec(cr * math.cos(raz), math.sin(rel), cr * math.sin(raz))
            local dn = (Vec(0, -1, 0) + rv * rv.Y).Unit
            local sd = rv:Cross(dn).Unit
            local pi = pickPal()
            local t = 0
            for _ = 1, 3 + math.random(0, 2) do
                t = t + 0.16 + math.random() * 0.42
                task.delay(t, function()
                    if not Config.Weather or not cfg("WeatherShootingStars", false) then
                        return
                    end
                    local phi = (math.random() - 0.5) * 2.8
                    local off = dn * math.cos(phi) + sd * math.sin(phi)
                    local th = math.rad(9 + math.random() * 24)
                    local ct, st = math.cos(th), math.sin(th)
                    local u = (rv * ct + off * st).Unit
                    if u.Y < MIN_SIN then
                        off = -off
                        u = (rv * ct + off * st).Unit
                    end
                    if u.Y < MIN_SIN then
                        return
                    end
                    local ci = 2
                    if th < 0.22 then
                        ci = 1
                    elseif th > 0.44 then
                        ci = 3
                    end
                    pcall(spawnStreak, base + u * (215 + math.random() * 75),
                        (off * ct - rv * st).Unit, ci, pi, floorY)
                end)
            end
        end
        local function stepStars(now)
            for i = #_starLive, 1, -1 do
                local s = _starLive[i]
                if not s.host.Parent then
                    table.remove(_starLive, i)
                else
                    local a = (now - s.t0) / s.dur
                    if a >= 1 then
                        s.tr.Enabled = false
                        if s.ion then
                            s.ion.Enabled = false
                        end
                        table.remove(_starLive, i)
                    elseif a >= 0 then
                        if not s.started then
                            s.started = true
                            s.tr.Enabled = true
                            s.core:Emit(1)
                            s.halo:Emit(1)
                            if s.ion then
                                s.ion.Enabled = true
                            end
                        end
                        s.host.CFrame = s.cf0 + s.dir * (s.dist * a)
                        if a > 0.7 then
                            local h = s.sep * 0.5 * (1 - (a - 0.7) / 0.3)
                            s.aT.Position = Vec(0, h, 0)
                            s.aB.Position = Vec(0, -h, 0)
                        end
                    end
                end
            end
        end
        startStars = function()
            if _starConn then
                return
            end
            _starNextT = tick() + 2 + math.random() * 4
            _starConn = RunService.Heartbeat:Connect(function()
                if not Config.Weather or not cfg("WeatherShootingStars", false) then
                    return
                end
                local now = tick()
                if now >= _starNextT then
                    local r = evRate("WeatherStarRate")
                    _starNextT = now + (5 + math.random() * 6) / r
                    if math.random() < math.min(0.06 * r, 0.35) then
                        pcall(spawnShower)
                    else
                        pcall(spawnSingle)
                        if math.random() < math.min(0.22 * r, 0.6) then
                            task.delay(0.3 + math.random() * 0.5, function()
                                pcall(spawnSingle)
                            end)
                        end
                    end
                end
                pcall(stepStars, now)
            end)
        end
        rescheduleStars = function()
            if not _starConn then
                return
            end
            _starNextT = math.min(_starNextT, tick() + 11 / evRate("WeatherStarRate"))
        end
        stopStars = function()
            if _starConn then
                _starConn:Disconnect()
                _starConn = nil
            end
            for _, s in _starLive do
                pcall(function() s.host:Destroy() end)
            end
            table.clear(_starLive)
        end
        registerSpectacle("StarShower", 1, function()
            if not cfg("WeatherShootingStars", false) then
                return
            end
            spawnShower()
        end)
    end)()
    local startFireflies, stopFireflies, refreshFireflies
    ;(function()
        local FF_N     = 7
        local FF_BODY  = Color3.fromRGB(215, 255, 120)
        local FF_LIGHT = Color3.fromRGB(244, 232, 120)
        local FF_DOWN  = Vec(0, -80, 0)
        local WANDER   = 28
        local FF_STEP  = 2
        local FF_SEG   = 1.2
        local FF_TRC = ColorSequence.new({ CSK(0, Color3.fromRGB(198, 255, 128)),
            CSK(0.45, Color3.fromRGB(216, 238, 108)), CSK(1, Color3.fromRGB(255, 196, 86)) })
        local FF_TRT = NumberSequence.new({ NSK(0, 0.36), NSK(0.35, 0.66), NSK(1, 1) })
        local FF_TRW = NumberSequence.new({ NSK(0, 0.8), NSK(0.3, 1), NSK(1, 0) })
        local _ff = { list = nil, conn = nil, folder = nil, burst = nil, burstHost = nil, n = 4 }
        local _swarm = { active = false, t0 = 0, cx = 0, cz = 0, y = 0 }
        local _ffRp = RaycastParams.new()
        _ffRp.FilterType = Enum.RaycastFilterType.Exclude
        local function groundY(camPos, x, z)
            local ch = lp and lp.Character
            if ch then
                _ffRp.FilterDescendantsInstances = { getFolder(), ch }
            else
                _ffRp.FilterDescendantsInstances = { getFolder() }
            end
            local hit = Workspace:Raycast(Vec(x, camPos.Y + 6, z), FF_DOWN, _ffRp)
            if hit then
                return hit.Position.Y
            end
            return camPos.Y - 7
        end
        local function pickWaypoint(H, camPos)
            local x = camPos.X + (math.random() - 0.5) * WANDER
            local z = camPos.Z + (math.random() - 0.5) * WANDER
            H.a = H.pos
            H.bpt = Vec(x, groundY(camPos, x, z) + 0.5 + math.random() * 3, z)
            H.dur = math.clamp((H.bpt - H.a).Magnitude / 2.2, 1.5, 6)
            H.t = 0
        end
        local function stepToward(cur, target, maxStep)
            local d = target - cur
            local m = d.Magnitude
            if m <= maxStep or m < 1e-4 then
                return target
            end
            return cur + d * (maxStep / m)
        end
        local function trailOff(H)
            H.calm = 0
            if H.trail.Enabled then
                H.trail.Enabled = false
                H.trail:Clear()
            end
        end
        local function buildFlies()
            local folder = Instance.new("Folder")
            folder.Name = "_wxFlies"; folder:SetAttribute("WX_Custom", true)
            folder.Parent = getFolder()
            _ff.folder = folder
            _ff.list = {}
            local cam = Camera
            local camPos
            if cam then camPos = cam.CFrame.Position else camPos = Vec(0, 0, 0) end
            for i = 1, FF_N do
                local b = mkBoltPart(FF_BODY, 0, Vec(0.25, 0.25, 0.25), CFrame.new(camPos), folder)
                b.Shape = Enum.PartType.Ball
                local light = Instance.new("PointLight")
                light.Color = FF_LIGHT; light.Range = 8; light.Brightness = 2.5
                light.Parent = b
                local halo = Instance.new("ParticleEmitter")
                halo:SetAttribute("WX_Custom", true)
                halo.Texture = TX_MGLOW
                halo.Color = ColorSequence.new(FF_BODY)
                halo.LightEmission = 1; halo.LightInfluence = 0
                halo.Size = NumberSequence.new(1.1, 1.5)
                halo.Transparency = NumberSequence.new({ NSK(0, 0.75), NSK(1, 1) })
                halo.Rate = 12; halo.Lifetime = NumberRange.new(0.25, 0.4)
                halo.Speed = NumberRange.new(0, 0)
                halo.LockedToPart = true
                halo.Parent = b
                local a0 = Instance.new("Attachment")
                a0.Position = Vec(0, 0.6, 0); a0.Parent = b
                local a1 = Instance.new("Attachment")
                a1.Position = Vec(0, -0.6, 0); a1.Parent = b
                local tr = Instance.new("Trail")
                tr:SetAttribute("WX_Custom", true)
                tr.Attachment0 = a0; tr.Attachment1 = a1
                tr.Texture = TX_MGLOW; tr.TextureMode = Enum.TextureMode.Stretch
                tr.Color = FF_TRC; tr.Transparency = FF_TRT; tr.WidthScale = FF_TRW
                tr.Lifetime = 0.65
                tr.LightEmission = 1; tr.LightInfluence = 0
                tr.FaceCamera = true
                tr.MinLength = 0.25; tr.MaxLength = 14
                tr.Enabled = false
                tr.Parent = b
                local H = { part = b, light = light, trail = tr, halo = halo, bm = 1,
                            calm = 0, jump = true,
                            pos = camPos, a = camPos, bpt = camPos, t = 0, dur = 1,
                            ph = math.random() * 6.283, spin = 1.7 + i * 0.25,
                            blinkT = math.random() * 3, period = 2.4 + math.random() * 1.4 }
                pickWaypoint(H, camPos)
                H.pos = H.bpt
                pickWaypoint(H, camPos)
                b.CFrame = CFrame.new(H.pos)
                _ff.list[i] = H
            end
            local bh = mkBoltPart(FF_BODY, 1, Vec(1.5, 1.5, 1.5), CFrame.new(camPos), folder)
            local be = Instance.new("ParticleEmitter")
            be:SetAttribute("WX_Custom", true)
            be.Texture = TX_MGLOW
            be.Color = ColorSequence.new(Color3.fromRGB(220, 255, 130), Color3.fromRGB(255, 200, 80))
            be.LightEmission = 0.95; be.LightInfluence = 0.05
            be.Size = NumberSequence.new({ NSK(0, 0.1), NSK(0.08, 0.62, 0.15), NSK(0.45, 0.5, 0.1), NSK(1, 0.08) })
            be.Transparency = NumberSequence.new({ NSK(0, 1), NSK(0.08, 0.08), NSK(0.4, 0.45), NSK(0.75, 0.85), NSK(1, 1) })
            be.Rate = 0; be.Lifetime = NumberRange.new(1.6, 2.8)
            be.Speed = NumberRange.new(0.8, 2.2); be.SpreadAngle = Vector2.new(180, 180)
            be.Drag = 2.5; be.EmissionDirection = Enum.NormalId.Top
            be.Parent = bh
            _ff.burst = be; _ff.burstHost = bh
        end
        refreshFireflies = function()
            local list = _ff.list
            if not list then
                return
            end
            local I = iAmt()
            _ff.n = math.clamp(math.floor(1.5 + 3 * I), 1, FF_N)
            local rm, bm = 0.8 + 0.2 * I, 0.7 + 0.3 * I
            for i = 1, FF_N do
                local H = list[i]
                local on = i <= _ff.n
                H.bm = bm
                H.light.Range = 8 * rm
                H.halo.Enabled = on
                if not on then
                    H.light.Brightness = 0
                    H.part.Transparency = 1
                    H.jump = true
                    trailOff(H)
                end
            end
        end
        startFireflies = function()
            if _ff.conn then return end
            buildFlies()
            refreshFireflies()
            local accum = 0
            _ff.conn = RunService.Heartbeat:Connect(function(dt)
                if not Config.Weather then return end
                accum = accum + dt
                if accum < 0.05 then return end
                local step = accum; accum = 0
                local cam = Camera; if not cam then return end
                local camPos = cam.CFrame.Position
                local now = tick()
                local sw = -1
                if _swarm.active then
                    sw = now - _swarm.t0
                    if sw > 9 then _swarm.active = false; sw = -1 end
                end
                local list = _ff.list
                for i = 1, _ff.n do
                    local H = list[i]
                    local prev = H.pos
                    local newPos
                    if sw >= 0 then
                        local ang = H.ph + now * H.spin
                        local r
                        if sw < 2.5 then r = 10 - 7.4 * (sw / 2.5)
                        elseif sw < 6.5 then r = 2.6
                        else r = 2.6 + (sw - 6.5) * 6 end
                        local target = Vec(_swarm.cx + math.cos(ang) * r,
                            _swarm.y + 0.55 * math.sin(now * 1.3 + H.ph * 2),
                            _swarm.cz + math.sin(ang) * r)
                        newPos = stepToward(prev, prev:Lerp(target, math.min(step * 3, 1)), FF_STEP)
                        H.bpt = newPos; H.t = 1; H.dur = 1
                    else
                        H.t = H.t + step
                        local relX, relZ = prev.X - camPos.X, prev.Z - camPos.Z
                        if H.t >= H.dur or (relX * relX + relZ * relZ) > 3600 then
                            pickWaypoint(H, camPos)
                        end
                        local u = H.t / H.dur
                        u = u * u * (3 - 2 * u)
                        newPos = stepToward(prev, H.a:Lerp(H.bpt, u), FF_STEP)
                    end
                    H.pos = newPos
                    if H.jump or (sw >= 0 and (sw < 2.5 or sw >= 6.4))
                        or (newPos - prev).Magnitude > FF_SEG then
                        H.jump = false
                        trailOff(H)
                    else
                        H.calm = H.calm + step
                        if H.calm >= 0.25 and not H.trail.Enabled then
                            H.trail:Clear()
                            H.trail.Enabled = true
                        end
                    end
                    H.part.CFrame = CFrame.new(H.pos.X, H.pos.Y + 0.3 * math.sin(now * 1.7 + H.ph), H.pos.Z)
                    local pulse = math.exp(-((now + H.blinkT) % H.period) * 1.4)
                    H.light.Brightness = (0.5 + 2.6 * pulse) * H.bm
                    H.part.Transparency = 0.4 * (1 - pulse)
                end
            end)
        end
        stopFireflies = function()
            if _ff.conn then _ff.conn:Disconnect(); _ff.conn = nil end
            if _ff.folder then pcall(function() _ff.folder:Destroy() end); _ff.folder = nil end
            _ff.list = nil; _ff.burst = nil; _ff.burstHost = nil
            _swarm.active = false
        end
        registerSpectacle("FireflySwarm", 1, function()
            if not Config.Weather or _curType ~= "Fireflies" or not _ff.list then return end
            local cam = Camera; if not cam then return end
            local camPos = cam.CFrame.Position
            local ang = math.random() * 6.283
            local d = 8 + math.random() * 8
            local cx = camPos.X + math.cos(ang) * d
            local cz = camPos.Z + math.sin(ang) * d
            _swarm.cx = cx; _swarm.cz = cz
            _swarm.y = groundY(camPos, cx, cz) + 2.2
            _swarm.t0 = tick(); _swarm.active = true
            _ff.burstHost.CFrame = CFrame.new(cx, _swarm.y, cz)
            for _, H in _ff.list do
                trailOff(H)
            end
            local em = math.max(1, math.floor(7 * iRate(iAmt(), IR.Fireflies.lo, IR.Fireflies.hi) + 0.5))
            for n = 0, 5 do
                task.delay(1.6 + n * 0.7, function()
                    if _swarm.active and _ff.burst then _ff.burst:Emit(em) end
                end)
            end
        end)
    end)()
    local stopLeafDevil
    ;(function()
        local RING_N   = 11
        local DEV_H    = 25
        local DEV_R    = 9.5
        local DEV_LIFE = 14
        local DEV_HOLD = 9.6
        local DEV_DOWN = Vec(0, -80, 0)
        local RELEASE  = Vec(-8, -3.5, 3)
        local RING_TEX  = { TX_LEAFA, TX_LEAFB, TX_LEAFA, TX_LEAFB, TX_LEAFC }
        local RING_GLOW = { 0.62, 0.07, 0.6, 0.08, 0.1 }
        local RING_COL  = {
            ColorSequence.new({ CSK(0, Color3.fromRGB(226,190,128)), CSK(0.45, Color3.fromRGB(255,246,200)),
                                CSK(1, Color3.fromRGB(190,132,62)) }),
            ColorSequence.new({ CSK(0, Color3.fromRGB(160,80,52)), CSK(1, Color3.fromRGB(104,44,30)) }),
            ColorSequence.new({ CSK(0, Color3.fromRGB(230,222,176)), CSK(0.5, Color3.fromRGB(255,254,228)),
                                CSK(1, Color3.fromRGB(200,180,122)) }),
            ColorSequence.new({ CSK(0, Color3.fromRGB(156,74,255)), CSK(1, Color3.fromRGB(106,46,200)) }),
            ColorSequence.new({ CSK(0, Color3.fromRGB(196,156,112)), CSK(1, Color3.fromRGB(146,110,74)) }),
        }
        local RING_SIZE = NumberSequence.new({ NSK(0, 0.56, 0.14), NSK(1, 0.46, 0.1) })
        local RING_TR   = NumberSequence.new({ NSK(0, 1), NSK(0.07, 0.05), NSK(0.78, 0.4), NSK(1, 1) })
        local RING_SQ   = NumberSequence.new({ NSK(0, -0.6), NSK(0.25, 0.16), NSK(0.5, -0.6),
                                               NSK(0.75, 0.16), NSK(1, -0.6) })
        local SKIRT_SIZE = NumberSequence.new({ NSK(0, 1.5), NSK(1, 4.4) })
        local SKIRT_TR   = NumberSequence.new({ NSK(0, 1), NSK(0.22, 0.82), NSK(0.75, 0.92), NSK(1, 1) })
        local LEAF_SIZE  = NumberSequence.new({ NSK(0, 0.52, 0.12), NSK(1, 0.44, 0.1) })
        local LEAF_TR    = NumberSequence.new({ NSK(0, 1), NSK(0.1, 0.08), NSK(0.75, 0.42), NSK(1, 1) })
        local DUCK_TI = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
        local BACK_TI = TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
        local _dev = { folder = nil, conn = nil }
        local _devRp = RaycastParams.new()
        _devRp.FilterType = Enum.RaycastFilterType.Exclude
        local function ambientRate(mul, ti)
            local I = iAmt()
            for _, L in _partLayers do
                if L.emitter and L.tag == nil then
                    if L.rateTween then L.rateTween:Cancel() end
                    L.rateMul = mul
                    local tw = TweenService:Create(L.emitter, ti, { Rate = layerRate(L, I) * mul })
                    L.rateTween = tw
                    tw:Play()
                end
            end
        end
        stopLeafDevil = function()
            if _dev.conn then _dev.conn:Disconnect(); _dev.conn = nil end
            if _dev.folder then pcall(function() _dev.folder:Destroy() end); _dev.folder = nil end
            if _dev.rings then
                _dev.rings = nil
                ambientRate(1, BACK_TI)
            end
        end
        local function mkRing(folder, cf, i, r)
            local p = mkBoltPart(WHITE, 1, Vec(0.3, 0.3, 0.3), cf, folder)
            local k = ((i - 1) % 5) + 1
            local glow = RING_GLOW[k]
            local e = Instance.new("ParticleEmitter")
            e:SetAttribute("WX_Custom", true)
            e.Texture = RING_TEX[k]
            e.Color = RING_COL[k]
            e.LightEmission = glow; e.LightInfluence = 1 - glow
            e.Size = RING_SIZE; e.Transparency = RING_TR; e.Squash = RING_SQ
            e.Rate = 0
            e.Lifetime = NumberRange.new(2, 3)
            e.Speed = NumberRange.new(5, 9)
            e.SpreadAngle = Vector2.new(8, 8)
            e.Rotation = NumberRange.new(-180, 180)
            e.RotSpeed = NumberRange.new(-300, 300)
            e.Acceleration = Vec(0, 2.6, 0)
            e.Drag = 1.4
            e.EmissionDirection = ND.Front
            e.Parent = p
            return { part = p, e = e, r = r }
        end
        registerSpectacle("LeafDevil", 1, function()
            if not Config.Weather or _curType ~= "Autumn" or _dev.conn then return end
            local cam = Camera; if not cam then return end
            local camPos = cam.CFrame.Position
            local bearing = math.random() * 6.283
            local dist = 18 + math.random() * 12
            local cx = camPos.X + math.cos(bearing) * dist
            local cz = camPos.Z + math.sin(bearing) * dist
            local ch = lp and lp.Character
            if ch then
                _devRp.FilterDescendantsInstances = { getFolder(), ch }
            else
                _devRp.FilterDescendantsInstances = { getFolder() }
            end
            local hit = Workspace:Raycast(Vec(cx, camPos.Y + 6, cz), DEV_DOWN, _devRp)
            local gy = camPos.Y - 4.6
            if hit then gy = hit.Position.Y end
            local folder = Instance.new("Folder")
            folder.Name = "_wxDevil"; folder:SetAttribute("WX_Custom", true)
            folder.Parent = getFolder()
            _dev.folder = folder
            local em = iRate(iAmt(), IR.Autumn.lo, IR.Autumn.hi)
            local seed = CFrame.new(cx, gy + 1, cz)
            local rings = table.create(RING_N)
            for i = 1, RING_N do
                local h = 0.8 + (i - 1) * (DEV_H - 0.8) / (RING_N - 1)
                local u = h / DEV_H
                local r = DEV_R * (0.15 + 0.85 * u ^ 0.9)
                if u > 0.72 then r = r * (1 + (u - 0.72) * 1.5) end
                local R = mkRing(folder, seed, i, r)
                R.h = h
                R.ph = (i - 1) * 0.62
                R.t0 = 0.12 * (i - 1)
                R.rate = (10 + 34 * (r / DEV_R)) * em
                rings[i] = R
            end
            _dev.rings = rings
            local foot = mkBoltPart(WHITE, 1, Vec(6.5, 0.4, 6.5), CFrame.new(cx, gy + 0.35, cz), folder)
            local leafSkirt = Instance.new("ParticleEmitter")
            leafSkirt:SetAttribute("WX_Custom", true)
            leafSkirt.Texture = TX_LEAFA
            leafSkirt.Color = RING_COL[1]
            leafSkirt.LightEmission = 0.3; leafSkirt.LightInfluence = 0.7
            leafSkirt.Size = LEAF_SIZE; leafSkirt.Transparency = LEAF_TR; leafSkirt.Squash = RING_SQ
            leafSkirt.Rate = 0
            leafSkirt.Lifetime = NumberRange.new(1.2, 2.2)
            leafSkirt.Speed = NumberRange.new(2, 5)
            leafSkirt.SpreadAngle = Vector2.new(70, 70)
            leafSkirt.Rotation = NumberRange.new(-180, 180)
            leafSkirt.RotSpeed = NumberRange.new(-260, 260)
            leafSkirt.Acceleration = Vec(0, 1.2, 0)
            leafSkirt.Drag = 2.2
            leafSkirt.EmissionDirection = ND.Top
            leafSkirt.Parent = foot
            local dustSkirt = Instance.new("ParticleEmitter")
            dustSkirt:SetAttribute("WX_Custom", true)
            dustSkirt.Texture = TX_DUST
            dustSkirt.Color = ColorSequence.new(Color3.fromRGB(190,166,130), Color3.fromRGB(140,118,90))
            dustSkirt.LightEmission = 0.04; dustSkirt.LightInfluence = 0.96
            dustSkirt.Size = SKIRT_SIZE; dustSkirt.Transparency = SKIRT_TR
            dustSkirt.Rate = 0
            dustSkirt.Lifetime = NumberRange.new(0.9, 1.4)
            dustSkirt.Speed = NumberRange.new(1, 2.6)
            dustSkirt.SpreadAngle = Vector2.new(85, 85)
            dustSkirt.RotSpeed = NumberRange.new(-25, 25)
            dustSkirt.Acceleration = Vec(0, 1, 0)
            dustSkirt.Drag = 2.4
            dustSkirt.EmissionDirection = ND.Top
            dustSkirt.Parent = foot
            local scuff = mkBoltPart(WHITE, 1, Vec(15, 0.08, 15), CFrame.new(cx, gy + 0.05, cz), folder)
            scuff.Material = Enum.Material.SmoothPlastic
            local sd = Instance.new("Decal")
            sd:SetAttribute("WX_Custom", true)
            sd.Face = ND.Top; sd.Texture = TX_DUST
            sd.Color3 = Color3.fromRGB(96, 74, 52); sd.Transparency = 0.55
            sd.Parent = scuff
            ambientRate(0.45, DUCK_TI)
            local t0 = tick()
            local ang, px, pz = 0, cx, cz
            local lean = math.random() * 6.283
            _dev.conn = RunService.Heartbeat:Connect(function(dt)
                if not folder.Parent then stopLeafDevil() return end
                local t = tick() - t0
                if t > DEV_LIFE then stopLeafDevil() return end
                ang = ang + dt * 2.7
                px = px + Wind.x * dt * 0.75
                pz = pz + Wind.z * dt * 0.75
                local lx = math.cos(lean + t * 0.21) * 0.13
                local lz = math.sin(lean + t * 0.17) * 0.13
                local climb = math.min(t / 1.5, 1)
                local release = t > DEV_HOLD
                for i = 1, RING_N do
                    local R = rings[i]
                    local h = R.h * climb
                    local th = ang + R.ph
                    local cs, sn = math.cos(th), math.sin(th)
                    local r = R.r * (0.55 + 0.45 * climb)
                    local p = Vec(px + lx * h + cs * r, gy + 0.35 + h, pz + lz * h + sn * r)
                    R.part.CFrame = CFrame.lookAt(p, p + Vec(-sn, 0.3, cs))
                    if release then
                        R.e.Rate = 0
                        R.e.Acceleration = RELEASE
                    else
                        R.e.Rate = R.rate * math.clamp((t - R.t0) / 0.6, 0, 1)
                    end
                end
                foot.CFrame = CFrame.new(px, gy + 0.35, pz)
                scuff.CFrame = CFrame.new(px, gy + 0.05, pz) * CFrame.Angles(0, t * 0.35, 0)
                if release then
                    leafSkirt.Rate = 0
                    dustSkirt.Rate = 0
                    leafSkirt.Acceleration = RELEASE
                    sd.Transparency = math.min(0.55 + (t - DEV_HOLD) * 0.35, 1)
                    if t > DEV_HOLD + 0.1 and _dev.rings then
                        _dev.rings = nil
                        ambientRate(1, BACK_TI)
                    end
                else
                    local k = math.min(t / 0.8, 1)
                    leafSkirt.Rate = 26 * em * k
                    dustSkirt.Rate = 15 * em * k
                    sd.Transparency = 0.95 - 0.4 * math.min(t / 1.2, 1)
                end
            end)
        end)
    end)()
    local puddlesRefresh, puddlesIntensity, stopPuddles
    ;(function()
        local TXP_RING = "rbxassetid://17738857765"
        local TXP_DROP = "rbxassetid://14964503448"
        local TXP_STAR = "rbxassetid://17726943419"
        local WATER_C  = Color3.fromRGB(22, 28, 37)
        local SHEEN_C  = Color3.fromRGB(150, 175, 205)
        local FOAM_C   = Color3.fromRGB(236, 246, 255)
        local PUD_DOWN = Vec(0, -90, 0)
        local FIT_DOWN = Vec(0, -4.2, 0)
        local HALF_PI  = 1.5707963
        local FIT_TOL  = 1.5
        local FIT_R    = 1.09
        local FIT_K    = { 1, 0.66, 0.44, 0.28 }
        local FIT_C = {
            1, 0, 0.70711, 0.70711, 0, 1, -0.70711, 0.70711,
            -1, 0, -0.70711, -0.70711, 0, -1, 0.70711, -0.70711,
        }
        local FIT_Q = {
            1, 1, 0.333, 1, -0.333, 1, -1, 1,
            -1, 0.333, -1, -0.333, -1, -1, -0.333, -1,
            0.333, -1, 1, -1, 1, -0.333, 1, 0.333,
        }
        local CELL     = 32
        local HALF     = 16
        local NOISE_F  = 0.018
        local POOL_F   = 0.74
        local TILE_K   = 1 / 470
        local K_CAP    = 48
        local MAX_REC  = 96
        local _pud = { folder = nil, conn = nil }
        local _plist = {}
        local _pmap = {}
        local _pfail = {}
        local _cd = { i = 0, j = 0, key = 0, kind = 0, cx = 0, cz = 0, gy = 0 }
        local _units, _uIdx = {}, 1
        local _prints, _pIdx = {}, 1
        local _pstates = {}
        local _abuf = {}
        local _prp = RaycastParams.new()
        _prp.FilterType = Enum.RaycastFilterType.Exclude
        local _pfilter = {}
        local _fieldToken, _rebuild = 0, false
        local _int, _thr, _placeR, _seed = 1, 0, 50, 0
        local _wTr, _wRf = 0.35, 0.16
        local _homeI, _homeJ = 1e9, 1e9
        local function pudActive()
            if not Config.Weather or not cfg("WeatherPuddles", false) then
                return false
            end
            if _curType == "Rain" then
                return true
            end
            return cfg("WeatherStorm", false)
        end
        local function pudIntensity()
            return iAmt()
        end
        local function mkFlatPart(size, cf, parent)
            local p = Instance.new("Part")
            p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
            p.CastShadow = false; p.Transparency = 1
            p.Size = size; p.CFrame = cf
            p:SetAttribute("WX_Custom", true)
            p.Parent = parent
            return p
        end
        local function mkSlab(d1, d2, cf, parent, sheen)
            local p = Instance.new("Part")
            p.Shape = Enum.PartType.Cylinder
            p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
            p.CastShadow = false; p.Material = Enum.Material.SmoothPlastic
            if sheen then
                p.Color = SHEEN_C; p.Transparency = 0.74; p.Reflectance = 0.38
            else
                p.Color = WATER_C; p.Transparency = _wTr; p.Reflectance = _wRf
                p:SetAttribute("WX_W", true)
            end
            p.Size = Vec(0.05, d1, d2)
            p.CFrame = cf
            p:SetAttribute("WX_Custom", true)
            p.Parent = parent
        end
        local function mkTile(w, l, cf, parent)
            local p = Instance.new("Part")
            p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
            p.CastShadow = false; p.Material = Enum.Material.SmoothPlastic
            p.Color = WATER_C; p.Transparency = _wTr; p.Reflectance = _wRf
            p.Size = Vec(w, 0.05, l)
            p.CFrame = cf
            p:SetAttribute("WX_Custom", true)
            p:SetAttribute("WX_W", true)
            p.Parent = parent
        end
        local function fitSlab(cx, cz, d1, d2, yaw, gy)
            local cs, sn = math.cos(yaw), math.sin(yaw)
            for k = 1, 4 do
                local f = FIT_K[k] * FIT_R * 0.5
                local a, b = d1 * f, d2 * f
                local ok, gx, gz, n = true, 0, 0, 0
                for i = 1, 8 do
                    local ct, st = FIT_C[i * 2 - 1], FIT_C[i * 2]
                    local ox = sn * b * st - cs * a * ct
                    local oz = sn * a * ct + cs * b * st
                    local h = Workspace:Raycast(Vec(cx + ox, gy + 2, cz + oz), FIT_DOWN, _prp)
                    local sup = false
                    if h and h.Normal.Y >= 0.86 and h.Instance.CanCollide then
                        local dy = h.Position.Y - gy
                        sup = dy < FIT_TOL and dy > -FIT_TOL
                    end
                    if sup then
                        gx, gz, n = gx + ox, gz + oz, n + 1
                    else
                        ok = false
                    end
                end
                if ok then
                    return cx, cz, d1 * FIT_K[k], d2 * FIT_K[k]
                end
                if n == 0 then
                    return nil
                end
                cx, cz = cx + gx / n * 0.5, cz + gz / n * 0.5
            end
            return nil
        end
        local function fitRect(cx, cz, w, l, gy)
            for k = 1, 4 do
                local f = FIT_K[k] * FIT_R * 0.5
                local a, b = w * f, l * f
                local ok = true
                for i = 1, 12 do
                    local h = Workspace:Raycast(
                        Vec(cx + FIT_Q[i * 2 - 1] * a, gy + 2, cz + FIT_Q[i * 2] * b), FIT_DOWN, _prp)
                    local sup = false
                    if h and h.Normal.Y >= 0.86 and h.Instance.CanCollide then
                        local dy = h.Position.Y - gy
                        sup = dy < FIT_TOL and dy > -FIT_TOL
                    end
                    if not sup then
                        ok = false
                        break
                    end
                end
                if ok then
                    return w * FIT_K[k], l * FIT_K[k]
                end
            end
            return nil
        end
        local function mkHost(m, cf, size, k, I)
            local host = mkFlatPart(size, cf, m)
            local e = Instance.new("ParticleEmitter")
            e:SetAttribute("WX_Custom", true)
            e.Texture = TXP_RING
            e.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
            e.EmissionDirection = Enum.NormalId.Top
            e.Speed = NumberRange.new(0.05, 0.05)
            e.Rate = (2.1 + 4.2 * I) * k
            e.Lifetime = NumberRange.new(1.1, 1.6)
            e.Size = NumberSequence.new({ NSK(0, 0.12), NSK(1, 4.4) })
            e.Transparency = NumberSequence.new({ NSK(0, 0.9), NSK(0.14, 0.12), NSK(0.62, 0.5), NSK(1, 1) })
            e.Color = ColorSequence.new(Color3.fromRGB(215, 234, 250))
            e.LightEmission = 0.45
            e.Parent = host
            local g = Instance.new("ParticleEmitter")
            g:SetAttribute("WX_Custom", true)
            g.Texture = TXP_STAR
            g.EmissionDirection = Enum.NormalId.Top
            g.Speed = NumberRange.new(0, 0)
            g.Rate = 0.8 * I * k
            g.Lifetime = NumberRange.new(0.16, 0.28)
            g.Size = NumberSequence.new({ NSK(0, 0.06), NSK(0.4, 0.3), NSK(1, 0.04) })
            g.Transparency = NumberSequence.new({ NSK(0, 0.6), NSK(1, 1) })
            g.Color = ColorSequence.new(Color3.fromRGB(240, 248, 255))
            g.LightEmission = 0.5
            g.Parent = host
            return e, g
        end
        local function mkPuddle(cd, span, nslab, I)
            local x, z, gy = cd.cx, cd.cz, cd.gy
            local m = Instance.new("Model")
            m.Name = "_pud"
            local px = x + (math.random() - 0.5) * CELL * 0.16
            local pz = z + (math.random() - 0.5) * CELL * 0.16
            local spine = math.random() * 6.28318
            local sx, sz = math.cos(spine), math.sin(spine)
            local lx, lz = -sz, sx
            local yaw0 = math.pi - spine
            local slabs, rmax = {}, 0
            local s0, s1, l0, l1 = 1e9, -1e9, 1e9, -1e9
            local function place(cx, cz, d1, d2, yaw, yoff, sheen)
                local fx, fz, fd1, fd2 = fitSlab(cx, cz, d1, d2, yaw, gy)
                if not fx then
                    return false
                end
                local rad = math.max(fd1, fd2) * 0.5
                local ex, ez = fx - x, fz - z
                if math.abs(ex) + rad > HALF or math.abs(ez) + rad > HALF then
                    return false
                end
                mkSlab(fd1, fd2, CFrame.new(fx, gy + yoff, fz)
                    * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, HALF_PI), m, sheen)
                if not sheen then
                    slabs[#slabs + 1] = {
                        cx = fx, cz = fz,
                        cs = math.cos(yaw), sn = math.sin(yaw),
                        ia = 2 / fd1, ib = 2 / fd2, rect = false,
                    }
                    rmax = math.max(rmax, math.sqrt(ex * ex + ez * ez) + rad)
                end
                local dx, dz = fx - px, fz - pz
                local t, lat = dx * sx + dz * sz, dx * lx + dz * lz
                local ins = math.min(fd1, fd2) * 0.375
                s0, s1 = math.min(s0, t - ins), math.max(s1, t + ins)
                l0, l1 = math.min(l0, lat - ins), math.max(l1, lat + ins)
                return true
            end
            if not place(px, pz, span, span * 0.62, yaw0, 0.002, false) then
                m:Destroy()
                return false
            end
            for i = 1, nslab do
                local t = ((i - 0.5) / nslab - 0.5) * span * 0.62 + (math.random() - 0.5) * span * 0.14
                local lat = (math.random() - 0.5) * span * 0.24
                local d1 = span * (0.34 + math.random() * 0.3)
                place(px + sx * t + lx * lat, pz + sz * t + lz * lat,
                    d1, d1 * (0.6 + math.random() * 0.34),
                    yaw0 + (math.random() - 0.5) * 1.6, 0.008 + i * 0.004, false)
            end
            for _ = 1, 2 do
                local t = (math.random() - 0.5) * span * 0.5
                local lat = (math.random() - 0.5) * span * 0.16
                local d1 = span * (0.14 + math.random() * 0.18)
                place(px + sx * t + lx * lat, pz + sz * t + lz * lat,
                    d1, d1 * (0.4 + math.random() * 0.35), math.random() * math.pi, 0.036, true)
            end
            s0, s1 = math.max(s0, span * -0.425), math.min(s1, span * 0.425)
            l0, l1 = math.max(l0, span * -0.225), math.min(l1, span * 0.225)
            local hw, hl = math.max(s1 - s0, 1), math.max(l1 - l0, 1)
            local hm, hn = (s0 + s1) * 0.5, (l0 + l1) * 0.5
            local k = (span / 26) ^ 1.5 * hw * hl / (span * span * 0.3825)
            local e, g = mkHost(m, CFrame.new(px + sx * hm + lx * hn, gy + 0.1, pz + sz * hm + lz * hn)
                * CFrame.Angles(0, -spine, 0), Vec(hw, 0.05, hl), k, I)
            m.Parent = _pud.folder
            local P = {
                cx = x, cz = z, top = gy + 0.06, r2 = rmax * rmax, k = k,
                key = cd.key, ci = cd.i, cj = cd.j, kind = cd.kind,
                slabs = slabs, ring = e, glint = g, model = m,
            }
            _plist[#_plist + 1] = P
            _pmap[cd.key] = P
            return true
        end
        local function mkFloodCell(cd, I)
            local gy = cd.gy
            local m = Instance.new("Model")
            m.Name = "_pud"
            local slabs = {}
            local area, rmax = 0, 0
            local x0, x1, z0, z1 = 1e9, -1e9, 1e9, -1e9
            for a = 0, 1 do
                for b = 0, 1 do
                    local scx = cd.cx + (a - 0.5) * HALF
                    local scz = cd.cz + (b - 0.5) * HALF
                    local fw, fl = fitRect(scx, scz, HALF, HALF, gy)
                    if fw then
                        mkTile(fw, fl, CFrame.new(scx, gy + 0.002, scz), m)
                        slabs[#slabs + 1] = {
                            cx = scx, cz = scz, cs = 1, sn = 0,
                            ia = 2 / fw, ib = 2 / fl, rect = true,
                        }
                        area = area + fw * fl
                        rmax = math.max(rmax, 0.7072 * (HALF + fw))
                        x0 = math.min(x0, scx - fw * 0.5)
                        x1 = math.max(x1, scx + fw * 0.5)
                        z0 = math.min(z0, scz - fl * 0.5)
                        z1 = math.max(z1, scz + fl * 0.5)
                    end
                end
            end
            if area <= 0 then
                m:Destroy()
                return false
            end
            if area > CELL * CELL * 0.98 and math.random() < 0.45 then
                local d1 = CELL * (0.15 + math.random() * 0.1)
                local sx = cd.cx + (math.random() - 0.5) * CELL * 0.4
                local sz = cd.cz + (math.random() - 0.5) * CELL * 0.4
                local yaw = math.random() * math.pi
                local fx, fz, fd1, fd2 = fitSlab(sx, sz, d1, d1 * (0.4 + math.random() * 0.35), yaw, gy)
                if fx and math.abs(fx - cd.cx) + fd1 * 0.5 < HALF
                    and math.abs(fz - cd.cz) + fd1 * 0.5 < HALF then
                    mkSlab(fd1, fd2, CFrame.new(fx, gy + 0.036, fz)
                        * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, HALF_PI), m, true)
                end
            end
            local hw, hl = math.max(x1 - x0, 1), math.max(z1 - z0, 1)
            local e, g = mkHost(m, CFrame.new((x0 + x1) * 0.5, gy + 0.1, (z0 + z1) * 0.5),
                Vec(hw, 0.05, hl), area * TILE_K, I)
            m.Parent = _pud.folder
            local P = {
                cx = cd.cx, cz = cd.cz, top = gy + 0.06, r2 = rmax * rmax, k = area * TILE_K,
                key = cd.key, ci = cd.i, cj = cd.j, kind = cd.kind,
                slabs = slabs, ring = e, glint = g, model = m,
            }
            _plist[#_plist + 1] = P
            _pmap[cd.key] = P
            return true
        end
        local function mkSplashUnit(parent)
            local p = mkFlatPart(Vec(1.1, 0.1, 1.1), CFrame.new(0, -900, 0), parent)
            local ring = Instance.new("ParticleEmitter")
            ring:SetAttribute("WX_Custom", true)
            ring.Texture = TXP_RING
            ring.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
            ring.EmissionDirection = Enum.NormalId.Top
            ring.Speed = NumberRange.new(0.05, 0.05)
            ring.Rate = 0
            ring.Lifetime = NumberRange.new(0.45, 0.7)
            ring.Size = NumberSequence.new({ NSK(0, 0.1), NSK(1, 4) })
            ring.Transparency = NumberSequence.new({ NSK(0, 0.75), NSK(0.1, 0.05), NSK(0.5, 0.4), NSK(1, 1) })
            ring.Color = ColorSequence.new(Color3.fromRGB(230, 244, 255))
            ring.LightEmission = 0.5
            ring.Parent = p
            local foam = Instance.new("ParticleEmitter")
            foam:SetAttribute("WX_Custom", true)
            foam.Texture = TX_SNOWSOFT
            foam.Orientation = Enum.ParticleOrientation.VelocityParallel
            foam.EmissionDirection = Enum.NormalId.Top
            foam.Rate = 0
            foam.SpreadAngle = Vector2.new(56, 56)
            foam.Acceleration = Vec(0, -80, 0)
            foam.Lifetime = NumberRange.new(0.3, 0.6)
            foam.Size = NumberSequence.new({ NSK(0, 0.6, 0.22), NSK(1, 0.2) })
            foam.Squash = NumberSequence.new({ NSK(0, 1.5), NSK(1, 0.4) })
            foam.Speed = NumberRange.new(6, 12)
            foam.Color = ColorSequence.new(FOAM_C)
            foam.Transparency = NumberSequence.new({ NSK(0, 0.18), NSK(0.7, 0.45), NSK(1, 1) })
            foam.LightEmission = 0.18
            foam.Parent = p
            local drops = Instance.new("ParticleEmitter")
            drops:SetAttribute("WX_Custom", true)
            drops.Texture = TXP_DROP
            drops.Orientation = Enum.ParticleOrientation.VelocityParallel
            drops.EmissionDirection = Enum.NormalId.Top
            drops.Rate = 0
            drops.SpreadAngle = Vector2.new(52, 52)
            drops.Acceleration = Vec(0, -80, 0)
            drops.Lifetime = NumberRange.new(0.32, 0.62)
            drops.Size = NumberSequence.new({ NSK(0, 0.55, 0.18), NSK(1, 0.28) })
            drops.Speed = NumberRange.new(6, 12)
            drops.Color = ColorSequence.new(Color3.fromRGB(210, 232, 250))
            drops.Transparency = NumberSequence.new({ NSK(0, 0.1), NSK(0.75, 0.3), NSK(1, 1) })
            drops.LightEmission = 0.25
            drops.Parent = p
            local mist = Instance.new("ParticleEmitter")
            mist:SetAttribute("WX_Custom", true)
            mist.Texture = TX_SNOWSOFT
            mist.EmissionDirection = Enum.NormalId.Top
            mist.Rate = 0
            mist.Speed = NumberRange.new(1.2, 2.8)
            mist.SpreadAngle = Vector2.new(48, 48)
            mist.Lifetime = NumberRange.new(0.3, 0.5)
            mist.Size = NumberSequence.new({ NSK(0, 0.5), NSK(1, 1.6) })
            mist.Transparency = NumberSequence.new({ NSK(0, 0.75), NSK(1, 1) })
            mist.Color = ColorSequence.new(FOAM_C)
            mist.LightEmission = 0.1
            mist.Parent = p
            return { part = p, ring = ring, foam = foam, drops = drops, mist = mist }
        end
        local function fireSplash(x, y, z, speed)
            local u = _units[_uIdx]
            if not u then
                return
            end
            _uIdx = (_uIdx % #_units) + 1
            local s = math.clamp(speed, 4, 36)
            u.part.CFrame = CFrame.new(x, y + 0.12, z)
            u.ring.Size = NumberSequence.new({ NSK(0, 0.1), NSK(1, 3.2 + s * 0.18) })
            local lo, hi = 5 + s * 0.38, 8 + s * 0.6
            u.foam.Speed = NumberRange.new(lo, hi)
            u.drops.Speed = NumberRange.new(lo * 0.8, hi * 0.9)
            u.ring:Emit(2)
            u.foam:Emit(9 + math.floor(s * 0.75))
            u.drops:Emit(4 + math.floor(s * 0.3))
            u.mist:Emit(3)
        end
        local function dropPrint(x, y, z, heading, side)
            local p = _prints[_pIdx]
            if not p then
                return
            end
            _pIdx = (_pIdx % #_prints) + 1
            p.CFrame = CFrame.new(x, y + 0.02, z) * CFrame.Angles(0, heading, 0) * CFrame.new(side * 0.4, 0, 0)
            p.Transparency = 0.42
            TweenService:Create(p, TweenInfo.new(2.2), { Transparency = 1 }):Play()
        end
        local function defaultActors()
            local n = 0
            local cam = Camera
            if not cam then
                return _abuf, 0
            end
            local camPos = cam.CFrame.Position
            for _, plr in Players:GetPlayers() do
                local ch = plr.Character
                local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local pos = hrp.Position
                    local dx, dy, dz = pos.X - camPos.X, pos.Y - camPos.Y, pos.Z - camPos.Z
                    if dx * dx + dy * dy + dz * dz < 12100 then
                        local vel = hrp.AssemblyLinearVelocity
                        local grounded = vel.Y > -6 and vel.Y < 6
                        if not grounded then
                            local hum = ch:FindFirstChildOfClass("Humanoid")
                            grounded = hum ~= nil and hum.FloorMaterial ~= Enum.Material.Air
                        end
                        n = n + 1
                        local rec = _abuf[n]
                        if not rec then
                            rec = {}
                            _abuf[n] = rec
                        end
                        rec.key = plr
                        rec.fx, rec.fy, rec.fz = pos.X, pos.Y - 2.9, pos.Z
                        rec.vx, rec.vy, rec.vz = vel.X, vel.Y, vel.Z
                        rec.speed = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
                        rec.grounded = grounded
                    end
                end
            end
            return _abuf, n
        end
        local actorsProvider = defaultActors
        local function inPuddle(P, x, z)
            local dx, dz = x - P.cx, z - P.cz
            if dx * dx + dz * dz > P.r2 then
                return false
            end
            for _, sl in P.slabs do
                local ux, uz = x - sl.cx, z - sl.cz
                local u = (-ux * sl.cs + uz * sl.sn) * sl.ia
                local v = (ux * sl.sn + uz * sl.cs) * sl.ib
                if sl.rect then
                    if u > -1 and u < 1 and v > -1 and v < 1 then
                        return true
                    end
                elseif u * u + v * v <= 1 then
                    return true
                end
            end
            return false
        end
        local function fieldAt(wx, wz)
            return math.noise(wx * NOISE_F, wz * NOISE_F, _seed)
        end
        local function floodThr(I)
            if I <= 1 then
                return -0.4043 * (I - 0.3)
            end
            if I <= 1.6 then
                return -0.283 - 0.3417 * (I - 1)
            end
            return -0.488 - 1.405 * (I - 1.6)
        end
        local function refreshParams()
            local I = pudIntensity()
            _int = I
            _thr = floodThr(I)
            _placeR = 46 + 20 * I
            _wTr = 0.46 - 0.11 * I
            _wRf = 0.11 + 0.05 * I
        end
        local function cellKind(i, j)
            local ccx, ccz = (i + 0.5) * CELL, (j + 0.5) * CELL
            if fieldAt(ccx, ccz) <= _thr then
                return 0
            end
            if fieldAt(ccx + CELL, ccz) > _thr and fieldAt(ccx - CELL, ccz) > _thr
                and fieldAt(ccx, ccz + CELL) > _thr and fieldAt(ccx, ccz - CELL) > _thr then
                return 2
            end
            return 1
        end
        local function placeCell(i, j, key, kind, by)
            local folder = _pud.folder
            if not folder then
                return false
            end
            local ccx, ccz = (i + 0.5) * CELL, (j + 0.5) * CELL
            _pfilter[1] = folder
            local ch = lp and lp.Character
            if ch then
                _pfilter[2] = ch
            else
                _pfilter[2] = folder
            end
            _prp.FilterDescendantsInstances = _pfilter
            local hit = Workspace:Raycast(Vec(ccx, by + 6, ccz), PUD_DOWN, _prp)
            if not hit or hit.Normal.Y < 0.94 then
                return false
            end
            local inst = hit.Instance
            if not inst.CanCollide then
                return false
            end
            if inst:IsA("Terrain") and hit.Material == Enum.Material.Water then
                return false
            end
            local cd = _cd
            cd.i, cd.j, cd.key, cd.kind = i, j, key, kind
            cd.cx, cd.cz, cd.gy = ccx, ccz, hit.Position.Y
            if kind == 2 then
                return mkFloodCell(cd, _int)
            end
            local nslab = 5
            if _int > 1.15 then
                nslab = 4
            end
            return mkPuddle(cd, CELL * POOL_F * (0.82 + 0.24 * math.random()), nslab, _int)
        end
        local function tryCell(i, j, bx, bz, by)
            local key = (i + 32768) * 65536 + j + 32768
            if _pmap[key] or _pfail[key] then
                return false
            end
            local dx = (i + 0.5) * CELL - bx
            local dz = (j + 0.5) * CELL - bz
            if dx * dx + dz * dz > _placeR * _placeR then
                return false
            end
            local kind = cellKind(i, j)
            if kind == 0 then
                return false
            end
            if not placeCell(i, j, key, kind, by) then
                _pfail[key] = true
            end
            return true
        end
        local function maintain(bx, by, bz)
            local ci, cj = math.floor(bx / CELL), math.floor(bz / CELL)
            local budget = 8
            if ci ~= _homeI or cj ~= _homeJ then
                _homeI, _homeJ = ci, cj
                table.clear(_pfail)
            end
            if _rebuild then
                _rebuild = false
                refreshParams()
                table.clear(_pfail)
                budget = 18
                for _, P in _plist do
                    for _, d in P.model:GetChildren() do
                        if d:GetAttribute("WX_W") then
                            d.Transparency = _wTr
                            d.Reflectance = _wRf
                        end
                    end
                end
                local n = 1
                while n <= #_plist do
                    local P = _plist[n]
                    if P.kind == cellKind(P.ci, P.cj) then
                        n = n + 1
                    else
                        _pmap[P.key] = nil
                        P.model:Destroy()
                        _plist[n] = _plist[#_plist]
                        _plist[#_plist] = nil
                    end
                end
            end
            local cull = _placeR + CELL * 0.75
            local cull2 = cull * cull
            local n = 1
            while n <= #_plist do
                local P = _plist[n]
                local dx, dz = P.cx - bx, P.cz - bz
                if dx * dx + dz * dz > cull2 then
                    _pmap[P.key] = nil
                    P.model:Destroy()
                    _plist[n] = _plist[#_plist]
                    _plist[#_plist] = nil
                else
                    n = n + 1
                end
            end
            local nr = math.ceil(_placeR / CELL)
            for ring = 0, nr do
                for di = -ring, ring do
                    for dj = -ring, ring do
                        if budget > 0 and #_plist < MAX_REC
                            and math.max(math.abs(di), math.abs(dj)) == ring
                            and tryCell(ci + di, cj + dj, bx, bz, by) then
                            budget = budget - 1
                        end
                    end
                end
            end
            local ksum = 0
            for _, P in _plist do
                ksum = ksum + P.k
            end
            local damp = 1
            if ksum > K_CAP then
                damp = K_CAP / ksum
            end
            local rr = (2.1 + 4.2 * _int) * damp
            local gr = 0.8 * _int * damp
            for _, P in _plist do
                P.ring.Rate = rr * P.k
                P.glint.Rate = gr * P.k
            end
        end
        local function tick20(now, doMaintain)
            local bx, by, bz
            local ch = lp and lp.Character
            local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
            if hrp then
                local p = hrp.Position
                bx, by, bz = p.X, p.Y, p.Z
            elseif Camera then
                local p = Camera.CFrame.Position
                bx, by, bz = p.X, p.Y, p.Z
            else
                return
            end
            if doMaintain then
                maintain(bx, by, bz)
            end
            local list, n = actorsProvider()
            for ai = 1, n do
                local a = list[ai]
                local st = _pstates[a.key]
                if not st then
                    st = { last = 0, wet = 0, side = 1, prevVy = 0 }
                    _pstates[a.key] = st
                end
                local sp = a.speed
                local pud = nil
                for _, P in _plist do
                    if math.abs(a.fy - P.top) < 4.5 and inPuddle(P, a.fx, a.fz) then
                        pud = P
                        break
                    end
                end
                local interval = math.clamp(3.6 / math.max(sp, 1), 0.15, 0.32)
                if pud and a.grounded and sp > 2.2 then
                    local landing = st.prevVy < -25
                    if landing or now - st.last >= interval then
                        st.last = now
                        st.side = -st.side
                        local fs = sp
                        if landing then
                            fs = 36
                        end
                        fireSplash(a.fx, pud.top, a.fz, fs)
                        st.wet = now + 1.7
                    end
                elseif not pud and now < st.wet and a.grounded and sp > 2.2 then
                    if now - st.last >= interval then
                        st.last = now
                        st.side = -st.side
                        dropPrint(a.fx, a.fy, a.fz, math.atan2(-a.vx, -a.vz), st.side)
                    end
                end
                st.prevVy = a.vy
            end
        end
        local function startPuddles()
            if _pud.conn then
                return
            end
            local folder = Instance.new("Folder")
            folder.Name = "_wxPuddles"
            folder:SetAttribute("WX_Custom", true)
            folder.Parent = getFolder()
            _pud.folder = folder
            _plist = {}
            _pmap = {}
            table.clear(_pfail)
            _seed = math.random() * 512
            _homeI, _homeJ = 1e9, 1e9
            refreshParams()
            _units, _uIdx = {}, 1
            for i = 1, 8 do
                _units[i] = mkSplashUnit(folder)
            end
            _prints, _pIdx = {}, 1
            for i = 1, 12 do
                local p = mkFlatPart(Vec(0.6, 0.02, 1.0), CFrame.new(0, -900, 0), folder)
                p.Material = Enum.Material.SmoothPlastic
                p.Color = Color3.fromRGB(14, 18, 25)
                p.Reflectance = 0.18
                _prints[i] = p
            end
            local accum = 0
            local mTick = 0
            _pud.conn = RunService.Heartbeat:Connect(function(dt)
                accum = accum + dt
                if accum < 0.05 then
                    return
                end
                accum = 0
                if not pudActive() then
                    return
                end
                mTick = mTick + 1
                local doMaintain = false
                if mTick >= 14 then
                    mTick = 0
                    doMaintain = true
                end
                pcall(tick20, os.clock(), doMaintain)
            end)
        end
        function stopPuddles(hard)
            if _pud.conn then
                _pud.conn:Disconnect()
                _pud.conn = nil
            end
            table.clear(_pstates)
            local folder = _pud.folder
            _pud.folder = nil
            _plist = {}
            _pmap = {}
            table.clear(_pfail)
            _units = {}
            _prints = {}
            _rebuild = false
            if not folder then
                return
            end
            if hard then
                folder:Destroy()
                return
            end
            for _, m in folder:GetDescendants() do
                if m:IsA("ParticleEmitter") then
                    m.Rate = 0
                elseif m:IsA("Part") and m.Transparency < 1 then
                    TweenService:Create(m, TweenInfo.new(1.4, Enum.EasingStyle.Sine), { Transparency = 1 }):Play()
                end
            end
            task.delay(2.2, function()
                pcall(function() folder:Destroy() end)
            end)
        end
        function puddlesRefresh()
            if pudActive() then
                startPuddles()
            else
                stopPuddles(false)
            end
        end
        function puddlesIntensity()
            if not _pud.conn then
                return
            end
            _fieldToken = _fieldToken + 1
            local token = _fieldToken
            task.delay(0.25, function()
                if token ~= _fieldToken then
                    return
                end
                _rebuild = true
            end)
        end
    end)()
    local function startClock()
        if _clockConn then return end
        local accum = 0
        _clockConn = RunService.Heartbeat:Connect(function(dt)
            accum = accum + dt
            if accum < 1 then return end
            accum = 0
            if not Config.Weather or not cfg("WeatherClockDial", false) then return end
            if Config.Visuals then return end
            local cycle = math.max(cfg("WeatherClockCycleMin", 8), 1) * 60
            local t = ((tick() % cycle) / cycle) * 24
            if math.abs(Lighting.ClockTime - t) > 0.02 then
                Lighting.ClockTime = t
            end
        end)
    end
    local function stopClock()
        if _clockConn then _clockConn:Disconnect(); _clockConn = nil end
    end
    local function normType(name)
        if name == "Rain" or name == "BloodMoon" or PRESETS[name] then
            return name
        end
        return "Rain"
    end
    local function applyType(name)
        name = normType(name)
        local prev = _curType
        stopRain(); clearSpecial()
        if #_partLayers > 0 then
            beginLayerFade()
        end
        _curType = name
        if name == "Rain" then
            buildRain(); startRain()
        elseif name == "BloodMoon" then
            buildBloodMoon(); startSpecialAnim()
        else
            local ramp = PRESETS[prev] ~= nil
            local ir = IR[name] or IR_DEF
            for _, spec in PRESETS[name] do
                mkPartLayer(spec, ir, ramp)
            end
        end
        if name == "Fireflies" then startFireflies() else stopFireflies() end
        applyMood(name)
        startAmbient(SOUND[name])
        puddlesRefresh()
    end
    function Weather.setType(name)
        name = normType(name)
        Config.WeatherType = name
        if Config.Weather then applyType(name) end
    end
    local _intensityToken = 0
    function Weather.setIntensity(v)
        Config.WeatherIntensity = math.clamp(v, 0.15, 2)
        if not Config.Weather then return end
        puddlesIntensity()
        local I = Config.WeatherIntensity
        for _, L in _partLayers do
            if L.emitter then
                pcall(tuneLayer, L, I)
                if L.rateTween then L.rateTween:Cancel(); L.rateTween = nil end
                pcall(function() L.emitter.Rate = layerRate(L, I) * L.rateMul end)
            end
        end
        if _special.kind == "BloodMoon" then pcall(tuneBloodMoon, I) end
        if _rays then
            pcall(function()
                _rays.Intensity = 0.10 + 0.18 * I
                _rays.Spread = 1.1 - 0.2 * I
            end)
        end
        _intensityToken = _intensityToken + 1
        local token = _intensityToken
        task.delay(0.12, function()
            if token ~= _intensityToken then return end
            if not Config.Weather then return end
            if _curType == "Rain" then pcall(tuneRain) end
            if _curType then pcall(applyMood, _curType) end
            pcall(refreshFireflies)
        end)
    end
    function Weather.setSoundVolume(v)
        Config.WeatherSoundVolume = v
        if _ambient then pcall(function() _ambient.Volume = v end) end
    end
    function Weather.toggleStorm(on)
        Config.WeatherStorm = on
        if not Config.Weather then return end
        if on then startStorm() else stopStormLoop() end
        puddlesRefresh()
    end
    function Weather.setStormMin(v)
        Config.WeatherStormMin = math.clamp(v, 1, 30)
        rescheduleStorm()
    end
    function Weather.setStormVar(v)
        Config.WeatherStormVar = math.clamp(v, 0, 30)
        rescheduleStorm()
    end
    function Weather.setMeteorRate(v)
        Config.WeatherMeteorRate = math.clamp(v, 0.25, 3)
        rescheduleMeteors()
    end
    function Weather.setStarRate(v)
        Config.WeatherStarRate = math.clamp(v, 0.25, 3)
        rescheduleStars()
    end
    function Weather.togglePuddles(on)
        Config.WeatherPuddles = on
        puddlesRefresh()
    end
    function Weather.toggleMood(on)
        Config.WeatherMood = on
        if Config.Weather and _curType then
            if on then applyMood(_curType) else clearMood() end
        end
    end
    function Weather.toggleMeteors(on)
        Config.WeatherMeteors = on
        if Config.Weather then if on then startMeteors() else stopMeteors() end end
    end
    function Weather.toggleShootingStars(on)
        Config.WeatherShootingStars = on
        if Config.Weather then if on then startStars() else stopStars() end end
    end
    function Weather.toggleClock(on)
        Config.WeatherClockDial = on
        if Config.Weather then if on then startClock() else stopClock() end end
    end
    function Weather.enableWeather()
        Config.Weather = true
        getFolder(); startFollow()
        applyType(cfg("WeatherType", "Rain"))
        if cfg("WeatherStorm", false) then startStorm() end
        if cfg("WeatherMeteors", false) then startMeteors() end
        if cfg("WeatherShootingStars", false) then startStars() end
        if cfg("WeatherClockDial", false) then startClock() end
    end
    function Weather.disableWeather()
        Config.Weather = false
        stopFollow(); stopStorm(); stopRain(); clearPartLayers(); killFade(); clearMood()
        clearSpecial(); stopMeteors(); stopStars(); stopFireflies(); stopLeafDevil(); stopClock()
        stopPuddles(true)
        if _ambient then pcall(function() _ambient:Destroy() end); _ambient = nil end
        _curType = nil
    end
    local SKY = {
        Space     = { Bk="rbxassetid://159454299", Dn="rbxassetid://159454296", Ft="rbxassetid://159454293", Lf="rbxassetid://159454286", Rt="rbxassetid://159454300", Up="rbxassetid://159454288" },
        Sunset    = { Bk="rbxassetid://264908339", Dn="rbxassetid://264907909", Ft="rbxassetid://264909420", Lf="rbxassetid://264909758", Rt="rbxassetid://264908886", Up="rbxassetid://264907379" },
        Clouds    = { Bk="rbxassetid://570557514", Dn="rbxassetid://570557775", Ft="rbxassetid://570557559", Lf="rbxassetid://570557620", Rt="rbxassetid://570557672", Up="rbxassetid://570557727" },
        Storm     = { Bk="rbxassetid://255027929", Dn="rbxassetid://255027967", Ft="rbxassetid://255027923", Lf="rbxassetid://255027938", Rt="rbxassetid://255027946", Up="rbxassetid://255027960" },
        Winter    = { Bk="rbxassetid://402229526", Dn="rbxassetid://402229596", Ft="rbxassetid://402229293", Lf="rbxassetid://402229368", Rt="rbxassetid://402229417", Up="rbxassetid://402229564" },
        Vaporwave = { Bk="rbxassetid://1417494030", Dn="rbxassetid://1417494146", Ft="rbxassetid://1417494253", Lf="rbxassetid://1417494402", Rt="rbxassetid://1417494499", Up="rbxassetid://1417494643" },
    }
    Weather.SkyboxOrder = { "Off", "Space", "Sunset", "Clouds", "Storm", "Winter", "Vaporwave" }
    local _sky, _skyConn = nil, nil
    local _origSkies = {}
    local function hideMapSkies()
        for _, c in ipairs(Lighting:GetChildren()) do
            if c:IsA("Sky") and not c:GetAttribute("WX_Custom") then
                table.insert(_origSkies, c)
                pcall(function() c.Parent = nil end)
            end
        end
    end
    local function restoreMapSkies()
        for i = #_origSkies, 1, -1 do
            local c = _origSkies[i]
            if c and c.Parent == nil then
                pcall(function() c.Parent = Lighting end)
            end
            _origSkies[i] = nil
        end
    end
    local function buildSky(preset)
        local set = SKY[preset]; if not set then return end
        hideMapSkies()
        local s = Instance.new("Sky")
        s.Name = "_wxSky"; s:SetAttribute("WX_Custom", true)
        s.SkyboxBk, s.SkyboxDn, s.SkyboxFt = set.Bk, set.Dn, set.Ft
        s.SkyboxLf, s.SkyboxRt, s.SkyboxUp = set.Lf, set.Rt, set.Up
        if cfg("SkyboxHideCelestial", false) then
            s.SunAngularSize = 0; s.MoonAngularSize = 0; s.StarCount = 0
            s.CelestialBodiesShown = false
        else
            s.CelestialBodiesShown = true
        end
        s.Parent = Lighting
        _sky = s
    end
    local function startSkyGuard()
        if _skyConn then return end
        _skyConn = Lighting.ChildAdded:Connect(function(c)
            if c:IsA("Sky") and not c:GetAttribute("WX_Custom") and Config.SkyboxPreset and Config.SkyboxPreset ~= "Off" then
                table.insert(_origSkies, c)
                pcall(function() c.Parent = nil end)
            end
        end)
    end
    local function stopSkyGuard()
        if _skyConn then _skyConn:Disconnect(); _skyConn = nil end
    end
    local function clearSky()
        if _sky then pcall(function() _sky:Destroy() end); _sky = nil end
        restoreMapSkies()
    end
    function Weather.setSkybox(preset)
        if preset and not SKY[preset] then preset = "Off" end
        Config.SkyboxPreset = preset
        clearSky()
        if preset == "Off" or preset == nil then stopSkyGuard(); return end
        buildSky(preset); startSkyGuard()
    end
    function Weather.toggleCelestial(hide)
        Config.SkyboxHideCelestial = hide
        if _sky then
            if hide then
                _sky.SunAngularSize = 0; _sky.MoonAngularSize = 0; _sky.StarCount = 0
                _sky.CelestialBodiesShown = false
            else
                _sky.SunAngularSize = 11; _sky.MoonAngularSize = 11; _sky.StarCount = 3000
                _sky.CelestialBodiesShown = true
            end
        end
    end
    local _rainbow = { host = nil, conn = nil }
    local RB_BANDS = {
        { Color3.fromRGB(255, 40, 40),  0.10, 24 },
        { Color3.fromRGB(255, 130, 20), 0.12, 24 },
        { Color3.fromRGB(255, 225, 40), 0.14, 24 },
        { Color3.fromRGB(60, 210, 70),  0.16, 24 },
        { Color3.fromRGB(40, 130, 255), 0.18, 24 },
        { Color3.fromRGB(85, 60, 235),  0.26, 18 },
        { Color3.fromRGB(165, 65, 230), 0.30, 16 },
    }
    local RB_DIST, RB_OY = 430, -20
    local function clearRainbow()
        if _rainbow.conn then _rainbow.conn:Disconnect(); _rainbow.conn = nil end
        if _rainbow.host then pcall(function() _rainbow.host:Destroy() end); _rainbow.host = nil end
    end
    local function buildRainbow()
        local host = Instance.new("Part")
        host.Name = "_wxRainbow"; host.Anchored = true; host.CanCollide = false; host.CanQuery = false
        host.CanTouch = false; host.CastShadow = false; host.Massless = true; host.Transparency = 1
        host.Size = Vec(1, 1, 1); host:SetAttribute("WX_Custom", true)
        local rot = CFrame.Angles(0, 0, math.rad(90))
        local function band(sp, rr, w, col, midT, emit, soft)
            local a0 = Instance.new("Attachment"); a0.CFrame = CFrame.new(-sp, 0, 0) * rot; a0.Parent = host
            local a1 = Instance.new("Attachment"); a1.CFrame = CFrame.new( sp, 0, 0) * rot; a1.Parent = host
            local b = Instance.new("Beam")
            b.Attachment0 = a0; b.Attachment1 = a1; b.Segments = 46; b.FaceCamera = true
            if soft then b.Texture = TX_SOFT; b.TextureMode = Enum.TextureMode.Stretch; b.TextureLength = 1 end
            b.Width0 = w; b.Width1 = w; b.CurveSize0 = rr; b.CurveSize1 = -rr
            b.LightEmission = emit; b.LightInfluence = 0
            b.Color = ColorSequence.new(col)
            local edge = math.min(midT + 0.25, 1)
            b.Transparency = NumberSequence.new({
                NSK(0, 1), NSK(0.08, edge), NSK(0.45, midT), NSK(0.55, midT), NSK(0.92, edge), NSK(1, 1) })
            b.Parent = host
        end
        for i = 1, #RB_BANDS do
            local B = RB_BANDS[i]
            band(340, 320 - (i - 1) * 15, B[3], B[1], B[2], 0.42, false)
        end
        band(340, 165, 52, Color3.fromRGB(242, 248, 255), 0.78, 0.6, true)
        for i = 1, #RB_BANDS do
            band(400, 355 + (i - 1) * 12, 20, RB_BANDS[i][1], 0.64 + i * 0.012, 0.42, false)
        end
        host.Parent = getFolder()
        _rainbow.host = host
    end
    local function startRainbowFollow()
        if _rainbow.conn then return end
        local accum = 0
        _rainbow.conn = RunService.Heartbeat:Connect(function(dt)
            if not cfg("WeatherRainbow", false) then return end
            accum = accum + dt; if accum < 0.08 then return end
            accum = 0
            local cam = Camera; if not cam then return end
            local host = _rainbow.host; if not host or not host.Parent then return end
            local p = cam.CFrame.Position
            local hp = Vec(p.X, p.Y + RB_OY, p.Z - RB_DIST)
            host.CFrame = CFrame.lookAt(hp, Vec(p.X, hp.Y, p.Z))
        end)
    end
    function Weather.toggleRainbow(on)
        Config.WeatherRainbow = on
        clearRainbow()
        if not on then return end
        buildRainbow(); startRainbowFollow()
    end
    function Weather.toggleGodRays(on)
        Config.WeatherGodRays = on
        if _rays then pcall(function() _rays:Destroy() end); _rays = nil end
        if not on then return end
        local r = Instance.new("SunRaysEffect")
        r.Name = "_wxRays"; r:SetAttribute("WX_Custom", true)
        local I = iAmt()
        r.Intensity = 0.10 + 0.18 * I
        r.Spread = 1.1 - 0.2 * I
        r.Parent = Lighting
        _rays = r
    end
    function Weather.init()
        if Config.Weather then pcall(Weather.enableWeather) end
        if Config.SkyboxPreset and Config.SkyboxPreset ~= "Off" then pcall(Weather.setSkybox, Config.SkyboxPreset) end
        if Config.WeatherGodRays then pcall(Weather.toggleGodRays, true) end
        if Config.WeatherRainbow then pcall(Weather.toggleRainbow, true) end
    end
    function Weather.unload()
        pcall(Weather.disableWeather)
        stopSkyGuard(); clearSky(); clearRainbow()
        if _rays then pcall(function() _rays:Destroy() end); _rays = nil end
        if _folder then pcall(function() _folder:Destroy() end); _folder = nil end
        _lightFolder = nil
    end
end)()
local HUDPlus = {}
;(function()
    local hasDrawing = screenDraw ~= nil
    local C_TEXT1  = Color3.fromRGB(243, 246, 250)
    local C_TEXT2  = Color3.fromRGB(174, 185, 197)
    local C_GOLD   = Color3.fromRGB(255, 194, 75)
    local C_ENEMY  = Color3.fromRGB(255, 59, 78)
    local C_EDGE   = Color3.fromRGB(155, 232, 255)
    local C_BLACK  = Color3.new(0, 0, 0)
    local PI  = math.pi
    local TAU = PI * 2
    local RAD60 = math.rad(60)
    local _alloc = false
    local _cRail, _cRailCas = nil, nil
    local _cTicks = nil
    local _cCard  = nil
    local _cCaret = nil
    local _cPips  = nil
    local _cPill  = nil
    local _taSeg, _taSegCas = nil, nil
    local _rng = nil
    local _conn = nil
    local _started = false
    local _thrT = 0
    local _pip = {}
    local function nd(kind, props)
        if not hasDrawing then return nil end
        local ok, d = pcall(screenDraw, kind, "fx")
        if not ok or not d then return nil end
        d.Visible = false
        if props then for k, v in pairs(props) do pcall(function() d[k] = v end) end end
        return d
    end
    local function alloc()
        if _alloc then return end
        _alloc = true
        _cRailCas = nd("Line", { Color = C_BLACK, Thickness = 3 })
        _cRail    = nd("Line", { Color = C_TEXT2, Thickness = 1 })
        _cTicks = {}
        for i = 1, 10 do _cTicks[i] = nd("Line", { Thickness = 1 }) end
        _cCard = {}
        for i = 1, 4 do _cCard[i] = nd("Text", { Center = true, Outline = true, Font = 3, Size = 11 }) end
        _cCaret = nd("Triangle")
        _cPips = {}
        for i = 1, 8 do _cPips[i] = nd("Circle", { Filled = true, NumSides = 12 }) end
        _cPill = nd("Text", { Center = true, Outline = true, Font = 3, Size = 11, Color = C_ENEMY })
        _taSegCas = {}
        for i = 1, 9 do _taSegCas[i] = nd("Line", { Color = C_BLACK, Thickness = 4 }) end
        _taSeg = {}
        for i = 1, 9 do _taSeg[i] = nd("Line", { Thickness = 2 }) end
        _rng = nd("Text", { Center = true, Outline = true, Font = 3, Size = 13, Color = C_TEXT1 })
    end
    local function hideCompass()
        if _cRail then _cRail.Visible = false; _cRailCas.Visible = false end
        if _cTicks then for i = 1, #_cTicks do _cTicks[i].Visible = false end end
        if _cCard then for i = 1, 4 do _cCard[i].Visible = false end end
        if _cCaret then _cCaret.Visible = false end
        if _cPips then for i = 1, #_cPips do _cPips[i].Visible = false end end
        if _cPill then _cPill.Visible = false end
    end
    local function hideArc()
        if _taSeg then for i = 1, 9 do _taSeg[i].Visible = false; _taSegCas[i].Visible = false end end
    end
    local function hideRange() if _rng then _rng.Visible = false end end
    local function hideAll()
        hideCompass(); hideArc(); hideRange()
    end
    local CARDINALS = {
        { "N", 0, 0, -1, true  },
        { "E", 1, 0,  0, false },
        { "S", 0, 0,  1, false },
        { "W", -1, 0, 0, false },
    }
    local function wrap(a)
        a = (a + PI) % TAU
        if a < 0 then a = a + TAU end
        return a - PI
    end
    local function drawCompass(vp, camYaw, y)
        local railW = math.floor(math.max(Config.HUDCompassWidth or 380, 120))
        local half = railW * 0.5
        local cxp = math.floor(vp.X * 0.5)
        local lx, rx = cxp - half, cxp + half
        _cRailCas.From = Vector2.new(lx, y); _cRailCas.To = Vector2.new(rx, y)
        _cRailCas.Transparency = 0.5; _cRailCas.Visible = true
        _cRail.From = Vector2.new(lx, y); _cRail.To = Vector2.new(rx, y)
        _cRail.Transparency = 0.85; _cRail.Visible = true
        local base = math.floor(math.deg(camYaw) / 15 + 0.5) * 15
        local shown = 0
        for k = -4, 4 do
            local degA = base + k * 15
            local rel = wrap(math.rad(degA) - camYaw)
            if rel >= -RAD60 and rel <= RAD60 then
                shown = shown + 1
                local L = _cTicks[shown]
                if L then
                    local tx = math.floor(cxp + (rel / RAD60) * half)
                    local tall = (degA % 45 == 0) and 7 or 4
                    L.From = Vector2.new(tx, y - tall); L.To = Vector2.new(tx, y)
                    L.Color = C_TEXT2; L.Transparency = 0.45; L.Visible = true
                end
            end
        end
        for i = shown + 1, #_cTicks do _cTicks[i].Visible = false end
        for i = 1, 4 do
            local c = CARDINALS[i]
            local bearing = math.atan2(c[2], c[4])
            local rel = wrap(bearing - camYaw)
            local T = _cCard[i]
            if T then
                if rel >= -RAD60 and rel <= RAD60 then
                    local tx = math.floor(cxp + (rel / RAD60) * half)
                    T.Position = Vector2.new(tx, y - 22)
                    T.Text = c[1]; T.Color = c[5] and C_GOLD or C_TEXT2
                    T.Transparency = 1; T.Visible = true
                else T.Visible = false end
            end
        end
        if _cCaret then
            local glint = 0.5 + 0.5 * math.sin((tick()) * 1.6 * TAU)
            _cCaret.Filled = true
            _cCaret.PointA = Vector2.new(cxp, y + 7)
            _cCaret.PointB = Vector2.new(cxp - 5, y + 1)
            _cCaret.PointC = Vector2.new(cxp + 5, y + 1)
            _cCaret.Color = C_EDGE
            _cCaret.Transparency = 0.65 + 0.35 * glint
            _cCaret.Visible = true
        end
    end
    local function update()
        if not (Config.HUD and hasDrawing) then hideAll(); return end
        local now = tick()
        if now - _thrT < 0.033 then return end
        _thrT = now
        local cam = Camera; if not cam then return end
        local vp = cam.ViewportSize
        local cx, cy = vp.X * 0.5, vp.Y * 0.5
        local compassOn = Config.HUDCompass
        local arcOn     = Config.HUDThreatArc
        local rangeOn   = Config.HUDRangeReadout
        local myC = lp.Character
        local myR = myC and myC:FindFirstChild("HumanoidRootPart")
        local myPos = myR and myR.Position
        local camPos = cam.CFrame.Position
        local look = cam.CFrame.LookVector
        local camYaw = math.atan2(look.X, look.Z)
        local nearD, nearRel = math.huge, 0
        local pipN, offCount = 0, 0
        if compassOn or arcOn or rangeOn then
            local players = getSafePlayers()
            for i = 1, #players do
                local pl = players[i]
                if pl ~= lp and not isTeammate(pl) and isAlive(pl) then
                    local ch = pl.Character
                    local r = ch and ch:FindFirstChild("HumanoidRootPart")
                    if r then
                        local pos = r.Position
                        local dx, dz = pos.X - camPos.X, pos.Z - camPos.Z
                        local rel = wrap(math.atan2(dx, dz) - camYaw)
                        local d = myPos and (myPos - pos).Magnitude
                            or math.sqrt(dx * dx + dz * dz)
                        if d < nearD then nearD = d; nearRel = rel end
                        if rel < -RAD60 or rel > RAD60 then offCount = offCount + 1 end
                        if compassOn and pipN < 8 then
                            pipN = pipN + 1
                            local e = _pip[pipN]; if not e then e = {}; _pip[pipN] = e end
                            e.rel = rel; e.dist = d
                        end
                    end
                end
            end
        end
        if compassOn then
            local y = 26
            drawCompass(vp, camYaw, y)
            local half = math.max(Config.HUDCompassWidth or 380, 120) * 0.5
            local cxp = math.floor(cx)
            local maxD = math.max(Config.ESPMaxDistance or 1200, 1)
            local drawPips = Config.HUDCompassPips and pipN or 0
            for i = 1, drawPips do
                local e = _pip[i]
                local P = _cPips[i]
                if P then
                    local rel = e.rel
                    local clamped = rel
                    if clamped < -RAD60 then clamped = -RAD60 elseif clamped > RAD60 then clamped = RAD60 end
                    local edge = (rel < -RAD60 or rel > RAD60)
                    local px = math.floor(cxp + (clamped / RAD60) * half)
                    local a = 1 - 0.6 * math.clamp(e.dist / maxD, 0, 1)
                    if edge then a = a * 0.4 end
                    P.Radius = 2; P.Position = Vector2.new(px, 26)
                    P.Color = C_ENEMY; P.Transparency = a; P.Visible = true
                end
            end
            for i = drawPips + 1, #_cPips do _cPips[i].Visible = false end
            if _cPill then
                if offCount > 0 then
                    _cPill.Text = "\226\150\178" .. offCount
                    _cPill.Position = Vector2.new(math.floor(cxp + half + 16), 20)
                    _cPill.Transparency = 1; _cPill.Visible = true
                else _cPill.Visible = false end
            end
        else hideCompass() end
        if arcOn and _taSeg and nearD < math.huge then
            local R = 42
            local width = math.rad(30)
            local step = width / 9
            local th0 = nearRel - width * 0.5
            local dfrac = math.clamp((nearD - 25) / (300 - 25), 0, 1)
            local col = C_GOLD:Lerp(C_TEXT2, dfrac)
            local a = 1 - 0.75 * dfrac
            for j = 1, 9 do
                local t1 = th0 + step * (j - 1)
                local t2 = t1 + step * 0.72
                local p1 = Vector2.new(cx + math.sin(t1) * R, cy - math.cos(t1) * R)
                local p2 = Vector2.new(cx + math.sin(t2) * R, cy - math.cos(t2) * R)
                local cs = _taSegCas[j]
                if cs then cs.From = p1; cs.To = p2; cs.Transparency = a * 0.8; cs.Visible = true end
                local L = _taSeg[j]
                if L then L.From = p1; L.To = p2; L.Color = col; L.Transparency = a; L.Visible = true end
            end
        else hideArc() end
        if rangeOn and _rng then
            if nearD < math.huge then
                _rng.Text = ("%dm"):format(math.floor(nearD + 0.5))
                _rng.Position = Vector2.new(math.floor(cx), math.floor(cy + 64))
                _rng.Transparency = 1; _rng.Visible = true
            else _rng.Visible = false end
        else hideRange() end
    end
    function HUDPlus.start()
        if _started then return end
        _started = true
        alloc()
        if not _conn then
            _conn = RunService.RenderStepped:Connect(function() if _started then pcall(update) end end)
        end
    end
    function HUDPlus.stop()
        if not _started then return end
        _started = false
        if _conn then _conn:Disconnect(); _conn = nil end
        hideAll()
    end
    function HUDPlus.init()
        if Config.HUD then pcall(HUDPlus.start) end
    end
    function HUDPlus.unload()
        pcall(HUDPlus.stop)
    end
end)()
local Rage = {}
;(function()
    local _tgtConn  = nil
    local _labConn  = nil
    local function bump(p) State.RageCharTokens[p] = (State.RageCharTokens[p] or 0) + 1 end
    local function killFloor()
        return workspace.FallenPartsDestroyHeight + Config.RageKillPlaneBuffer
    end
    local function hasLOS(fromPos, toPos, ignore)
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.FilterDescendantsInstances = ignore
        local res = workspace:Raycast(fromPos, toPos - fromPos, rp)
        if not res then return true end
        return (res.Position - toPos).Magnitude < 3
    end
    local function lookCF(fromPos, toPos)
        local dir = toPos - fromPos
        if dir.Magnitude < 1e-4 then dir = Vector3.new(0, -1, 0) end
        local up = Vector3.new(0, 1, 0)
        if math.abs(dir.Unit.Y) > 0.999 then up = Vector3.new(0, 0, 1) end
        return CFrame.lookAt(fromPos, fromPos + dir, up)
    end
    Rage._lookCF = lookCF
    local function buildShotFields(camData, eyeCF, muzzleCF, hitPart, aimWorldPos, jitter, clampFrac, jitterFrac)
        local objSpace = hitPart.CFrame:PointToObjectSpace(aimWorldPos)
        local hs = hitPart.Size * (clampFrac or 0.45)
        objSpace = Vector3.new(
            math.clamp(objSpace.X, -hs.X, hs.X),
            math.clamp(objSpace.Y, -hs.Y, hs.Y),
            math.clamp(objSpace.Z, -hs.Z, hs.Z)
        )
        if jitter then
            local jf = jitterFrac or 1.0
            objSpace = Vector3.new(
                math.clamp(objSpace.X + (math.random() - 0.5) * hs.X * jf, -hs.X, hs.X),
                math.clamp(objSpace.Y + (math.random() - 0.5) * hs.Y * jf, -hs.Y, hs.Y),
                math.clamp(objSpace.Z + (math.random() - 0.5) * hs.Z * jf, -hs.Z, hs.Z)
            )
        end
        local hitWorld   = hitPart.CFrame:PointToWorldSpace(objSpace)
        local objSpaceCF = hitPart.CFrame:ToObjectSpace(CFrame.new(hitWorld))
        camData[utf8.char(0)] = Rivals.Util:EncodeCFrame(eyeCF)
        camData[utf8.char(1)] = Rivals.Util:EncodeCFrame(muzzleCF)
        camData[utf8.char(2)] = hitPart
        camData[utf8.char(3)] = Rivals.Util:EncodeCFrame(objSpaceCF)
    end
    Rage._buildShotFields = buildShotFields
    local RAGE_CLAMP_FRAC  = 0.30
    local RAGE_JITTER_FRAC = 1.0
    local function encodeShot(camData, hitPart, targetChar, fromCamPos, claimOffset)
        if not hitPart or not camData or not Rivals.Util then return false end
        local lead      = calculateLead(targetChar, fromCamPos)
        local off       = (typeof(claimOffset) == "Vector3") and claimOffset or Vector3.zero
        local leadedPos = hitPart.Position + lead + off
        local eyeCF     = lookCF(fromCamPos, leadedPos)
        local muzzlePos = fromCamPos + (eyeCF.RightVector * 0.2) + Vector3.new(0, -Config.RageEyeMuzzleSep, 0)
        local muzzleCF  = lookCF(muzzlePos, leadedPos)
        buildShotFields(camData, eyeCF, muzzleCF, hitPart, leadedPos, Config.SilentAimJitter, 0.45, 1.0)
        return true
    end
    Rage._encodeShot = encodeShot
    local PICK_SLOT = { Primary = 1, Secondary = 2, Melee = 3 }
    ;(function()
        local function fighterItems()
            local lf = Rivals.Fighter and Rivals.Fighter.LocalFighter
            return lf and lf.Items or nil
        end
        local function itemIsMelee(item)
            if not item then return false end
            local viaInfo = false
            pcall(function()
                local info = item.Info
                if info == nil then return end
                if info.Type == "Melee" or info.Class == "Melee" then viaInfo = true return end
                if type(info.AttackReach) == "number" and info.MaxAmmo == nil then viaInfo = true end
            end)
            if viaInfo then return true end
            local okN, nm = pcall(function() return item:Get("Name") or item.Name end)
            if okN and type(nm) == "string" and nm:lower():find("melee", 1, true) then return true end
            return false
        end
        Rage._itemIsMelee = itemIsMelee
        local function itemAmmo(item)
            if not item then return nil end
            local ok, a = pcall(function() return item:Get("Ammo") or item:Get("CurrentAmmo") end)
            if ok and type(a) == "number" then return a end
            return nil
        end
        local function slotItemByIndex(idx)
            local items = fighterItems(); if not items then return nil end
            if items[idx] then return items[idx] end
            if items[tostring(idx)] then return items[tostring(idx)] end
            for key, it in pairs(items) do
                if it and typeof(it) == "table" then
                    local okS, s = pcall(function() return tonumber(it:Get("Slot") or it:Get("Index") or it:Get("ItemSlot") or key) end)
                    if okS and s == idx then return it end
                    local okT, t = pcall(function() return it:Get("ItemType") or it:Get("Type") end)
                    if okT then
                        if idx == 1 and (t == "Primary" or t == 1 or t == "1") then return it end
                        if idx == 2 and (t == "Secondary" or t == 2 or t == "2") then return it end
                        if idx == 3 and (t == "Melee" or (type(t) == "string" and t:lower():find("melee", 1, true))) then return it end
                    end
                end
            end
            return nil
        end
        local function whichSlotNow()
            local cur = getEquippedItem(); if not cur then return nil end
            local okId, oid = pcall(function() return cur:Get("ObjectID") end)
            if okId and oid then
                for idx = 1, 3 do
                    local it = slotItemByIndex(idx)
                    if it then
                        local okI, iid = pcall(function() return it:Get("ObjectID") end)
                        if okI and iid == oid then return idx end
                    end
                end
            end
            if itemIsMelee(cur) then return 3 end
            return nil
        end
        local function slotUsable(idx)
            local it = slotItemByIndex(idx); if not it then return false end
            if itemIsMelee(it) then return Config.RageSwitchMelee == true end
            local a = itemAmmo(it)
            return a == nil or a > 0
        end
        local function slotOrder()
            local pref = PICK_SLOT[Config.RageWeaponPick] or 1
            local order = { pref }
            for _, s in ipairs({ 1, 2, 3 }) do
                if s ~= pref then order[#order + 1] = s end
            end
            if not Config.RageSwitchMelee then
                local filtered = {}
                for _, s in ipairs(order) do if s ~= 3 then filtered[#filtered + 1] = s end end
                order = filtered
            end
            return order
        end
        local function nextUsableSlot(excludeIdx)
            for _, s in ipairs(slotOrder()) do
                if s ~= excludeIdx and slotUsable(s) then return s end
            end
            return nil
        end
        local function equipSlot(idx)
            if not idx then return false end
            if whichSlotNow() == idx then return true end
            local now = tick()
            if now - (State.RageSwitchLast or 0) < (Config.RageSwitchRateLimit or 0.06) then return false end
            State.RageSwitchLast = now
            local lf = Rivals.Fighter and Rivals.Fighter.LocalFighter
            local equipped = false
            if lf and lf.EquipItem then
                equipped = pcall(function() lf:EquipItem(idx) end)
            end
            if not equipped then
                pcall(function()
                    local kc = ({ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three })[idx]
                    if kc then
                        VirtualInputMgr:SendKeyEvent(true, kc, false, game)
                        VirtualInputMgr:SendKeyEvent(false, kc, false, game)
                    end
                end)
            end
            return true
        end
        Rage._equipSlot = equipSlot
        Rage._nextUsableSlot = nextUsableSlot
        Rage._whichSlotNow = whichSlotNow
    end)()
    local function encodeRageShot(camData)
        if tick() - (State.RageFireStamp or 0) > 0.03 then return false end
        local hitPart = State.RageFireHitPart
        local eyePos  = State.RageFireFromPos
        local aimPos  = State.RageFireAimPos
        if not (hitPart and hitPart.Parent and eyePos and aimPos) then return false end
        if not isSanePos(eyePos) or not isSanePos(hitPart.Position) then return false end
        if (hitPart.Position - eyePos).Magnitude > (400 - 5) then return false end
        local ignore = { lp.Character }
        local t = State.RageTarget or State.Target
        if t and t.Character then ignore[2] = t.Character end
        if not hasLOS(eyePos, hitPart.Position, ignore) then return false end
        local item = getEquippedItem(); if not item then return false end
        local okE, equipping = pcall(function() return item:IsEquipping() end)
        if okE and equipping then return false end
        if not (Rage._itemIsMelee and Rage._itemIsMelee(item)) then
            local okR, reloading = pcall(function() return (item._reload_cooldown or 0) > tick() end)
            if okR and reloading then return false end
            local okA, ammo = pcall(function() return item:Get("Ammo") end)
            if not okA or type(ammo) ~= "number" or ammo <= 0 then return false end
        end
        local now = tick()
        local interval = 0
        if Rage._fireInterval then interval = Rage._fireInterval() end
        if now - (State.RageLastFireTime or 0) < interval then return false end
        State.RageLastFireTime = now
        local eyeCF    = lookCF(eyePos, aimPos)
        local muzzleCF = eyeCF - Vector3.new(0, Config.RageEyeMuzzleSep, 0)
        buildShotFields(camData, eyeCF, muzzleCF, hitPart, aimPos, true, RAGE_CLAMP_FRAC, RAGE_JITTER_FRAC)
        State.Shots = State.Shots + 1
        return true
    end
    local function findTarget()
        local myChar = lp.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        local cands  = {}
        for _, p in ipairs(getSafePlayers()) do
            if isValidTarget(p, Config.RageVisCheck, true, true) then
                local hum = p.Character:FindFirstChildOfClass("Humanoid")
                local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                local d = 9999
                local sane = myRoot ~= nil and hrp ~= nil and isSanePos(hrp.Position)
                if sane then d = (hrp.Position - myRoot.Position).Magnitude end
                if (not sane) or d <= (Config.MaxDistance or 1200) then
                    table.insert(cands, { p = p, hp = hum.Health, d = d })
                end
            end
        end
        if #cands == 0 then return nil end
        if Config.RageHPPriority then
            table.sort(cands, function(a, b)
                if math.abs(a.hp - b.hp) > 10 then return a.hp < b.hp end
                return a.d < b.d
            end)
        else
            table.sort(cands, function(a, b) return a.d < b.d end)
        end
        return cands[1].p
    end
    Rage._findTarget = findTarget
    local function findTargetHeadSane()
        local myChar = lp.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        local cands  = {}
        for _, p in ipairs(getSafePlayers()) do
            if isValidTarget(p, Config.RageVisCheck, true, true) then
                local hum = p.Character:FindFirstChildOfClass("Humanoid")
                local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                local hh  = p.Character:FindFirstChild("HitboxHead") or p.Character:FindFirstChild("Head")
                local headSane = false
                if hh and isSanePos(hh.Position) then headSane = true end
                local d = 9999
                if myRoot and hrp and isSanePos(hrp.Position) then d = (hrp.Position - myRoot.Position).Magnitude end
                table.insert(cands, { p = p, hp = hum.Health, d = d, s = headSane })
            end
        end
        if #cands == 0 then return nil end
        table.sort(cands, function(a, b)
            if a.s ~= b.s then return a.s end
            if Config.RageHPPriority and math.abs(a.hp - b.hp) > 10 then return a.hp < b.hp end
            return a.d < b.d
        end)
        return cands[1].p
    end
    Rage._findTargetHeadSane = findTargetHeadSane
    local _meleeLogAt = 0
    local function meleeReadout()
        if Config.RageMeleeLog == false then return end
        local now = tick()
        if now - _meleeLogAt < 1 then return end
        local lf = Rivals.Fighter and Rivals.Fighter.LocalFighter
        local item = lf and lf.EquippedItem
        if not item then return end
        if not (Rage._itemIsMelee and Rage._itemIsMelee(item)) then return end
        _meleeLogAt = now
        local mode = Config.RageMode or "Polar"
        if mode ~= "Polar" then
            print("[LuaHook] melee: the knife bot is POLAR-ONLY and rage mode is " .. mode
                .. " — no melee code runs at all in this mode. Switch Rage > Mode to Polar.")
            return
        end
        local why = State.RageKnifeStatus
        if why == nil then
            why = "NEVER REACHED (rage=" .. tostring(State.RageStatus) .. ")"
        end
        print("[LuaHook] melee=" .. tostring(why)
            .. " swings=" .. tostring(State.RageKnifeSwings or 0)
            .. " rage=" .. tostring(State.RageStatus)
            .. " target=" .. tostring(State.RageTarget and State.RageTarget.Name or "none"))
    end
    local function startTargetLoop()
        if _tgtConn then _tgtConn:Disconnect() end
        local lastPosMap, lastTimeMap = {}, {}
        _tgtConn = RunService.Heartbeat:Connect(function()
            if not Config.Rage then return end
            pcall(meleeReadout)
            local nowTime = tick()
            local safe = getSafePlayers() or {}
            for i = 1, #safe do
                local p = safe[i]
                if p ~= lp and p.Character then
                    local pRoot = p.Character:FindFirstChild("HumanoidRootPart")
                    if pRoot then
                        local currentPos = pRoot.Position
                        if lastPosMap[p] and lastTimeMap[p] then
                            local dt = nowTime - lastTimeMap[p]
                            if dt > 0 then State.RageTrueVelocityMap[p] = (currentPos - lastPosMap[p]) / dt end
                        end
                        lastPosMap[p] = currentPos
                        lastTimeMap[p] = nowTime
                    end
                end
            end
            if Config.RageFastTargetSwitch and State.Target and not isValidTarget(State.Target, false, true, true) then
                State.Target = nil
            end
            State.Target = findTarget()
        end)
    end
    Rage._startTargetLoop = startTargetLoop
    local function startLabPoll()
        if _labConn then return end
        local lastHP = {}
        _labConn = RunService.Heartbeat:Connect(function()
            if not Config.RageLab then return end
            local safe = getSafePlayers() or {}
            for i = 1, #safe do
                local p = safe[i]
                if p ~= lp then
                    local c = p.Character
                    local hum = c and c:FindFirstChildOfClass("Humanoid")
                    if hum then
                        local h, last = hum.Health, lastHP[p]
                        if last and h < last - 0.5 then
                            State.RageDealtTotal = (State.RageDealtTotal or 0) + (last - h)
                            if p == State.Target then State.Hits = State.Hits + 1 end
                        end
                        lastHP[p] = h
                    else
                        lastHP[p] = nil
                    end
                end
            end
        end)
    end
    Rage._startLabPoll = startLabPoll
    Rage._isCheater = function() return false end
    function Rage.init()
        for _, p in ipairs(getSafePlayers()) do bump(p) end
        Players.PlayerAdded:Connect(function(p)
            bump(p)
            p.CharacterAdded:Connect(function() bump(p) end)
        end)
        for _, p in ipairs(getSafePlayers()) do
            p.CharacterAdded:Connect(function() bump(p) end)
        end
        Players.PlayerRemoving:Connect(function(p)
            State.RageCharTokens[p] = nil
        end)
        lp.CharacterAdded:Connect(function()
            bump(lp)
            State.RageRealCF = nil; State.RageRealChar = nil
            State.RageParkDirty = false
            State.RageTarget = nil
        end)
        bump(lp)
        startLabPoll()
    end
    local _rageConn, _rageCharConn = nil, nil
    local _rageStepConn = nil
    local _rageRestoreName = "__lh_rage_restore"
    local _rageDiedConn = nil
    local _rageCooldownConn = nil
    local function fireInterval()
        return Config.RageFireRateOverride or 0
    end
    Rage._fireInterval = fireInterval
    local _preParkCF = nil
    local _identGet, _identSet, _identTried = nil, nil, false
    local function rawSetCFrame(hrp, cf)
        if not _identTried then
            _identTried = true
            pcall(function()
                local g = getthreadidentity or get_thread_identity
                local s = setthreadidentity or set_thread_identity or setidentity or setthreadcontext
                if type(g) == "function" and type(s) == "function" then _identGet, _identSet = g, s end
            end)
        end
        if _identSet ~= nil then
            local okPrev, prev = pcall(_identGet)
            if okPrev then
                pcall(_identSet, 8)
                local wrote = pcall(function() hrp.CFrame = cf end)
                pcall(_identSet, prev)
                if wrote then return true end
            end
        end
        return pcall(function() hrp.CFrame = cf end)
    end
    local function displace(hrp, cf)
        if _preParkCF == nil then _preParkCF = hrp.CFrame end
        return rawSetCFrame(hrp, cf)
    end
    Rage._displace = displace
    local ORBIT_PRIME_S   = 0.07
    local ORBIT_JITTER_MAX = 0.25
    local ORBIT_JUMP      = 5
    local _orbHiding      = true
    local _orbPrimeUntil  = 0
    local ORB_IMMUNE_MAX_HOLD = 6.0
    local _orbImmuneSince, _orbImmuneTgt = 0, nil
    local _orbLastDisp    = nil
    local function voidAxis()
        local v = math.random(110000, 140000)
        if math.random(0, 1) == 0 then
            return -v
        end
        return v
    end
    local function rollVoid()
        return CFrame.new(voidAxis(), math.random(110000, 140000), voidAxis())
    end
    local function stepClears(cf, prev, minStep)
        if not prev then return true end
        return (cf.Position - prev.Position).Magnitude >= minStep
    end
    local function voidCFrame()
        local now = tick()
        if not Config.RageVoidMove then
            if (not State.RageVoidCF) or now >= (State.RageVoidNext or 0) then
                State.RageVoidCF   = rollVoid()
                State.RageVoidNext = now + 4 + math.random() * 4
            end
            return State.RageVoidCF
        end
        local prev = State.RageVoidCF
        local cf
        if Config.RageVoidJitterLocal then
            if (not State.RageVoidBase) or now >= (State.RageVoidNext or 0) then
                State.RageVoidBase = rollVoid()
                State.RageVoidNext = now + 4 + math.random() * 4
            end
            local base = State.RageVoidBase.Position
            local span = Config.RageVoidJitterStuds or 2000
            local function offset()
                local v = 500 + math.random() * (span - 500)
                if math.random(0, 1) == 0 then
                    return -v
                end
                return v
            end
            local tries = 0
            repeat
                cf = CFrame.new(base.X + offset(), math.max(base.Y + offset(), 110000), base.Z + offset())
                tries = tries + 1
            until tries >= 8 or stepClears(cf, prev, 600)
        else
            local minStep = Config.RageVoidMinStep or 25000
            local tries = 0
            repeat
                cf = rollVoid()
                tries = tries + 1
            until tries >= 8 or stepClears(cf, prev, minStep)
        end
        State.RageVoidCF    = cf
        State.RageVoidSteps = (State.RageVoidSteps or 0) + 1
        return cf
    end
    local function weaponReady(it)
        if not it then return false end
        local okE, equipping = pcall(function() return it:IsEquipping() end)
        if okE and equipping then return false end
        if (it._reload_cooldown or 0) > tick() then return false end
        if Rage._itemIsMelee and Rage._itemIsMelee(it) then return true end
        local okA, ammo = pcall(function() return it:Get("Ammo") end)
        return okA and type(ammo) == "number" and ammo > 0
    end
    Rage._ensureReload = function(it)
        if it == nil then return "no item" end
        local okR, reloading = pcall(function() return (it._reload_cooldown or 0) > tick() end)
        if okR and reloading then return "waiting" end
        local okA, ammo = pcall(function() return it:Get("Ammo") end)
        if okA and type(ammo) == "number" and ammo > 0 then return "loaded" end
        local okRes, reserve = pcall(function() return it:Get("AmmoReserve") end)
        if okRes and type(reserve) == "number" and reserve <= 0 then
            local okInf, inf = pcall(function()
                return it.ClientFighter ~= nil and it.ClientFighter:Get("InfiniteAmmoReserve") == true
            end)
            if not okInf or inf ~= true then return "dry" end
        end
        if tick() - (State.RageReloadLast or 0) < 0.5 then return "throttled" end
        State.RageReloadLast = tick()
        pcall(function()
            local lf = Rivals.Fighter and Rivals.Fighter.LocalFighter
            if lf ~= nil then
                task.spawn(function()
                    if setthreadidentity then setthreadidentity(2) elseif setidentity then setidentity(2) end
                    pcall(function() lf:Input("StartReloading") end)
                    if setthreadidentity then setthreadidentity(8) elseif setidentity then setidentity(8) end
                end)
            end
        end)
        pcall(function() it:StartReloading() end)
        return "requested"
    end
    local _SLOT_INDEX = { Primary = 1, Secondary = 2 }
    Rage._weaponRecovery = function(it)
        local mode = Config.RageOnEmpty or "Reload"
        local okA, ammo = pcall(function() return it and it:Get("Ammo") end)
        local empty = not (okA and type(ammo) == "number" and ammo > 0)
        if mode ~= "Swap" or not empty then
            return Rage._ensureReload(it)
        end
        local lf = Rivals.Fighter and Rivals.Fighter.LocalFighter
        local items = lf and lf.Items
        if type(items) ~= "table" then return Rage._ensureReload(it) end
        if tick() - (State.RageSwitchLast or 0) < 0.5 then return "swap-wait" end
        local pref = _SLOT_INDEX[Config.RagePreferredSlot or "Primary"] or 1
        local other = pref == 1 and 2 or 1
        for _, slot in ipairs({ pref, other }) do
            local w = items[slot]
            if w and w ~= it then
                local okW, wammo = pcall(function() return w:Get("Ammo") end)
                if okW and type(wammo) == "number" and wammo > 0 then
                    local busy = false
                    pcall(function()
                        if w:IsEquipping() then busy = true end
                    end)
                    pcall(function()
                        if (w._reload_cooldown or 0) > tick() then busy = true end
                    end)
                    if not busy then
                        State.RageSwitchLast = tick()
                        local okE = pcall(function() lf.EquipItem(lf, slot) end)
                        if okE then
                            State.AutoWeaponFails = 0
                            return "swap"
                        end
                        State.AutoWeaponFails = (State.AutoWeaponFails or 0) + 1
                    end
                end
            end
        end
        return Rage._ensureReload(it)
    end
    local _transportWatchStarted = false
    Rage._startTransportWatcher = function()
        if _transportWatchStarted then return end
        _transportWatchStarted = true
        task.spawn(function()
            local EF
            for _ = 1, 60 do
                local ps = lp and lp:FindFirstChildOfClass("PlayerScripts")
                if ps then
                    local ok, m = pcall(require, ps:WaitForChild("Modules", 5)
                        :WaitForChild("ClientReplicatedClasses", 5)
                        :WaitForChild("ClientDuel", 5)
                        :WaitForChild("DuelInterface", 5)
                        :WaitForChild("EliminationFeed", 5))
                    if ok and type(m) == "table" and type(m.Play) == "function" then EF = m break end
                end
                task.wait(1)
            end
            if not EF then return end
            local orig = EF.Play
            shared._LH_ElimFeedOrig = shared._LH_ElimFeedOrig or orig
            EF.Play = function(self, victim, eliminator, ...)
                local results = { pcall(orig, self, victim, eliminator, ...) }
                if not results[1] then return unpack(results, 2) end
                pcall(function()
                    if victim ~= lp then return end
                    if Config.RageRestoreMode ~= "auto" then return end
                    if eliminator == nil or typeof(eliminator) ~= "Instance" then return end
                    local tgt = State.RageTarget
                    local match = (tgt == eliminator)
                    if not match and tgt and eliminator.Name == tgt.Name then match = true end
                    if not match then return end
                    local now = tick()
                    if now - (State.RageLastLossAt or 0) < 3 then return end
                    State.RageLastLossAt = now
                    State.RageTransportSwitches = (State.RageTransportSwitches or 0) + 1
                    State.RageAutoTransport = (State.RageAutoTransport == "render") and "kicia" or "render"
                    local lib = _G["\76\72"]
                    if lib and lib.Notify then
                        pcall(function()
                            lib:Notify({
                                Title = "Park (Auto)",
                                Description = "Switched to " .. (State.RageAutoTransport == "render" and "render" or "kerp"),
                                Time = 4,
                            })
                        end)
                    end
                end)
                return unpack(results, 2)
            end
        end)
    end
    local _awLast = 0
    Rage.autoWeaponStep = function()
        if not Config.AutoWeaponEnabled then return end
        if Config.Rage then return end
        if (State.AutoWeaponFails or 0) >= 3 then return end
        if tick() - _awLast < 1 then return end
        _awLast = tick()
        local lf = Rivals.Fighter and Rivals.Fighter.LocalFighter
        local items = lf and lf.Items
        if type(items) ~= "table" then return end
        local function itemName(w)
            local n
            pcall(function() n = w.Name end)
            if type(n) ~= "string" then pcall(function() n = w.Info and w.Info.Name end) end
            return n
        end
        local want = {
            [1] = Config.AutoWeaponPrimary or "",
            [2] = Config.AutoWeaponSecondary or "",
            [3] = Config.AutoWeaponMelee or "",
            [4] = Config.AutoWeaponUtility or "",
        }
        for slot = 1, 4 do
            local name = want[slot]
            if name ~= "" then
                if itemName(items[slot]) ~= name then
                    for src = 1, 4 do
                        if itemName(items[src]) == name then
                            State.RageSwitchLast = tick()
                            local okE = pcall(function() lf.EquipItem(lf, src) end)
                            if okE then
                                State.AutoWeaponFails = 0
                            else
                                State.AutoWeaponFails = (State.AutoWeaponFails or 0) + 1
                                State.RageSwitchLast = 0
                            end
                            return
                        end
                    end
                    return
                end
            end
        end
        State.AutoWeaponFails = 0
    end
    local function flankPoint(tgt, hh)
        if not tgt or not tgt.Character or not hh or not isSanePos(hh.Position) then return nil end
        local katana = Config.AvoidDeflect and isKatana(tgt)
        local shield = Config.RageShieldBackstab and isRiotShield(tgt)
        local stowed = Config.RageShieldBackstab and ownsRiotShield(tgt)
        if not (katana or shield or stowed) then return nil end
        local thrp = tgt.Character:FindFirstChild("HumanoidRootPart")
        if not thrp then return nil end
        local look = thrp.CFrame.LookVector
        look = Vector3.new(look.X, 0, look.Z)
        if look.Magnitude < 1e-3 then return nil end
        local inv    = -look.Unit
        if not katana and not shield and stowed then inv = look.Unit end
        local anchor = hh.Position
        local kf     = killFloor()
        local dist   = shield and 2.5 or 3.0
        local ignore = { tgt.Character, lp.Character }
        local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.FilterDescendantsInstances = ignore
        local flank = anchor + inv * dist
        local wr = workspace:Raycast(anchor, inv * dist, rp)
        if wr then flank = wr.Position - inv * 0.5 end
        flank = Vector3.new(flank.X, math.max(flank.Y, kf + 3), flank.Z)
        if not hasLOS(flank, hh.Position, ignore) then return nil end
        return flank
    end
    local _shootEnum
    local function polarFire(eyePos, aimPos, hh)
        local reach = 1e9
        if hh and hh.Parent then reach = (hh.Position - eyePos).Magnitude end
        if not (reach <= 395) then
            State.RageBlankCanary = State.RageBlankCanary + 1
            return
        end
        local it = getEquippedItem()
        if not it then return end
        if Config.RageDirectFire then
            if Config.RageRateLimit then
                if tick() - (State.RageLastFireTime or 0) < fireInterval() then return end
                State.RageLastFireTime = tick()
            end
            pcall(function()
                it._shoot_cooldown = 0
                it._shoot_cooldown_no_ammo = 0
                it._last_shot = tick() - 1
            end)
            if not (Rivals.Ready and Rivals.Enums and Rivals.Util) then return end
            if _shootEnum == nil then
                pcall(function() _shootEnum = Rivals.Enums:ToEnum("StartShooting") end)
            end
            if _shootEnum == nil then return end
            local okId, objId = pcall(function() return it:Get("ObjectID") end)
            if not okId or not objId then return end
            local eyeCF    = Rage._lookCF(eyePos, aimPos)
            local muzzleCF = eyeCF - Vector3.new(0, Config.RageEyeMuzzleSep, 0)
            local taps = Config.RageTapsPerFrame
            if type(taps) ~= "number" then taps = 1 end
            taps = math.max(1, math.min(math.floor(taps), math.floor(Config.RageTaps or 6)))
            local sent     = 0
            local rayCast  = false
            pcall(function() rayCast = it.Info.IsRaycast == true end)
            State.RageForging = true
            pcall(function()
                local remote = ReplicatedStorage.Remotes.Replication.Fighter.UseItem
                for _ = 1, taps do
                    if not (hh and hh.Parent) then break end
                    local inner = {}
                    Rage._buildShotFields(inner, eyeCF, muzzleCF, hh, aimPos, true, 0.30, 1.0)
                    local env = { [utf8.char(1)] = inner }
                    if rayCast then env[utf8.char(2)] = true end
                    remote:FireServer(objId, _shootEnum, env, nil)
                    sent = sent + 1
                end
            end)
            State.RageForging = false
            State.Shots = State.Shots + sent
            return
        end
        if not weaponReady(it) then return end
        if not hh or not hh.Parent or not isSanePos(hh.Position) then return end
        local hpos = hh.Position
        if (hpos - eyePos).Magnitude > (400 - 5) then return end
        local ignore = { lp.Character }
        local tgt = State.RageTarget or State.Target
        if tgt and tgt.Character then ignore[2] = tgt.Character end
        if not hasLOS(eyePos, hpos, ignore) then return end
        if tick() - (State.RageLastFireTime or 0) < fireInterval() then return end
        State.RageFireFromPos = eyePos
        State.RageFireAimPos  = aimPos
        State.RageFireHitPart = hh
        State.RageFireStamp   = tick()
        local lf = Rivals.Fighter and Rivals.Fighter.LocalFighter
        if not lf then return end
        task.spawn(function()
            if setthreadidentity then setthreadidentity(2) elseif setidentity then setidentity(2) end
            pcall(function() lf:Input("StartShooting") end)
            if setthreadidentity then setthreadidentity(8) elseif setidentity then setidentity(8) end
        end)
    end
    local function clearFireSolution()
        State.RageFireFromPos = nil
        State.RageFireAimPos  = nil
        State.RageFireHitPart = nil
        State.RageFireStamp   = 0
    end
    ;(function()
        local function orbitVantage(aimPos, ignore, kf, knife)
            State.OrbitAngle = ((State.OrbitAngle or 0) + 2.39996) % (math.pi * 2)
            local base = Config.RageCombatOrbitRadius or 60
            local radii
            if knife then
                radii = { math.max(base, 75), 95 }
            else
                radii = { base, base * 0.6, math.min(base * 1.5, 380) }
            end
            for _, r in ipairs(radii) do
                for i = 0, 5 do
                    local ang    = State.OrbitAngle + i * (math.pi / 3)
                    local jitter = 0
                    if Config.RageCombatOrbitJitter then jitter = (math.random() - 0.5) * 14 end
                    local h = (Config.RageCombatOrbitHeight or 8) + jitter
                    local pos = Vector3.new(aimPos.X + math.cos(ang) * r,
                        math.max(aimPos.Y + h, kf + 6),
                        aimPos.Z + math.sin(ang) * r)
                    if isSanePos(pos) and not posIsOOB(pos) and hasLOS(pos, aimPos, ignore) then
                        return pos
                    end
                end
            end
            return nil
        end
        local function orbitVoid(hrp, status)
            State.RageStatus = status
            State.OrbitVantage = nil
            State.OrbitVantageUntil = 0
            State.RageFiring = false
            State.RageVoidActive = true
            clearFireSolution()
            _orbHiding = true
            _orbPrimeUntil = 0
            _orbLastDisp = nil
            Rage._displace(hrp, voidCFrame())
        end
        local _orbDeflectSince = 0
        local function orbitTick(ch, hrp, tgt)
            local kf = killFloor()
            if not tgt or not tgt.Character then
                return orbitVoid(hrp, "No target")
            end
            local tc   = tgt.Character
            local thrp = tc:FindFirstChild("HumanoidRootPart")
            local hh   = tc:FindFirstChild("HitboxHead") or tc:FindFirstChild("Head")
            if not hh or not isSanePos(hh.Position) then
                return orbitVoid(hrp, "Hiding")
            end
            if Config.AvoidDeflect and isDeflecting(tgt) then
                if _orbDeflectSince == 0 then _orbDeflectSince = tick() end
                if tick() - _orbDeflectSince < 1.5 then
                    return orbitVoid(hrp, "Deflecting")
                end
            else
                _orbDeflectSince = 0
            end
            if not weaponReady(getEquippedItem()) then
                local act = Rage._weaponRecovery(getEquippedItem())
                if act == "dry" then
                    return orbitVoid(hrp, "Dry")
                end
                if act == "swap" or act == "swap-wait" then
                    return orbitVoid(hrp, "Swapping")
                end
                return orbitVoid(hrp, "Reloading")
            end
            local aimPos = hh.Position
            if posIsOOB(aimPos) or aimPos.Y < kf + 1 then
                return orbitVoid(hrp, "Hiding")
            end
            local ignore = { tc, lp.Character }
            local vantage, status = nil, nil
            local flank = flankPoint(tgt, hh)
            if not flank and thrp and Config.RageKnifeBackstab and isLocalKnife() then
                local inv = -thrp.CFrame.LookVector
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Exclude
                rp.FilterDescendantsInstances = ignore
                local f  = thrp.Position + inv * 3.0
                local wr = workspace:Raycast(thrp.Position, inv * 3.0, rp)
                if wr then f = wr.Position - inv * 0.5 end
                local cand = Vector3.new(f.X, math.max(f.Y, kf + 3), f.Z)
                if isSanePos(cand) and not posIsOOB(cand) and hasLOS(cand, hh.Position, ignore) then
                    flank = cand
                end
            end
            if flank then
                vantage = flank
                State.OrbitVantage = nil
                if isRiotShield(tgt) then
                    status = "Anti-riot"
                elseif isKatana(tgt) then
                    status = "Katana flank"
                else
                    status = "Backstab"
                end
            else
                local knife = isEnemyKnife(tgt)
                local held  = State.OrbitVantage
                if (not held) or tick() >= (State.OrbitVantageUntil or 0) or not hasLOS(held, aimPos, ignore) then
                    local v = orbitVantage(aimPos, ignore, kf, knife)
                    if v then
                        State.OrbitVantage = v
                        State.OrbitVantageUntil = tick() + (Config.RageOrbitDwell or 0.09)
                        held = v
                    elseif held and hasLOS(held, aimPos, ignore) then
                        State.OrbitVantageUntil = tick() + (Config.RageOrbitDwell or 0.09)
                    else
                        held = nil
                    end
                end
                if held then
                    vantage = held
                    if knife then status = "Orbit (kept dist)" else status = "Orbit" end
                end
            end
            if not vantage or not isSanePos(vantage) or posIsOOB(vantage) then
                return orbitVoid(hrp, "Orbit (hiding)")
            end
            State.RageStatus = status or "Orbit"
            State.RageVoidActive = false
            local jumped = _orbLastDisp == nil or (vantage - _orbLastDisp).Magnitude > ORBIT_JUMP
            _orbLastDisp = vantage
            if _orbHiding or jumped then
                _orbHiding = false
                local extra = 0
                if Config.RageHideJitter ~= false then extra = math.random() * ORBIT_JITTER_MAX end
                _orbPrimeUntil = tick() + ORBIT_PRIME_S + extra
            end
            Rage._displace(hrp, CFrame.new(vantage))
            local holdFire = false
            if Config.RageSkipImmune ~= false then holdFire = isSpawnProtected(tgt) end
            if not holdFire then
                _orbImmuneSince, _orbImmuneTgt = 0, nil
            else
                local nowI = tick()
                if _orbImmuneTgt ~= tgt then
                    _orbImmuneSince, _orbImmuneTgt = nowI, tgt
                end
                if nowI - _orbImmuneSince > ORB_IMMUNE_MAX_HOLD then
                    holdFire = false
                    State.RageImmuneOverride = (State.RageImmuneOverride or 0) + 1
                end
            end
            if holdFire then
                State.RageFiring = false
                State.RageStatus = "Protected — vantage held, holding fire"
            elseif tick() < _orbPrimeUntil then
                State.RageFiring = false
                State.RageStatus = "Priming"
            else
                State.RageFiring = true
                local eye = vantage + Vector3.new(0, Config.RagePBEyeUp or 3, 0)
                polarFire(eye, aimPos, hh)
            end
            pcall(Visuals.notifyTarget, tgt)
        end
        local function rageTick(ch, hrp, tgt)
            if (Config.RageMode or "Polar") ~= "Orbit" then
                State.RageStatus = "Mode error"
                return
            end
            orbitTick(ch, hrp, tgt)
        end
        Rage._rageTick = rageTick
    end)()
    local function onLocalDied()
        pcall(function()
            if tick() - State.RageBelowPlaneLast < 0.5 then
                State.RageBelowPlaneDeaths = State.RageBelowPlaneDeaths + 1
                State.RageBelowPlaneLast = 0
            end
            if not Config.Rage then
                return
            end
            if Config.RageMode == "Orbit" then
                return
            end
            if tick() - (State.RageKnifeHintLast or 0) < 90 then
                return
            end
            local knifed = false
            local tgt = State.RageTarget
            if tgt and tgt.Parent and isEnemyKnife(tgt) then
                knifed = true
            else
                local dpos = nil
                local real = State.RageRealCF
                if real then
                    dpos = real.Position
                else
                    local ch = lp.Character
                    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        dpos = hrp.Position
                    end
                end
                if dpos then
                    for _, plr in ipairs(getSafePlayers()) do
                        if plr ~= lp and not (Config.TeamCheck and isTeammate(plr)) then
                            local r = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
                            if r and (r.Position - dpos).Magnitude <= 18 and isEnemyKnife(plr) then
                                knifed = true
                                break
                            end
                        end
                    end
                end
            end
            if not knifed then
                return
            end
            State.RageKnifeHintLast = tick()
            local lib = _G["\76\72"]
            if lib and lib.Notify then
                pcall(function() lib:Notify("Knifed by a melee player â€” switch Rage mode to Orbit (our knife counter)", 5) end)
            end
        end)
    end
    local function hookDied(char)
        if _rageDiedConn then
            _rageDiedConn:Disconnect()
            _rageDiedConn = nil
        end
        if not char then
            return
        end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            _rageDiedConn = hum.Died:Connect(onLocalDied)
        end
    end
    local function restoreHome(pin)
        if State.RagePostPark then State.RageOrderCanary = State.RageOrderCanary + 1 end
        local ch = lp.Character
        if not ch then return end
        local hrp = ch:FindFirstChild("HumanoidRootPart")
        if not hrp or not hrp.Parent then return end
        local back = _preParkCF
        _preParkCF = nil
        if back == nil then
            local real = State.RageRealCF
            if real and State.RageRealChar == ch then
                back = CFrame.new(real.Position) * hrp.CFrame.Rotation
            end
        end
        pcall(function()
            if back then hrp.CFrame = back end
            State.RageParkDirty = false
            if pin then
                local hu = ch:FindFirstChildOfClass("Humanoid")
                if hu and hu:GetState() == Enum.HumanoidStateType.Freefall and hu.FloorMaterial ~= Enum.Material.Air then
                    hu:ChangeState(Enum.HumanoidStateType.Running)
                end
            end
        end)
    end
    local function startRage()
        if _rageConn then return end
        if Rage._setPhysicsFlags then pcall(Rage._setPhysicsFlags, true) end
        hookDied(lp.Character)
        if not _rageCharConn then
            _rageCharConn = lp.CharacterAdded:Connect(function()
                State.RageRealCF = nil; State.RageRealChar = nil
                State.RageVoidCF = nil; State.RageVoidBase = nil
                State.RageParkDirty = false; State.RageLastParkPos = nil
                hookDied(lp.Character)
            end)
        end
        local function rageRestoreActive()
            if not Config.Rage then return false end
            if not State.RageInMatch then return false end
            if State.RageRealChar ~= lp.Character then return false end
            return true
        end
        pcall(function() RunService:UnbindFromRenderStep(_rageRestoreName) end)
        RunService:BindToRenderStep(_rageRestoreName, Enum.RenderPriority.First.Value - 1000, function()
            State.RagePostPark = false
            if rageRestoreActive() then restoreHome(true) end
        end)
        if not _rageStepConn then
            _rageStepConn = RunService.Stepped:Connect(function()
                State.RagePostPark = false
                if rageRestoreActive() then restoreHome(true) end
            end)
        end
        local function defeatCooldowns()
            if not Config.Rage then return end
            local it = getEquippedItem()
            if not it then return end
            it._shoot_cooldown = 0
            it._shoot_cooldown_no_ammo = 0
            if (it._last_shot or 0) > tick() + 1 then it._last_shot = tick() - 1 end
            if it._shot_but_ammo_hasnt_updated then it._shot_but_ammo_hasnt_updated = false end
        end
        if not _rageCooldownConn then
            _rageCooldownConn = RunService.Heartbeat:Connect(function()
                pcall(defeatCooldowns)
            end)
        end
        _rageConn = RunService.Heartbeat:Connect(function()
            if not Config.Rage or (Config.RageMode or "Polar") ~= "Orbit" then
                if Rage._setPhysicsFlags then pcall(Rage._setPhysicsFlags, false) end
                restoreHome(false)
                pcall(function() RunService:UnbindFromRenderStep(_rageRestoreName) end)
                if _rageConn then _rageConn:Disconnect(); _rageConn = nil end
                if _rageStepConn then _rageStepConn:Disconnect(); _rageStepConn = nil end
                if _rageCooldownConn then _rageCooldownConn:Disconnect(); _rageCooldownConn = nil end
                if _rageCharConn then _rageCharConn:Disconnect(); _rageCharConn = nil end
                if _rageDiedConn then _rageDiedConn:Disconnect(); _rageDiedConn = nil end
                State.RageRealCF = nil; State.RageRealChar = nil
                State.RageTarget = nil; State.RageVoidCF = nil; State.RageVoidBase = nil
                State.RageParkDirty = false; State.RageLastParkPos = nil
                State.RageInMatch = false
                State.OrbitVantage = nil; State.OrbitVantageUntil = 0
                clearFireSolution()
                return
            end
            local ch  = lp.Character
            local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
            if not hrp or not hrp.Parent then
                if tick() - State.RageBelowPlaneLast < 0.5 then
                    State.RageBelowPlaneDeaths = State.RageBelowPlaneDeaths + 1
                    State.RageBelowPlaneLast = 0
                end
                clearFireSolution()
                return
            end
            if State.RageParkDirty and State.RageRealChar == ch then
                State.RageParkLatchCanary = State.RageParkLatchCanary + 1
                if State.RageLastParkPos then
                    State.RageLatchStuds = (hrp.Position - State.RageLastParkPos).Magnitude
                end
            elseif isSanePos(hrp.Position) then
                State.RageRealCF = hrp.CFrame
                State.RageRealChar = ch
            end
            State.RageInMatch = inMatch()
            if not State.RageInMatch then
                if not isSanePos(hrp.Position) then restoreHome(false) end
                State.RageTarget = nil
                State.RageStatus = "Lobby"
                State.RageFiring = false
                clearFireSolution()
                return
            end
            if not State.RageRealCF or State.RageRealChar ~= ch then
                State.RageStatus = "Waiting"
                State.RageFiring = false
                clearFireSolution()
                return
            end
            local hum0 = ch:FindFirstChildOfClass("Humanoid")
            if hum0 and hum0.Health <= 0 then
                if not isSanePos(hrp.Position) then restoreHome(false) end
                State.RageFiring = false
                State.RageVoidActive = false
                State.RageStatus = "Dead"
                clearFireSolution()
                return
            end
            local tgt = State.RageTarget
            do
                if tgt and (not tgt.Parent or not tgt.Character or not isAlive(tgt)
                    or (Config.TeamCheck and isTeammate(tgt))) then
                    tgt = nil
                end
                if not tgt then tgt = Rage._findTarget() end
                State.RageTarget = tgt
            end
            State.RagePostPark = true
            Rage._rageTick(ch, hrp, tgt)
            local anchor    = State.RageRealCF
            local displaced = false
            if anchor then displaced = (hrp.Position - anchor.Position).Magnitude > 0.001 end
            State.RageParkDirty = displaced
            if displaced then State.RageLastParkPos = hrp.Position end
        end)
    end
    function Rage.enable()
        Config.Rage = true
        if Rage._startTargetLoop then Rage._startTargetLoop() end
        if (Config.RageMode or "Polar") ~= "Orbit" then
            if Rage._polarCoreStart then Rage._polarCoreStart() end
            return
        end
        startRage()
    end
    function Rage.disable()
        Config.Rage = false
        if Rage._polarCoreStop then Rage._polarCoreStop() end
        State.RagePostPark = false
        pcall(function() RunService:UnbindFromRenderStep(_rageRestoreName) end)
        if _rageConn then _rageConn:Disconnect(); _rageConn = nil end
        if _rageStepConn then _rageStepConn:Disconnect(); _rageStepConn = nil end
        if _rageCooldownConn then _rageCooldownConn:Disconnect(); _rageCooldownConn = nil end
        if _rageCharConn then _rageCharConn:Disconnect(); _rageCharConn = nil end
        if _rageDiedConn then _rageDiedConn:Disconnect(); _rageDiedConn = nil end
        restoreHome(false)
        State.RageRealCF = nil; State.RageRealChar = nil
        State.RageTarget = nil; State.RageVoidCF = nil; State.RageVoidBase = nil
        State.RageParkDirty = false; State.RageLastParkPos = nil
        State.RageInMatch = false
        State.OrbitVantage = nil; State.OrbitVantageUntil = 0
        State.RageFiring = false
        State.RageVoidActive = false
        State.RageStatus = "Idle"
        clearFireSolution()
    end
    function Rage.unload()
        Rage.disable()
        if _tgtConn then pcall(function() _tgtConn:Disconnect() end); _tgtConn = nil end
        if _labConn then pcall(function() _labConn:Disconnect() end); _labConn = nil end
    end
    Rage._encodeRageShot = encodeRageShot
end)()
;(function()
    local PolarCore = {}
    local _realCF, _realChar = nil, nil
    local _voidCF     = nil
    local _target     = nil
    local _firing     = false
    local _inMatch    = false
    local _deflectSince = 0
    local _shots      = 0
    local _voidSteps  = 0
    local _shootEnum  = nil
    local _useItem    = nil
    local _notified   = nil
    local _conn, _stepConn, _charConn = nil, nil, nil
    local RENDER_NAME = "LuaHook_PolarCore_Restore"
    local CAMERA_NAME = "LuaHook_PolarCore_CamAnchor"
    local SANE_POS_LIMIT  = 100000
    local MAX_DISTANCE    = 1200
    local VOID_HIDE       = true
    local POLAR_TAPS_SANE = 6
    local EYE_UP_SANE     = 2.5
    local KILL_PLANE_BUF  = 200
    local PARK_DRIFT_STUDS = 1.5
    local VOID_MOVE       = true
    local VOID_MIN_STEP   = 25000
    local VOID_R_MIN      = 110000
    local VOID_R_MAX      = 140000
    local HIDE_WHEN_UNREACHABLE = true
    local DEFLECT_MAX_HOLD = 1.5
    local IMMUNE_MAX_HOLD = 6.0
    local _immuneSince = 0
    local _immuneTgt   = nil
    local EYE_MUZZLE_SEP  = 0.07
    local RAGE_CLAMP_FRAC = 0.30
    local function parity()
        return Config.RagePolarParity ~= false
    end
    local _preParkCF = nil
    local FFLAGS_ON  = { DFIntS2PhysicsSenderRate = "120", DFIntAssemblyHistoryBufferSize = "2147483648", DFIntAssemblyHistorySkipSize = "0" }
    local FFLAGS_OFF = { DFIntS2PhysicsSenderRate = "15",  DFIntAssemblyHistoryBufferSize = "15",         DFIntAssemblyHistorySkipSize = "8" }
    local _fpdhOriginal = nil
    local _flagsOn = false
    local _physSet  = false
    local _physLive = false
    local function fflagApi()
        local set, get, name = nil, nil, "none"
        pcall(function()
            if type(setfflag) == "function" then
                set, name = setfflag, "setfflag"
            elseif type(setfastflag) == "function" then
                set, name = setfastflag, "setfastflag"
            elseif type(set_fflag) == "function" then
                set, name = set_fflag, "set_fflag"
            end
            if type(getfflag) == "function" then
                get = getfflag
            elseif type(getfastflag) == "function" then
                get = getfastflag
            end
        end)
        return set, get, name
    end
    local function readsBack(get, name, want)
        if get == nil then return nil end
        local ok, v = pcall(get, name)
        if not ok or v == nil then return nil end
        if tostring(v) == want then return true end
        local got, req = tonumber(v), tonumber(want)
        if got == nil or req == nil then return false end
        if req >= 2147483647 then return got >= 2147483646 end
        return got == req
    end
    local function setPhysicsFlags(on)
        if on == _flagsOn then return end
        if on and Config.RagePhysicsFlags == false then return end
        _flagsOn = on
        if _fpdhOriginal == nil then
            local prev = workspace.FallenPartsDestroyHeight
            if prev ~= prev then prev = -500 end
            _fpdhOriginal = prev
        end
        local fpdhOk = false
        pcall(function()
            if on then
                workspace.FallenPartsDestroyHeight = 0 / 0
            else
                workspace.FallenPartsDestroyHeight = _fpdhOriginal
            end
            local v = workspace.FallenPartsDestroyHeight
            fpdhOk = v ~= v
        end)
        local set, get, setName = fflagApi()
        if set == nil then
            _physSet, _physLive = false, false
            State.RagePhysVerified = false
            State.RagePhysRate = "no fflag setter — history decimation stays stock"
            return
        end
        local want = FFLAGS_OFF
        if on then want = FFLAGS_ON end
        local threw, detail = false, ""
        local keyOk = false
        for name, value in want do
            local wrote = pcall(set, name, value)
            if not wrote then threw = true end
            local seen = readsBack(get, name, value)
            local tag = "?"
            if seen == true then tag = "ok" end
            if seen == false then tag = "REFUSED" end
            if not wrote then tag = "THREW" end
            if name == "DFIntAssemblyHistorySkipSize" and seen == true then keyOk = true end
            detail = detail .. string.sub(name, 5) .. "=" .. tag .. " "
        end
        _physSet  = on and not threw
        _physLive = _physSet and keyOk and fpdhOk
        State.RagePhysVerified = _physLive
        State.RagePhysSet = _physSet
        State.RagePhysDetail = detail .. "FPDH=" .. tostring(fpdhOk)
        local how = "verified"
        if not on then
            how = "off"
        elseif threw then
            how = "THREW"
        elseif not fpdhOk then
            how = "FPDH refused"
        elseif not keyOk then
            how = "SkipSize unproven"
        end
        State.RagePhysRate = setName .. " " .. how
    end
    local glueActive
    local function restoreMode()
        if glueActive ~= nil and glueActive() then return "kicia" end
        local m = Config.RageRestoreMode
        if m == "kicia" or m == "render" or m == "none" then return m end
        return "none"
    end
    local _identGet, _identSet = nil, nil
    local _identTried = false
    local function identEnsure()
        if _identTried then return _identSet ~= nil end
        _identTried = true
        pcall(function()
            local g = getthreadidentity or get_thread_identity
            local s = setthreadidentity or set_thread_identity or setidentity or setthreadcontext
            if type(g) == "function" and type(s) == "function" then
                _identGet, _identSet = g, s
            end
        end)
        State.RageRawSet = _identSet ~= nil
        return _identSet ~= nil
    end
    local function rawSetCFrame(hrp, cf)
        identEnsure()
        if _identSet ~= nil then
            local okPrev, prev = pcall(_identGet)
            if okPrev then
                pcall(_identSet, 8)
                local wrote = pcall(function() hrp.CFrame = cf end)
                pcall(_identSet, prev)
                if wrote then return true end
            end
        end
        return pcall(function() hrp.CFrame = cf end)
    end
    local _rvCF = nil
    local GLUE_PARK_OFF = Vector3.new(0, -0.7, 0.05)
    local GLUE_CHAR0 = {
        [utf8.char(0)] = -9e37,
        [utf8.char(1)] = 0,
        [utf8.char(2)] = 0,
        [utf8.char(3)] = -math.pi / 2,
        [utf8.char(4)] = math.pi,
        [utf8.char(5)] = math.pi,
    }
    local GLUE_CHAR1 = {
        [utf8.char(0)] = 0,
        [utf8.char(1)] = -90000000,
        [utf8.char(2)] = 0,
        [utf8.char(3)] = -math.pi / 2,
        [utf8.char(4)] = math.pi,
        [utf8.char(5)] = math.pi,
    }
    local GLUE_CHAR3 = {
        [utf8.char(0)] = 0,
        [utf8.char(1)] = 1,
        [utf8.char(2)] = 0,
        [utf8.char(3)] = 0,
        [utf8.char(4)] = 0,
        [utf8.char(5)] = 0,
    }
    local _glueHit       = nil
    local _glueWeld      = nil
    local _glueWeldPart1 = nil
    local _glueAnchored  = nil
    local _gluePrev   = nil
    local _gluePrevOk = false
    local function gumMode()
        local m = Config.RageGumMode
        if m ~= "off" and m ~= "lite" and m ~= "on" then
            local g = Config.RageGlueMode
            if g == "lite" or g == "off" then
                m = g
            elseif g == "full" then
                m = "on"
            else
                m = "off"
            end
        end
        if m == "off" and Config.RagePartGlue == true then return "on" end
        return m
    end
    local _liteHit    = nil
    local _liteDriven = false
    local _glueDriven = false
    local TRANSLOCATE_PULSES_PER_BURST = 2
    local TRANSLOCATE_ARM_FRAMES = 12
    local _translocateFireFrames = 0
    local _translocateNext = false
    local _translocateBurstPulses = 0
    local _translocatePart = nil
    local POISON_ARM_FRAMES = 2
    local POISON_PER_BURST  = 1
    local _poisonFireFrames = 0
    local _poisonBlips      = 0
    local function setRepRoot(part, target)
        if _identSet == nil then return false end
        local ok, seen = false, nil
        pcall(function()
            local prev = _identGet()
            _identSet(8)
            local wrote = pcall(sethiddenproperty, part, "PhysicsRepRootPart", target)
            if wrote and type(gethiddenproperty) == "function" then
                local okR, v = pcall(gethiddenproperty, part, "PhysicsRepRootPart")
                if okR then seen = v end
            end
            _identSet(prev)
            ok = wrote
        end)
        if not ok then return false end
        if seen == nil then
            State.RageGlueVerified = "unverified (no gethiddenproperty)"
            return true
        end
        if seen ~= target then
            State.RageGlueVerified = "REFUSED (read back " .. tostring(seen) .. ")"
            return false
        end
        State.RageGlueVerified = "verified"
        return true
    end
    local function liteRelease()
        if _liteHit == nil then return end
        _liteHit    = nil
        _liteDriven = false
        State.RageGlueBound = false
        local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        if not hrp or not hrp.Parent then return end
        local back = hrp
        if _gluePrevOk then back = _gluePrev end
        setRepRoot(hrp, back)
        State.RageGlueVerified = "released"
    end
    local function liteAcquire(hit, predicting, melee)
        if gumMode() ~= "lite" or predicting or melee then
            liteRelease()
            return false
        end
        if type(sethiddenproperty) ~= "function" then
            liteRelease()
            return false
        end
        if not identEnsure() then
            liteRelease()
            return false
        end
        if hit == nil or hit.Parent == nil then
            liteRelease()
            return false
        end
        local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        if not hrp or not hrp.Parent then
            liteRelease()
            return false
        end
        if not _gluePrevOk and type(gethiddenproperty) == "function" then
            local okP, v = pcall(gethiddenproperty, hrp, "PhysicsRepRootPart")
            if okP then
                _gluePrev   = v
                _gluePrevOk = true
            end
        end
        if not setRepRoot(hrp, hit) then
            liteRelease()
            return false
        end
        _liteHit    = hit
        _liteDriven = true
        State.RageGlueBound = true
        return true
    end
    glueActive = function()
        return _glueHit ~= nil
    end
    local function glueSetup(hit)
        local weld = hit:FindFirstChildOfClass("WeldConstraint")
        if weld == nil then weld = hit:FindFirstChild("WeldConstraint") end
        if weld == nil then return end
        _glueWeld      = weld
        _glueWeldPart1 = weld.Part1
        _glueAnchored  = hit.Anchored
        pcall(function()
            if _glueWeldPart1 ~= nil then weld.Part1 = nil end
            hit.Anchored = true
        end)
    end
    local function glueTeardown()
        local weld, part1, hit, anch = _glueWeld, _glueWeldPart1, _glueHit, _glueAnchored
        _glueWeld, _glueWeldPart1, _glueAnchored = nil, nil, nil
        pcall(function()
            if weld ~= nil and weld.Parent ~= nil and part1 ~= nil then weld.Part1 = part1 end
            if hit ~= nil and hit.Parent ~= nil and anch ~= nil then hit.Anchored = anch end
        end)
    end
    local function glueRelease()
        State.RageTranslocating = false
        if _glueHit == nil then return end
        glueTeardown()
        _glueHit    = nil
        _glueDriven = false
        State.RageGlueBound = false
        local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        if not hrp or not hrp.Parent then return end
        local back = hrp
        if _gluePrevOk then
            back = _gluePrev
        end
        setRepRoot(hrp, back)
        State.RageGlueVerified = "released"
    end
    local function glueAcquire(hit)
        if gumMode() ~= "on" then return nil end
        if type(sethiddenproperty) ~= "function" then return nil end
        if not identEnsure() then return nil end
        if hit == nil or hit.Parent == nil then return nil end
        local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        if not hrp or not hrp.Parent then return nil end
        if not _gluePrevOk and type(gethiddenproperty) == "function" then
            local okP, v = pcall(gethiddenproperty, hrp, "PhysicsRepRootPart")
            if okP then
                _gluePrev   = v
                _gluePrevOk = true
            end
        end
        if not setRepRoot(hrp, hit) then
            glueRelease()
            return nil
        end
        if _glueHit ~= hit then
            glueTeardown()
            _glueHit = hit
            glueSetup(hit)
        end
        if _rvCF == nil then
            _rvCF = CFrame.new(math.random(-100000, -10000), 100000, math.random(-100000, 10000))
        end
        local rv = _rvCF.Position
        local moved = pcall(function() hit.CFrame = CFrame.new(rv) end)
        if not moved then
            glueRelease()
            return nil
        end
        _glueDriven = true
        State.RageGlueBound = true
        return rv
    end
    local function displace(hrp, cf)
        if _preParkCF == nil then _preParkCF = hrp.CFrame end
        return rawSetCFrame(hrp, cf)
    end
    local _prevPark    = nil
    local _prevParkTgt = nil
    local _lastPark    = nil
    local PRIME_S         = 0.07
    local HIDE_JITTER_MAX = 0.25
    local _hiding     = false
    local _primeUntil = 0
    local HACK_SPEED = 120
    local HACK_ACCUM = 0.15
    local _hackTag   = {}
    local _lastSeen  = {}
    local _hackAccum = {}
    local function tickHackers(dt)
        if dt <= 0 or dt > 0.5 then return end
        for _, p in Players:GetPlayers() do
            if p ~= lp and not _hackTag[p] then
                local c = p.Character
                local hrp = c and c:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local pos = hrp.Position
                    if not isSanePos(pos) then
                        _hackTag[p] = true
                    else
                        local last = _lastSeen[p]
                        if last then
                            if (pos - last).Magnitude / dt > HACK_SPEED then
                                local a = (_hackAccum[p] or 0) + dt
                                _hackAccum[p] = a
                                if a >= HACK_ACCUM then _hackTag[p] = true end
                            else
                                _hackAccum[p] = 0
                            end
                        end
                        _lastSeen[p] = pos
                    end
                end
            end
        end
    end
    local PRED_LEAD    = 0.15
    local PRED_MIN     = 0.05
    local PRED_MAX     = 120.0
    local PRED_SAMPLES = 5
    local PRED_NEEDED  = 3
    local _predHidden  = {}
    local _predDur     = {}
    local _predLast    = {}
    local PRED_MIN_PRES = 0.004
    local _predShown   = {}
    local _predPres    = {}
    local function isSanePos(p)
        return p == p
            and math.abs(p.X) < SANE_POS_LIMIT
            and math.abs(p.Y) < SANE_POS_LIMIT
            and math.abs(p.Z) < SANE_POS_LIMIT
    end
    local function tickPredict()
        local now = os.clock()
        for _, p in Players:GetPlayers() do
            if p ~= lp then
                local c = p.Character
                local hh = nil
                if c then hh = c:FindFirstChild("HitboxHead") or c:FindFirstChild("Head") end
                isSpawnProtected(p)
                local rp   = c and c:FindFirstChild("HumanoidRootPart") or nil
                local mine = hh ~= nil and hh == _glueHit
                if c == nil and _predHidden[p] ~= nil then
                    _predHidden[p] = nil
                    _predShown[p] = nil
                end
                local ref  = rp
                if ref == nil and not mine then ref = hh end
                if ref ~= nil and isSanePos(ref.Position) then
                    if hh ~= nil and not mine then _predLast[p] = hh.Position end
                    local since = _predHidden[p]
                    if since ~= nil then
                        _predHidden[p] = nil
                        _predShown[p] = now
                        local d = now - since
                        if d >= PRED_MIN and d <= PRED_MAX then
                            local r = _predDur[p]
                            if r == nil then
                                r = {}
                                _predDur[p] = r
                            end
                            r[#r + 1] = d
                            if #r > PRED_SAMPLES then table.remove(r, 1) end
                        end
                    end
                elseif ref ~= nil and _predHidden[p] == nil then
                    _predHidden[p] = now
                    local shown = _predShown[p]
                    if shown ~= nil then
                        _predShown[p] = nil
                        local dp = now - shown
                        if dp >= PRED_MIN_PRES and dp <= PRED_MAX then
                            local rr = _predPres[p]
                            if rr == nil then
                                rr = {}
                                _predPres[p] = rr
                            end
                            rr[#rr + 1] = dp
                            if #rr > PRED_SAMPLES then table.remove(rr, 1) end
                        end
                    end
                end
            end
        end
    end
    local function predMedian(p)
        local r = _predDur[p]
        if r == nil or #r < PRED_NEEDED then return nil end
        local s = {}
        for i = 1, #r do s[i] = r[i] end
        table.sort(s)
        return s[math.floor(#s / 2) + 1]
    end
    local function aboutToResurface(p)
        local since = _predHidden[p]
        if since == nil then return false end
        local m = predMedian(p)
        if m == nil then return false end
        local elapsed = os.clock() - since
        if elapsed > m + PRED_LEAD then return false end
        return elapsed >= m - PRED_LEAD
    end
    local function resurfaceIn(p)
        local since = _predHidden[p]
        if since == nil then return nil end
        local m = predMedian(p)
        if m == nil then return nil end
        return m - (os.clock() - since)
    end
    local function preFireLead()
        local ok, v = pcall(function() return lp:GetNetworkPing() end)
        local ping = 0.05
        if ok and type(v) == "number" and v == v and v > 0 then ping = v end
        if ping > 0.2 then ping = 0.2 end
        return ping
    end
    local function medianOf(tab, p, need)
        local r = tab[p]
        if r == nil or #r < need then return nil end
        local t = {}
        for i = 1, #r do t[i] = r[i] end
        table.sort(t)
        return t[math.floor(#t / 2) + 1]
    end
    local function publishPredict(p)
        if p == nil then
            State.RagePredTarget = nil
            return
        end
        State.RagePredTarget = p.Name
        State.RagePredHide   = predMedian(p) or 0
        State.RagePredHideN  = _predDur[p] and #_predDur[p] or 0
        State.RagePredAtk    = medianOf(_predPres, p, 2) or 0
        State.RagePredAtkN   = _predPres[p] and #_predPres[p] or 0
        local since = _predHidden[p]
        if since ~= nil then
            State.RagePredPhase = "HIDDEN"
            State.RagePredFor   = os.clock() - since
        else
            local shown = _predShown[p]
            State.RagePredPhase = "PRESENT"
            State.RagePredFor   = shown ~= nil and (os.clock() - shown) or 0
        end
        State.RagePredDue    = resurfaceIn(p) or 0
        State.RagePredWindow = aboutToResurface(p)
        local c  = p.Character
        local rr = c and c:FindFirstChild("HumanoidRootPart")
        State.RagePredMag = rr and rr.Position.Magnitude or 0
    end
    local function posInPart(pos, part)
        if not part or not part.Parent then return false end
        local lpv = part.CFrame:PointToObjectSpace(pos)
        local s = part.Size * 0.5
        return math.abs(lpv.X) <= s.X and math.abs(lpv.Y) <= s.Y and math.abs(lpv.Z) <= s.Z
    end
    local function posIsOOB(pos)
        local ok, result = pcall(function()
            for _, p in CollectionService:GetTagged("OutOfBoundsSafePart") do
                if posInPart(pos, p) then return false end
            end
            for _, p in CollectionService:GetTagged("OutOfBoundsPart") do
                if posInPart(pos, p) then return true end
            end
            return false
        end)
        return ok and result == true
    end
    local function killFloor()
        local ok, val = pcall(function() return Workspace.FallenPartsDestroyHeight end)
        if ok and type(val) == "number" and val == val then return val + KILL_PLANE_BUF end
        return -400
    end
    local function envIdOf(player)
        local id = nil
        pcall(function()
            local fc = Rivals.Fighter
            if fc == nil then return end
            local f = (player == lp) and fc.LocalFighter or (fc._player_to_fighter and fc._player_to_fighter[player])
            if f == nil then return end
            id = f:Get("EnvironmentID")
            if id == nil and f.Entity ~= nil then id = f.Entity:Get("EnvironmentID") end
        end)
        return id
    end
    local function isTeammate(player)
        if player == lp then return true end
        local myEnv, theirEnv = envIdOf(lp), envIdOf(player)
        if myEnv ~= nil and theirEnv ~= nil and myEnv ~= theirEnv then return true end
        local a = lp:GetAttribute("TeamID")
        local b = player:GetAttribute("TeamID")
        if a == nil or b == nil then
            if lp.Team ~= nil and player.Team ~= nil then return lp.Team == player.Team end
            return false
        end
        return a == b
    end
    local function isAlive(player)
        local c = player.Character
        local h = c and c:FindFirstChildOfClass("Humanoid")
        return h ~= nil and h.Health > 0
    end
    local function isProtected(player)
        if not player or not player.Character then return false end
        if player.Character:FindFirstChildOfClass("ForceField") then return true end
        if not Config.RageSkipImmune then return false end
        return isSpawnProtected(player)
    end
    local function inMatch()
        local envOk = false
        pcall(function()
            local lf = Rivals.Fighter and Rivals.Fighter.LocalFighter
            if lf ~= nil and lf:Get("EnvironmentID") ~= nil and lf:IsAlive() then envOk = true end
        end)
        if envOk then return true end
        if lp:GetAttribute("TeamID") ~= nil then return true end
        if lp.Team ~= nil then return true end
        return false
    end
    local function getEquippedItem()
        local ok, result = pcall(function()
            local lf = Rivals.Fighter and Rivals.Fighter.LocalFighter
            if lf and lf.EquippedItem then return lf.EquippedItem end
            return nil
        end)
        if ok then return result end
        return nil
    end
    local function weaponReady(it)
        if not it then return false end
        local okE, equipping = pcall(function() return it:IsEquipping() end)
        if okE and equipping then return false end
        if (it._reload_cooldown or 0) > tick() then return false end
        local magazine = true
        pcall(function() magazine = it.Info.MaxAmmo ~= nil end)
        if not magazine then return true end
        local okA, ammo = pcall(function() return it:Get("Ammo") end)
        return okA and type(ammo) == "number" and ammo > 0
    end
    local function findTarget()
        local myChar = lp.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        local cands = {}
        local unreachable = {}
        for _, p in Players:GetPlayers() do
            if p ~= lp and not isTeammate(p) and isAlive(p) then
                local c = p.Character
                local hrp = c and c:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local d = 9999
                    if myRoot then d = (hrp.Position - myRoot.Position).Magnitude end
                    local hum = c:FindFirstChildOfClass("Humanoid")
                    local health = 9999
                    if hum then health = hum.Health end
                    local entry = { p = p, hp = health, d = d, prot = isProtected(p),
                                    hack = _hackTag[p] == true }
                    if isSanePos(hrp.Position) and d <= MAX_DISTANCE then
                        table.insert(cands, entry)
                    else
                        table.insert(unreachable, entry)
                    end
                end
            end
        end
        if #cands == 0 then cands = unreachable end
        if #cands == 0 then return nil end
        table.sort(cands, function(a, b)
            if Config.RagePrioritizeHackers ~= false and a.hack ~= b.hack then return a.hack end
            if a.prot ~= b.prot then return b.prot end
            if math.abs(a.hp - b.hp) > 10 then return a.hp < b.hp end
            return a.d < b.d
        end)
        return cands[1].p
    end
    local function voidAxis()
        local v = math.random(VOID_R_MIN, VOID_R_MAX)
        if math.random(0, 1) == 0 then return -v end
        return v
    end
    local VOID_DEEP_AXIS   = 1073741824
    local VOID_DEEP_JITTER = 0.4
    local _voidOrder       = { 1, 2, 3 }
    local function voidDeep()
        return Config.RageVoidDepth ~= "shallow"
    end
    local function deepMag(allowNeg)
        local m = VOID_DEEP_AXIS * (1 + math.random() * VOID_DEEP_JITTER)
        if allowNeg and math.random(0, 1) == 1 then return -m end
        return m
    end
    local function rollVoidDeep()
        local ang = math.random() * math.pi * 2
        local r   = math.random(1000, 1500)
        local x   = math.cos(ang) * r
        local y   = math.random(1000, 1500)
        local z   = math.sin(ang) * r
        local o   = _voidOrder
        o[1], o[2], o[3] = 1, 2, 3
        for i = 3, 2, -1 do
            local j = math.random(1, i)
            o[i], o[j] = o[j], o[i]
        end
        for i = 1, math.random(1, 3) do
            local axis = o[i]
            if axis == 1 then
                x = deepMag(true)
            elseif axis == 2 then
                y = deepMag(false)
            else
                z = deepMag(true)
            end
        end
        return CFrame.new(x, y, z)
    end
    local function rollVoid()
        if voidDeep() then return rollVoidDeep() end
        return CFrame.new(voidAxis(), math.random(VOID_R_MIN, VOID_R_MAX), voidAxis())
    end
    local function voidCFrame()
        local prev = _voidCF
        local cf = rollVoid()
        if VOID_MOVE and prev then
            local tries = 0
            while tries < 8 and (cf.Position - prev.Position).Magnitude < VOID_MIN_STEP do
                cf = rollVoid()
                tries = tries + 1
            end
        end
        _voidCF = cf
        _voidSteps = _voidSteps + 1
        return cf
    end
    local TRANSLOCATE_OFFSET = -5
    local TRANSLOCATE_OFFSET = -5
    local TRANSLOCATE_FALLBACK_MIN = 10000
    local TRANSLOCATE_FALLBACK_MAX = 90000
    local function attackTranslocateCFrame(origin)
        local ok, result = pcall(function()
            local part = _translocatePart
            if part == nil or part.Parent == nil
               or not CollectionService:HasTag(part, "OutOfBoundsPart")
               or part:GetAttribute("KillDelay") ~= 0 then
                part = nil
                for _, candidate in CollectionService:GetTagged("OutOfBoundsPart") do
                    if candidate:GetAttribute("KillDelay") == 0 then
                        part = candidate
                        break
                    end
                end
                _translocatePart = part
            end
            if part ~= nil then
                return part.CFrame * CFrame.new(0, -part.Size.Y / 2 + TRANSLOCATE_OFFSET, 0)
            end
            local ang = math.random() * math.pi * 2
            local dist = TRANSLOCATE_FALLBACK_MIN
                + math.random() * (TRANSLOCATE_FALLBACK_MAX - TRANSLOCATE_FALLBACK_MIN)
            return CFrame.new(origin.X + math.cos(ang) * dist, origin.Y, origin.Z + math.sin(ang) * dist)
        end)
        if not ok then
            _translocatePart = nil
            return nil
        end
        return result
    end
    local PARK_UP_STUDS = 12
    local _parkRP = nil
    local function parkHasLOS(from, to, ourChar, tgtChar)
        if _parkRP == nil then
            _parkRP = RaycastParams.new()
            _parkRP.FilterType = Enum.RaycastFilterType.Exclude
        end
        _parkRP.FilterDescendantsInstances = { ourChar, tgtChar }
        local res = Workspace:Raycast(from, to - from, _parkRP)
        if not res then return true end
        return (res.Position - to).Magnitude < 3
    end
    local function eyeRise(fromPos, tgtChar)
        local rise = EYE_UP_SANE
        pcall(function()
            if _parkRP == nil then
                _parkRP = RaycastParams.new()
                _parkRP.FilterType = Enum.RaycastFilterType.Exclude
            end
            _parkRP.FilterDescendantsInstances = { lp.Character, tgtChar }
            local res = Workspace:Raycast(fromPos, Vector3.new(0, EYE_UP_SANE, 0), _parkRP)
            if res ~= nil then
                local room = (res.Position.Y - fromPos.Y) - 0.25
                if room < rise then
                    rise = math.max(room, 0.15)
                    State.RageEyeClampFrames = (State.RageEyeClampFrames or 0) + 1
                end
            end
        end)
        return rise
    end
    local MELEE_DWELL_S    = 0.07
    local _meleeDwellStart = nil
    local function pointBlank(hp)
        local y = math.max(hp.Y, killFloor() + 3)
        if y > hp.Y + 0.001 then
            State.RageParkClampFrames = (State.RageParkClampFrames or 0) + 1
        end
        return Vector3.new(hp.X, y, hp.Z)
    end
    local function meleeProfile(it)
        local prof = nil
        pcall(function()
            local info = it.Info
            if info == nil then return end
            if info.MaxAmmo ~= nil then return end
            local heavy = info.CriticalDamage ~= nil and type(info.HeavyAttackCooldown) == "number"
            prof = { heavy = heavy }
        end)
        return prof
    end
    local function meleeStrike(firePark, hpos, hh, tgt)
        local it = getEquippedItem()
        if it == nil then State.RageKnifeStatus = "no item" return false end
        local prof = meleeProfile(it)
        if prof == nil then State.RageKnifeStatus = "not a melee item" return false end
        local now = tick()
        if _meleeDwellStart == nil then _meleeDwellStart = now end
        if now - _meleeDwellStart < MELEE_DWELL_S then
            State.RageKnifeStatus = "dwell"
            return false
        end
        local actionName, animName = "StartShooting", "Attack1"
        if prof.heavy then
            actionName, animName = "StartAiming", "HeavyAttack1"
        end
        local actionEnum, animEnum = nil, nil
        pcall(function() actionEnum = Rivals.Enums:ToEnum(actionName) end)
        pcall(function() animEnum = Rivals.Enums:ToEnum(animName) end)
        local tc = tgt.Character
        local trp = tc and tc:FindFirstChild("HumanoidRootPart")
        if trp == nil then State.RageKnifeStatus = "target has no root" return false end
        local vp, vy = trp.CFrame:ToOrientation()
        if prof.heavy and Config.RageKnifeCamForge ~= false then
            ViewAngle.forge(vp, vy)
        end
        local eyePos   = firePark + Vector3.new(0, eyeRise(firePark, tgt and tgt.Character or nil), 0)
        local eyeCF    = Rage._lookCF(eyePos, hpos)
        local muzzleCF = eyeCF - Vector3.new(0, EYE_MUZZLE_SEP, 0)
        local sent = false
        State.RageFireFromPos = eyePos
        State.RageFireAimPos  = hpos
        State.RageFireHitPart = hh
        State.RageFireStamp   = tick()
        pcall(function()
            it._attack_cooldown = 0
            it._last_attack = tick() - 1
        end)
        local function lowerToId2()
            local g = getthreadidentity or get_thread_identity or getidentity or getthreadcontext
            local s = setthreadidentity or set_thread_identity or setidentity or setthreadcontext
            if g == nil or s == nil then return nil end
            local prev = nil
            pcall(function() prev = g() end)
            if prev == nil or prev == 2 then return nil end
            if not pcall(s, 2) then return nil end
            return function() pcall(s, prev) end
        end
        local function atId2(fn)
            local restoreId = lowerToId2()
            local ok, res = pcall(fn)
            if restoreId ~= nil then restoreId() end
            return ok, res
        end
        local hitData = { part = hh }
        if prof.heavy and type(it.HeavyAttack) == "function" then
            local ok = atId2(function() it:HeavyAttack(eyeCF, eyeCF, hitData) end)
            if ok then sent = true end
        elseif (not prof.heavy) and type(it.Attack) == "function" then
            local ok = atId2(function() it:Attack(eyeCF, eyeCF, hitData) end)
            if ok then sent = true end
        end
        local lf = Rivals.Fighter and Rivals.Fighter.LocalFighter
        if not sent then
            if Config.RageMeleeAsk ~= false then
                if lf == nil then State.RageKnifeStatus = "no LocalFighter" return false end
                local restoreId = lowerToId2()
                local ok, err = pcall(function() lf:Input(actionName) end)
                if restoreId ~= nil then restoreId() end
                local ran = false
                pcall(function() ran = (it._attack_cooldown or 0) > 0 end)
                sent = ok and ran
                if not ok then
                    State.RageKnifeStatus = "Input failed: " .. tostring(err)
                elseif not ran then
                    State.RageKnifeStatus = "item refused " .. actionName
                end
            else
                if _useItem == nil then
                    pcall(function() _useItem = ReplicatedStorage.Remotes.Replication.Fighter.UseItem end)
                end
                local okId, objId = pcall(function() return it:Get("ObjectID") end)
                if not okId or objId == nil then
                    pcall(function() objId = it.Info.ObjectID end)
                end
                if _useItem == nil then State.RageKnifeStatus = "no UseItem remote" return false end
                if objId == nil then State.RageKnifeStatus = "no ObjectID" return false end
                if actionEnum == nil then
                    State.RageKnifeStatus = "no " .. actionName .. " enum"
                    return false
                end
                State.RageForging = true
                local ferr = nil
                local fok = atId2(function()
                    local inner = {}
                    Rage._buildShotFields(inner, eyeCF, muzzleCF, hh, hpos, true, RAGE_CLAMP_FRAC, 1.0)
                    local env = { [utf8.char(1)] = inner }
                    if animEnum ~= nil then env[utf8.char(2)] = animEnum end
                    _useItem:FireServer(objId, actionEnum, env, nil)
                    sent = true
                end)
                State.RageForging = false
                if not fok then State.RageKnifeStatus = "FireServer failed: " .. tostring(ferr) end
            end
        end
        if sent then
            _shots = _shots + 1
            State.Shots = State.Shots + 1
            State.RageKnifeSwings = (State.RageKnifeSwings or 0) + 1
            State.RageKnifeStatus = "swinging " .. actionName
        else
            State.RageKnifeStatus = "send failed"
        end
        return sent
    end
    local function polarFire(eyePos, aimPos, hh, taps)
        local it = getEquippedItem()
        if not it then return 0 end
        pcall(function()
            it._shoot_cooldown = 0
            it._shoot_cooldown_no_ammo = 0
            it._last_shot = tick() - 1
        end)
        if _shootEnum == nil then
            pcall(function() _shootEnum = Rivals.Enums:ToEnum("StartShooting") end)
        end
        if _shootEnum == nil then return 0 end
        if _useItem == nil then
            pcall(function() _useItem = ReplicatedStorage.Remotes.Replication.Fighter.UseItem end)
        end
        if _useItem == nil then return 0 end
        local okId, objId = pcall(function() return it:Get("ObjectID") end)
        if not okId or not objId then return 0 end
        local fireEyePos = eyePos
        local base = eyePos - Vector3.new(0, EYE_UP_SANE, 0)
        local ftgt = State.RageTarget or State.Target
        local rise = eyeRise(base, ftgt and ftgt.Character or nil)
        if rise < EYE_UP_SANE then fireEyePos = base + Vector3.new(0, rise, 0) end
        local eyeCF    = Rage._lookCF(fireEyePos, aimPos)
        local muzzleCF = eyeCF - Vector3.new(0, EYE_MUZZLE_SEP, 0)
        local sent     = 0
        local rayCast = false
        pcall(function() rayCast = it.Info.IsRaycast == true end)
        local glued = glueActive()
        State.RageForging = true
        pcall(function()
            for _ = 1, taps do
                local inner = {}
                if glued then
                    inner[utf8.char(0)] = GLUE_CHAR0
                    inner[utf8.char(1)] = GLUE_CHAR1
                    inner[utf8.char(2)] = hh
                    inner[utf8.char(3)] = GLUE_CHAR3
                else
                    Rage._buildShotFields(inner, eyeCF, muzzleCF, hh, aimPos, true, RAGE_CLAMP_FRAC, 1.0)
                end
                local env = { [utf8.char(1)] = inner }
                if rayCast and not parity() then env[utf8.char(2)] = true end
                _useItem:FireServer(objId, _shootEnum, env, nil)
                sent = sent + 1
            end
        end)
        State.RageForging = false
        _shots = _shots + sent
        State.Shots = State.Shots + sent
        return sent
    end
    local function tapsPerFrame()
        local n = Config.RageTapsPerFrame
        if type(n) ~= "number" then return 1 end
        if n < 1 then return 1 end
        if n > POLAR_TAPS_SANE then return POLAR_TAPS_SANE end
        return math.floor(n)
    end
    local ATTACK_GAP_HOLD = 0.30
    local _attackGapTgt = nil
    local _attackGapUntil = 0
    local _attackReadyTgt = nil
    local function clearAttackGap()
        _attackGapTgt = nil
        _attackGapUntil = 0
    end
    local function resetAttackContinuity()
        clearAttackGap()
        _attackReadyTgt = nil
    end
    local function holdAttackGap(hrp, tgt, status)
        if Config.RageAttackContinuity == false then return false end
        local now = os.clock()
        if _attackGapTgt ~= tgt then
            if _attackReadyTgt ~= tgt or _prevPark == nil or _prevParkTgt ~= tgt then
                return false
            end
            _attackGapTgt = tgt
            _attackGapUntil = now + ATTACK_GAP_HOLD
        elseif now > _attackGapUntil then
            clearAttackGap()
            return false
        end
        _firing = false
        State.RageFiring = false
        State.RageStatus = status
        State.RageVoidActive = VOID_HIDE
        _lastPark = nil
        _meleeDwellStart = nil
        _translocateNext = false
        _translocateBurstPulses = 0
        _translocateFireFrames = 0
        _poisonFireFrames = 0
        _poisonBlips = 0
        liteRelease()
        glueRelease()
        if VOID_HIDE then
            displace(hrp, voidCFrame())
        end
        return true
    end
    local function hide(hrp, status)
        resetAttackContinuity()
        _firing = false
        State.RageFiring = false
        State.RageStatus = status
        State.RageVoidActive = VOID_HIDE
        _prevPark    = nil
        _prevParkTgt = nil
        _lastPark    = nil
        _hiding     = true
        _primeUntil = 0
        _meleeDwellStart = nil
        _translocateNext = false
        _translocateBurstPulses = 0
        _translocateFireFrames = 0
        _poisonFireFrames = 0
        _poisonBlips = 0
        liteRelease()
        glueRelease()
        if VOID_HIDE then
            displace(hrp, voidCFrame())
        end
    end
    local function polarTick(ch, hrp)
        local tgt = _target
        if tgt and (not tgt.Parent or not tgt.Character or not isAlive(tgt) or isTeammate(tgt)
                    or isProtected(tgt)) then
            tgt = nil
        end
        if not tgt then tgt = findTarget() end
        _target = tgt
        State.RageTarget = tgt
        publishPredict(tgt)
        if not tgt or not tgt.Character then return hide(hrp, "No target") end
        local holdFire = isProtected(tgt)
        if not holdFire then
            _immuneSince, _immuneTgt = 0, nil
        else
            local now = tick()
            if _immuneTgt ~= tgt then
                _immuneSince, _immuneTgt = now, tgt
            end
            if now - _immuneSince > IMMUNE_MAX_HOLD then
                holdFire = false
                State.RageImmuneOverride = (State.RageImmuneOverride or 0) + 1
            end
        end
        if Config.AvoidDeflect and isDeflecting(tgt) then
            local now = tick()
            if _deflectSince == 0 then _deflectSince = now end
            if now - _deflectSince < DEFLECT_MAX_HOLD then return hide(hrp, "Deflecting") end
        else
            _deflectSince = 0
        end
        local it = getEquippedItem()
        if not weaponReady(it) then
            local act = Rage._weaponRecovery(it)
            if act == "dry" then
                return hide(hrp, "Dry")
            end
            if act == "swap" or act == "swap-wait" then
                return hide(hrp, "Swapping")
            end
            return hide(hrp, "Reloading")
        end
        local hh = tgt.Character:FindFirstChild("HitboxHead") or tgt.Character:FindFirstChild("Head")
        if not hh then return hide(hrp, "Hiding") end
        if _hiding then
            _hiding = false
            local extra = 0
            if Config.RageHideJitter ~= false then
                extra = math.random() * HIDE_JITTER_MAX
            end
            _primeUntil = tick() + PRIME_S + extra
        end
        local trp  = tgt.Character:FindFirstChild("HumanoidRootPart")
        local mine = (hh == _glueHit)
        local hpos = hh.Position
        if mine and trp ~= nil then hpos = trp.Position end
        local predicting = false
        local voidFire   = false
        local rv         = nil
        if not isSanePos(hpos) then
            local pre = nil
            if Config.RagePredictResurface ~= false and aboutToResurface(tgt) then pre = _predLast[tgt] end
            if pre == nil or not isSanePos(pre) then
                if holdAttackGap(hrp, tgt, "Holding target swap") then
                    return nil
                end
                return hide(hrp, "Head voided")
            end
            hpos = pre
            predicting = true
            if Config.RageGumVoidFire ~= false and gumMode() == "on"
               and meleeProfile(it) == nil then
                rv = glueAcquire(hh)
                if rv ~= nil then
                    predicting = false
                    voidFire   = true
                end
            end
        end
        _firing = true
        State.RageFiring = not holdFire
        State.RageVoidActive = false
        local melee = meleeProfile(it) ~= nil
        local park
        if melee then
            local tc = tgt.Character
            local trp = tc and tc:FindFirstChild("HumanoidRootPart")
            if trp and (it.name == "Knife" or (meleeProfile(it) and meleeProfile(it).heavy)) then
                park = trp.Position - (trp.CFrame.LookVector * 1.2) + Vector3.new(0, 0.6, 0)
            else
                park = hpos + (trp and (trp.CFrame.LookVector * -0.8) or Vector3.new(0, -0.5, 0))
            end
        else
            park = pointBlank(hpos)
        end
        if posIsOOB(hpos) or posIsOOB(park) or not isSanePos(park) then
            if holdAttackGap(hrp, tgt, "Holding target swap") then
                return nil
            end
            return hide(hrp, "Hiding")
        end
        clearAttackGap()
        if Config.RageParkLift ~= false and not melee then
            local lifted = park + Vector3.new(0, PARK_UP_STUDS, 0)
            if isSanePos(lifted) and not posIsOOB(lifted)
               and parkHasLOS(lifted, hpos, ch, tgt.Character) then
                park = lifted
            end
        end
        local aimPos = hpos
        if rv == nil and not predicting and not melee then rv = glueAcquire(hh) end
        if rv == nil then liteAcquire(hh, predicting, melee) end
        if rv ~= nil then
            park   = rv + GLUE_PARK_OFF
            aimPos = hh.Position
        else
            glueRelease()
        end
        local firePark = nil
        if _prevPark ~= nil and _prevParkTgt == tgt then firePark = _prevPark end
        if restoreMode() ~= "kicia" then firePark = park end
        local translocateReady = Config.RageAttackTranslocate ~= false
            and restoreMode() == "kicia"
            and not predicting and not holdFire and not melee and firePark ~= nil
            and not voidFire
            and (parity() or tick() >= _primeUntil)
        local startingTranslocate = translocateReady
            and _translocateNext
            and _translocateBurstPulses < TRANSLOCATE_PULSES_PER_BURST
        local translocateCF = nil
        if startingTranslocate then
            translocateCF = attackTranslocateCFrame(hrp.Position)
        end
        local poisonCF = nil
        if translocateCF == nil
           and Config.RageGatePoison ~= false
           and voidDeep()
           and not predicting and not holdFire and not melee and firePark ~= nil
           and _poisonBlips < POISON_PER_BURST
           and _poisonFireFrames >= POISON_ARM_FRAMES then
            poisonCF = rollVoidDeep()
        end
        local desiredCFrame = CFrame.new(park)
        if translocateCF ~= nil then
            desiredCFrame = translocateCF
        elseif poisonCF ~= nil then
            desiredCFrame = poisonCF
        end
        local parked = displace(hrp, desiredCFrame)
        if parked and translocateCF == nil and poisonCF == nil then
            _prevPark, _prevParkTgt = park, tgt
            _lastPark = CFrame.new(park)
        elseif not parked then
            _prevPark, _prevParkTgt = nil, nil
            _lastPark = nil
        end
        if translocateCF ~= nil then
            _translocateNext = false
            if startingTranslocate then
                _translocateBurstPulses = _translocateBurstPulses + 1
                State.RageTranslocateBaits = (State.RageTranslocateBaits or 0) + 1
                _translocateFireFrames = 0
            end
            State.RageFiring = false
            State.RageTranslocating = parked
            if parked then
                State.RageStatus = "Translocating"
            else
                State.RageStatus = "Translocate failed"
            end
        elseif poisonCF ~= nil then
            _translocateNext = false
            State.RageFiring = false
            if parked then
                _poisonBlips = _poisonBlips + 1
                _poisonFireFrames = 0
                State.RagePoisonBlips = (State.RagePoisonBlips or 0) + 1
                State.RageStatus = "Poisoning"
            else
                State.RageStatus = "Poison failed"
            end
        elseif predicting then
            _translocateNext = false
            local lead = nil
            if Config.RagePredictPrefire ~= false and firePark ~= nil then
                lead = resurfaceIn(tgt)
            end
            if lead ~= nil and lead <= preFireLead() and lead > -PRED_LEAD then
                local sent = polarFire(firePark + Vector3.new(0, EYE_UP_SANE, 0), aimPos, hh, tapsPerFrame())
                if sent > 0 then
                    _attackReadyTgt = tgt
                    _poisonFireFrames = _poisonFireFrames + 1
                    State.RagePreFires = (State.RagePreFires or 0) + 1
                end
                State.RageStatus = "Prefiring resurface"
            else
                State.RageFiring = false
                State.RageStatus = "Predicting resurface"
            end
        elseif holdFire then
            _translocateNext = false
            State.RageStatus = "Protected — parked, holding fire"
        elseif firePark == nil then
            _translocateNext = false
            State.RageFiring = false
            State.RageStatus = "Priming"
            _meleeDwellStart = nil
        elseif (not parity()) and (tick() < _primeUntil) then
            _translocateNext = false
            State.RageFiring = false
            State.RageStatus = "Priming"
            _meleeDwellStart = nil
        elseif melee and Config.RageKnifeBot ~= false then
            _translocateNext = false
            if meleeStrike(firePark, aimPos, hh, tgt) then
                _attackReadyTgt = tgt
                State.RageStatus = "Melee"
            else
                State.RageFiring = false
                State.RageStatus = "Melee (cooldown)"
            end
        else
            local sent = polarFire(firePark + Vector3.new(0, EYE_UP_SANE, 0), aimPos, hh, tapsPerFrame())
            if sent > 0 then
                _attackReadyTgt = tgt
                _translocateFireFrames = _translocateFireFrames + 1
                _poisonFireFrames = _poisonFireFrames + 1
            end
            if voidFire and sent > 0 then
                State.RageVoidFires = (State.RageVoidFires or 0) + 1
            end
            _translocateNext = sent > 0 and parked and not melee
                and _translocateFireFrames >= TRANSLOCATE_ARM_FRAMES
                and _translocateBurstPulses < TRANSLOCATE_PULSES_PER_BURST
                and Config.RageAttackTranslocate ~= false
            State.RageStatus = "Attacking"
            if voidFire then State.RageStatus = "Attacking (gum void prefire)" end
        end
        if _notified ~= tgt then
            _notified = tgt
            pcall(Visuals.notifyTarget, tgt)
        end
    end
    local function restoreHome(pin)
        local ch = lp.Character
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        if not hrp or not hrp.Parent then return end
        local back = _preParkCF
        _preParkCF = nil
        pcall(function()
            if back then hrp.CFrame = back end
            if pin then
                local hu = ch:FindFirstChildOfClass("Humanoid")
                if hu and hu:GetState() == Enum.HumanoidStateType.Freefall
                   and hu.FloorMaterial ~= Enum.Material.Air then
                    hu:ChangeState(Enum.HumanoidStateType.Running)
                end
            end
        end)
    end
    local function cameraAnchor()
        if Config.RageCameraAnchor == false then return end
        local back = _preParkCF
        if back == nil then return end
        local ch = lp.Character
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        if not hrp or not hrp.Parent then return end
        local delta = back.Position - hrp.Position
        if not isSanePos(delta) then return end
        Camera.CFrame = Camera.CFrame + delta
    end
    local function reparkAfterRender()
        local cf = _lastPark
        if cf == nil then return end
        local ch = lp.Character
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        if not hrp or not hrp.Parent then return end
        displace(hrp, cf)
    end
    Players.PlayerRemoving:Connect(function(p)
        _hackTag[p]   = nil
        _lastSeen[p]  = nil
        _hackAccum[p] = nil
        _predHidden[p] = nil
        _predDur[p]    = nil
        _predLast[p]   = nil
    end)
    function PolarCore.start()
        if _conn then return end
        _firing = false
        resetAttackContinuity()
        setPhysicsFlags(true)
        _notified = nil
        pcall(function() RunService:UnbindFromRenderStep(RENDER_NAME) end)
        pcall(function() RunService:UnbindFromRenderStep(CAMERA_NAME) end)
        RunService:BindToRenderStep(CAMERA_NAME, Enum.RenderPriority.Camera.Value + 5, function()
            pcall(cameraAnchor)
        end)
        RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.First.Value - 1000, function()
            if _firing and restoreMode() == "none" then return end
            restoreHome(false)
        end)
        _stepConn = RunService.Stepped:Connect(function()
            if _firing then
                local pol = restoreMode()
                if pol == "render" then return reparkAfterRender() end
                if pol ~= "kicia" then return end
            end
            restoreHome(true)
        end)
        _charConn = lp.CharacterAdded:Connect(function()
            pcall(glueTeardown)
            _glueHit = nil
            _gluePrevOk = false
            _glueDriven = false
            _liteHit = nil
            _liteDriven = false
            _translocateNext = false
            _translocateBurstPulses = 0
            _translocateFireFrames = 0
            _poisonFireFrames = 0
            _poisonBlips = 0
            _translocatePart = nil
            State.RageGlueBound = false
            State.RageTranslocating = false
            _realCF = nil
            _realChar = nil
            _voidCF = nil
            _target = nil
            _notified = nil
            _firing = false
            resetAttackContinuity()
            _preParkCF = nil
            _prevPark, _prevParkTgt = nil, nil
            _lastPark = nil
            _hiding, _primeUntil = true, 0
        end)
        _conn = RunService.Heartbeat:Connect(function(dt)
            State.RageTranslocating = false
            tickHackers(dt or 0)
            tickPredict()
            if _glueHit ~= nil and not _glueDriven then
                pcall(glueRelease)
            end
            _glueDriven = false
            if _liteHit ~= nil and not _liteDriven then
                pcall(liteRelease)
            end
            _liteDriven = false
            State.RageGumMode = gumMode()
            if not Config.Rage or (Config.RageMode or "Polar") ~= "Polar" then
                PolarCore.stop()
                return
            end
            local ch  = lp.Character
            local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
            if not hrp or not hrp.Parent then return end
            if _preParkCF == nil and isSanePos(hrp.Position) then
                _realCF   = hrp.CFrame
                _realChar = ch
            end
            if _lastPark ~= nil and _firing and restoreMode() == "none" then
                local ok, d, dy = pcall(function()
                    local off = hrp.Position - _lastPark.Position
                    return off.Magnitude, off.Y
                end)
                if ok and d == d and d > PARK_DRIFT_STUDS then
                    State.RageParkDriftFrames = (State.RageParkDriftFrames or 0) + 1
                    State.RageParkDrift = math.floor(d)
                    State.RageParkDriftY = math.floor(dy or 0)
                end
            end
            _inMatch = inMatch()
            State.RageInMatch = _inMatch
            if not _inMatch then
                _target = nil
                _firing = false
                resetAttackContinuity()
                _translocateNext = false
                _translocateBurstPulses = 0
                _translocateFireFrames = 0
                State.RageFiring = false
                State.RageTarget = nil
                State.RageStatus = "Lobby"
                if not isSanePos(hrp.Position) then restoreHome(false) end
                return
            end
            if not _realCF or _realChar ~= ch then
                _firing = false
                resetAttackContinuity()
                _translocateNext = false
                _translocateBurstPulses = 0
                _translocateFireFrames = 0
                State.RageFiring = false
                State.RageStatus = "Waiting"
                return
            end
            local hum = ch:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health <= 0 then
                _firing = false
                resetAttackContinuity()
                _translocateNext = false
                _translocateBurstPulses = 0
                _translocateFireFrames = 0
                State.RageFiring = false
                State.RageVoidActive = false
                State.RageStatus = "Dead"
                pcall(glueRelease)
                pcall(liteRelease)
                if not isSanePos(hrp.Position) then restoreHome(false) end
                return
            end
            polarTick(ch, hrp)
        end)
    end
    function PolarCore.stop()
        pcall(liteRelease)
        pcall(glueRelease)
        setPhysicsFlags(false)
        pcall(ViewAngle.restore)
        if _conn then _conn:Disconnect(); _conn = nil end
        if _stepConn then _stepConn:Disconnect(); _stepConn = nil end
        if _charConn then _charConn:Disconnect(); _charConn = nil end
        pcall(function() RunService:UnbindFromRenderStep(RENDER_NAME) end)
        pcall(function() RunService:UnbindFromRenderStep(CAMERA_NAME) end)
        _firing = false
        resetAttackContinuity()
        local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        if hrp and hrp.Parent then
            if _realCF and _realChar == lp.Character then
                pcall(function() hrp.CFrame = CFrame.new(_realCF.Position) * hrp.CFrame.Rotation end)
            elseif not isSanePos(hrp.Position) then
                pcall(function() hrp.CFrame = CFrame.new(0, 100, 0) end)
            end
        end
        _realCF = nil; _realChar = nil; _target = nil; _voidCF = nil; _notified = nil
        _translocateNext = false
        _translocateBurstPulses = 0
        _translocateFireFrames = 0
        _poisonFireFrames = 0
        _poisonBlips = 0
        _translocatePart = nil
        State.RageFiring = false
        State.RageVoidActive = false
        State.RageTranslocating = false
        State.RageTarget = nil
        State.RageInMatch = false
        State.RageStatus = "Idle"
    end
    PolarCore.shots     = function() return _shots end
    PolarCore.voidSteps = function() return _voidSteps end
    Rage._polarCoreStart = PolarCore.start
    Rage._polarCoreStop  = PolarCore.stop
    Rage._setPhysicsFlags = setPhysicsFlags
    function Rage._physDiag()
        local set, get, setName = fflagApi()
        print("[LuaHook] fflag api: setter=" .. setName .. "  getter=" .. tostring(get ~= nil))
        print("[LuaHook] flags:  " .. tostring(State.RagePhysDetail or "(never set — is rage on?)"))
        print("[LuaHook] summary: " .. tostring(State.RagePhysRate or "off")
              .. "   set=" .. tostring(_physSet) .. "  verified=" .. tostring(_physLive))
        print("[LuaHook] immune-hold overrides: " .. tostring(State.RageImmuneOverride or 0))
        print("[LuaHook] gum: mode=" .. tostring(gumMode())
              .. "  (RageGumMode=" .. tostring(Config.RageGumMode)
              .. ", legacy RageGlueMode=" .. tostring(Config.RageGlueMode)
              .. ", RagePartGlue=" .. tostring(Config.RagePartGlue)
              .. ", voidFire=" .. tostring(Config.RageGumVoidFire ~= false) .. ")"
              .. "  liteBound=" .. tostring(_liteHit ~= nil)
              .. "  BOUND=" .. tostring(State.RageGlueBound == true)
              .. "  readback=" .. tostring(State.RageGlueVerified or "n/a")
              .. "  (sethiddenproperty=" .. tostring(type(sethiddenproperty) == "function")
              .. ", gethiddenproperty=" .. tostring(type(gethiddenproperty) == "function")
              .. ", identity=" .. tostring(_identSet ~= nil) .. ")")
        local rvTxt = "unrolled"
        if _rvCF ~= nil then rvTxt = tostring(_rvCF.Position) end
        print("[LuaHook] rendezvous: " .. rvTxt
              .. "   glued to: " .. tostring(_glueHit or _liteHit)
              .. "   (full=" .. tostring(_glueHit ~= nil) .. ", lite=" .. tostring(_liteHit ~= nil) .. ")")
        print("[LuaHook] attack translocate: enabled=" .. tostring(Config.RageAttackTranslocate ~= false)
              .. "  active=" .. tostring(State.RageTranslocating == true)
              .. "  next=" .. tostring(_translocateNext)
              .. "  burst=" .. tostring(_translocateBurstPulses)
              .. "/" .. tostring(TRANSLOCATE_PULSES_PER_BURST)
              .. "  part=" .. tostring(_translocatePart))
        print("[LuaHook] restore mode: " .. restoreMode()
              .. "   (Config.RageRestoreMode=" .. tostring(Config.RageRestoreMode)
              .. ", glue forces kicia=" .. tostring(glueActive())
              .. ", fires from " .. tostring(restoreMode() == "kicia") .. "=prev-frame park)")
        print("[LuaHook] gum void prefire (S45): allowed=" .. tostring(Config.RageGumVoidFire ~= false
                  and gumMode() == "on")
              .. "   shots sent through a hide=" .. tostring(State.RageVoidFires or 0)
              .. "   (0 against a deep-voider means the seam never ran — check the gum mode above first)")
        return restoreMode()
    end
    Rage._gumDiag = Rage._physDiag
end)()
local function silentPartVisible(part)
    if not part or not part:IsA("BasePart") then return false end
    if not Config.SilentAimMultipoint then return isVisible(part.Position) end
    if isVisible(part.Position) then return true end
    local n = math.max(1, math.floor(Config.SilentAimMultipointCount or 5))
    local r = math.min(part.Size.X, part.Size.Y, part.Size.Z) * 0.4
    for i = 1, n do
        local a   = (i / n) * math.pi * 2
        local off = Vector3.new(math.cos(a) * r, ((i % 2 == 0) and 0.5 or -0.5) * r, math.sin(a) * r)
        if isVisible(part.Position + off) then return true end
    end
    return false
end
local function pickSilentPart(char, primary)
    if not char then return primary end
    if silentPartVisible(primary) then return primary end
    for _, name in ipairs(HEAD_PARTS) do
        local p = char:FindFirstChild(name)
        if p and p ~= primary and silentPartVisible(p) then return p end
    end
    if Config.SilentAimTorsoFallback then
        for _, name in ipairs(TORSO_PARTS) do
            local p = char:FindFirstChild(name)
            if p and silentPartVisible(p) then return p end
        end
    end
    return primary
end
function hookGunModule()
    if not Rivals.Ready or not Rivals.Gun then return end
    if shared._LH_GunOrig then pcall(function() Rivals.Gun.StartShooting = shared._LH_GunOrig end) end
    if shared._LH_TracerOrig then pcall(function() Rivals.Gun._LocalTracers = shared._LH_TracerOrig end) end
    if shared._LH_ShootEffectOrig then pcall(function() Rivals.Gun._ShootEffect = shared._LH_ShootEffectOrig end) end
    if shared._LH_MeleeOrig and Rivals.Melee then
        pcall(function() Rivals.Melee.StartShooting = shared._LH_MeleeOrig end)
    end
    if shared._LH_KnifeOrig and Rivals.Knife then
        pcall(function() Rivals.Knife.StartAiming = shared._LH_KnifeOrig end)
    end
    shared._gunHooked = game
    local oldStart = Rivals.Gun.StartShooting
    shared._LH_GunOrig = oldStart
    local hookWrapper = function(self, ...)
        local suppress = (Config.Rage == true and Config.RageDirectFire == true)
        if suppress then
            pcall(function()
                local cf = self.ClientFighter
                if cf and cf.IsLocalPlayer == false then suppress = false end
            end)
        end
        if suppress then return false end
        local results = { oldStart(self, ...) }
        pcall(function()
            if not self.ClientFighter or not self.ClientFighter.IsLocalPlayer then return end
            pcall(function()
                local wname = nil
                pcall(function() wname = self.Name end)
                if type(wname) ~= "string" then
                    local ci = self.ClientItem
                    pcall(function() wname = ci and ci.Name or nil end)
                end
                if type(wname) == "string" then
                    State.LastAttackWeapon = wname
                    State.LastAttackWeaponAt = tick()
                end
            end)
            local camData = results[3]
            if not camData or typeof(camData) ~= "table" then return end
            local camPos = Camera.CFrame.Position
            State.CamPos = camPos
            if Config.Rage then
                if Rage._encodeRageShot(camData) then results[4] = true end
                return
            end
            if Config.SilentAim then
                local tgt, part = selectTarget({
                    fov        = Config.SilentAimFOV,
                    checkVis   = Config.SilentAimVisCheck,
                    partMode   = Config.SilentAimTargetPart,
                    stickyTarget = State.SilentLastTarget,
                    stickyBonus  = Config.SilentAimStickiness or 0.05,
                })
                if tgt and part then
                    State.SilentLastTarget = tgt
                    Visuals.notifyTarget(tgt)
                    if math.random(1, 100) <= (Config.SilentAimHitChance or 100) then
                        local hitPart = pickSilentPart(tgt.Character, part)
                        if math.random(1, 100) <= (Config.SilentAimBodyMix or 0) then
                            local body = tgt.Character:FindFirstChild("HitboxBody")
                            if body and silentPartVisible(body.Position) then hitPart = body end
                        end
                        local jit = Vector3.zero
                        local jd = Config.SilentAimJitterDeg or 0
                        if jd > 0 then
                            local dir = jit
                            local okD, unit = pcall(function()
                                return Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
                            end)
                            if okD and unit.Magnitude > 1e-4 then dir = unit.Unit end
                            local dist = 0
                            pcall(function() dist = (hitPart.Position - camPos).Magnitude end)
                            local off = math.min(math.tan(math.rad(jd)) * dist, 3) * (math.random() * 0.5)
                            jit = dir * off
                        end
                        if Rage._encodeShot(camData, hitPart, tgt.Character, camPos, jit) then
                            results[4] = true
                            State.Shots = State.Shots + 1
                            State.Hits  = State.Hits  + 1
                        end
                    end
                    return
                end
            end
            if Config.Aimbot and Config.AimbotShotOverride
                and State.AimbotTarget and State.AimbotPart and State.AimbotKeyHeld then
                local tgt = State.AimbotTarget
                if tgt and tgt.Character and isValidTarget(tgt, false) then
                    Visuals.notifyTarget(tgt)
                    if Rage._encodeShot(camData, State.AimbotPart, tgt.Character, camPos) then
                        results[4] = true
                        State.Shots = State.Shots + 1
                        State.Hits  = State.Hits  + 1
                    end
                end
            end
            if Config.HUD or Config.VisualsHolograms then
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Exclude
                rp.FilterDescendantsInstances = { lp.Character }
                local res = workspace:Raycast(camPos, Camera.CFrame.LookVector * (Config.MaxDistance or 1000), rp)
                if res and res.Instance then
                    local m  = res.Instance:FindFirstAncestorOfClass("Model")
                    local pl = m and Players:GetPlayerFromCharacter(m)
                    if pl and pl ~= lp then Visuals.notifyTarget(pl) end
                end
            end
        end)
        return unpack(results)
    end
    if setfenv then pcall(setfenv, hookWrapper, getfenv(oldStart)) end
    if setreadonly then pcall(setreadonly, Rivals.Gun, false) end
    Rivals.Gun.StartShooting = hookWrapper
    local oldLocalTracers = Rivals.Gun._LocalTracers
    if type(oldLocalTracers) == "function" then
        shared._LH_TracerOrig = oldLocalTracers
        Rivals.Gun._LocalTracers = function(selfItem, ...)
            if Config.Rage == true and Config.RageDirectFire == true then
                State.RageTracerCanary = (State.RageTracerCanary or 0) + 1
                return
            end
            return oldLocalTracers(selfItem, ...)
        end
    end
    local function wrapMeleeAttack(cls, method, saveKey)
        if type(cls) ~= "table" then return end
        local orig = rawget(cls, method)
        if type(orig) ~= "function" then return end
        shared[saveKey] = shared[saveKey] or orig
        if setreadonly then pcall(setreadonly, cls, false) end
        cls[method] = function(selfItem, ...)
            local g = getthreadidentity or get_thread_identity or getidentity or getthreadcontext
            local s = setthreadidentity or set_thread_identity or setidentity or setthreadcontext
            local prev, switched = nil, false
            if g ~= nil and s ~= nil then pcall(function() prev = g() end) end
            if prev ~= nil and prev ~= 2 then switched = pcall(s, 2) end
            local results = { orig(selfItem, ...) }
            if switched then pcall(s, prev) end
            pcall(function()
                if not selfItem.ClientFighter or not selfItem.ClientFighter.IsLocalPlayer then return end
                pcall(function()
                    local wname = nil
                    pcall(function() wname = selfItem.Name end)
                    if type(wname) ~= "string" then
                        local ci = selfItem.ClientItem
                        pcall(function() wname = ci and ci.Name or nil end)
                    end
                    if type(wname) == "string" then
                    State.LastAttackWeapon = wname
                    State.LastAttackWeaponAt = tick()
                end
                end)
                if not Config.Rage then return end
                local camData = results[3]
                if typeof(camData) ~= "table" then return end
                Rage._encodeRageShot(camData)
            end)
            return unpack(results)
        end
    end
    wrapMeleeAttack(Rivals.Melee, "StartShooting", "_LH_MeleeOrig")
    wrapMeleeAttack(Rivals.Knife, "StartAiming",  "_LH_KnifeOrig")
    local oldShootEffect = Rivals.Gun._ShootEffect
    if type(oldShootEffect) == "function" then
        shared._LH_ShootEffectOrig = oldShootEffect
        Rivals.Gun._ShootEffect = function(selfItem, results, ...)
            pcall(function()
                if Config.Rage ~= true or Config.RageDirectFire ~= true then return end
                if type(results) ~= "table" then return end
                local cf = selfItem.ClientFighter
                if not cf or not cf.IsLocalPlayer then return end
                local tgt = State.RageTarget
                local tchar = tgt and tgt.Character
                local myRoot = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
                for _, entry in results do
                    local hitPart = entry[utf8.char(1)]
                    local hitPos  = entry[utf8.char(0)]
                    local onTarget = false
                    if hitPart and tchar and hitPart:IsDescendantOf(tchar) then onTarget = true end
                    if onTarget then
                        State.RageHitsOn = (State.RageHitsOn or 0) + 1
                    else
                        State.RageHitsOff = (State.RageHitsOff or 0) + 1
                        if typeof(hitPos) == "Vector3" then
                            if myRoot then
                                State.RageOffFromSelf = (hitPos - myRoot.Position).Magnitude
                            end
                            local th = tchar and (tchar:FindFirstChild("HitboxHead") or tchar:FindFirstChild("Head"))
                            if th then
                                State.RageOffFromTarget = (hitPos - th.Position).Magnitude
                            end
                        end
                    end
                end
            end)
            return oldShootEffect(selfItem, results, ...)
        end
    end
end
hookGunModule()
ViewAngle = {}
;(function()
    local _remote     = nil
    local _forged     = nil
    local _loopFn, _utilIdx, _utilOrig = nil, nil, nil
    local _suppressed = false
    local _joints, _jointsOrig = nil, nil
    local function remote()
        if _remote == nil then
            pcall(function()
                _remote = ReplicatedStorage.Remotes.Replication.Fighter.UpdateCameraRotation
            end)
        end
        return _remote
    end
    local function resolveLoop()
        if _loopFn ~= nil then return true end
        if type(debug) ~= "table" or type(debug.getupvalues) ~= "function"
           or type(debug.setupvalue) ~= "function" then
            return false
        end
        pcall(function()
            local F = Rivals.Fighter
            if F == nil then return end
            local fn = rawget(F, "_CameraReplicationLoop")
            if type(fn) ~= "function" then
                local mt = getmetatable(F)
                local proto = mt and rawget(mt, "__index")
                if type(proto) == "table" then fn = rawget(proto, "_CameraReplicationLoop") end
            end
            if type(fn) ~= "function" then return end
            for i, v in debug.getupvalues(fn) do
                if type(v) == "table" then
                    local vmt = getmetatable(v)
                    local vidx = vmt and rawget(vmt, "__index")
                    if type(vidx) == "table" and rawget(vidx, "EncodeCameraRotation") ~= nil then
                        _loopFn, _utilIdx, _utilOrig = fn, i, v
                        return
                    end
                end
            end
        end)
        return _loopFn ~= nil
    end
    local function makeShim()
        local shim = {}
        shim.EncodeCameraRotation = function(_, rot)
            local last = nil
            pcall(function()
                local F = Rivals.Fighter
                if F ~= nil then
                    F._replication_stopped = false
                    last = F._last_encoded_camera_rotation
                end
            end)
            if last ~= nil then return last end
            return _utilOrig:EncodeCameraRotation(rot)
        end
        return setmetatable(shim, { __index = _utilOrig })
    end
    local function suppress(on)
        if on == _suppressed then return end
        if on then
            if not resolveLoop() then return end
            if pcall(debug.setupvalue, _loopFn, _utilIdx, makeShim()) then
                _suppressed = true
                State.ViewAngleForged = true
            end
            return
        end
        if _loopFn ~= nil and _utilOrig ~= nil then
            pcall(debug.setupvalue, _loopFn, _utilIdx, _utilOrig)
        end
        _suppressed = false
        State.ViewAngleForged = false
    end
    local function patchJoints(on)
        if on then
            if _jointsOrig ~= nil then return end
            pcall(function()
                _joints = loadGameModule(lp.PlayerScripts,
                    {"Modules", "ClientReplicatedClasses", "ClientFighter", "ClientFighterCharacter", "Joints"})
                if type(_joints) ~= "table" then
                    _joints = nil
                    return
                end
                local orig = rawget(_joints, "Update")
                if type(orig) ~= "function" then
                    _joints = nil
                    return
                end
                _jointsOrig = orig
                if setreadonly then pcall(setreadonly, _joints, false) end
                _joints.Update = function(selfJoints, dt, data)
                    if _forged ~= nil and type(data) == "table" then
                        pcall(function()
                            local cfc = selfJoints.ClientFighterCharacter
                            local cf = cfc and cfc.ClientFighter
                            if cf and cf.IsLocalPlayer == true then
                                data.CameraRotationRaw = _forged
                            end
                        end)
                    end
                    return orig(selfJoints, dt, data)
                end
            end)
            return
        end
        if _joints ~= nil and _jointsOrig ~= nil then
            pcall(function()
                if setreadonly then pcall(setreadonly, _joints, false) end
                _joints.Update = _jointsOrig
            end)
        end
        _jointsOrig = nil
    end
    function ViewAngle.forge(pitch, yaw)
        local r = remote()
        if r == nil or not Rivals.Util then return false end
        local ok = pcall(function()
            local enc = Rivals.Util:EncodeCameraRotation(Vector2.new(pitch, yaw))
            _forged = Rivals.Util:DecodeCameraRotation(enc)
            r:FireServer(enc, nil)
        end)
        if not ok then return false end
        suppress(true)
        patchJoints(true)
        return true
    end
    function ViewAngle.restore()
        _forged = nil
        suppress(false)
        patchJoints(false)
    end
    ViewAngle.isForging = function() return _forged ~= nil end
end)()
local Aimbot = {}
;(function()
    local TAU = math.pi * 2
    local D2R = math.pi / 180
    local R2D = 180 / math.pi
    local MAX_TAU     = 0.30
    local RETAIN_MUL  = 1.6
    local STICKY_MEM  = 2.0
    local FF_TAU      = 0.05
    local FF_MAX      = 12
    local UNIT_MAX    = 2000
    local RAMP_TIME   = 0.15
    local PITCH_LIMIT = 1.5690509975429023
    local CAL_MIN     = 1.5
    local CAL_FAST_N  = 8
    local BAND_LO     = 0.05
    local BAND_HI     = 6.0
    local OSC_ERR     = 0.02
    local RUNAWAY_ERR = 1.0
    local SEED_MX     = -0.008726646259971648
    local SEED_MY     = -0.006719517620178168
    local SEED_DX     = 1.0
    local SEED_DY     = 1.0
    local _bound       = false
    local _mouseMove   = mousemoverel
    local _fovC, _lockC, _dbgT = nil, nil, nil
    local _tgt, _part  = nil, nil
    local _prevTgt     = nil
    local _notified    = nil
    local _acquireAt   = 0
    local _lastSeenAt  = 0
    local _ramp        = 0
    local _gx, _gy     = SEED_MX, SEED_MY
    local _sdx, _sdy   = SEED_MX, SEED_MY
    local _nx, _ny     = 0, 0
    local _sx, _sy     = 0, 0
    local _fx, _fy     = 0, 0
    local _lyaw, _lpit = 0, 0
    local _haveCam     = false
    local _ffy, _ffp   = 0, 0
    local _lty, _ltp   = 0, 0
    local _haveTgt     = false
    local _lastPartRef = nil
    local _flickActive   = false
    local _flickT        = 0
    local _flickDur      = 0.15
    local _flickCtrl1Y   = 0
    local _flickCtrl1P   = 0
    local _flickCtrl2Y   = 0
    local _flickCtrl2P   = 0
    local _auth        = 1.0
    local _flips       = 0
    local _errEma      = 0
    local _lastSign    = nil
    local _drive       = 0
    local _trips       = 0
    local _calOff      = false
    local _lastFOV     = 0
    local _errDeg      = 0
    local _path        = "none"
    local _ctl, _ctlTried = nil, false
    local function wrapPi(a)
        return (a + math.pi) % TAU - math.pi
    end
    local function yawOf(v)
        return math.atan2(-v.X, -v.Z)
    end
    local function pitchOf(v)
        return math.asin(math.clamp(v.Y, -1, 1))
    end
    local function angTo(cf, pos)
        local d = pos - cf.Position
        local m = d.Magnitude
        if m < 1e-4 then return 0 end
        return math.acos(math.clamp(cf.LookVector:Dot(d) / m, -1, 1))
    end
    local function fovPixels(deg)
        local vp = Camera.ViewportSize
        local lim = math.max(vp.X, vp.Y)
        if deg >= 89 then return lim end
        local half = math.tan(math.rad(Camera.FieldOfView) * 0.5)
        if half <= 0 then return lim end
        return math.clamp(math.tan(deg * D2R) / half * (vp.Y * 0.5), 4, lim)
    end
    local function minJerk(s)
        s = math.clamp(s, 0, 1)
        return s * s * s * (10 + s * (-15 + 6 * s))
    end
    local function bezier(p0, p1, p2, p3, t)
        local it = 1 - t
        return it * it * it * p0 + 3 * it * it * t * p1 + 3 * it * t * t * p2 + t * t * t * p3
    end
    local function validFor(pl)
        if not isValidTarget(pl, false) then return false end
        if Config.AimbotSkipImmune and isSpawnProtected(pl) then return false end
        return true
    end
    local function firstVisible(char, list, skip)
        for _, n in ipairs(list) do
            local p = char:FindFirstChild(n)
            if p and p ~= skip and p:IsA("BasePart") and isVisible(p.Position) then return p end
        end
        return nil
    end
    local function resolveBest(char, primary)
        if not char then return primary end
        if primary and isVisible(primary.Position) then return primary end
        return firstVisible(char, HEAD_PARTS, primary)
            or firstVisible(char, TORSO_PARTS, primary)
            or primary
    end
    local function acquire(cf, fovR, retainR, cur)
        local mode = Config.AimbotTargetPart or "Best"
        local pick = (mode == "Best") and "Head" or mode
        local prio = Config.AimbotPriority or "Crosshair"
        local vis  = Config.AimbotVisCheck
        local myRoot = nil
        if prio == "Distance" then
            local mc = lp.Character
            myRoot = mc and mc:FindFirstChild("HumanoidRootPart")
        end
        local bP, bPart, bAng, bScore = nil, nil, math.huge, math.huge
        local cPart, cAng, cOK = nil, math.huge, false
        for _, pl in ipairs(getSafePlayers()) do
            if pl ~= lp and validFor(pl) then
                local char = pl.Character
                local part = pickPart(char, pick)
                if part then
                    local ang    = angTo(cf, part.Position)
                    local isCur  = (pl == cur)
                    if ang <= (isCur and retainR or fovR) then
                        local hasVis = (not vis) or isVisible(part.Position)
                        if hasVis then
                            local score = ang
                            if prio == "Health" then
                                local hp = getHealth(pl)
                                score = hp * 100 + ang
                            elseif prio == "Distance" and myRoot then
                                score = (part.Position - myRoot.Position).Magnitude * 100 + ang
                            end
                            if isCur then
                                cPart, cAng, cOK = part, ang, true
                                score = score * (1 - (Config.AimbotStickiness or 0))
                            end
                            if score < bScore then bScore, bP, bPart, bAng = score, pl, part, ang end
                        end
                    end
                end
            end
        end
        if prio == "Crosshair" and cOK and bP and bP ~= cur then
            if bAng > cAng - (Config.AimbotSwitchDeg or 0) * D2R then
                return cur, cPart, cAng
            end
        end
        return bP, bPart, bAng
    end
    local function ensureDraw()
        pcall(function()
            if not _fovC then
                local c = screenDraw("Circle")
                if c then
                    c.Thickness = 1; c.NumSides = 64
                    c.Color = Color3.fromRGB(180, 180, 180)
                    c.Transparency = 0.6; c.Filled = false; c.Visible = false
                    _fovC = c
                end
            end
            if not _lockC then
                local c = screenDraw("Circle")
                if c then
                    c.Thickness = 2; c.NumSides = 32
                    c.Color = Color3.fromRGB(255, 80, 100)
                    c.Transparency = 0.9; c.Filled = false; c.Radius = 6; c.Visible = false
                    _lockC = c
                end
            end
            if not _dbgT then
                local t = screenDraw("Text")
                if t then
                    t.Font = 3; t.Size = 13; t.Outline = true
                    t.Color = Color3.fromRGB(0, 230, 160)
                    t.Position = Vector2.new(14, 330); t.Visible = false
                    _dbgT = t
                end
            end
        end)
    end
    local function diagText()
        return string.format(
            "AIMBOT [MATH V2]  path=%s%s\ngain  x=%.6f (n%d)   y=%.6f (n%d)\nerr %.2f deg   sent %d,%d   auth %.2f   trips %d\ntarget %s",
            _path, _calOff and "  [gain PINNED]" or "",
            _gx, _nx, _gy, _ny, _errDeg, _sx, _sy, _auth, _trips,
            _tgt and _tgt.Name or "-")
    end
    local function updateDraw()
        local wantFov  = Config.Aimbot and Config.AimbotShowFOV
        local wantLock = Config.Aimbot and Config.AimbotShowLock and _part
        local wantDbg  = Config.Aimbot and Config.AimbotDebug
        if not (wantFov or wantLock or wantDbg) then
            if _fovC  and _fovC.Visible  then _fovC.Visible  = false end
            if _lockC and _lockC.Visible then _lockC.Visible = false end
            if _dbgT  and _dbgT.Visible  then _dbgT.Visible  = false end
            return
        end
        ensureDraw()
        if _fovC then
            if wantFov then
                local vp = Camera.ViewportSize
                _fovC.Position = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
                _fovC.Radius   = fovPixels(Config.AimbotFOVDeg or 20)
                _fovC.Visible  = true
            else
                _fovC.Visible = false
            end
        end
        if _lockC then
            local on = false
            if wantLock then
                local sp, vis = Camera:WorldToViewportPoint(_part.Position)
                if vis and sp.Z > 0 then
                    _lockC.Position = Vector2.new(sp.X, sp.Y)
                    on = true
                end
            end
            _lockC.Visible = on
        end
        if _dbgT then
            if wantDbg then
                _dbgT.Text = diagText(); _dbgT.Visible = true
            else
                _dbgT.Visible = false
            end
        end
    end
    local function resolvePath()
        local uis = UserInputService or game:GetService("UserInputService")
        local touchOnly = uis.TouchEnabled and not uis.MouseEnabled
        if _mouseMove and not touchOnly then return "mouse" end
        if Config.AimbotDirectCamera or touchOnly then
            if not _ctlTried then
                _ctlTried = true
                task.spawn(function()
                    local ok, m = pcall(loadGameModule, lp.PlayerScripts, { "Controllers", "CameraController" })
                    if ok and type(m) == "table" and typeof(m.Rotation) == "Vector2"
                       and type(m.ApplyRotationDelta) == "function" then
                        _ctl = m
                        _gx, _gy   = SEED_DX, SEED_DY
                        _sdx, _sdy = SEED_DX, SEED_DY
                        _nx, _ny   = 0, 0
                    end
                end)
            end
            if _ctl then return "direct" end
        end
        return "none"
    end
    local function getSpringOffset()
        if not Config.AimbotCancelSprings then return 0, 0 end
        if _ctl then
            local s = rawget(_ctl, "_aim_spring") or rawget(_ctl, "_camera_rotation_spring")
            if s and typeof(s.Position) == "Vector2" then
                return s.Position.Y, s.Position.X
            elseif s and typeof(s.Position) == "Vector3" then
                return s.Position.X, s.Position.Y
            end
        end
        return 0, 0
    end
    local function quant(v, frac)
        local w = v + frac
        local n = (w >= 0) and math.floor(w + 0.5) or math.ceil(w - 0.5)
        return n, w - n
    end
    local function emit(ux, uy)
        if _path == "mouse" then
            pcall(_mouseMove, ux, uy)
        elseif _path == "direct" and _ctl then
            pcall(function() _ctl:ApplyRotationDelta(Vector2.new(uy, ux)) end)
        end
    end
    local function calibrate(obs, sent, gain, n, seed)
        if math.abs(sent) < CAL_MIN then return gain, n end
        local s = obs / sent
        if (s * seed) <= 0 then return gain, n end
        local a  = math.abs(s)
        local lo = math.abs(seed) * BAND_LO
        local hi = math.abs(seed) * BAND_HI
        if a < lo or a > hi then return gain, n end
        if n < CAL_FAST_N then return s, n + 1 end
        local r = math.abs(s / gain)
        if r < 0.34 or r > 3.0 then return gain, n end
        return gain + (s - gain) * 0.05, n + 1
    end
    local function clearTarget()
        _tgt, _part  = nil, nil
        _prevTgt     = nil
        _notified    = nil
        _haveTgt     = false
        _lastPartRef = nil
        _ffy, _ffp   = 0, 0
        _errDeg      = 0
        _flips, _errEma, _lastSign, _drive = 0, 0, nil, 0
        _flickActive = false
        State.AimbotTarget      = nil
        State.AimbotPart        = nil
        State.AimbotFlickActive = false
    end
    local function step(dt)
        dt = math.clamp(dt or (1 / 60), 1 / 1000, 0.1)
        local cf     = Camera.CFrame
        local look   = cf.LookVector
        local curYaw, curPit = yawOf(look), pitchOf(look)
        if _haveCam and not _calOff then
            _gx, _nx = calibrate(wrapPi(curYaw - _lyaw), _sx, _gx, _nx, _sdx)
            _gy, _ny = calibrate(curPit - _lpit,         _sy, _gy, _ny, _sdy)
        end
        _lyaw, _lpit, _haveCam = curYaw, curPit, true
        local fov = Camera.FieldOfView
        if math.abs(fov - _lastFOV) > 0.5 then
            _lastFOV = fov
            _nx, _ny = 0, 0
        end
        _sx, _sy = 0, 0
        updateDraw()
        if not Config.Aimbot then
            State.AimbotKeyHeld = false
            clearTarget()
            return
        end
        if State.RageFiring then clearTarget(); return end
        if not inMatch() then
            State.AimbotKeyHeld = false
            clearTarget()
            return
        end
        local keyDown = aimbotKeyDown()
        State.AimbotKeyHeld = keyDown
        if not keyDown then
            clearTarget()
            return
        end
        _path = resolvePath()
        if _path == "none" then clearTarget(); return end
        local fovR    = math.clamp(Config.AimbotFOVDeg or 20, 0.1, 180) * D2R
        local retainR = math.min(fovR * RETAIN_MUL, math.pi)
        local sticky  = _tgt
        if not sticky then
            local last = State.AimbotLastTarget
            if last and (tick() - (State.AimbotLastTargetTime or 0)) <= STICKY_MEM then sticky = last end
        end
        local tgt, part = acquire(cf, fovR, retainR, sticky)
        local now = tick()
        if tgt and part then
            _lastSeenAt = now
        else
            local forget = Config.AimbotForgetTime or 0.2
            if _tgt and (now - _lastSeenAt) <= forget then
                tgt, part = _tgt, _part
            else
                clearTarget()
                return
            end
        end
        if (Config.AimbotTargetPart or "Best") == "Best" then
            part = resolveBest(tgt.Character, part) or part
        end
        if tgt ~= _prevTgt then
            _acquireAt   = now
            _ramp        = 0
            _haveTgt     = false
            _ffy, _ffp   = 0, 0
            _prevTgt     = tgt
            _flickActive = false
        end
        _tgt, _part = tgt, part
        State.AimbotTarget         = tgt
        State.AimbotPart           = part
        State.AimbotLastTarget     = tgt
        State.AimbotLastTargetTime = now
        if _notified ~= tgt then
            _notified = tgt
            pcall(Visuals.notifyTarget, tgt)
        end
        local targetPos = part.Position
        local targetChar = tgt.Character
        local targetRP = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
        local targetVel = targetRP and targetRP.AssemblyLinearVelocity or Vector3.zero
        local myChar = lp.Character
        local myRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
        local myVel = myRP and myRP.AssemblyLinearVelocity or Vector3.zero
        local vRel = targetVel - myVel
        if Config.AimbotPrediction then
            local lead = calculateLead(targetChar, cf.Position, true)
            targetPos = targetPos + lead
            local hum = targetChar and targetChar:FindFirstChildOfClass("Humanoid")
            if hum and hum.FloorMaterial == Enum.Material.Air then
                local dist = (targetPos - cf.Position).Magnitude
                local leadTime = math.clamp(dist / 1000, 0, 0.5)
                targetPos = targetPos + Vector3.new(0, 0.5 * -196.2 * leadTime * leadTime, 0)
            end
        end
        local d = targetPos - cf.Position
        local dDist = d.Magnitude
        if dDist < 1e-3 then return end
        local u = d / dDist
        local tYaw = yawOf(u)
        local tPit = math.clamp(pitchOf(u), -PITCH_LIMIT, PITCH_LIMIT)
        local errYaw = wrapPi(tYaw - curYaw)
        local errPit = tPit - curPit
        _errDeg = math.sqrt(errYaw * errYaw + errPit * errPit) * R2D
        local dH2 = d.X * d.X + d.Z * d.Z
        if _haveTgt and part == _lastPartRef and dH2 > 1e-4 then
            local vDotU = vRel:Dot(u)
            local dH = math.sqrt(dH2)
            local rawFFY = (d.Z * vRel.X - d.X * vRel.Z) / dH2
            local rawFFP = (vRel.Y - vDotU * u.Y) / dH
            local k = math.clamp(dt / FF_TAU, 0, 1)
            _ffy = _ffy + (math.clamp(rawFFY, -FF_MAX, FF_MAX) - _ffy) * k
            _ffp = _ffp + (math.clamp(rawFFP, -FF_MAX, FF_MAX) - _ffp) * k
        else
            _ffy, _ffp = 0, 0
        end
        _lty, _ltp, _haveTgt, _lastPartRef = tYaw, tPit, true, part
        if (Config.AimbotReactionMs or 0) > 0
           and (now - _acquireAt) * 1000 < Config.AimbotReactionMs then return end
        if (Config.AimbotDeadzoneDeg or 0) > 0 then
            local m = math.sqrt(errYaw * errYaw + errPit * errPit)
            if m < Config.AimbotDeadzoneDeg * D2R then return end
        end
        local smoothX = Config.AimbotLinkAxes and (Config.AimbotSmoothness or 0) or (Config.AimbotSmoothnessX or Config.AimbotSmoothness or 0)
        local smoothY = Config.AimbotLinkAxes and (Config.AimbotSmoothness or 0) or (Config.AimbotSmoothnessY or Config.AimbotSmoothness or 0)
        smoothX = math.clamp(smoothX, 0, 100)
        smoothY = math.clamp(smoothY, 0, 100)
        local isHardLock = (smoothX == 0 and smoothY == 0)
        local targetHum = targetChar and targetChar:FindFirstChildOfClass("Humanoid")
        local isAirborne = (targetHum and targetHum.FloorMaterial == Enum.Material.Air) or math.abs(targetVel.Y) > 5
        if isAirborne and (Config.AimbotJumpDamping or 0) > 0 and smoothY > 0 then
            local jDamp = (Config.AimbotJumpDamping / 100)
            local vyFrac = math.clamp(math.abs(targetVel.Y) / 60, 0, 1)
            smoothY = math.clamp(smoothY + (100 - smoothY) * vyFrac * jDamp, 0, 100)
        end
        local aErr = math.sqrt(errYaw * errYaw + errPit * errPit)
        _errEma = _errEma + (aErr - _errEma) * math.clamp(dt / 0.15, 0, 1)
        _drive  = _drive + dt
        local sPos = (errYaw >= 0)
        if _lastSign ~= nil and sPos ~= _lastSign then _flips = _flips + 1 end
        _lastSign = sPos
        _flips = _flips * math.exp(-dt / 0.25)
        if _flips >= 4 and _errEma > OSC_ERR and not isHardLock then
            _auth  = math.max(0.15, _auth * 0.5)
            _flips = 0
        else
            _auth = math.min(1, _auth + dt * 0.3)
        end
        local avgSmooth = (smoothX + smoothY) * 0.5
        if _errEma > RUNAWAY_ERR and _drive > (0.15 + (avgSmooth / 100) * MAX_TAU * 3) and not isHardLock then
            _auth    = math.max(0.08, _auth * 0.5)
            _gx, _gy = _sdx, _sdy
            _nx, _ny = 0, 0
            _drive   = 0
            _trips   = _trips + 1
            if _trips >= 2 then _calOff = true end
        end
        local alphaX = 1
        if smoothX > 0 then
            alphaX = (1 - math.exp(-dt / ((smoothX / 100) * MAX_TAU))) * _auth
        end
        local alphaY = 1
        if smoothY > 0 then
            alphaY = (1 - math.exp(-dt / ((smoothY / 100) * MAX_TAU))) * _auth
        end
        local cy = errYaw * alphaX
        local cp = errPit * alphaY
        if Config.AimbotCurvedFlick and _errDeg > 3.0 and not isHardLock then
            if not _flickActive then
                _flickActive = true
                _flickT = 0
                _flickDur = math.clamp((_errDeg / 90) * 0.22 + 0.08, 0.08, 0.35)
                local intensity = (Config.AimbotCurvedIntensity or 0.35) * (_errDeg * D2R)
                local normY, normP = -errPit / (aErr + 1e-4), errYaw / (aErr + 1e-4)
                local curveSign = ((math.floor(now * 10) % 2 == 0) and 1 or -1)
                _flickCtrl1Y = normY * intensity * curveSign
                _flickCtrl1P = normP * intensity * curveSign
                _flickCtrl2Y = normY * (intensity * 0.7) * curveSign
                _flickCtrl2P = normP * (intensity * 0.7) * curveSign
            end
            _flickT = math.min(_flickDur, _flickT + dt)
            local prog = _flickT / _flickDur
            local sJerk = minJerk(prog)
            local p1Y = errYaw * 0.33 + _flickCtrl1Y
            local p1P = errPit * 0.33 + _flickCtrl1P
            local p2Y = errYaw * 0.66 + _flickCtrl2Y
            local p2P = errPit * 0.66 + _flickCtrl2P
            local targetCurveY = bezier(0, p1Y, p2Y, errYaw, sJerk)
            local targetCurveP = bezier(0, p1P, p2P, errPit, sJerk)
            cy = targetCurveY * alphaX
            cp = targetCurveP * alphaY
            if prog >= 1.0 or _errDeg < 1.0 then
                _flickActive = false
            end
        else
            _flickActive = false
        end
        State.AimbotFlickActive = _flickActive
        if not isHardLock then
            local spPit, spYaw = getSpringOffset()
            cy = cy - (spYaw * alphaX)
            cp = cp - (spPit * alphaY)
        end
        local os = Config.AimbotOvershoot or 0
        if os > 0 and not isHardLock then
            _ramp = math.min(1, _ramp + dt / RAMP_TIME)
            local k = 1 + math.sin(_ramp * math.pi) * os
            cy, cp = cy * k, cp * k
        end
        local ff = (Config.AimbotTrackAssist or 100) / 100
        if ff > 0 and not isHardLock then
            cy = cy + _ffy * dt * ff
            cp = cp + _ffp * dt * ff
        end
        local nz = Config.AimbotNoiseDeg or 0
        if nz > 0 then
            local n = nz * D2R * dt
            cy = cy + (math.random() - 0.5) * 2 * n
            cp = cp + (math.random() - 0.5) * 2 * n
        end
        local cap = Config.AimbotMaxSpeed or 0
        if cap > 0 then
            local m = math.sqrt(cy * cy + cp * cp)
            local lim = cap * D2R * dt
            if m > lim then local k = lim / m; cy, cp = cy * k, cp * k end
        end
        cp = math.clamp(curPit + cp, -PITCH_LIMIT, PITCH_LIMIT) - curPit
        if _gx == 0 or _gy == 0 then return end
        local ux, uy = cy / _gx, cp / _gy
        local um = math.max(math.abs(ux), math.abs(uy))
        if um > UNIT_MAX then local k = UNIT_MAX / um; ux, uy = ux * k, uy * k end
        if _path == "mouse" then
            ux, _fx = quant(ux, _fx)
            uy, _fy = quant(uy, _fy)
        else
            _fx, _fy = 0, 0
        end
        if ux == 0 and uy == 0 then return end
        emit(ux, uy)
        _sx, _sy = ux, uy
    end
    function Aimbot.enable()
        Config.Aimbot = true
        if _bound then return end
        RunService:BindToRenderStep("LuaHook_Aimbot", Enum.RenderPriority.Camera.Value + 1, function(dt)
            pcall(step, dt)
        end)
        _bound = true
    end
    function Aimbot.disable()
        Config.Aimbot = false
        State.AimbotKeyHeld = false
        clearTarget()
        _sx, _sy, _fx, _fy = 0, 0, 0, 0
        _haveCam, _ramp, _notified = false, 0, nil
        _auth = 1.0
        if _bound then
            pcall(function() RunService:UnbindFromRenderStep("LuaHook_Aimbot") end)
            _bound = false
        end
        if _fovC  then _fovC.Visible  = false end
        if _lockC then _lockC.Visible = false end
        if _dbgT  then _dbgT.Visible  = false end
    end
    function Aimbot.init()
        if Config.Aimbot then Aimbot.enable() end
    end
    function Aimbot.unload()
        Aimbot.disable()
        if shared._LH_velConn then
            pcall(function() shared._LH_velConn:Disconnect() end)
            shared._LH_velConn = nil
        end
        if _fovC  then pcall(function() _fovC:Remove()  end); _fovC  = nil end
        if _lockC then pcall(function() _lockC:Remove() end); _lockC = nil end
        if _dbgT  then pcall(function() _dbgT:Remove()  end); _dbgT  = nil end
    end
    function Aimbot.hasMouseMove() return _mouseMove ~= nil end
    function Aimbot._diag() return diagText() end
end)()
local Trigger = {}
do
    local _bound    = false
    local _lastFire = 0
    local _onTgtAt  = 0
    local _lastChar = nil
    local trigParams = RaycastParams.new()
    trigParams.FilterType = Enum.RaycastFilterType.Exclude
    local _filterChar = nil
    local function isHeadHit(part)
        if not part then return false end
        local n = part.Name
        for _, h in ipairs(HEAD_PARTS) do
            if n == h then return true end
        end
        return false
    end
    local function fullyScoped()
        local lf = Rivals.Fighter and Rivals.Fighter.LocalFighter
        local it = lf and lf.EquippedItem
        if not it then return true end
        local cur, pct = nil, nil
        pcall(function() cur = it.ViewModel.CurrentAimValue end)
        pcall(function() pct = it.Info.AimScopePercent end)
        if type(cur) == "number" then
            if type(pct) == "number" then return cur >= pct end
            return cur >= 1
        end
        local aiming
        pcall(function() aiming = it:Get("IsAiming") end)
        if aiming == nil then return true end
        return aiming == true
    end
    local function askToShoot()
        local lf = Rivals.Fighter and Rivals.Fighter.LocalFighter
        if not lf then return end
        task.spawn(function()
            if setthreadidentity then setthreadidentity(2) elseif setidentity then setidentity(2) end
            pcall(function() lf:Input("StartShooting") end)
            if setthreadidentity then setthreadidentity(8) elseif setidentity then setidentity(8) end
        end)
    end
    local function underCrosshair()
        local c = lp.Character
        if c ~= _filterChar then
            trigParams.FilterDescendantsInstances = { c }
            _filterChar = c
        end
        local cf   = Camera.CFrame
        local dist = math.clamp(Config.TriggerMaxDist or 400, 1, 400)
        local res  = Workspace:Raycast(cf.Position, cf.LookVector * dist, trigParams)
        if not res or not res.Instance then return nil end
        local model = res.Instance:FindFirstAncestorOfClass("Model")
        if not model then return nil end
        local pl = Players:GetPlayerFromCharacter(model)
        if not pl or pl == lp then return nil end
        return pl, res.Instance
    end
    local function step()
        if not Config.Trigger then return end
        if Config.Rage then
            _lastChar = nil
            return
        end
        if not isInputActive(Config.TriggerKey) then
            _lastChar = nil
            return
        end
        local pl, hit = underCrosshair()
        if not pl then
            _lastChar = nil
            return
        end
        if not isValidTarget(pl, false) then
            _lastChar = nil
            return
        end
        if Config.TriggerHeadOnly and not isHeadHit(hit) then
            _lastChar = nil
            return
        end
        if Config.TriggerScopeCheck and not fullyScoped() then
            _lastChar = nil
            return
        end
        local now = tick()
        if pl.Character ~= _lastChar then
            _lastChar = pl.Character
            _onTgtAt  = now
        end
        if (now - _onTgtAt) * 1000 < (Config.TriggerDelayMs or 0) then return end
        if (now - _lastFire) * 1000 < (Config.TriggerRefireMs or 0) then return end
        _lastFire = now
        askToShoot()
    end
    function Trigger.enable()
        Config.Trigger = true
        if _bound then return end
        RunService:BindToRenderStep("LuaHook_Trigger", Enum.RenderPriority.Camera.Value + 2, function()
            pcall(step)
        end)
        _bound = true
    end
    function Trigger.disable()
        Config.Trigger = false
        _lastChar = nil
        _lastFire = 0
        _onTgtAt  = 0
        if not _bound then return end
        pcall(function() RunService:UnbindFromRenderStep("LuaHook_Trigger") end)
        _bound = false
    end
    function Trigger.init()
        if Config.Trigger then Trigger.enable() end
    end
    function Trigger.unload()
        Trigger.disable()
    end
end


--// Compatibility fix for the original UI:
--// the source UI called Weather.toggleSkyFlash(), but the Weather implementation
--// reads Config.WeatherStormFlash directly.
function Weather.toggleSkyFlash(on)
    Config.WeatherStormFlash = on
end


--// LinoriaLib UI
local WeatherBox = Tabs.Visuals:AddLeftGroupbox('Weather & Skybox')

WeatherBox:AddToggle('Weather', {
    Text = 'Enable',
    Default = (Config.Weather or false),
    Callback = function(v)
        if v then
            Weather.enableWeather()
        else
            Weather.disableWeather()
        end
    end
})

local wxDep = WeatherBox:AddDependencyBox()

wxDep:AddDropdown('WeatherType', {
    Values = {'Rain','Snow','Petals','Autumn','Mist','Ash','Sandstorm','Embers','Fireflies'},
    Default = (Config.WeatherType or 'Rain'),
    Text = 'Precipitation',
    Callback = function(v)
        Weather.setType(v)
    end
})

wxDep:AddSlider('WeatherIntensity', {
    Text = 'Intensity',
    Default = (Config.WeatherIntensity or 1.0),
    Min = 0.15,
    Max = 2,
    Rounding = 2,
    Suffix = 'x',
    Callback = function(v)
        Weather.setIntensity(v)
    end
})

wxDep:AddSlider('WeatherSoundVolume', {
    Text = 'Volume',
    Default = (Config.WeatherSoundVolume or 0.35),
    Min = 0,
    Max = 1,
    Rounding = 2,
    Callback = function(v)
        Weather.setSoundVolume(v)
    end
})

wxDep:AddToggle('WeatherMood', {
    Text = 'Mood tint',
    Default = (Config.WeatherMood ~= false),
    Callback = function(v)
        Weather.toggleMood(v)
    end
})

wxDep:AddDivider('Atmosphere')

wxDep:AddToggle('WeatherStorm', {
    Text = 'Storm & lightning',
    Default = (Config.WeatherStorm or false),
    Callback = function(v)
        Weather.toggleStorm(v)
    end
})

local stormDep = wxDep:AddDependencyBox()

stormDep:AddToggle('WeatherStormFlash', {
    Text = 'Sky flash',
    Default = (Config.WeatherStormFlash ~= false),
    Callback = function(v)
        Weather.toggleSkyFlash(v)
    end
})

stormDep:SetupDependencies({
    { Toggles.WeatherStorm, true }
})

wxDep:AddToggle('WeatherMeteors', {
    Text = 'Meteors',
    Default = (Config.WeatherMeteors or false),
    Callback = function(v)
        Weather.toggleMeteors(v)
    end
})

local metDep = wxDep:AddDependencyBox()

metDep:AddSlider('WeatherMeteorRate', {
    Text = 'Rate',
    Default = (Config.WeatherMeteorRate or 1.0),
    Min = 0.25,
    Max = 3,
    Rounding = 2,
    Suffix = 'x',
    Compact = true,
    Callback = function(v)
        Weather.setMeteorRate(v)
    end
})

metDep:SetupDependencies({
    { Toggles.WeatherMeteors, true }
})

wxDep:AddToggle('WeatherShootingStars', {
    Text = 'Shooting stars',
    Default = (Config.WeatherShootingStars or false),
    Callback = function(v)
        Weather.toggleShootingStars(v)
    end
})

local starDep = wxDep:AddDependencyBox()

starDep:AddSlider('WeatherStarRate', {
    Text = 'Rate',
    Default = (Config.WeatherStarRate or 1.0),
    Min = 0.25,
    Max = 3,
    Rounding = 2,
    Suffix = 'x',
    Compact = true,
    Callback = function(v)
        Weather.setStarRate(v)
    end
})

starDep:SetupDependencies({
    { Toggles.WeatherShootingStars, true }
})

wxDep:AddDropdown('SkyboxPreset', {
    Values = Weather.SkyboxOrder or {'Off','Space','Sunset','Clouds','Storm','Winter','Vaporwave'},
    Default = (Config.SkyboxPreset or 'Off'),
    Text = 'Skybox',
    Callback = function(v)
        Weather.setSkybox(v)
    end
})

wxDep:AddToggle('SkyboxHideCelestial', {
    Text = 'Hide celestial',
    Default = (Config.SkyboxHideCelestial or false),
    Callback = function(v)
        Weather.toggleCelestial(v)
    end
})

wxDep:AddToggle('WeatherGodRays', {
    Text = 'God rays',
    Default = (Config.WeatherGodRays or false),
    Callback = function(v)
        Weather.toggleGodRays(v)
    end
})

wxDep:AddToggle('WeatherRainbow', {
    Text = 'Rainbow',
    Default = (Config.WeatherRainbow or false),
    Callback = function(v)
        Weather.toggleRainbow(v)
    end
})

wxDep:AddToggle('WeatherPuddles', {
    Text = 'Puddles',
    Default = (Config.WeatherPuddles or false),
    Callback = function(v)
        Weather.togglePuddles(v)
    end
})

wxDep:AddToggle('WeatherClockDial', {
    Text = 'Clock dial',
    Default = (Config.WeatherClockDial or false),
    Callback = function(v)
        Weather.toggleClock(v)
    end
})

wxDep:SetupDependencies({
    { Toggles.Weather, true }
})
