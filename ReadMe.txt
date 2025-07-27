Description
A multi-threaded batch ESP cleaning utility utilizing TES4Edit as its backend. Similar to the concept of "P.A.C.T" for Fallout 4, but now for Oblivion. Using xEdit's Auto-Clean. This tool automates the cleaning process
using parallel instances of xEdit specifically made for relating game
(ie TES4Edit for Oblivion), significantly reducing time and effort when
working with large mod lists. For those whom may not know, this enables
cleaning of Esps that one may have as part of a large mod collection,
which in-turn prevents random, crashes and issues, from uncleaned mods.

Features:
- 1–4 thread parallel cleaning using xEdit-AutoCleaner
- Auto-blacklist to skip recently cleaned ESPs
- Error logging and real-time progress
- Batch script to launch powershell scripts
- Install script to Automatically setup program,
- Designed for future multi-game support
- Will run from, game subfolder or custom location.

Instructions:
```
1. Download and Extract the BethesdaGameEspCleaner release into a subfolder of your game directory (e.g. `C:\Games\Oblivion\BethesdaGameEspCleaner\`).
2. Download the latest TES4Edit `.7z` from [Nexus Mods](https://www.nexusmods.com/oblivion/mods/11536) and place it in the same folder as the program files.
3. Ensure structure looks like:
  **BethesdaGame**EspCleaner\
  +-- **BethesdaGame**EspCleaner.bat
  +-- TES4Edit*.7z
4. Run Setup by launching the `.bat` file as Administrator ? select option `2` to extract TES4Edit, set up thread folders, and generate config ? choose 1–4 threads based on your system.
- It will download the portable `7za.exe` from the official `7z` site, in order to extract the `TES4Edit*.7z` file, obviously it needs to do that.
5. Start Cleaning by running the `.bat` again as Administrator or just having returned to the menu, (if you have second monitor put command prompt into it) then select option `1` to begin processing ESPs...
- There is occasionally a mod that will pause the TES4Edit-AutoClean page open (AutoClean would otherwise do that anyhow), but, if there is an "Ok" on the bottom right of AutoClean click that or if there is no "Ok" button then press the `[x]` in the top right.
6. Review Logs: `oec_blacklist.txt` (cleaned), `oec_errorlist.txt` (failures); temp files and thread folders are auto-managed. ```

### Warnings
- Epilepsy - Processing phase involves repeating open/close of full-screen tool.