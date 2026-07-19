--[[
    biscoitodasorte.koplugin — Biscoito da Sorte / Fortune Cookie
    ============================================================
    Exibe uma frase inspiradora ao estilo biscoito da sorte.
    Displays an inspirational phrase in fortune cookie style.

    Estratégia de APIs (gratuitas, sem autenticação):
      1. ZenQuotes  → https://zenquotes.io/api/random   (frases com autor)
      2. Quotable   → https://api.quotable.io/random     (frases com autor)
      3. Advice Slip → http://api.adviceslip.com/advice  (conselhos simples)
      4. Frases locais (carregadas do arquivo frases.txt na pasta do plugin)

    A ordem das APIs ativas é aleatória a cada tentativa. Se uma falhar,
    passa automaticamente para a próxima até encontrar uma resposta válida.

    Frases locais são lidas do arquivo "frases.txt" dentro da pasta do plugin.
    Esse arquivo é criado automaticamente na primeira execução (ou ao restaurar
    o padrão) com frases padrão. O formato esperado por linha:
      "frase" ou "frase|autor" ou "frase\tautor"

    Instalação:
      Copie a pasta biscoitodasorte.koplugin/ para:
        /sdcard/koreader/plugins/   (Android)
        ~/.config/koreader/plugins/ (Linux/PC)
      Reinicie o KOReader. O item aparece em Menu → Ferramentas.
--]]

-- ── dependências ──────────────────────────────────────────────────────────────
local Blitbuffer       = require("ffi/blitbuffer")
local Button           = require("ui/widget/button")
local CenterContainer  = require("ui/widget/container/centercontainer")
local Font             = require("ui/font")
local FrameContainer   = require("ui/widget/container/framecontainer")
local HorizontalGroup  = require("ui/widget/horizontalgroup")
local HorizontalSpan   = require("ui/widget/horizontalspan")
local InfoMessage      = require("ui/widget/infomessage")
local InputContainer   = require("ui/widget/container/inputcontainer")
local InputDialog      = require("ui/widget/inputdialog")
local JSON             = require("json")
local NetworkMgr       = require("ui/network/manager")
local Screen           = require("device").screen
local Size             = require("ui/size")
local TextBoxWidget    = require("ui/widget/textboxwidget")
local TextWidget       = require("ui/widget/textwidget")
local UIManager        = require("ui/uimanager")
local VerticalGroup    = require("ui/widget/verticalgroup")
local VerticalSpan     = require("ui/widget/verticalspan")
local http             = require("socket.http")
local ltn12            = require("ltn12")
local logger           = require("logger")
local _                = require("gettext")
local util             = require("util")

-- Suporte HTTPS via LuaSec
local https_ok, ssl_https = pcall(require, "ssl.https")

-- ═════════════════════════════════════════════════════════════════════════════
-- Sistema de tradução
-- ═════════════════════════════════════════════════════════════════════════════
local translations = {
    pt = {
        fortune_cookie = "Biscoito da Sorte",
        open_cookie = "Abrir biscoito",
        settings = "Configurações",
        config_apis = "APIs",
        local_phrases = "Frases locais",
        restore_default = "Restaurar padrão",
        view_phrases = "Ver frases carregadas",
        add_phrase = "Adicionar frase",
        new = "Novo",
        close = "Fechar",
        opening_cookie = "Abrindo seu biscoito…",
        offline_mode = "Modo offline - frase local",
        settings_title = "Configurações",
        save = "Salvar",
        new_phrase_title = "Nova frase",
        phrase_hint = "Digite a frase (sem autor)",
        cancel = "Cancelar",
        add = "Adicionar",
        phrase_added = "Frase adicionada com sucesso!",
        phrase_empty = "A frase não pode estar vazia.",
        error_saving = "Erro ao salvar a frase: ",
        error_opening = "Erro ao abrir o arquivo de frases: ",
        error_restoring = "Erro ao restaurar o arquivo de frases padrão.",
        no_phrases = "Nenhuma frase local carregada.",
        empty_file = "Arquivo de frases vazio ou sem frases válidas.",
        phrases_loaded = "Carregadas %d frases do arquivo interno.",
        language = "Idioma",
        portuguese = "Português",
        english = "English",
        one_per_day = "Modo 1 por dia",
        one_per_day_desc = "Permite abrir apenas 1 biscoito por dia",
        already_opened_today = "Você já abriu seu biscoito hoje! Volte amanhã.",
        one_per_day_enabled = "Modo 1 por dia ativado.",
        one_per_day_disabled = "Modo 1 por dia desativado.",
    },
    en = {
        fortune_cookie = "Fortune Cookie",
        open_cookie = "Open cookie",
        settings = "Settings",
        config_apis = "APIs",
        local_phrases = "Local phrases",
        restore_default = "Restore default",
        view_phrases = "View loaded phrases",
        add_phrase = "Add phrase",
        new = "New",
        close = "Close",
        opening_cookie = "Opening your cookie…",
        offline_mode = "Offline mode - local phrase",
        settings_title = "Settings",
        save = "Save",
        new_phrase_title = "New phrase",
        phrase_hint = "Type the phrase (without author)",
        cancel = "Cancel",
        add = "Add",
        phrase_added = "Phrase added successfully!",
        phrase_empty = "Phrase cannot be empty.",
        error_saving = "Error saving phrase: ",
        error_opening = "Error opening phrases file: ",
        error_restoring = "Error restoring default phrases file.",
        no_phrases = "No local phrases loaded.",
        empty_file = "Phrases file empty or no valid phrases.",
        phrases_loaded = "Loaded %d phrases from internal file.",
        language = "Language",
        portuguese = "Português",
        english = "English",
        one_per_day = "One per day mode",
        one_per_day_desc = "Allow only 1 cookie per day",
        already_opened_today = "You've already opened your cookie today! Come back tomorrow.",
        one_per_day_enabled = "One per day mode enabled.",
        one_per_day_disabled = "One per day mode disabled.",
    }
}

