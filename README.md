# FnMacAssistant
Welcome to FnMacAssistant! An easy to use assistant that helps you download the latest Fortnite IPA and applies the necessary patches for it to work properly.<br>
<img width="612" alt="Picture of FnMacAssistant v1.0" src="https://github.com/user-attachments/assets/df141825-7a77-4c31-a0e0-d2724364dca2">

<h2>Discord</h2>
Join the official Fortnite Mac discord here: https://discord.gg/nfEBGJBfHD

<h2>Buy me a coffee</h2>
If you found this program useful and want to support me, buy me a coffee! 
<br/><br/>
<a href="https://www.buymeacoffee.com/Isacucho" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-orange.png" alt="Buy Me A Coffee" height="41" width="174"></a>

<h2>Requirments:</h2> 
Have Sideloadly installed on your mac <br/>
Mac must be on MacOS 15.1 or later <br/>
A mac with an M series chip. (Fortnite mobile will never work on an Intel Mac)

<h2>Instructions:</h2>

1. Download and install [Sideloadly](https://sideloadly.io)

2. Download the newest version of the FnMacAssistant App from [Releases](https://github.com/isacucho/FnMacAssistant/releases) and unzip it. (if you have python knowledge, you can use the python version by cloning this repository) 

3. You should now have an app called FnMacAssistant on your downloads folder. Double-click to open it.
 
4. Select your desired IPA, and click the _Download IPA_ button to download it. <br>
(To check the differences between the different IPAs, click [here](https://github.com/isacucho/FnMacAssistant/edit/main/README.md#fnmacassistant).

5. Go to sideloadly and sideload the downloaded IPA (the IPA will be saved to your _Downloads_ folder.

6. Open the Fortnite app. It should crash after a few seconds.

7. Return to FnMacAssistant and click on the _Patch App_ button. (This will patch the embedded.mobileprovision to _/Applications/Fortnite.app/Wrapper/FortniteClient-IOS-Shipping.app_, and remove old app if it exists)

8. Open fortnite and enjoy!


<h2>FAQ</h2>

<h3>How do I update the game?</h3>
1. Download the updated IPA from your preffered source (FnMacAssistant, the website, etc.)<br>
2. Install the newest IPA with the same Apple ID you installed the last version. <br>
3. Open the "Fortnite-1" app, or enable 'Update Skip' if on the newest version. Make sure you open it before patching. Don't attempt to patch first as it will not work.<br>
 (Make sure you only have Fortnite and Fortnite-1. If you have more than one duplicate delete all of them and install again)<br>
4. Allow Fortnite-x to be used for testing purposes through System Settings > Privacy & Security if prompted.<br>
5. Patch the app.<br>
6. Fortnite-1 should "delete and merge" itself with the existing Fortnite install, open it, and you should be good to go.<br>


<h3>Error: “Fortnite” cannot be opened because the developer did not intend for it to be run on this Mac.</h3>


If you get this message, do the following steps:
1. delete fortnite.app from your applications folder
2. Install the Fortnite IPA again using sideloadly
3. Open Fortnite. You should see the Epic Games logo for a few seconds, then the app will crash.
4. Go to FnMacAssistant and press the 'Patch App' button.
5. Open Fortnite again. This time it shouldn't crash!


<h3>Error: _Failed to patch the app: [Errno 1] Operation not permitted_</h3>
If you get this error message, you may need to give the FnMacAssistant additional permitions. 

1. Go to System Settings > Privacy & Security > App Management.
2. Click on the plus sign.
3. Add the FnMacAssistant app.
4. Restart the app and try to patch again.

Doing this should fix your issue and you should successfuly be able to patch Fortnite. 

<h3>Fortnite keeps crashing even after patching</h3>
This usually means that you're MacOS version is not supported. Please update your mac and try again.

<br><br>

If you still get the same message after following this steps, contact me on Discord: _@isacucho_ and I'll do my best to help!




<h2>Credits:</h2>
LrdSnow for the help with extracting the IPAs
Drohy for the inspiration to make this app. https://github.com/Drohy/FortniteMAC
