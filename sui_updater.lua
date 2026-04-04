-- sui_updater.lua — Simple UI OTA Updater
-- Manual check only: verifica no GitHub Releases se há uma versão mais recente,
-- informa o utilizador e pergunta se quer descarregar e instalar.
--
-- Uso (em sui_menu.lua):
--   local Updater = require("sui_updater")
--   Updater.checkForUpdates()

local UIManager   = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox  = require("ui/widget/confirmbox")
local logger      = require("logger")
local _           = require("gettext")

-- ---------------------------------------------------------------------------
-- Configuração — ajusta ao teu repositório
-- ---------------------------------------------------------------------------
-- O updater chama: https://api.github.com/repos/<OWNER>/<REPO>/releases/latest
-- e espera encontrar um asset chamado ASSET_NAME no release.
local GITHUB_OWNER = "doctorhetfield-cmd"     -- ← o teu username GitHub
local GITHUB_REPO  = "simpleui.koplugin"     -- ← nome do repositório
local ASSET_NAME   = "simpleui.koplugin.zip" -- ← nome do ficheiro no release

-- ---------------------------------------------------------------------------
-- Internals
-- ---------------------------------------------------------------------------

local M = {}

-- Diretório do plugin (resolvido a partir do caminho deste ficheiro).
local _plugin_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+)/[^/]+$")
    or "/mnt/us/extensions/simpleui.koplugin"  -- fallback Kindle

local _API_URL = string.format(
    "https://api.github.com/repos/%s/%s/releases/latest",
    GITHUB_OWNER, GITHUB_REPO
)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function _currentVersion()
    -- Load _meta.lua directly from disk to avoid require() cache/path issues.
    local meta_path = _plugin_dir .. "/_meta.lua"
    local ok, meta = pcall(dofile, meta_path)
    if ok and type(meta) == "table" and meta.version then
        return meta.version
    end
    -- Fallback: try require() in case dofile is unavailable.
    local rok, rmeta = pcall(require, "_meta")
    return (rok and rmeta and rmeta.version) or "0.0.0"
end

