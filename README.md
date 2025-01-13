# FnMacAssistant
Welcome to FnMacAssistant! An easy to use assistant that helps you download the latest Fortnite IPA and applies the necessary patches for it to work properly.<br>
<img width="612" alt="Screenshot 2024-10-13 at 3 51 23 p m" src="https://github.com/user-attachments/assets/df141825-7a77-4c31-a0e0-d2724364dca2">
<hr/>
<h1>Anouncement</h1>
TL;DR: Fortnite-XX.XX.ipa now includes both regular and fullscreen versions, as the two types of IPAs have been merged. The clean IPA doesn't include any modifications, but you may encounter installation and compatibility issues, so it’s not recommended. You can now download Fall Guys from FnMacAssistant. This app doesn’t require patching and can be installed using Sideloadly or PlayCover. It’s also available for free on iOS outside the EU, with the recommended method being LiveContainer.
<br><br>

Hey guys!

First of all, if you're new here, welcome! We're happy to have you. This announcement is intended to current users, regarding a change made to the new IPA naming scheme. The instructions have been updated with this new info, so you may skip this if you wish.

When trying to download the newest IPA, you may have noticed that the Fullscreen version is gone. I want to assure you that it is intentional. Now, the regular IPA (Fortnite-XX.XX) will include both the fullscreen patch for Mac and document browser support. This change was made because now I have my own IPA extraction method. This means I can now guarantee that our IPAs are fully clean. The reason I provided two separate IPAs before was because I wanted to give you the IPA as I found it, without any junk. Now, there will still be two IPAs: the modified one with the tweaks made above, and another one called Fortnite-XX.XX_clean.ipa. This clean IPA will come straight from source, which means it won't have any modifications. Using this one isn't recommended because it still contains device restrictions and it may not work, but if you want to modify it yourself and want the peace of mind that the IPA isn't tweaked at all, you can download this one.

You might also have noticed that in the IPA list on FnMacAssistant, you can now find the Fall Guys IPA. This was added because I decided to also upload the Fall Guys IPA, and since FnMacAssistant is programmed to check for any IPA under the releases page, it now also appears on the app. The Fall Guys IPAs will follow the same scheme that the Fortnite ones, meaning that the regular one will contain the tweaks mentioned above, and the clean one will come straight from source, with no tweaks made whatsoever. Unlike Fortnite, Fall Guys doesn't need patching and can be installed through PlayCover, and it can also be installed on iOS outside the EU for free. The recommended method for installing on iOS is to use LiveContainer, because since the IPA is so heavy, some sideloading apps might fail when installing it. On LiveContainer, you don't need to install the app. Just import the IPA, and you're ready to play. Here's a tutorial on how to install LiveContainer: You can find a tutorial on how to install LiveContainer [Here](https://youtu.be/7LV27FKGa0I?si=xMjDkK2aSY-da9p7)

The IPA file containing the announcement was made due to the absence of a proper announcements feature in the app, and will be removed in a week. 

Those were all the changes made to the FnMacAssistant app. I want to thank you all for your trust and hope that these new changes will be able to move the community forward. Thank you!
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
 
5. Select your desired IPA (Fullscreen or regular), and click the _Download IPA_ button to download it.

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