-- ═════════════════════════════════════════════════════════════════════════════
-- Símbolos aleatórios para o rodapé
-- ═════════════════════════════════════════════════════════════════════════════
local FOOTER_SYMBOLS = {
    "(｡•ᴗ•｡)♡",
    "(◕‿◕)",
    "~ ☆ ~",
    "♪ (ˆ▽ˆ) ♪",
    "(˘▽˘)っ♨",
    "✧ (◍•ᴗ•◍) ✧",
    "(づ｡◕‿‿◕｡)づ",
    "~ ★ ~",
    "(｡♥‿♥｡)",
    "✿ (◠‿◠) ✿",
}

-- ═════════════════════════════════════════════════════════════════════════════
-- Frases locais padrão (fallback offline) - PT e EN
-- ═════════════════════════════════════════════════════════════════════════════
local DEFAULT_FORTUNES_PT = {
    { q = "Um pequeno gesto multiplica as suas alegrias." },
    { q = "A esperança iluminará os seus passos de hoje em diante." },
    { q = "A verdadeira felicidade mudará a sua visão do mundo." },
    { q = "A luz dentro de você mudará a sua visão do mundo." },
    { q = "A intuição vai lhe proporcionar momentos inesquecíveis." },
    { q = "Uma atitude positiva supera qualquer obstáculo no caminho." },
    { q = "A coragem multiplica as suas alegrias." },
    { q = "A jornada recompensa os que sabem esperar." },
    { q = "O entusiasmo supera qualquer obstáculo no caminho." },
    { q = "O conhecimento traz a calma após a tempestade." },
    { q = "Uma nova oportunidade está mais perto do que você imagina." },
    { q = "O seu coração lhe dará a resposta que procura." },
    { q = "Um sorriso sincero sempre encontra uma maneira de florescer." },
    { q = "A sorte está prestes a bater na sua porta." },
    { q = "A verdadeira felicidade multiplica as suas alegrias." },
    { q = "Uma nova oportunidade revela a sua verdadeira essência." },
    { q = "A força de vontade revela a sua verdadeira essência." },
    { q = "Uma atitude positiva traz a calma após a tempestade." },
    { q = "O verdadeiro amigo nasce das sementes que você planta hoje." },
    { q = "Um novo amanhecer nunca se esgota quando é verdadeiro." },
    { q = "A verdadeira felicidade cria laços que o tempo não apaga." },
    { q = "O poder do agora multiplica as suas alegrias." },
    { q = "A verdadeira amizade é o reflexo do seu coração puro." },
    { q = "O respeito está mais perto do que você imagina." },
    { q = "Acredite nos seus sonhos, eles estão mais perto do que você pensa." },
    { q = "O seu destino floresce no momento certo." },
    { q = "Uma atitude positiva vai transformar a sua realidade em breve." },
    { q = "O tempo é o reflexo da sua alma pura." },
    { q = "O seu coração cria laços que o tempo não apaga." },
    { q = "A luz dentro de você lhe dará a resposta que procura." },
    { q = "A vida cura até as feridas mais profundas." },
    { q = "A bondade é o seu maior tesouro escondido." },
    { q = "Um sorriso sincero está prestes a bater na sua porta." },
    { q = "A fé conspira a seu favor neste momento." },
    { q = "O entusiasmo é um presente que você deve abraçar." },
    { q = "A paciência é a fundação de um futuro brilhante." },
    { q = "A força de vontade conspira a seu favor neste momento." },
    { q = "A fé recompensa os que sabem esperar." },
    { q = "Siga o seu coração, mas leve o seu cérebro junto." },
    { q = "Uma nova oportunidade multiplica as suas alegrias." },
}

