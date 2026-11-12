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
local keptRecordings = 50
local toggleKey = { { "ctrl", "alt" }, "space" }
local retryKey = { { "ctrl", "alt", "shift" }, "space" }
local retryHint = "Recording kept. Press ⌃⌥⇧Space to transcribe it later."

-- The values of kern.memorystatus_vm_pressure_level, which Activity Monitor shows as green, yellow and red.
local pressure = { normal = 1, warning = 2 }

local recorder, recording, stopping, transcriber

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

local function whisperArguments(recordingPath, model)
  local arguments = { "-m", model, "--vad", "-vm", vadModel, "-f", recordingPath, "-l", "auto", "-nt" }
  local vocabulary = collapseWhitespace(readFile(vocabularyPath))
  if vocabulary ~= "" then
    table.insert(arguments, "--prompt")
    table.insert(arguments, vocabulary)
  end
  return arguments
end

local function onTranscribed(recordingPath, stdout, stderr)
  local text = collapseWhitespace(stdout)
  if text == "" then
    os.remove(recordingPath)
    return hs.alert.show("Nothing heard")
  end
  logTranscript(recordingPath, stderr:match("auto%-detected language: (%a+)") or "?", text)
  pruneTranscribedRecordings()
  hs.pasteboard.setContents(text)
  hs.sound.getByName("Glass"):play()
  hs.alert.show("Copied")
end

local function transcribe(recordingPath, model)
  for _, path in ipairs({ model, vadModel }) do
    if not hs.fs.attributes(path) then
      return fail("Missing Whisper model " .. path .. ". Run the dotfiles install. " .. retryHint)
    end
  end
  transcriber = hs.task.new(whisper, function(exitCode, stdout, stderr)
    transcriber = nil
    if exitCode ~= 0 then
      return fail("Transcription failed: " .. stderr:sub(-300) .. "\n" .. retryHint)
    end
    onTranscribed(recordingPath, stdout, stderr)
  end, whisperArguments(recordingPath, model))
  transcriber:start()
  hs.alert.show("Transcribing…")
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