-- Retorna true se a versão `a` for inferior a `b` (comparação semver simples).
local function _versionLessThan(a, b)
    local function parts(v)
        local t = {}
        for n in (v .. "."):gmatch("(%d+)%.") do t[#t + 1] = tonumber(n) end
        while #t < 3 do t[#t + 1] = 0 end
        return t
    end
    local pa, pb = parts(a), parts(b)
    for i = 1, 3 do
        if pa[i] < pb[i] then return true end
        if pa[i] > pb[i] then return false end
    end
    return false
end

-- Faz um pedido HTTP/HTTPS GET seguindo redirects manualmente (até 5 saltos).
-- Devolve o corpo da resposta ou nil + mensagem de erro.
local function _httpRequest(url, sink)
    local http      = require("socket.http")
    local ltn12     = require("ltn12")
    local https_ok, https = pcall(require, "ssl.https")

    local resp_headers = {}
    local ok, code

    if url:match("^https") and https_ok then
        ok, code = https.request {
            url     = url,
            sink    = sink,
            headers = { ["User-Agent"] = "KOReader-SimpleUI-Updater/1.0" },
        }
    else
        ok, code = http.request {
            url     = url,
            sink    = sink,
            headers = { ["User-Agent"] = "KOReader-SimpleUI-Updater/1.0" },
        }
    end
    return ok, code
end

-- HTTP GET seguindo redirects manualmente (o LuaSec do KOReader não os segue).
local function _httpGet(url)
    local ltn12 = require("ltn12")
    local http  = require("socket.http")
    local https_ok, https = pcall(require, "ssl.https")

    for _ = 1, 5 do  -- máximo de 5 redirects
        local chunks = {}
        local resp_headers = {}
        local ok, code, headers

        if url:match("^https") and https_ok then
            ok, code, headers = https.request {
                url     = url,
                sink    = ltn12.sink.table(chunks),
                headers = { ["User-Agent"] = "KOReader-SimpleUI-Updater/1.0" },
            }
        else
            ok, code, headers = http.request {
                url     = url,
                sink    = ltn12.sink.table(chunks),
                headers = { ["User-Agent"] = "KOReader-SimpleUI-Updater/1.0" },
            }
        end

        if (code == 301 or code == 302 or code == 303 or code == 307 or code == 308)
                and headers and headers.location then
            url = headers.location
        elseif not ok or code ~= 200 then
            return nil, string.format("HTTP %s (ok=%s)", tostring(code), tostring(ok))
        else
            return table.concat(chunks)
        end
    end
    return nil, "Too many redirects"
end

-- Descarrega `url` para `dest_path` seguindo redirects.
local function _httpGetToFile(url, dest_path)
    local ltn12 = require("ltn12")
    local http  = require("socket.http")
    local https_ok, https = pcall(require, "ssl.https")

    for _ = 1, 5 do  -- máximo de 5 redirects
        -- Primeiro faz HEAD/GET para obter headers sem guardar o body
        local redirect_chunks = {}
        local ok, code, headers

        if url:match("^https") and https_ok then
            ok, code, headers = https.request {
                url     = url,
                sink    = ltn12.sink.table(redirect_chunks),
                headers = { ["User-Agent"] = "KOReader-SimpleUI-Updater/1.0" },
            }
        else
            ok, code, headers = http.request {
                url     = url,
                sink    = ltn12.sink.table(redirect_chunks),
                headers = { ["User-Agent"] = "KOReader-SimpleUI-Updater/1.0" },
            }
        end

        if (code == 301 or code == 302 or code == 303 or code == 307 or code == 308)
                and headers and headers.location then
            url = headers.location
        elseif code == 200 then
            -- Esta foi a resposta final — guardar o body já obtido
            local fh, err = io.open(dest_path, "wb")
            if not fh then return nil, "Could not create file: " .. tostring(err) end
            fh:write(table.concat(redirect_chunks))
            fh:close()
            return true
        else
            return nil, string.format("HTTP %s (ok=%s)", tostring(code), tostring(ok))
        end
    end
    return nil, "Too many redirects"
end

-- Extrai o valor de uma chave string de um objeto JSON simples.
local function _jsonStr(json, key)
    return json:match('"' .. key .. '"%s*:%s*"([^"]*)"')
end

-- Descarrega `url` para `dest_path` (usa _httpGetToFile que segue redirects).
local function _download(url, dest_path)
    local ok, err = _httpGetToFile(url, dest_path)
    if not ok then
        os.remove(dest_path)
        return nil, err
    end
    return true
end

-- Extrai `zip_path` para `dest_dir` usando o binario `unzip` do sistema.
local function _unzip(zip_path, dest_dir)
    local cmd = string.format("unzip -o -q %q -d %q", zip_path, dest_dir)
    local ret = os.execute(cmd)
    if ret ~= 0 and ret ~= true then
        return nil, "unzip failed (exit " .. tostring(ret) .. ")"
    end
    return true
end

-- Mostra uma mensagem temporaria.
local function _toast(msg, timeout)
    local w = InfoMessage:new{ text = msg, timeout = timeout or 4 }
    UIManager:show(w)
    return w
end

local function _closeWidget(w)
    if w then
        UIManager:close(w)
    end
end

-- ---------------------------------------------------------------------------
-- Fluxo principal
-- ---------------------------------------------------------------------------

-- Fase 2: descarrega e instala apos confirmacao do utilizador.
local function _applyUpdate(download_url, new_version)
    local tmp_zip = "/tmp/simpleui_update.zip"

    _toast(_("Downloading Simple UI ") .. new_version .. "...", 60)

    UIManager:scheduleIn(0.3, function()
        local ok, err = _download(download_url, tmp_zip)
        if not ok then
            logger.err("simpleui updater: download falhou:", err)
            _toast(_("Download error: ") .. tostring(err))
            return
        end

        -- Extrai para o diretorio pai (o ZIP contem a pasta simpleui.koplugin/).
        local parent_dir = _plugin_dir:match("^(.+)/[^/]+$") or _plugin_dir
        local ok2, err2 = _unzip(tmp_zip, parent_dir)
        os.remove(tmp_zip)

        if not ok2 then
            logger.err("simpleui updater: extracao falhou:", err2)
            _toast(_("Extraction error: ") .. tostring(err2))
            return
        end

        UIManager:show(ConfirmBox:new{
            text = string.format(
                _("Simple UI %s successfully installed.\n\nRestart KOReader to apply the update?"),
                new_version
            ),
            ok_text     = _("Restart"),
            cancel_text = _("Later"),
            ok_callback = function() UIManager:restartKOReader() end,
        })
    end)
end

-- Fase 1: verifica se ha atualizacao disponivel (chamada pelo menu).
function M.checkForUpdates()
    local current = _currentVersion()

    -- Garante que a rede está ativa antes de fazer o pedido HTTP.
    local ok_nm, NetworkMgr = pcall(require, "ui/network/manager")
    if ok_nm and NetworkMgr and NetworkMgr.runWhenOnline then
        NetworkMgr:runWhenOnline(function()
            M._doCheckForUpdates(current)
        end)
        return
    end
    -- Fallback para dispositivos sem NetworkMgr (ex: Android, desktop).
    M._doCheckForUpdates(current)
end

function M._doCheckForUpdates(current)
    local checking_toast = _toast(_("Checking for updates..."), 10)

    UIManager:scheduleIn(0.3, function()
        _closeWidget(checking_toast)
        local body, err = _httpGet(_API_URL)
        if not body then
            logger.err("simpleui updater: falha na verificacao:", err)
            _toast(_("Error checking for updates: ") .. tostring(err))
            return
        end

        local tag    = _jsonStr(body, "tag_name")
        local latest = tag and tag:match("v?(.+)") or nil

        -- Procura o URL de download do asset ZIP na resposta da API.
        local download_url = body:match(
            '"browser_download_url"%s*:%s*"([^"]*'
            .. ASSET_NAME:gsub("%.", "%%.")
            .. '[^"]*)"'
        )

        if not latest then
            logger.warn("simpleui updater: nao foi possivel ler a versao da API")
            _toast(_("Could not retrieve version information."))
            return
        end

        if not _versionLessThan(current, latest) then
            logger.info("simpleui updater: ja atualizado (" .. current .. ")")
            _toast(string.format(_("Simple UI is up to date (%s)."), current))
            return
        end

        -- Ha uma versao mais recente disponivel.
        logger.info("simpleui updater: nova versao disponivel:", latest)

        if not download_url then
            -- Sem asset ZIP no release — redireciona para o GitHub.
            UIManager:show(ConfirmBox:new{
                text = string.format(
                    _("Simple UI %s is available (you have %s).\n\nNo automatic update file was found.\n\nOpen the releases page on GitHub?"),
                    latest, current
                ),
                ok_text     = _("Open in browser"),
                cancel_text = _("Cancel"),
                ok_callback = function()
                    local Device = require("device")
                    if Device:canOpenLink() then
                        Device:openLink(string.format(
                            "https://github.com/%s/%s/releases/latest",
                            GITHUB_OWNER, GITHUB_REPO
                        ))
                    end
                end,
            })
            return
        end

        -- Pergunta ao utilizador se quer descarregar e instalar.
        UIManager:show(ConfirmBox:new{
            text = string.format(
                _("Simple UI %s is available!\nCurrent version: %s\n\nDownload and install now?"),
                latest, current
            ),
            ok_text     = _("Download and install"),
            cancel_text = _("Cancel"),
            ok_callback = function()
                _applyUpdate(download_url, latest)
            end,
        })
    end)
end

return M