local DEFAULT_FORTUNES_EN = {
    { q = "A small gesture multiplies your joys." },
    { q = "Hope will light your steps from today onwards." },
    { q = "True happiness will change your view of the world." },
    { q = "The light within you will change your view of the world." },
    { q = "Intuition will give you unforgettable moments." },
    { q = "A positive attitude overcomes any obstacle on the path." },
    { q = "Courage multiplies your joys." },
    { q = "The journey rewards those who know how to wait." },
    { q = "Enthusiasm overcomes any obstacle on the path." },
    { q = "Knowledge brings calm after the storm." },
    { q = "A new opportunity is closer than you think." },
    { q = "Your heart will give you the answer you seek." },
    { q = "A sincere smile always finds a way to bloom." },
    { q = "Luck is about to knock on your door." },
    { q = "True happiness multiplies your joys." },
    { q = "A new opportunity reveals your true essence." },
    { q = "Willpower reveals your true essence." },
    { q = "A positive attitude brings calm after the storm." },
    { q = "A true friend is born from the seeds you plant today." },
    { q = "A new dawn never runs out when it is true." },
    { q = "True happiness creates bonds that time cannot erase." },
    { q = "The power of now multiplies your joys." },
    { q = "True friendship is the reflection of your pure heart." },
    { q = "Respect is closer than you think." },
    { q = "Believe in your dreams, they are closer than you think." },
    { q = "Your destiny blooms at the right moment." },
    { q = "A positive attitude will transform your reality soon." },
    { q = "Time is the reflection of your pure soul." },
    { q = "Your heart creates bonds that time cannot erase." },
    { q = "The light within you will give you the answer you seek." },
    { q = "Life heals even the deepest wounds." },
    { q = "Kindness is your greatest hidden treasure." },
    { q = "A sincere smile is about to knock on your door." },
    { q = "Faith conspires in your favor at this moment." },
    { q = "Enthusiasm is a gift you must embrace." },
    { q = "Patience is the foundation of a bright future." },
    { q = "Willpower conspires in your favor at this moment." },
    { q = "Faith rewards those who know how to wait." },
    { q = "Follow your heart, but take your brain with you." },
    { q = "A new opportunity multiplies your joys." },
}

-- Alias para compatibilidade
local DEFAULT_FORTUNES = DEFAULT_FORTUNES_PT

local local_fortunes = {}

-- ═════════════════════════════════════════════════════════════════════════════
-- APIs disponíveis
-- ═════════════════════════════════════════════════════════════════════════════
local API_LIST = {
    {
        key  = "zenquotes",
        name = "ZenQuotes",
        desc = "Frases com autor (HTTPS)",
        fetch = function(self)
            local body = self:makeRequest("https://zenquotes.io/api/random")
            if body then
                local ok, data = pcall(JSON.decode, body)
                if ok and type(data) == "table" and data[1] and data[1].q ~= "" then
                    local author = (data[1].a ~= "" and data[1].a ~= "Unknown") and data[1].a or nil
                    return { q = data[1].q, a = author }
                end
            end
            return nil
        end,
    },
    {
        key  = "quotable",
        name = "Quotable",
        desc = "Frases e autores variados (HTTPS)",
        fetch = function(self)
            local body = self:makeRequest("https://api.quotable.io/random")
            if body then
                local ok, data = pcall(JSON.decode, body)
                if ok and data and data.content and data.content ~= "" then
                    local author = (data.author and data.author ~= "") and data.author or nil
                    return { q = data.content, a = author }
                end
            end
            return nil
        end,
    },
    {
        key  = "adviceslip",
        name = "Advice Slip",
        desc = "Conselhos simples (HTTP)",
        fetch = function(self)
            local body = self:makeRequest("http://api.adviceslip.com/advice")
            if body then
                local ok, data = pcall(JSON.decode, body)
                if ok and data and data.slip and data.slip.advice then
                    return { q = data.slip.advice, a = nil }
                end
            end
            return nil
        end,
    },
}

-- ═════════════════════════════════════════════════════════════════════════════
-- Plugin principal
-- ═════════════════════════════════════════════════════════════════════════════
local BiscoitoDaSorte = InputContainer:extend{
    name        = "biscoitodasorte",
    fullname    = "Biscoito da Sorte",
    is_doc_only = false,
}

