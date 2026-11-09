Sprint Time Tracker - local version

What it does: you log time on your Azure DevOps Tasks and Bugs, and the app writes Completed and Remaining Work back to DevOps. It runs only on your PC.

1. Unzip the folder anywhere (e.g. C:\Tools\SprintTimeTracker).
2. Double-click Start.cmd. The browser opens at http://localhost:8787/. Keep the black window open; closing it stops the app.
3. Go to "Settings > DevOps connection", enter organization, project, team and your PAT (Work Items: Read & Write), then press Fetch sprints.
   The PAT is stored in Windows Credential Manager (entry "SprintTimeTracker:AzureDevOpsPAT"), not in any file.
   Save the connection under "Projects" to switch between several DevOps projects from the top bar.
4. Your time entries are saved in %APPDATA%\SprintTimeTracker\data.json (back this file up if you care about the data).
5. Time is written to DevOps automatically when you add a log, stop the timer, or edit/delete a log. The Sync button under Sprints pushes any other pending changes.
Nothing leaves your PC except calls to dev.azure.com. To remove the PAT: delete the entry in Windows Credential Manager.
See TECHNICAL.md for a technical description of the files and how everything works.
