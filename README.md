# FnMacAssistant
Welcome to FnMacAssistant! An easy to use assistant that helps you download the latest Fortnite IPA and applies the necessary patches for it to work properly.<br>
<img width="612" alt="Screenshot 2024-10-13 at 3 51 23 p m" src="https://github.com/user-attachments/assets/df141825-7a77-4c31-a0e0-d2724364dca2">
<hr/>
<h2>Notice</h2>
Fortnite-XX.XX.ipa now includes both regular and fullscreen versions, as the two types of IPAs have been merged. The clean IPA doesn't include any modifications, but you may encounter installation and compatibility issues, so it’s not recommended. You can now download Fall Guys from FnMacAssistant. This app doesn’t require patching and can be installed using Sideloadly or PlayCover. It’s also available for free on iOS outside the EU, with the recommended method being LiveContainer.

<hr>
<h2>Join the official Fortnite Mac discord here: https://discord.gg/nfEBGJBfHD</h2>
<hr>
<h2>Buy me a coffee</h2>
If you found this program useful and want to support me, buy me a coffee! 
<br/><br/>
<a href="https://www.buymeacoffee.com/Isacucho" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-orange.png" alt="Buy Me A Coffee" height="41" width="174"></a>
<hr/>
<h2>Requirments:</h2> 
Have Sideloadly installed on your mac <br/>
Mac must be on MacOS 15.0 or later <br/>
A mac with an M series chip. (Fortnite mobile will never work on an Intel Mac)

<hr/>

**note:** The game can be played with keyboard and mouse, but a controller is needed to login and to interact with the lobby (ready up, select gamemode, change skin, etc.) 

Update: Acording to recent testing, it looks like sprinting, crouching, building, and other main actions in the game aren't possible using the native implementation of keyboard and mouse. We are working on finding a fix to this, but it isn't 100% certain that we will find it. I would recommend you to play on controller for the time being.


If anyone has any idea as to how to solve the controller issue, open a request (or PM me on discord: isacucho) and I'll try to implement it!
<hr/>

<h2>Instructions:</h2>
<h3>Video tutorial is out! Thanks to @Ordr. for making the tutorial: https://www.youtube.com/watch?v=N8Cm-rPrI_w</h3>


1. Download and install [Sideloadly](https://sideloadly.io)

2. Download the newest version of the FnMacAssistant App from [Releases](https://github.com/isacucho/FnMacAssistant/releases) and unzip it. (if you have knowledge on python, you can use the python version by cloning this repository) 

3. You should now have an app called FnMacAssistant on your downloads folder. Double-click to open it.

4. You may get a "FnMacAssistant.app is damaged and can’t be opened. You should move it to the Trash.". That is completely normal, and the only way to bypass it would be to buy an apple developer account to sign the app. To open the app, copy and paste the following commands on terminal:
```
cd downloads
xattr -dr com.apple.quarantine FnMacAssistant.app
```
(If you moved the app from your downloads folder, change the _downloads_ on `cd downloads` for the folder where the app is located)
Alternatively, you can download and run the python version of the app.
 
5. Select the Fortnite-XX.XX.ipa (the clean IPA may not work unless manually tweaked), and click the _Download IPA_ button to download it.

6. Go to sideloadly and sideload the downloaded IPA (the IPA will be saved to your _Downloads_ folder.

7. Open the Fortnite app. It should crash after a few seconds.

8. Return to FnMacAssistant and click on the _Patch App_ button. (This will patch the embedded.mobileprovision to _/Applications/Fortnite.app/Wrapper/FortniteClient-IOS-Shipping.app_, and remove old app if it exists)

9. Open fortnite and enjoy!

<hr/>

<h2>Troubleshooting</h2>

**“Fortnite” cannot be opened because the developer did not intend for it to be run on this Mac.**


If you get this message, do the following steps:
1. delete fortnite.app from your applications folder
2. Install the Fortnite IPA again using sideloadly
3. Open Fortnite. You should see the Epic Games logo for a few seconds, then the app will crash.
4. Go to FnMacAssistant and press the 'Patch App' button.
5. Open Fortnite again. This time it shouldn't crash!

If you still get the same message after following this steps, contact me on Discord: _@isacucho_ and I'll do my best to help!
<hr/>

<h2>Credits:</h2>
The guys at the CelestialiOS Discord server for the Fortnite IPAs. https://discord.gg/celestialios<br/>
Drohy for the inspiration to make this app. https://github.com/Drohy/FortniteMAC
