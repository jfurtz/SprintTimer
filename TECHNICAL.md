# Sprint Time Tracker - technical description

## 1. Overview
A local, single-user time tracker that reads sprint work items from Azure DevOps, lets you log time on tasks, and writes the time back to DevOps (Completed Work / Remaining Work). It runs entirely on the user's PC: a small PowerShell web server (`server.ps1`) serves one HTML page (`index.html`) and acts as a secure proxy to Azure DevOps. No cloud hosting is involved; the only outbound traffic is to `dev.azure.com`.

```
Browser (index.html, vanilla JS)  <--HTTP, localhost:8787, X-Token-->  server.ps1  <--HTTPS, PAT-->  dev.azure.com
                                                                          |
                                                          data.json (%APPDATA%) + Windows Credential Manager (PAT)
```

## 2. Files in the package

| File | Purpose |
|---|---|
| `Start.cmd` | Launcher. Runs `server.ps1` with PowerShell (`-ExecutionPolicy Bypass` for this process only, no system change). Keep its window open while using the app. |
| `server.ps1` | Local web server and proxy (PowerShell 5.1, built into Windows, no installation). See section 3. |
| `index.html` | The whole user interface and all application logic (HTML + CSS + JavaScript in one file, no external libraries or network resources). Contains the placeholder `__TOKEN__`, which the server replaces with a random per-run token when serving the page. |
| `README.txt` | Short user instructions (install, first run, where data lives). |
| `TECHNICAL.md` | This document. |

Files created at runtime (outside the package folder):

