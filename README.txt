Sprint Time Tracker - local version (Windows and Mac)

What it does: you log time on your Azure DevOps Tasks and Bugs, and the app writes Completed and Remaining Work back to DevOps. It runs only on your computer.

WINDOWS
1. Unzip the folder anywhere (e.g. C:\Tools\SprintTimeTracker).
2. Double-click Start.cmd. The browser opens at http://localhost:8787/. Keep the black window open; closing it stops the app.
   (If Node.js is installed it is used; otherwise the built-in PowerShell server is used. Both work the same.)

MAC
1. Install Node.js (LTS) from https://nodejs.org if you do not have it. Check with: node -v   (18 or newer)
2. Unzip the folder anywhere (e.g. in Documents).
3. Double-click Start.command. The first time, macOS may say it cannot verify the developer: right-click the file, choose Open, and confirm.
   If it does not run at all, open Terminal once and run:  chmod +x ~/Documents/SprintTimeTracker/Start.command
   Or just run it from Terminal:  cd SprintTimeTracker && node server.js
4. The browser opens at http://localhost:8787/. Keep the Terminal window open; closing it stops the app.

FIRST TIME (both)
- Go to "Settings > DevOps connection", enter organization, project, team and your PAT (Work Items: Read & Write), then press Fetch sprints.
- Save the connection under "Projects" to switch between several DevOps projects from the top bar.

WHERE THINGS ARE STORED
- PAT: Windows Credential Manager (entry "SprintTimeTracker:AzureDevOpsPAT") or the macOS Keychain (item "SprintTimeTracker:AzureDevOpsPAT"). Never in a file.
- Time entries: Windows %APPDATA%\SprintTimeTracker\data.json, Mac ~/Library/Application Support/SprintTimeTracker/data.json. Back this file up if you care about the data.
- Time is written to DevOps automatically when you add a log, stop the timer, or edit/delete a log. The Sync button under Sprints pushes any other pending changes.
Nothing leaves your computer except calls to dev.azure.com. To remove the PAT: Settings > DevOps connection, or delete the entry in Credential Manager / Keychain Access.
See TECHNICAL.md for a technical description of the files and how everything works.
