# FnMacAssistant
Welcome to FnMacAssistant! An easy to use assistant that helps you download the latest Fortnite IPA and applies the necessary patches for it to work properly.<br>
<img width="612" alt="Screenshot 2024-10-13 at 3 51 23 p m" src="https://github.com/user-attachments/assets/df141825-7a77-4c31-a0e0-d2724364dca2">
<hr/>
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

~~**note 2:** The screen size will be in an iPad's screen size format, so you may see black bars on the edges of your screen. I haven't found a way to make the game fullscreen yet.~~ <br>

The Fortnite fullscreen patch is now live! Make sure to select the Fullscreen IPA when downloading with FnMasAssistant for it to work.

If anyone manages to solve the controller issue, open a request (or PM me on discord) and I'll try to implement it!
<hr/>

<h2>Instructions:</h2>

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
 
5. Select your desired IPA (Fullscreen or regular), and click the _Download IPA_ button to download it.

6. Go to sideloadly and sideload the downloaded IPA (the IPA will be saved to your _Downloads_ folder.

7. Return to FnMacAssistant and click on the _Patch App_ button. (This will patch the embedded.mobileprovision to _/Applications/Fortnite.app/Wrapper/FortniteClient-IOS-Shipping.app_)

8. Open fortnite and enjoy!

<hr/>

<h2>Credits:</h2>
The guys at the CelestialiOS Discord server for the Fortnite IPAs. https://discord.gg/celestialios<br/>
Drohy for the inspiration to make this app. https://github.com/Drohy/FortniteMAC