| Location | Content |
|---|---|
| `%APPDATA%\SprintTimeTracker\data.json` | All app state: settings (org/project/team, never the PAT), fetched work items, time entries, notes, UI state. |
| Windows Credential Manager, entry `SprintTimeTracker:AzureDevOpsPAT` | The Personal Access Token (Generic credential, persisted for the user's profile). |

## 3. server.ps1 in detail
- **Listener:** `System.Net.HttpListener` on `http://localhost:8787/` (loopback only; other machines cannot connect; no admin rights needed). It handles one request at a time.
- **Token:** at start-up a random GUID is generated. `GET /` returns `index.html` with `__TOKEN__` replaced. Every `/api/*` call must send header `X-Token` with this value, otherwise `403`. This stops other web pages open in the browser from calling the local API (CSRF / DNS-rebinding protection). A restart creates a new token, so reload the page after restarting.
- **Credential Manager access:** a small C# class compiled at start-up with `Add-Type` calls `CredWrite`, `CredRead` and `CredDelete` from `advapi32.dll`. No PowerShell modules are needed.
- **Endpoints:**

| Endpoint | Behaviour |
|---|---|
| `GET /` | Serves the page (with token). |
| `GET /api/state` | Returns `data.json` (or `{}` if it does not exist). |
| `PUT /api/state` | Overwrites `data.json` with the request body (UTF-8, no BOM). |
| `GET /api/pat` | Returns `{"has":true/false}`. The PAT value is never returned to the browser. |
| `POST /api/pat` | Body `{"pat":"..."}`; stores the PAT in Credential Manager. |
| `DELETE /api/pat` | Removes the stored PAT. |
| `GET/POST/PATCH /api/az/<rest>` | Proxy: forwards to `https://dev.azure.com/<rest>` (same query string and body) with header `Authorization: Basic base64(":" + PAT)`. Only these three methods and only the host `dev.azure.com` are allowed, so it cannot be used to reach other servers. Status code and body are passed back unchanged. Returns `401` if no PAT is stored. |

## 4. index.html in detail
**Views**
- *Time tracker:* start/pause/stop timer, manual entry (date + hours + minutes), list of logs for the last 7 days grouped by day (notes tagged to a task are also shown, editable, under that task's most recent log, with a fold/unfold header; free notes appear only in the pad), sticky-note pad on the right. The pad can be folded and filtered: "Unlinked" (default, notes without a work item) or "All"; the notes group under a task in *Sprints* can be folded too. Notes can be tagged to a task, story or bug (searchable picker); a tagged note shows a link to the work item in DevOps and notes can also be added, edited and deleted directly under a task in *Sprints* when it is expanded (same `notes[]` store with `itemId` set to the task; the task row shows a note count). Notes can be reordered with the mouse by dragging the ⠿ handle (HTML5 drag and drop, desktop browsers; the order is the order of `notes[]`).
- *Sprints:* the fetched sprint as a hierarchy. Tickets/user stories are headers with their tasks below; bugs and tasks without a parent are shown separately. Each task shows assignee, state, Original Estimate vs. used time, a quick "Add" (hours/minutes), and can be expanded to show its logs. Links open the work item in DevOps. The same sticky-note pad as on the Time tracker page is shown on the right, so all notes (free and tagged) are available here too.
- *Board:* kanban view of the selected sprint's tasks and bugs. Columns are the work item states from DevOps (read per work item type from `workitemtypes/{type}/states`; Removed is hidden; with both Task and Bug shown the columns are the union of their states, ordered by state category Proposed > InProgress > Resolved > Complete). Each card shows type, title, user story, assignee and used/estimate; it has a start/stop timer button and hours/minutes + **Add**. Dragging a card (grab the upper part of the card) to another column changes the state in DevOps; columns that are not valid for the card's type are dimmed. Filters: sprint, assigned person (list built from the people on the tasks) and type. The person filter is shared with *Sprints*.
- *Reports:* month calendar (day totals, tasks per day, click a day for details), last-7-days chart, table of tasks that have logs (estimate / used / remaining), CSV export.
- *DevOps connection:* organization, project, team, PAT; fetch sprint; JSON import; restore demo data.
- A sticky **running-timer bar** at the top of every view except *Time tracker* (which has its own timer row) shows the active task, a live clock and Pause/Resume and Stop buttons.
- Theme switch (Auto/Dark/Light) in the menu.

**Data model (in `data.json`)**
- `items[]`: `{id, title, type, state, est (Original Estimate, hours), done (Completed Work from DevOps, hours), parent, who, sprint, az}`. `az:1` means fetched from DevOps (only these can be synced).
- `entries[]`: `{id, itemId, desc, date (YYYY-MM-DD), min}`. Time is stored as whole minutes per day; clock times are deliberately not stored. Logs for the same task, description and day are merged into one entry.
- `pushed{}`: minutes per work item that have already been written to DevOps.
- `cfg`: `{org, project, team}`; `run`: the running timer (`itemId, desc, start, t0, acc, paused`); `notes[]` (`{id, text, color (0-2, fixed per note), itemId?}`, where `itemId` is an optional link to a task, user story or bug); plus UI state (selected sprint/month/day, theme, expanded tasks, folded note groups).
- State is saved automatically (debounced, 300 ms) via `PUT /api/state`. Nothing is saved until the initial load has succeeded, so a failed load cannot overwrite existing data.

**Business rules**
- Time can only be logged on Tasks and Bugs, and every log must have a task. User stories/tickets are never loggable.
- Bugs are treated as stand-alone items, never nested under a user story.
- Used time = `done` (Completed Work already in DevOps) + local minutes - `pushed`. Original Estimate is the budget; over-budget tasks are highlighted and listed in a warning.
- The timer counts only running time; Pause/Resume accumulates elapsed time in `acc`.

## 5. Azure DevOps integration (REST API 7.1)
**Fetching (on "Fetch sprints", and automatically on page load when a PAT and org/project exist)**
1. `GET {org}/{project}/{team}/_apis/work/teamsettings/iterations` - picks the current iteration (`timeFrame = current`, otherwise the latest non-future one) and the iteration that follows it in the list (the next sprint, if one exists).
2. `GET .../iterations/{id}/workitems` - ids of work items in the sprint.
3. `POST {org}/_apis/wit/workitemsbatch` with fields Title, WorkItemType, State, OriginalEstimate, CompletedWork, Parent, AssignedTo.
4. A second batch call fetches parent user stories that are not part of the sprint, so they can be shown as headers.
Items from earlier fetches are kept only if they have logged time, so existing logs never lose their task.

**Writing back (sync)**
- Triggered when a log is added, the timer is stopped, or a log is edited or deleted (and by the "Sync to DevOps" button for anything pending).
- Per work item: `delta = (all local minutes for the item) - pushed[item]`. Then `GET {org}/_apis/wit/workitems/{id}` (fields CompletedWork, RemainingWork, plus `rev`) and `PATCH` with `application/json-patch+json`:
  - `test /rev` (fails if someone else changed the item meanwhile, so nothing is overwritten),
  - `add /fields/Microsoft.VSTS.Scheduling.CompletedWork` = current + delta,
  - `add /fields/Microsoft.VSTS.Scheduling.RemainingWork` = max(0, current - delta) (only if the field is set).
- Because only the difference is written, repeated syncs never double-count, and edits/deletions are corrected (negative delta) on the next sync. After success `pushed` and `done` are updated.
- Sync requests are serialised (one at a time).
- Requires a PAT with scope **Work Items: Read & write**. A 401 on the write step means the PAT is read-only.

**State handling**
- States are fetched together with the sprint (`GET {org}/{project}/_apis/wit/workitemtypes/{type}/states?api-version=7.1-preview.1`) and stored in `data.json` as `states{type: [{name, category, color}]}`. If the call fails the board falls back to the states found on the items (or New/Active/Done for demo data) and categories are guessed from the names.
- Moving a card: the state is changed locally at once, then `PATCH /fields/System.State` (with `test /rev`). If DevOps refuses (e.g. a transition rule), the card jumps back and the error is shown.
- **Auto-Active:** starting a timer or adding time on a task (Time tracker, Sprints or Board) sets the task to the first state of category InProgress for its type (Active / In Progress / Committed) if it is still in a Proposed state (New / To Do). Tasks already started, resolved or closed are not touched.
- **Remaining Work rule:** when time is synced, Completed Work is increased by the delta. If Remaining Work is set it is reduced by the same delta (never below 0). If Remaining Work is empty but Original Estimate exists, Remaining Work is set to Original Estimate minus the new Completed Work (never below 0). If both are empty only Completed Work is written. Values are rounded to 4 decimals (hours) to avoid rounding drift.
- All writes to DevOps (time and state) are serialised through one queue, so two quick actions never collide on the revision check.

## 6. Security notes
- The PAT lives only in Windows Credential Manager and in server memory while proxying; it is never sent to the browser or written to `data.json` (the page blanks it before saving).
- Server listens on loopback only, requires the per-run token, and proxies only to `dev.azure.com`.
- The page loads no external scripts, fonts or images.
- `data.json` is plain text and contains time entries and work item titles; protect the user profile accordingly.

## 7. Requirements and limitations
- Windows with PowerShell 5.1 (default) and a browser. No admin rights, no Node.js, no installers.
- Port 8787 must be free (change `$port` at the top of `server.ps1` if needed). One instance per user.
- Completed/Remaining Work exist on Tasks (and on Bugs only in some process templates); other types fail with a clear error message.
- Only the current sprint and the next one are fetched per run; hours are decimal numbers; the app does not store time of day.
- Not tested against every Azure DevOps process template or on-premises Azure DevOps Server (the proxy targets `dev.azure.com`).

## Active timer visibility
While a timer runs: red sticky bar on all views (grey when paused), highlighted timer row on Time tracker, pulsing dot on the "Time tracker" nav item, and the browser tab title shows `● hh:mm:ss · #id title` (⏸ when paused). Implemented in `runBar()`, `liveUI()`, `liveTitle()`.

## Notes on Board cards
Cards with notes get a yellow left border and a 📝 n badge; the 📝 button (or badge) toggles the task's note panel (`bnote()`, state `S.bOpen`), which reuses `tnotes()` — same notes as on Sprints and the notes pad.

## Board columns
The Board always has three columns: New (category Proposed), Active (InProgress) and Closed (Resolved/Completed). A card whose DevOps status is something else (Impeded, On Hold, Resolved ...) sits in the column of its category and shows the real status as a small tag. Dropping a card in a column sets the first matching DevOps state of the item's type (preferring a state literally named New/Active/Closed) — see `targetState()` and `kDrop()`. Removed items are hidden.

## Settings and feature toggles
The "Settings" nav item (view `settings`; the old `conn` view redirects there) has a Features list and, below it, the DevOps connection. Toggles live in `S.feat` (defaults in `FD`, read with `F(key)`; list/labels in `FL`; handler `setF`). Keys: `board`, `reports` (hide nav items), `notes` (pad, task/log/card notes), `runbar`, `autoActive` (gates `activate()`), `overBudget` (`ob()` chip), `backdate` (date field in `qa()`/`quick()`), `longTimer` (`longChk()`, warns once after 8 h). To add a feature: add a default to `FD`, a row to `FL`, and gate the code with `F("key")`.

## Design, command palette and added features
- **Layout:** icon sidebar, top bar (`#top`, `topbar()`: palette button + sync status), stat tiles (`tiles()`), pinned/recent chips (`quickStrip()`). Accent colour = `--ac` (`S.acc`, `applyAccent()`).
- **Command palette:** Ctrl+K / Cmd+K (`palOpen()`, `palKey()`, `palList()`); Enter starts a timer on a task, Tab opens task actions (start, add time, pin, open in DevOps).
- **Sync queue:** DevOps writes that fail are kept as pending deltas (`pend()`) and the error text in `S.syncErr`; `syncBar()` shows them with a Retry button and `sync(true)` retries every 60 s and when the browser comes online.
- **Forgotten/away timer:** `longChk()` + `fixModal()`/`fixDo()` (runs > 8 h, or a gap > 3 min between ticks).
- **Backup:** `exportData()`, `loadSnap()` (import/restore, PAT never exported), `autoBackup()` keeps 7 daily snapshots in localStorage key `st1bak`.
- **Week view:** `vWeek()`, `setCell()` (edits aggregate the day's entries for a task into one entry and syncs the delta), `parseDur()` accepts 1:30, 90m, 1.5h, 1h30.
- **Reports:** period (sprint/week/last week/month/last 30 days/custom) and grouping (task/person/story/day) in `S.rp`; CSV export uses `rpEntries()`.
- **Projects:** saved connection profiles in `S.profiles`/`S.pid` (`profSave/profSwitch/profDel`); switching refetches from DevOps.
- **Daily reminder:** `remChk()`, settings `S.rt` (time) and `S.rh` (goal hours).

## Notes (task-centred)
Notes belong to a task (`itemId`) or sit in the Inbox (no `itemId`). Fields: `id`, `text`, `itemId`, `done`. One renderer (`nItem()`) is used everywhere: the Inbox / "On tasks" panel (`notes()`), the task block on Sprints and Board cards (`tnotes()`), and under logs on the Timer page (`rowNotes()`). Badges count open (not done) notes. Quick note: type `#123 text` to attach to task 123. In the command palette: "New note…" or Tab on a task > "Add note…".

## User setup and scope
- `S.me = {name,id,auto,org}`: detected via `/_apis/connectionData` (local build) or chosen manually in Settings.
- `S.scope`: `"me"` (default), `"all"` or a person's name. `mine(i)`, `scopeOk(i)` filter tiles, search, palette and picker.
- Unassigned tasks and tasks you have logged on are included by default (`S.incUn`, `S.incLogged`).
- Logging on someone else's task asks for confirmation once per task (`S.askOther`, `S.okO`).

## Timer / Add time switch
- Segmented control `.seg` above the entry bar in `vTrack()`: "Timer" and "Add time" (`S.manual` false/true). Add time is disabled while a timer runs.
- `S.manual` is reset to `false` on every start, so Timer is always the default.
- `tmode(m)` switches mode and copies the description and the task text between the two forms (`desc`/`sel` <-> `md`/`mi`), so the chosen task is kept.

## Board status colours
- Each card gets class `s0`/`s1`/`s2` from `grp(i)` (New/Active/Closed). CSS gives a 4px left border: grey `#a0a0a0`, blue `#009ccc`, green `#339933` - the same colours as the dots in the column headers.
- A card with a running timer keeps a red border (`.kc.run`). The old yellow notes stripe (`.kc.hn`) was removed; notes are shown only by the note badge/icon on the card.

## Central sprint selector
- `sprintSel()` renders one Sprint dropdown in the top bar, left of the user scope selector (`topbar()`). It sets `S.sprint`, which Timer tiles, Sprints, Board and Reports (sprint period) all use.
- The per-page sprint dropdowns on Sprints, Board and Reports were removed, so the sprint is chosen in one place only.

## Active project in the top bar
- `projSel()` shows which DevOps project is active, first in the top bar (left of the sprint and user selectors).
- With two or more saved projects (`S.profiles`) it is a dropdown that calls `profSwitch()`; with one it is a label with the project name (tooltip `org/project`). It is hidden when DevOps is not connected.

## Notes: adding on the "On tasks" tab
- On the "On tasks" tab the quick-note field has a required task picker (`#nkt`, remembered in `S.ntask`), so a new note lands on that task and stays visible. Without a task the user gets a message instead of the note silently going to the Inbox.
- A `#123 text` note typed on the Inbox tab switches to "On tasks" so the note is seen where it ended up.

## Work items per project
- Each DevOps project (`org/project/team`, `pkey()`) has its own work items. `projSwap()` runs when switching profile or fetching: the current project's items are stashed in `S.cache[key]` and `S.items` becomes the new project's items (empty until fetched), so tasks from another project never show up. A project with no sprint or tasks therefore shows an empty list and the fetch message explains why.
- `item(id)` also searches `S.cache`, so time already logged on a task in another project still shows its title; switching back restores the items at once.
- Logged time is kept across projects (entries are not tied to a project). Unsynced time on another project's task is not pushed until that project is active.
