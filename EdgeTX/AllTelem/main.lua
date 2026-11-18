-- Garantiert stabiles Telemetrie-Widget ohne ID-Verwirrung (mit Auto-Page-Scrolling)
local s_list = {}
local last_page_switch = 0
local current_page = 1

-- Lückenlose Blacklist für ALLE Empfänger- und Verbindungsdaten
local ignore_sensors = {
    ["RSSI"] = true, ["Rssi"] = true, ["1RSS"] = true, ["2RSS"] = true,
    ["RQly"] = true, ["RQLY"] = true, ["TQly"] = true, ["TQLY"] = true,
    ["TRSS"] = true, ["RFMD"] = true, ["TPWR"] = true, ["Ant"] = true, ["Anta"] = true,
    ["RSNR"] = true, ["Rsnr"] = true, ["TSNR"] = true, ["Tsnr"] = true, ["ANT"] = true
}

-- Hilfsfunktion zur sauberen Formatierung von Werten (Cels und GPS)
local function formatValue(name, val)
    if type(val) == "table" then
        if name == "Cels" or name == "Cells" then
            local total = 0
            for _, cellVolt in ipairs(val) do
                total = total + cellVolt
            end
            return string.format("%.2fV (%dS)", total, #val)
        elseif val.lat ~= nil and val.lon ~= nil then
            return string.format("%.4f, %.4f", val.lat, val.lon)
        else
            return "{Tab.}"
        end
    end
    return tostring(val)
end

local function create(zone)
    local widget = { zone = zone }
    return widget
end

local function update(widget)
    s_list = {}
    local seen_names = {}
    
    -- EdgeTX erlaubt max. 64 registrierte Sensoren im Modell
    for i = 0, 63 do
        local sensorData = model.getSensor(i)
        
        if sensorData and sensorData.name and sensorData.name ~= "" then
            if not ignore_sensors[sensorData.name] then
                
                -- Wir holen uns das exakte FieldInfo-Objekt über den Sensornamen
                local fieldInfo = getFieldInfo(sensorData.name)
                
                if fieldInfo then
                    seen_names[sensorData.name] = (seen_names[sensorData.name] or 0) + 1
                    local exact_id = fieldInfo.id + (seen_names[sensorData.name] - 1)
                    
                    local liveValue = getValue(exact_id)
                    
                    if liveValue ~= nil then
                        table.insert(s_list, {
                            raw_name = sensorData.name,
                            occurence = seen_names[sensorData.name],
                            val = formatValue(sensorData.name, liveValue)
                        })
                    end
                end
            end
        end
    end
end

local function background(widget)
    update(widget)
end

local function refresh(widget)
    update(widget)
    lcd.clear()
    
    local x = widget.zone.x + 10
    local y = widget.zone.y + 10
    local height = 24  
    local max_rows = math.floor((widget.zone.h - 15) / height)
    local sensors_per_page = max_rows * 2
    
    if #s_list == 0 then
        lcd.drawText(x, y, "Keine relevanten Sensoren gefunden", 0)
        return
    end
    
    -- Seiten-Logik berechnen
    local total_pages = math.ceil(#s_list / sensors_per_page)
    local now = getTime() -- Liefert die Zeit in 10ms-Schritten (EdgeTX Standard)
    
    -- Alle 400 Ticks (4 Sekunden) die Seite wechseln, falls nötig
    if total_pages > 1 then
        if now - last_page_switch > 400 then
            current_page = current_page + 1
            if current_page > total_pages then
                current_page = 1
            end
            last_page_switch = now
        end
    else
        current_page = 1
    end
    
    -- Zählen, welche Namen insgesamt mehrfach vorkommen
    local total_counts = {}
    for _, s in ipairs(s_list) do
        total_counts[s.raw_name] = (total_counts[s.raw_name] or 0) + 1
    end
    
    -- Start- und End-Index für die aktuelle Seite festlegen
    local start_index = ((current_page - 1) * sensors_per_page) + 1
    local end_index = math.min(start_index + sensors_per_page - 1, #s_list)
    
    -- Nur die Sensoren der aktuellen Seite ausgeben
    local display_counter = 1
    for index = start_index, end_index do
        local sensor = s_list[index]
        
        local current_x = x
        local current_y = y + ((display_counter - 1) % max_rows) * height
        
        if display_counter > max_rows then
            current_x = x + math.floor(widget.zone.w / 2)
        end
        
        -- Namen für die Anzeige bestimmen
        local displayName = sensor.raw_name
        if total_counts[sensor.raw_name] > 1 then
            displayName = string.format("%s-%d", sensor.raw_name, sensor.occurence)
        end
        
        -- Text und echten Live-Wert zeichnen
        lcd.drawText(current_x, current_y, displayName, 0)
        lcd.drawText(current_x + 75, current_y, sensor.val, BOLD)
        
        display_counter = display_counter + 1
    end
    
    -- Kleine Seitenzahl unten rechts einblenden, wenn gescrollt wird
    if total_pages > 1 then
        local page_str = string.format("S. %d/%d", current_page, total_pages)
        lcd.drawText(widget.zone.x + widget.zone.w - 45, widget.zone.y + widget.zone.h - 12, page_str, SMLSIZE)
    end
end

local function destroy(widget)
    s_list = nil
    ignore_sensors = nil
end

return {
    name = "AllTelemetry",
    options = {},
    create = create,
    update = update,
    background = background,
    refresh = refresh,
    destroy = destroy
}
