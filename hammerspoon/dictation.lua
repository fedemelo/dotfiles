local home = os.getenv("HOME")
local recordingsDir = home .. "/Dictations"
local logPath = recordingsDir .. "/log.tsv"
local vocabularyPath = home .. "/.config/dictation/words.txt"
local models = {
  large = home .. "/.local/share/whisper/ggml-large-v3-turbo-q5_0.bin",
  small = home .. "/.local/share/whisper/ggml-small-q5_1.bin",
}
-- Without voice activity detection, Whisper invents text for silence ("Thanks for watching").
local vadModel = home .. "/.local/share/whisper/ggml-silero-v5.1.2.bin"
local rec = "/opt/homebrew/bin/rec"
local whisper = "/opt/homebrew/bin/whisper-cli"
local maxRecordingSeconds = 300
local centerStatusSeconds = 2
local keptRecordings = 50
local toggleKey = { { "ctrl", "alt" }, "space" }
local retryKey = { { "ctrl", "alt", "shift" }, "space" }
local retryHint = "Recording kept. Press ⌃⌥⇧Space to transcribe it later."

-- The values of kern.memorystatus_vm_pressure_level, which Activity Monitor shows as green, yellow and red.
local pressure = { normal = 1, warning = 2 }

local recorder, recording, stopping, transcriber
local transcriptionStatus = {}

local function fail(message)
  hs.sound.getByName("Basso"):play()
  hs.alert.show(message, 6)
end

local function memoryPressure()
  local output = hs.execute("/usr/sbin/sysctl -n kern.memorystatus_vm_pressure_level")
  return tonumber(output)
end

local function readFile(path)
  local file = io.open(path)
  if not file then
    return ""
  end
  local text = file:read("a")
  file:close()
  return text
end

