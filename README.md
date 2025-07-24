# BethesdaGameEspCleaner
Status: Alpha

### Description
Its P.A.C.T. for ALL BETHESDA GAMES compatible with Auto-Clean versions of xEdit....!!! For those whom may not know, this enables cleaning of Esps that one may have as part of a large mod collection, which in-turn prevents random, crashes and issues, from uncleaned mods. The user may put 1 xEdit Auto-Clean in both ".\Thread#" folder, thus enabling dual-thread parallel processing of Esps, which is necessary for obvious reasons "it takes half the time", but as more ".\Thread#` folders are setup by the user and utilized, it becomes more frequently to occasionally pop, the ok button on chance that load with no esp selected, 1/100 chance of this. if install only to the first thread folder, in which case it will run in single thread.

### Preview
- The new dual-thread version (Yes its 2x faster than P.A.C.T.)...
```
===============================================================================
    Oblivion Esp Cleaner
===============================================================================

Using 2 thread(s) for processing
[OK] Blacklist maintenance complete
[OK] Found 134 ESP files
[OK] Loaded 85 blacklist entries
[OK] Processing 49 ESPs (skipped 85)
[OK] Task queue initialized with 49 tasks

Starting task queue processing with 2 thread(s)...
Monitoring thread progress...
Thread1 = 2, Thread2 = 0, Completed/Total = 2/49
Thread1 = 2, Thread2 = 2, Completed/Total = 4/49
Thread1 = 3, Thread2 = 2, Completed/Total = 5/49
Thread1 = 3, Thread2 = 3, Completed/Total = 6/49
Thread1 = 4, Thread2 = 3, Completed/Total = 7/49
Thread1 = 4, Thread2 = 4, Completed/Total = 8/49
Thread1 = 5, Thread2 = 4, Completed/Total = 9/49
Thread1 = 6, Thread2 = 4, Completed/Total = 10/49
Thread1 = 7, Thread2 = 4, Completed/Total = 11/49
...
...
```
- Its doing it (single thread version)..
```
===============================================================================
    Oblivion Esp Cleaner
===============================================================================

Cleaning SM Plugin Refurbish Lite.esp... SUCCESS
Cleaning Smarter Ally Combat Positioning.esp... SUCCESS
Cleaning Spell Delete And Item Remove.esp... SUCCESS
Cleaning StoneMarkers.esp... SUCCESS
Cleaning TestAutoSheathWeapon.esp... SUCCESS
Cleaning The Player Random Conversation System.esp... SUCCESS
Cleaning Toaster Says Share Faction Recruitment.esp... SUCCESS
Cleaning Travelers of Cyrodiil.esp... SUCCESS
Cleaning Tropical Cyrodiil.esp... SUCCESS
Cleaning TSS Custom Companion  Template.esp... SUCCESS
Cleaning Unofficial Oblivion Patch.esp... SUCCESS
Cleaning UOP Vampire Aging & Face Fix.esp... SUCCESS
Cleaning Vanilla Staff Replacer.esp... SUCCESS
Cleaning WayshrineMapMarkers.esp... SUCCESS
Cleaning Wayshrines Improved.esp... SUCCESS
Cleaning zzCCAO.esp... SUCCESS

Results:
Success: 16  Fail: 0
Successfully cleaned:
  SM Plugin Refurbish Lite.esp
  Smarter Ally Combat Positioning.esp
  Spell Delete And Item Remove.esp
  StoneMarkers.esp
  TestAutoSheathWeapon.esp
  The Player Random Conversation System.esp
  Toaster Says Share Faction Recruitment.esp
  Travelers of Cyrodiil.esp
  Tropical Cyrodiil.esp
  TSS Custom Companion  Template.esp
  Unofficial Oblivion Patch.esp
  UOP Vampire Aging & Face Fix.esp
  Vanilla Staff Replacer.esp
  WayshrineMapMarkers.esp
  Wayshrines Improved.esp
  zzCCAO.esp
Done:
```

### Structure:
- Program...
```
.\OblivionEspCleaner.bat
.\oec_powershell.ps1
.\oec_thread.ps1
```
- Additions After install.
```
.\TES4Edit #.#.#*\*  # <--- lateset TES4Edit expanded, folder contained moved.
.\Thread#\*  # <--- sequential folders with word thread for replication of AutoClean exe.
```

### Plan
Currently its branded towards the testing platform Oblivion, but for GitHub will be special generic branded one, before that it must work how I want. There will be game braned versions for each game I can cover featured on NexusMods.
