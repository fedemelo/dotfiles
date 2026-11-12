-- Lets the hs command line tool run code in this config.
require("hs.ipc")
hs.autoLaunch(true)

-- ~/.hammerspoon holds links, so the files to watch are in the directory they point to.
local repoDir = hs.fs.pathToAbsolute(hs.configdir .. "/init.lua"):match("^(.*)/")
-- Global, or garbage collection stops the watcher. Only Lua changes reload: a reload mid-recording
-- loses the recording, and words.txt is read fresh on every transcription anyway.
configWatcher = hs.pathwatcher.new(repoDir, function(paths)
  for _, path in ipairs(paths) do
    if path:match("%.lua$") then
      return hs.reload()
    end
  end
end):start()

require("dictation")