local function collapseWhitespace(text)
  return (text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function recordingName(path)
  return path:match("([^/]+)%.wav$")
end

local function transcribedNames()
  local names = {}
  for line in readFile(logPath):gmatch("[^\n]+") do
    names[line:match("^[^\t]+")] = true
  end
  return names
end

local function logTranscript(recordingPath, language, text)
  local file = io.open(logPath, "a")
  file:write(table.concat({ recordingName(recordingPath), language, text }, "\t"), "\n")
  file:close()
end

local function recordingsOldestFirst()
  local paths = {}
  for name in hs.fs.dir(recordingsDir) do
    if name:match("%.wav$") then
      table.insert(paths, recordingsDir .. "/" .. name)
    end
  end
  table.sort(paths)
  return paths
end

-- Only transcribed recordings are pruned: one waiting for ⌃⌥⇧Space has no transcript anywhere else.
local function pruneTranscribedRecordings()
  local transcribed = transcribedNames()
  local prunable = {}
  for _, path in ipairs(recordingsOldestFirst()) do
    if transcribed[recordingName(path)] then
      table.insert(prunable, path)
    end
  end
  for i = 1, #prunable - keptRecordings do
    os.remove(prunable[i])
  end
end

local function whisperArguments(recordingPath, model, transcriptBase)
  local arguments = { "-m", model, "--vad", "-vm", vadModel, "-f", recordingPath, "-l", "auto", "-pp", "-otxt", "-of",
    transcriptBase }
  local vocabulary = collapseWhitespace(readFile(vocabularyPath))
  if vocabulary ~= "" then
    table.insert(arguments, "--prompt")
    table.insert(arguments, vocabulary)
  end
  return arguments
end

local textRoles = { AXTextField = true, AXTextArea = true, AXComboBox = true }

-- Reading the focused element and pressing ⌘V both need Accessibility access. Passing true makes
-- macOS ask for it while it isn't granted; until then the text is only copied.
local function textFieldIsFocused()
  if not hs.accessibilityState(true) then
    return false
  end
  local focused = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  return focused ~= nil and textRoles[focused:attributeValue("AXRole")] == true
end

local function deliver(text)
  hs.pasteboard.setContents(text)
  hs.sound.getByName("Glass"):play()
  if not textFieldIsFocused() then
    return hs.alert.show("Copied")
  end
  hs.eventtap.keyStroke({ "cmd" }, "v")
  hs.alert.show("Pasted")
end

local function statusText()
  if transcriptionStatus.percent then
    return string.format("Transcribing… %d%%", transcriptionStatus.percent)
  end
  return "Transcribing…"
end

local function cornerBadge(text)
  local screen = hs.screen.mainScreen():frame()
  local width, height, margin = 210, 40, 20
  local badge = hs.canvas.new({
    x = screen.x + screen.w - width - margin,
    y = screen.y + screen.h - height - margin,
    w = width,
    h = height,
  })
  badge[1] = {
    type = "rectangle",
    action = "fill",
    fillColor = { white = 0, alpha = 0.75 },
    roundedRectRadii = { xRadius = 10, yRadius = 10 },
  }
  badge[2] = {
    type = "text",
    text = text,
    textColor = { white = 1 },
    textSize = 18,
    textAlignment = "center",
    frame = { x = 0, y = 8, w = width, h = height - 8 },
  }
  badge:level(hs.canvas.windowLevels.overlay)
  badge:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  return badge:show()
end

local function showStatusInCorner()
  transcriptionStatus.badge = cornerBadge(statusText())
end

local function startStatus()
  transcriptionStatus = { timer = hs.timer.doAfter(centerStatusSeconds, showStatusInCorner) }
  hs.alert.show("Transcribing…", centerStatusSeconds)
end

-- Whisper reports progress once per segment, and with voice activity detection it overshoots 100%.
local function updateStatus(whisperStderr)
  local percent = whisperStderr:match(".*progress =%s*(%d+)%%")
  if not percent then
    return
  end
  transcriptionStatus.percent = math.min(tonumber(percent), 99)
  if transcriptionStatus.badge then
    transcriptionStatus.badge[2].text = statusText()
  end
end

local function endStatus()
  transcriptionStatus.timer:stop()
  if transcriptionStatus.badge then
    transcriptionStatus.badge:delete()
  end
  transcriptionStatus = {}
end

local function onTranscribed(recordingPath, transcript, stderr)
  local text = collapseWhitespace(transcript)
  if text == "" then
    os.remove(recordingPath)
    return hs.alert.show("Nothing heard")
  end
  logTranscript(recordingPath, stderr:match("auto%-detected language: (%a+)") or "?", text)
  pruneTranscribedRecordings()
  deliver(text)
end

local function transcribe(recordingPath, model)
  for _, path in ipairs({ model, vadModel }) do
    if not hs.fs.attributes(path) then
      return fail("Missing Whisper model " .. path .. ". Run the dotfiles install. " .. retryHint)
    end
  end
  -- With a streaming callback, hs.task gives the exit callback no output and can deliver the last chunk
  -- after it, so the transcript is read from the file Whisper writes instead.
  local transcriptBase = recordingPath:gsub("%.wav$", "")
  local transcriptPath = transcriptBase .. ".txt"
  local stderr = ""
  transcriber = hs.task.new(whisper, function(exitCode)
    transcriber = nil
    endStatus()
    local transcript = readFile(transcriptPath)
    os.remove(transcriptPath)
    if exitCode ~= 0 then
      return fail("Transcription failed: " .. stderr:sub(-300) .. "\n" .. retryHint)
    end
    onTranscribed(recordingPath, transcript, stderr)
  end, function(_, _, stderrChunk)
    stderr = stderr .. stderrChunk
    updateStatus(stderrChunk)
    return true
  end, whisperArguments(recordingPath, model, transcriptBase))
  transcriber:start()
  startStatus()
end

local function transcribeIfMemoryAllows(recordingPath)
  local level = memoryPressure()
  if level == pressure.normal then
    return transcribe(recordingPath, models.large)
  end
  if level == pressure.warning then
    local choice = hs.dialog.blockAlert(
      "Memory is under pressure",
      "Transcribe now with the small model, or wait and keep the recording?",
      "Small model",
      "Wait"
    )
    if choice == "Small model" then
      return transcribe(recordingPath, models.small)
    end
    return hs.alert.show(retryHint, 4)
  end
  fail("Memory pressure is critical, so nothing was transcribed. " .. retryHint)
end

-- rec exits 0 by itself only when its trim reaches maxRecordingSeconds.
local function onRecorderExit(exitCode)
  recorder = nil
  if not stopping then
    if exitCode ~= 0 then
      return fail("Recording stopped unexpectedly. Check that Hammerspoon has microphone access.")
    end
    hs.alert.show(string.format("Recording stopped at the %d-minute limit", maxRecordingSeconds // 60))
  end
  transcribeIfMemoryAllows(recording)
end

local function startRecording()
  hs.fs.mkdir(recordingsDir)
  recording = recordingsDir .. "/" .. os.date("%Y-%m-%d_%H-%M-%S") .. ".wav"
  stopping = false
  recorder = hs.task.new(rec, onRecorderExit,
    { "-q", "-c", "1", "-r", "16000", "-b", "16", recording, "trim", "0", tostring(maxRecordingSeconds) })
  if not recorder:start() then
    recorder = nil
    return fail("Could not start recording. Run the dotfiles install to check for sox.")
  end
  hs.sound.getByName("Tink"):play()
  hs.alert.show("Recording…")
end

local function stopRecording()
  stopping = true
  recorder:terminate()
end

local function toggle()
  if transcriber then
    return hs.alert.show("Still transcribing the last recording")
  end
  if recorder then
    return stopRecording()
  end
  startRecording()
end

local function latestUntranscribed()
  local transcribed = transcribedNames()
  local paths = recordingsOldestFirst()
  for i = #paths, 1, -1 do
    if not transcribed[recordingName(paths[i])] then
      return paths[i]
    end
  end
end

local function retryLatest()
  if recorder or transcriber then
    return hs.alert.show("Busy recording or transcribing")
  end
  local path = hs.fs.attributes(recordingsDir) and latestUntranscribed()
  if not path then
    return hs.alert.show("No recording is waiting to be transcribed")
  end
  transcribeIfMemoryAllows(path)
end

return {
  hotkeys = {
    hs.hotkey.bind(toggleKey[1], toggleKey[2], toggle),
    hs.hotkey.bind(retryKey[1], retryKey[2], retryLatest),
  },
}
