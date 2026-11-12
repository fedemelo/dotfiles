local home = os.getenv("HOME")
local recordingsDir = home .. "/Dictations"
local models = {
  large = home .. "/.local/share/whisper/ggml-large-v3-turbo-q5_0.bin",
  small = home .. "/.local/share/whisper/ggml-small-q5_1.bin",
}
local rec = "/opt/homebrew/bin/rec"
local whisper = "/opt/homebrew/bin/whisper-cli"
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
  return tonumber(hs.execute("/usr/sbin/sysctl -n kern.memorystatus_vm_pressure_level"))
end

local function withoutExtension(path)
  return (path:gsub("%.wav$", ""))
end

local function readTranscript(recordingPath)
  local file = io.open(withoutExtension(recordingPath) .. ".txt")
  local text = file:read("a")
  file:close()
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function transcribe(recordingPath, model)
  if not hs.fs.attributes(model) then
    return fail("Missing Whisper model " .. model .. ". Run the dotfiles install. " .. retryHint)
  end
  transcriber = hs.task.new(whisper, function(exitCode, _, stderr)
    transcriber = nil
    if exitCode ~= 0 then
      return fail("Transcription failed: " .. stderr:sub(-300) .. "\n" .. retryHint)
    end
    hs.pasteboard.setContents(readTranscript(recordingPath))
    hs.sound.getByName("Glass"):play()
    hs.alert.show("Copied")
  end, { "-m", model, "-f", recordingPath, "-l", "auto", "-np", "-nt", "-otxt", "-of", withoutExtension(recordingPath) })
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

local function onRecorderExit()
  recorder = nil
  if not stopping then
    return fail("Recording stopped unexpectedly. Check that Hammerspoon has microphone access.")
  end
  transcribeIfMemoryAllows(recording)
end

local function startRecording()
  hs.fs.mkdir(recordingsDir)
  recording = recordingsDir .. "/" .. os.date("%Y-%m-%d_%H-%M-%S") .. ".wav"
  stopping = false
  recorder = hs.task.new(rec, onRecorderExit, { "-q", "-c", "1", "-r", "16000", "-b", "16", recording })
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
  local latest
  for name in hs.fs.dir(recordingsDir) do
    local path = recordingsDir .. "/" .. name
    local untranscribed = name:match("%.wav$") and not hs.fs.attributes(withoutExtension(path) .. ".txt")
    if untranscribed and (not latest or path > latest) then
      latest = path
    end
  end
  return latest
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
