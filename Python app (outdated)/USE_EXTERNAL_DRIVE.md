# Fortnite on macOS — Using an External Drive or Custom Data Folder

This guide explains how to run **Fortnite on macOS** using a **custom data folder** (including an **external drive**) instead of the default macOS app container.

This setup relies on a **startup tweak** that allows Fortnite to request user permission to access a folder outside the sandbox container.

## Requirements

Make sure you have **all** of the following before starting:

- FnMacAssistant v1.5.0+
- FnMacTweak 1.0.3+
  - Fortnite ipa after version 39.11 will have FnMacTweak 1.0.3+. (Version 39.11 or earlier will not work without manual injection of the tweak)

## Step-by-Step

After installing Fortnite **normally** using **FnMacAssistant** and **Sideloadly**.

### 1. Configure the Folder in FnMacAssistant

<img width="612" height="540" alt="Screenshot of FnMacAssistant v1.5.0" src="https://github.com/user-attachments/assets/08308966-ddff-44e9-ac24-7590c843fed7" />

1. Make sure Fortnite was launched at least once after installation.
2. Open **FnMacAssistant** or Refresh the **Game Data** section.
3. On **Game Data** section, Click **Change**.
4. Select:
   - An **empty folder**, **or**
   - A folder that **already contains Fortnite data**.

> **Important:**
> The folder must be empty or already contain Fortnite data. Do not choose a folder with unrelated files.

5. FnMacAssistant will:
   - Move all game data to the selected folder
   - Create the required **symbolic link** automatically

---


### 2. Select the Custom / External Data Folder (In-Game)

<p align="center"><img width="443" height="368" alt="Screenshot of FnMacTweak v1.0.3" src="https://github.com/user-attachments/assets/37c26a6f-6be6-4e50-801c-0380e3f32049" /></p>

1. When Fortnite opens, press **`P`**.
2. A menu appears.
3. Click the purple button:
   **Select Data Folder**
4. Choose the location where you will give Fortnite permission to store data:
   - An external drive **or**
   - Any folder where you want Fortnite data stored
5. Click **Open**.
6. Fully Close Fortnite if it doesn’t close automatically.

> This grants macOS permission for Fortnite to access that folder and all inside it.

---

### 3. Import Archive (Optional)

If you do not have Fortnite downloaded game data yet, you can import an archive:

- You may use **Import Archive** **before or after** changing the data folder.
- Recommended: **after** setting the external/custom folder so imported data goes directly there.

---

## Result

- Fortnite runs normally on external storage or custom folder.
- Game data is stored:
  - Outside the default app container
  - In your chosen custom folder or external drive
- Permissions persist for future launches (as long as the folder doesn’t change).
  - If you change the folder again, do `Step 2` again to re-grant permission.

---

## Notes
- If you change the data folder again, macOS may ask for permission once more.
- An external SSD is recommended for best performance.