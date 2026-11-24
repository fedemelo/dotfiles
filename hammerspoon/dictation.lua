local home = os.getenv("HOME")
local recordingsDir = home .. "/Dictations"
local logPath = recordingsDir .. "/log.tsv"
-- Per machine and outside the repo, so each user writes their own. Whisper reads the prompt as text
-- said just before the recording, so a sentence naming the topic pulls ambiguous words toward it.
local topicPath = home .. "/.config/dictation/topic.txt"
local vocabularyPath = home .. "/.config/dictation/words.txt"
local modelsDir = home .. "/.local/share/whisper"
local function whisperModel(url)
  return { url = url, path = modelsDir .. "/" .. url:match("[^/]+$") }
end
-- install.sh reads these URLs to report the models that are missing.
local models = {
  large = whisperModel("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin"),
  small = whisperModel("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin"),
}
-- Without voice activity detection, Whisper invents text for silence ("Thanks for watching").
local vadModel = whisperModel("https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin")
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

local recorder, recording, stopping, discarding, transcriber
local status = {}

local function fail(message)
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
  local arguments = { "-m", model.path, "--vad", "-vm", vadModel.path, "-f", recordingPath, "-l", "auto", "-pp", "-otxt", "-of",
    transcriptBase }
  local prompt = collapseWhitespace(readFile(topicPath) .. " " .. readFile(vocabularyPath))
  if prompt ~= "" then
    table.insert(arguments, "--prompt")
    table.insert(arguments, prompt)
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
  if not textFieldIsFocused() then
    return hs.alert.show("Copied")
  end
  hs.eventtap.keyStroke({ "cmd" }, "v")
  hs.alert.show("Pasted")
end

local function transcriptionText()
  if status.percent then
    return string.format("Transcribing… %d%%", status.percent)
  end
  return "Transcribing…"
end

local buttonRadius, buttonGap = 12, 8

local function badgeButton(center, button)
  return {
    {
      type = "circle",
      action = "fill",
      fillColor = button.color,
      center = center,
      radius = buttonRadius,
      id = button.glyph,
      trackMouseUp = true,
    },
    {
      type = "text",
      text = button.glyph,
      textColor = { white = 1 },
      textSize = 15,
      textAlignment = "center",
      frame = { x = center.x - buttonRadius, y = center.y - 10, w = 2 * buttonRadius, h = 2 * buttonRadius },
      id = button.glyph,
      trackMouseUp = true,
    },
  }
end

local function buttonsWidth(buttons)
  return #buttons * (2 * buttonRadius + buttonGap)
end

local function addBadgeButtons(badge, buttons, width, height)
  local actions = {}
  for i, button in ipairs(buttons) do
    local x = width - buttonsWidth(buttons) + (i - 1) * (2 * buttonRadius + buttonGap) + buttonRadius
    badge:appendElements(badgeButton({ x = x, y = height / 2 }, button))
    actions[button.glyph] = button.action
  end
  badge:clickActivating(false)
  badge:mouseCallback(function(_, event, id)
    if event == "mouseUp" and actions[id] then
      actions[id]()
    end
  end)
end

local function cornerBadge(text, buttons)
  buttons = buttons or {}
  local screen = hs.screen.mainScreen():frame()
  local width, height, margin = 210 + buttonsWidth(buttons), 40, 20
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
    frame = { x = 0, y = 8, w = width - buttonsWidth(buttons), h = height - 8 },
  }
  if #buttons > 0 then
    addBadgeButtons(badge, buttons, width - buttonGap, height)
  end
  badge:level(hs.canvas.windowLevels.overlay)
  badge:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  return badge:show()
end

-- The center alert is easy to miss, so anything still going after it fades stays in the corner.
local function startStatus(text, showBadge)
  status = {}
  status.timer = hs.timer.doAfter(centerStatusSeconds, function()
    status.badge = showBadge()
  end)
  hs.alert.show(text, centerStatusSeconds)
end

-- Whisper reports progress once per segment, and with voice activity detection it overshoots 100%.
local function updateTranscriptionStatus(whisperStderr)
  local percent = whisperStderr:match(".*progress =%s*(%d+)%%")
  if not percent then
    return
  end
  status.percent = math.min(tonumber(percent), 99)
  if status.badge then
    status.badge[2].text = transcriptionText()
  end
end

local function endStatus()
  status.timer:stop()
  if status.badge then
    status.badge:delete()
  end
  status = {}
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
  for _, required in ipairs({ model, vadModel }) do
    if not hs.fs.attributes(required.path) then
      hs.pasteboard.setContents(string.format("curl -fL --create-dirs -o '%s' '%s'", required.path, required.url))
      return fail("Missing Whisper model " .. required.path .. ". The command that downloads it is on the clipboard. "
        .. retryHint)
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
    updateTranscriptionStatus(stderrChunk)
    return true
  end, whisperArguments(recordingPath, model, transcriptBase))
  transcriber:start()
  startStatus("Transcribing…", function()
    return cornerBadge(transcriptionText())
  end)
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
  endStatus()
  if discarding then
    os.remove(recording)
    return hs.alert.show("Recording discarded")
  end
  if not stopping then
    if exitCode ~= 0 then
      return fail("Recording stopped unexpectedly. Check that Hammerspoon has microphone access.")
    end
    hs.alert.show(string.format("Recording stopped at the %d-minute limit", maxRecordingSeconds // 60))
  end
  transcribeIfMemoryAllows(recording)
end

local function stopRecording()
  if stopping then
    return
  end
  stopping = true
  recorder:terminate()
end

-- The safe choice comes first so that Return keeps the recording.
local function discardRecording()
  local choice = hs.dialog.blockAlert(
    "Discard this recording?",
    "The audio will be deleted and not transcribed.",
    "Keep recording",
    "Discard",
    "warning"
  )
  if choice ~= "Discard" then
    return
  end
  if not recorder or stopping then
    return hs.alert.show("The recording already ended, so it was not discarded")
  end
  discarding = true
  stopRecording()
end

local recordingButtons = {
  { glyph = "✓", color = { red = 0.2, green = 0.6, blue = 0.3 }, action = stopRecording },
  { glyph = "✕", color = { red = 0.75, green = 0.2, blue = 0.2 }, action = discardRecording },
}

local function startRecording()
  hs.fs.mkdir(recordingsDir)
  recording = recordingsDir .. "/" .. os.date("%Y-%m-%d_%H-%M-%S") .. ".wav"
  stopping = false
  discarding = false
  recorder = hs.task.new(rec, onRecorderExit,
    { "-q", "-c", "1", "-r", "16000", "-b", "16", recording, "trim", "0", tostring(maxRecordingSeconds) })
  if not recorder:start() then
    recorder = nil
    return fail("Could not start recording. Install sox with: brew install sox")
  end
  startStatus("Recording…", function()
    return cornerBadge("Recording…", recordingButtons)
  end)
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