function BiscoitoDaSorte:init()
    math.randomseed(os.time() + math.random(10000))
    self.ui.menu:registerToMainMenu(self)

    self.plugin_dir = self:getPluginDirectory()
    self.frases_file = self.plugin_dir .. "/frases.txt"

    local default_enabled = {}
    for _, api in ipairs(API_LIST) do
        default_enabled[api.key] = true
    end
    self.enabled_apis = G_reader_settings:readSetting("biscoitodasorte_apis") or default_enabled
    self.language = G_reader_settings:readSetting("biscoitodasorte_language") or "pt"

    if G_reader_settings:readSetting("biscoitodasorte_one_per_day") == nil then
        self.one_per_day = true
        G_reader_settings:saveSetting("biscoitodasorte_one_per_day", true)
    else
        self.one_per_day = G_reader_settings:readSetting("biscoitodasorte_one_per_day")
    end

    self.last_cookie_date = G_reader_settings:readSetting("biscoitodasorte_last_date") or ""

    self:ensureFortuneFile()
    self:loadFortunesFromFile()
end

function BiscoitoDaSorte:getTranslation(key)
    local lang = self.language or "pt"
    local t = translations[lang]
    if t and t[key] then
        return t[key]
    end
    if translations.pt and translations.pt[key] then
        return translations.pt[key]
    end
    return key
end

