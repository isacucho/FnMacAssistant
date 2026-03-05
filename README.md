# FnMacAssistant
Welcome to FnMacAssistant! An easy to use assistant that helps you download the latest Fortnite IPA and applies the necessary patches for it to work properly.<br>
<img width="1012" height="674" alt="Screenshot of FnMacAssistant v2.0" src="https://github.com/user-attachments/assets/55ba74e0-f045-4486-9f27-2442fda7b0a4" />


<h2>Discord</h2>
Join the official Fortnite Mac discord here: https://discord.gg/nfEBGJBfHD

<h2>Support me</h2>
If you found this program useful and want to support me, consider using my Support a Creator Code in Fortnite!

`Isacucho`

You can also support me through buy me a coffee! 
<br/><br/>
<a href="https://www.buymeacoffee.com/Isacucho" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-orange.png" alt="Buy Me A Coffee" height="41" width="174"></a>


<h2>Requirments</h2> 
- A valid Apple ID<br/>
- MacOS 15.1 or later <br/>
-  Mac must have an M series chip. (Fortnite mobile will never work on an Intel Mac)

<h2>Guide</h2>

1. Download and install [Sideloadly](https://sideloadly.io/) or [PlumeImpactor](https://github.com/claration/Impactor/releases/latest)
<br>
2. Download [FnMacAssistant](https://github.com/isacucho/FnMacAssistant/releases/latest) and drag it to your applications folder.

> [!NOTE]
> To get full app functionality, you need to give your terminal Full Disk Access. 
>
>Go to `System Settings > Privacy & Security > Full Disk Access` and toggle 'Terminal.app' on, or add it if it isn't listed.
<br>
3. Open FnMacAssistant. Navigate to the `IPA Downloads` tab, select your desired IPA and click `Download`.
<br>
4. Open your sideloading app of choice and log in with your apple ID. 
<br>
5. Drag and drop your freshly downloaded IPA. Make sure to select your mac (`Apple Silicon` on sideloadly and `[LOCAL] This Mac` on Impactor) and click Install/Start.
<br>
6. Wait for the installation to complete. Once it does, go back to FnMacAssistant, navigate to the `Patch` tab, and  click `Apply Patch`. 
<br>(NOTICE: you might need to go to privacy and security and click `Open Anyway`)
<br>
7. Navigate to the `Update Assistant`tab, and click `Start Update`. Fortnite will open and close automatically to perform the update. Don't touch Fortnite while the update assistant downloads the game assets.

<br>
Fortnite is now installed! You can now open the game and play. By default, the only game mode pre-installed is Blitz. If you would like to play another gamemode, you will have to install it through the update assistant. To do this, start the update assistant, wait for fortnite to launch, then select your gamemode and click `Download`. Fortnite should close automatically after a few seconds. If it doesn't, cancel the download in-game and re-try.
<br>
Note: You might need to do this process twice the first time: once for the cosmetics and one for the game mode itself.

<br>
<br>
<h2>FAQ</h2>

<h3>I'm getting a connection / storage error while downloading the game files! What should I do?</h3>

To fix this, you need to download the game data using FnMacAssistant.

1. Open FnMacAssistant and select the "Update Assistant" tab.
2. Click on 'Start Update'.
3. Don't touch anything. FnMacAssistant will open and close Fortnite, and start the download automatically.
4. If the update assistant is not working properly, manually close and re-open fortnite. 
5. Wait for the download to complete, and once it's done open the game. 

You can also install the data using the "Game Assets" tab.
<br>
<br>

<h3>How do I update the game?</h3>
Follow these steps to update Fortnite:
<br><br>
1. Download the updated IPA.<br>
2. Install it through PlumeImpactor or Sideloadly using the same Apple ID you used previously.<br>
3. On FnMacAssistant, go to the 'Patch' tab and click on 'Apply Patch'.<br>
4. If prompted, go to 'System Settings > Privacy & Security', scroll down and click on 'Open Anyway'<br>
5. Download game files through the Update Assistant or the Game Assets tab.
<br><br>


<h3>Error: “Fortnite” cannot be opened because the developer did not intend for it to be run on this Mac.</h3>

This error might appear 7 days after you first installed. This happens because sideloaded apps expire every 7 days. To fix this: 
<br>
1. Delete Fortnite.app from Applications.<br>
2. Reinstall the IPA using Sideloadly or PlumeImpactor.<br>
3. Patch using FnMacAssistant.<br>
4. Open Fortnite.
<br>
<br>
<h3>FnMacAssistant cannot find Fortnite's container</h3>
Grant Full Disk Access to FnMacAssistant:<br>
1. System Settings > Privacy & Security > Full Disk Access.<br>
2. Add FnMacAssistant and enable it.<br>
3. Restart FnMacAssistant and patch again.<br><br>
<h3>Fortnite keeps crashing even after patching</h3>
This usually means that you're MacOS version is not supported. Please update your mac and try again.
<br><br>

<h3>What is the difference between the various IPAs?</h3>

**Clean IPA** <br />
The clean IPA (Fortnite-XX.XX_Clean.ipa) is the decrypted IPA as-is, no modifications whatsoever. Useful when trying to debug, but it may cause some issues like black bars.
<br /><br />
**Regular IPA** <br />
The regular IPA (Fortnite-XX.XX.ipa) contains the following tweaks:
- MacOS Fullscreen Patch
- Removed device restriction
- Allows editing files from the Files app
- Lowered minimum iOS version to iOS 10
<br />

**Tweak IPA**
<br />
The tweak IPA (Fortnite-XX.XX+Tweak.ipa) comes bundled with the FnMacTweak made by rt2746. In addition to the tweaks mentioned on the regular IPA, this one also contains:
- Toggle pointer locking with Left Option key (unlocked by default on game load)
- Unlocks 120 FPS option (requires 120Hz display for full effect)
- Unlocks graphic preset selection (Low, Medium, High, Epic; 120 FPS sets to Medium)
- Custom options menu (press P) for mouse sensitivity adjustments
- Mouse interaction with mobile UI
- Use external storage for game data [See The Guide](./USE_EXTERNAL_DRIVE.md) (requires FnMacAssistant v1.5.0+ and FnMacTweak v1.0.3+)
<br />

You can download the standalone tweak or build it yourself on the project's [Github page](https://github.com/victorwads/FnMacTweak) .
<br /><br />

If you have any questions that are not in here, join the [Fortnite Mac discord server](https://discord.gg/nfEBGJBfHD) and I'll be happy to answer your questions over there!




<h2>Credits:</h2>

- [rt-someone](https://github.com/rt-someone) and [KohlerVG](https://github.com/KohlerVG) for [FnMacTweak](https://github.com/KohlerVG/FnMacTweak)
- [VictorWads](https://github.com/victorwads) for external drive support
- [f1shy-dev](https://github.com/f1shy-dev) for [fort-dl](https://github.com/f1shy-dev/fort-dl)
- [Altermine](https://github.com/altermine) for [Update Assistant](https://github.com/altermine/FnMacAssistant/tree/update-assistant)
- [Jasonsika](https://jasonsika.com/) for the app icon