function BiscoitoDaSorte:getRandomSymbol()
    return FOOTER_SYMBOLS[math.random(1, #FOOTER_SYMBOLS)]
end

function BiscoitoDaSorte:refreshMenu()
    self.ui.menu:registerToMainMenu(self)
end

function BiscoitoDaSorte:getPluginDirectory()
    if self.path then return self.path end
    local source = debug.getinfo(1, "S").source
    if source and source:match("^@") then
        local dir = source:match("^@(.*/)main%.lua$") or source:match("^@(.*/)[^/]+$")
        if dir then return dir end
    end
    local ok, DataStorage = pcall(require, "datastorage")
    if ok and DataStorage then
        return DataStorage:getDataDir() .. "/plugins/biscoitodasorte.koplugin"
    end
    return "./plugins/biscoitodasorte.koplugin"
end

function BiscoitoDaSorte:ensureFortuneFile()
    if not util.fileExists(self.frases_file) then
        self:writeDefaultFortunesToFile()
    end
end

function BiscoitoDaSorte:getDefaultFortunesForLanguage()
    if self.language == "en" then
        return DEFAULT_FORTUNES_EN
    end
    return DEFAULT_FORTUNES_PT
end

function BiscoitoDaSorte:writeDefaultFortunesToFile()
    local file, err = io.open(self.frases_file, "w")
    if not file then
        logger.warn("BiscoitoDaSorte: não foi possível criar", self.frases_file, err)
        return false
    end
    local fortunes = self:getDefaultFortunesForLanguage()
    for _, entry in ipairs(fortunes) do
        local line = entry.q
        if entry.a then line = line .. "|" .. entry.a end
        file:write(line .. "\n")
    end
    file:close()
    return true
end

function BiscoitoDaSorte:loadFortunesFromFile(show_msg)
    if show_msg == nil then show_msg = false end
    local file, err = io.open(self.frases_file, "r")
    if not file then
        logger.warn("BiscoitoDaSorte: não foi possível abrir", self.frases_file, err)
        if show_msg then
            UIManager:show(InfoMessage:new{
                text = self:getTranslation("error_opening") .. tostring(err),
            })
            UIManager:setDirty(nil, "full")
        end
        return false
    end
    local new_list = {}
    local line_count = 0
    for line in file:lines() do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then
            local quote, author
            local sep_pos = line:find("[|\t]")
            if sep_pos then
                quote = line:sub(1, sep_pos - 1):gsub("^%s+", ""):gsub("%s+$", "")
                author = line:sub(sep_pos + 1):gsub("^%s+", ""):gsub("%s+$", "")
                if author == "" then author = nil end
            else
                quote = line
                author = nil
            end
            if quote and quote ~= "" then
                table.insert(new_list, { q = quote, a = author })
                line_count = line_count + 1
            end
        end
    end
    file:close()
    if line_count == 0 then
        if show_msg then
            UIManager:show(InfoMessage:new{
                text = self:getTranslation("empty_file"),
            })
            UIManager:setDirty(nil, "full")
        end
        local_fortunes = self:getDefaultFortunesForLanguage()
        return false
    end
    local_fortunes = new_list
    if show_msg then
        UIManager:show(InfoMessage:new{
            text = string.format(self:getTranslation("phrases_loaded"), line_count),
        })
        UIManager:setDirty(nil, "full")
    end
    return true
end

function BiscoitoDaSorte:restoreDefaultFortunes()
    if self:writeDefaultFortunesToFile() then
        self:loadFortunesFromFile(true)
    else
        UIManager:show(InfoMessage:new{
            text = self:getTranslation("error_restoring"),
        })
        UIManager:setDirty(nil, "full")
    end
end

function BiscoitoDaSorte:showLoadedFortunes()
    if #local_fortunes == 0 then
        UIManager:show(InfoMessage:new{
            text = self:getTranslation("no_phrases"),
        })
        UIManager:setDirty(nil, "full")
        return
    end
    local lines = {}
    local max = math.min(20, #local_fortunes)
    for i = 1, max do
        local entry = local_fortunes[i]
        local line = entry.q
        if entry.a then line = line .. " — " .. entry.a end
        table.insert(lines, tostring(i) .. ". " .. line)
    end
    if #local_fortunes > 20 then
        table.insert(lines, "... e mais " .. (#local_fortunes - 20) .. " frases.")
    end
    local msg = table.concat(lines, "\n")
    UIManager:show(InfoMessage:new{
        text = msg,
        timeout = 8,
    })
    UIManager:setDirty(nil, "full")
end

function BiscoitoDaSorte:addFortune()
    local input_dialog
    input_dialog = InputDialog:new{
        title = self:getTranslation("new_phrase_title"),
        input_hint = self:getTranslation("phrase_hint"),
        buttons = {
            {
                {
                    text = self:getTranslation("cancel"),
                    callback = function()
                        UIManager:close(input_dialog)
                        UIManager:setDirty(nil, "full")
                    end,
                },
                {
                    text = self:getTranslation("add"),
                    is_enter_default = true,
                    callback = function()
                        local phrase = input_dialog:getInputText()
                        if phrase and phrase ~= "" then
                            local file, err = io.open(self.frases_file, "a")
                            if file then
                                file:write(phrase .. "\n")
                                file:close()
                                self:loadFortunesFromFile()
                                UIManager:close(input_dialog)
                                UIManager:show(InfoMessage:new{
                                    text = self:getTranslation("phrase_added"),
                                })
                                UIManager:setDirty(nil, "full")
                            else
                                UIManager:close(input_dialog)
                                UIManager:show(InfoMessage:new{
                                    text = self:getTranslation("error_saving") .. tostring(err),
                                })
                                UIManager:setDirty(nil, "full")
                            end
                        else
                            UIManager:show(InfoMessage:new{
                                text = self:getTranslation("phrase_empty"),
                            })
                            UIManager:setDirty(nil, "full")
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    UIManager:setDirty(nil, "full")
    input_dialog:onShowKeyboard()
end

function BiscoitoDaSorte:canOpenCookieToday()
    if not self.one_per_day then return true end
    local today = os.date("%Y-%m-%d")
    if self.last_cookie_date == today then return false end
    return true
end

function BiscoitoDaSorte:markCookieOpened()
    local today = os.date("%Y-%m-%d")
    self.last_cookie_date = today
    G_reader_settings:saveSetting("biscoitodasorte_last_date", today)
end

function BiscoitoDaSorte:toggleOnePerDay()
    self.one_per_day = not self.one_per_day
    G_reader_settings:saveSetting("biscoitodasorte_one_per_day", self.one_per_day)
    UIManager:show(InfoMessage:new{
        text = self.one_per_day and self:getTranslation("one_per_day_enabled") or self:getTranslation("one_per_day_disabled"),
    })
    UIManager:setDirty(nil, "full")
end

-- ── rede ──────────────────────────────────────────────────────────────────────

function BiscoitoDaSorte:makeRequest(url)
    local chunks  = {}
    local ok_flag, code
    local function doRequest()
        local opts = {
            url     = url,
            sink    = ltn12.sink.table(chunks),
            headers = { ["User-Agent"] = "KOReader-BiscoitoDaSorte/1.0" },
        }
        if url:match("^https://") and https_ok then
            opts.verify = "none"
            ok_flag, code = ssl_https.request(opts)
        else
            ok_flag, code = http.request(opts)
        end
    end
    local pcall_ok = pcall(doRequest)
    if pcall_ok and ok_flag and tonumber(code) == 200 then
        return table.concat(chunks)
    end
    logger.warn("BiscoitoDaSorte: falha em", url, "→", tostring(code))
    return nil
end

function BiscoitoDaSorte:fetchFortuneFromAPI()
    local enabled = {}
    for _, api in ipairs(API_LIST) do
        if self.enabled_apis[api.key] then table.insert(enabled, api) end
    end
    if #enabled == 0 then return nil end
    for i = #enabled, 2, -1 do
        local j = math.random(i)
        enabled[i], enabled[j] = enabled[j], enabled[i]
    end
    for _, api in ipairs(enabled) do
        local result = api.fetch(self)
        if result then return result end
    end
    return nil
end

function BiscoitoDaSorte:getLocalFortune()
    if #local_fortunes == 0 then
        local fallback = self:getDefaultFortunesForLanguage()
        if #fallback > 0 then
            return fallback[math.random(1, #fallback)]
        end
        return { q = "A vida é bela. / Life is beautiful.", a = nil }
    end
    math.randomseed(os.time() + math.random(10000) + #local_fortunes)
    return local_fortunes[math.random(1, #local_fortunes)]
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Widget de diálogo da frase
-- ═════════════════════════════════════════════════════════════════════════════
local FortuneDialog = InputContainer:extend{
    quote   = "",
    author  = nil,
    offline = false,
    on_new  = nil,
    plugin  = nil,
    symbol  = nil,
}

function FortuneDialog:init()
    local sw  = Screen:getWidth()
    local w   = math.floor(sw * 0.84)
    local pad = Size.padding.large
    local iw  = w - pad * 2

    local quote = self.quote or ""
    if #quote > 420 then quote = quote:sub(1, 417) .. "…" end

    local body_text = quote
    if self.author then body_text = body_text .. "\n\n— " .. self.author end
    if self.offline then
        body_text = body_text .. "\n\n" .. (self.plugin and self.plugin:getTranslation("offline_mode") or "Modo offline - frase local")
    end

    local title_text = "~ ★ ~\n" .. (self.plugin and self.plugin:getTranslation("fortune_cookie") or "Biscoito da Sorte")

    local title_w = TextWidget:new{
        text      = title_text,
        face      = Font:getFace("tfont"),
        bold      = true,
        max_width = iw,
        alignment = "center",
    }

    local divider_w = TextWidget:new{
        text      = "─ ◇ ─ ◇ ─",
        face      = Font:getFace("x_smallinfofont"),
        fgcolor   = Blitbuffer.gray(0.5),
        max_width = iw,
        alignment = "center",
    }

    local quote_w = TextBoxWidget:new{
        text      = body_text,
        face      = Font:getFace("cfont"),
        width     = iw,
        alignment = "center",
    }

    local smile_w = TextWidget:new{
        text      = self.symbol or "(｡•ᴗ•｡)♡",
        face      = Font:getFace("cfont"),
        max_width = iw,
        alignment = "center",
    }

    local btn_new = Button:new{
        text     = self.plugin and self.plugin:getTranslation("new") or "Novo",
        width    = math.floor(iw * 0.47),
        radius   = Size.radius.button,
        callback = function()
            UIManager:close(self)
            UIManager:setDirty(nil, "full")
            if self.on_new then self.on_new() end
        end,
    }

    local btn_close = Button:new{
        text     = self.plugin and self.plugin:getTranslation("close") or "Fechar",
        width    = math.floor(iw * 0.47),
        radius   = Size.radius.button,
        callback = function()
            UIManager:close(self)
            UIManager:setDirty(nil, "full")
        end,
    }

    local btns_row = HorizontalGroup:new{
        align = "center",
        btn_new,
        HorizontalSpan:new{ width = math.floor(iw * 0.06) },
        btn_close,
    }

    local content = VerticalGroup:new{
        align = "center",
        title_w,
        VerticalSpan:new{ width = Size.span.vertical_default },
        divider_w,
        VerticalSpan:new{ width = Size.span.vertical_large },
        quote_w,
        VerticalSpan:new{ width = Size.span.vertical_default },
        smile_w,
        VerticalSpan:new{ width = Size.span.vertical_large },
        btns_row,
    }

    local dialog_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        radius     = Size.radius.window,
        padding    = pad,
        content,
    }

    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        dialog_frame,
    }
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Diálogo de Configurações (unificado e remodelado)
-- ═════════════════════════════════════════════════════════════════════════════
local SettingsDialog = InputContainer:extend{
    plugin  = nil,
    enabled = nil,
}

function SettingsDialog:init()
    local sw   = Screen:getWidth()
    local w    = math.floor(sw * 0.84)
    local pad  = Size.padding.large
    local iw   = w - pad * 2

    local title = TextWidget:new{
        text      = self.plugin:getTranslation("settings_title"),
        face      = Font:getFace("tfont"),
        bold      = true,
        max_width = iw,
        alignment = "center",
    }

    local rows = VerticalGroup:new{ align = "left" }

    -- ═══════════════ SEÇÃO 1: COMPORTAMENTO ═══════════════
    local sec1_label = TextWidget:new{
        text      = "— " .. self.plugin:getTranslation("one_per_day") .. " —",
        face      = Font:getFace("smalltfont"),
        bold      = true,
        max_width = iw,
        alignment = "left",
    }
    table.insert(rows, sec1_label)
    table.insert(rows, VerticalSpan:new{ width = Size.span.vertical_small })

    local one_mark = self.plugin.one_per_day and "☑" or "☐"
    local one_label = "  " .. one_mark .. "  " .. self.plugin:getTranslation("one_per_day_desc")

    local btn_one = Button:new{
        text     = one_label,
        width    = iw,
        radius   = Size.radius.button,
        callback = function()
            self.plugin:toggleOnePerDay()
            UIManager:close(self)
            UIManager:show(SettingsDialog:new{
                plugin  = self.plugin,
                enabled = self.enabled,
            })
            UIManager:setDirty(nil, "full")
        end,
    }
    table.insert(rows, btn_one)
    table.insert(rows, VerticalSpan:new{ width = Size.span.vertical_default })

    -- ═══════════════ SEÇÃO 2: IDIOMA ═══════════════
    local sec2_label = TextWidget:new{
        text      = "— " .. self.plugin:getTranslation("language") .. " —",
        face      = Font:getFace("smalltfont"),
        bold      = true,
        max_width = iw,
        alignment = "left",
    }
    table.insert(rows, sec2_label)
    table.insert(rows, VerticalSpan:new{ width = Size.span.vertical_small })

    local current_lang = self.plugin.language
    local pt_mark = (current_lang == "pt") and "☑" or "☐"
    local en_mark = (current_lang == "en") and "☑" or "☐"

    local lang_btns = HorizontalGroup:new{
        align = "center",
        Button:new{
            text   = pt_mark .. " " .. self.plugin:getTranslation("portuguese"),
            width  = math.floor(iw * 0.47),
            radius = Size.radius.button,
            callback = function()
                self.plugin.language = "pt"
                G_reader_settings:saveSetting("biscoitodasorte_language", "pt")
                UIManager:close(self)
                self.plugin:refreshMenu()
                UIManager:show(SettingsDialog:new{
                    plugin  = self.plugin,
                    enabled = self.enabled,
                })
                UIManager:setDirty(nil, "full")
            end,
        },
        HorizontalSpan:new{ width = math.floor(iw * 0.06) },
        Button:new{
            text   = en_mark .. " " .. self.plugin:getTranslation("english"),
            width  = math.floor(iw * 0.47),
            radius = Size.radius.button,
            callback = function()
                self.plugin.language = "en"
                G_reader_settings:saveSetting("biscoitodasorte_language", "en")
                UIManager:close(self)
                self.plugin:refreshMenu()
                UIManager:show(SettingsDialog:new{
                    plugin  = self.plugin,
                    enabled = self.enabled,
                })
                UIManager:setDirty(nil, "full")
            end,
        },
    }
    table.insert(rows, lang_btns)
    table.insert(rows, VerticalSpan:new{ width = Size.span.vertical_default })

    -- ═══════════════ SEÇÃO 3: APIs ═══════════════
    local sec3_label = TextWidget:new{
        text      = "— " .. self.plugin:getTranslation("config_apis") .. " —",
        face      = Font:getFace("smalltfont"),
        bold      = true,
        max_width = iw,
        alignment = "left",
    }
    table.insert(rows, sec3_label)
    table.insert(rows, VerticalSpan:new{ width = Size.span.vertical_small })

    for _, api in ipairs(API_LIST) do
        local key = api.key
        local enabled = self.enabled[key]
        local mark = enabled and "☑" or "☐"
        local label = "  " .. mark .. "  " .. api.name .. " — " .. api.desc

        local btn = Button:new{
            text     = label,
            width    = iw,
            radius   = Size.radius.button,
            callback = function()
                self.enabled[key] = not self.enabled[key]
                UIManager:close(self)
                UIManager:show(SettingsDialog:new{
                    plugin  = self.plugin,
                    enabled = self.enabled,
                })
                UIManager:setDirty(nil, "full")
            end,
        }
        table.insert(rows, btn)
        table.insert(rows, VerticalSpan:new{ width = Size.span.vertical_small })
    end
    table.insert(rows, VerticalSpan:new{ width = Size.span.vertical_default })

    -- ═══════════════ SEÇÃO 4: FRASES LOCAIS ═══════════════
    local sec4_label = TextWidget:new{
        text      = "— " .. self.plugin:getTranslation("local_phrases") .. " —",
        face      = Font:getFace("smalltfont"),
        bold      = true,
        max_width = iw,
        alignment = "left",
    }
    table.insert(rows, sec4_label)
    table.insert(rows, VerticalSpan:new{ width = Size.span.vertical_small })

    local btn_add = Button:new{
        text     = "  +  " .. self.plugin:getTranslation("add_phrase"),
        width    = iw,
        radius   = Size.radius.button,
        callback = function()
            UIManager:close(self)
            UIManager:setDirty(nil, "full")
            self.plugin:addFortune()
        end,
    }
    table.insert(rows, btn_add)
    table.insert(rows, VerticalSpan:new{ width = Size.span.vertical_small })

    local btn_view = Button:new{
        text     = "  " .. self.plugin:getTranslation("view_phrases"),
        width    = iw,
        radius   = Size.radius.button,
        callback = function()
            UIManager:close(self)
            UIManager:setDirty(nil, "full")
            self.plugin:showLoadedFortunes()
        end,
    }
    table.insert(rows, btn_view)
    table.insert(rows, VerticalSpan:new{ width = Size.span.vertical_small })

    local btn_restore = Button:new{
        text     = "  " .. self.plugin:getTranslation("restore_default"),
        width    = iw,
        radius   = Size.radius.button,
        callback = function()
            UIManager:close(self)
            UIManager:setDirty(nil, "full")
            self.plugin:restoreDefaultFortunes()
        end,
    }
    table.insert(rows, btn_restore)
    table.insert(rows, VerticalSpan:new{ width = Size.span.vertical_large })

    -- ═══════════════ BOTÃO FECHAR ═══════════════
    local btn_close = Button:new{
        text     = self.plugin:getTranslation("close"),
        width    = iw,
        radius   = Size.radius.button,
        callback = function()
            self.plugin.enabled_apis = self.enabled
            G_reader_settings:saveSetting("biscoitodasorte_apis", self.enabled)
            UIManager:close(self)
            UIManager:setDirty(nil, "full")
        end,
    }
    table.insert(rows, btn_close)

    local content = VerticalGroup:new{
        align = "center",
        title,
        VerticalSpan:new{ width = Size.span.vertical_large },
        rows,
    }

    local dialog_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        radius     = Size.radius.window,
        padding    = pad,
        content,
    }

    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        dialog_frame,
    }
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Orquestração
-- ═════════════════════════════════════════════════════════════════════════════
function BiscoitoDaSorte:addToMainMenu(menu_items)
    menu_items.biscoito_da_sorte = {
        text         = self:getTranslation("fortune_cookie"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text     = self:getTranslation("open_cookie"),
                callback = function()
                    self:fetchAndShowFortune()
                end,
            },
            {
                text     = self:getTranslation("settings"),
                callback = function()
                    self:showSettings()
                end,
            },
        },
    }
end

function BiscoitoDaSorte:showSettings()
    local enabled_copy = {}
    for k, v in pairs(self.enabled_apis) do
        enabled_copy[k] = v
    end
    UIManager:show(SettingsDialog:new{
        plugin  = self,
        enabled = enabled_copy,
    })
    UIManager:setDirty(nil, "full")
end

function BiscoitoDaSorte:fetchAndShowFortune()
    if not self:canOpenCookieToday() then
        UIManager:show(InfoMessage:new{
            text = self:getTranslation("already_opened_today"),
            timeout = 4,
        })
        UIManager:setDirty(nil, "full")
        return
    end

    local loading = InfoMessage:new{
        text = "♨ " .. self:getTranslation("opening_cookie"),
    }
    UIManager:show(loading)
    UIManager:setDirty(nil, "full")

    UIManager:scheduleIn(0.6, function()
        local fortune
        local offline = false

        if NetworkMgr:isConnected() then
            fortune = self:fetchFortuneFromAPI()
            if not fortune then offline = true end
        else
            offline = true
        end

        fortune = fortune or self:getLocalFortune()
        self:markCookieOpened()

        UIManager:close(loading)

        local dlg = FortuneDialog:new{
            quote   = fortune.q,
            author  = fortune.a,
            offline = offline,
            plugin  = self,
            symbol  = self:getRandomSymbol(),
            on_new  = function()
                self:fetchAndShowFortune()
            end,
        }
        UIManager:show(dlg)
        UIManager:setDirty(nil, "full")
    end)
end

return BiscoitoDaSorte
