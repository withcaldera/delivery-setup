# Set up Claude Code with the Caldera delivery plugin (Mac)

> **Where this lives:** this guide and the setup script are in the public `withcaldera/delivery-setup`
> repo so the one-liner below works before you have any access. The plugin itself lives in the
> private `withcaldera/delivery-plugin` repo, which is why step 3 signs you in to GitHub.

This takes about **15 minutes** the first time (most of it waiting for Apple's download), and
you only do it once. You do not need to know how Terminal works; you paste one line and answer
a few prompts.

**Before you start**
- A Mac running macOS 13 or newer.
- Your Mac login password (Homebrew will ask for it once).
- A GitHub account that has been added to `withcaldera/delivery-plugin`. If you are not sure,
  ask Wade (wade.kallhoff@withcaldera.com) before you begin.
- The Claude desktop app installed, and a Claude account (sign in with your Caldera login).

## 1. Open Terminal

Press **Cmd + Space**, type `Terminal`, press **Enter**. A window with a blinking cursor opens.
That window is where you paste the command below. Everything else happens in dialogs and your
browser.

## 2. Paste this one line and press Enter

```
curl -fsSL https://raw.githubusercontent.com/withcaldera/delivery-setup/main/bootstrap.sh | bash
```

Terminal shows a short description of what will be installed and asks `Continue? [Y/n]`.
Press **Enter**.

The script checks seven things in order and prints a line for each: `✓` already there,
`→` installing now, `✗` something you need to act on. It never asks for your password itself
and never touches anything unrelated to this setup. If you run it again later it simply
re-checks and skips what is done.

## 3. What each prompt looks like and what to do

**Apple's Command Line Tools** (only if missing; 5-20 min)
A macOS window pops up: "The xcode-select command requires the command line developer tools.
Would you like to install the tools now?" Click **Install**, then **Agree**. A progress bar runs
for several minutes. Leave Terminal open; it prints dots while it waits and continues by itself
when Apple's installer finishes.

**Homebrew** (only if missing; 2-5 min)
Terminal prints a list of folders Homebrew will create and says `Press RETURN/ENTER to continue
or any other key to abort`. Press **Enter**. It then says `Password:` and asks for your **Mac
login password**. Nothing appears while you type (not even dots); that is normal. Type it and
press Enter.

**GitHub sign-in** (only if not already signed in; 1 min)
Terminal shows `! First copy your one-time code: XXXX-XXXX` and `Press Enter to open
github.com in your browser...`. Select and copy the code (Cmd + C), press **Enter**, and your
browser opens GitHub. Sign in if needed, paste the code, click **Continue**, then **Authorize
github**. Back in Terminal it says `✓ Logged in as <your username>`.

Right after that the script checks that your account can see the private plugin repo. If it
prints `✗ Your GitHub account (<name>) cannot read the private repo`, see Troubleshooting below;
nothing is broken, you just need access.

**Claude Code** (only if missing; 1 min)
No prompts. The script downloads the `claude` command into your home folder.

**Plugin registration** (30 s)
No prompts. The script records the Caldera marketplace in `~/.claude/settings.json` (a backup
copy `settings.json.bak` is kept) and installs the `delivery` plugin.

## 4. How to know it worked

The last thing printed is a **Summary** with a `✓` on every line, followed by **Next steps**.
Then:

1. Open the **Claude desktop app** (quit and reopen it if it was already open).
2. Open the **Code** tab and start a session in your project folder.
3. Type `/delivery:doctor` and press Enter. It checks the same things again from inside Claude
   and offers to fix anything that is off. All green means you are done.

You should also see `/delivery:ground`, `/delivery:decide` and the other delivery commands when
you type `/`.

## Troubleshooting

**"Your GitHub account (name) cannot read the private repo withcaldera/delivery-plugin"**
Your GitHub account has not been given access yet. Send your GitHub username (the name shown in
that message) to Wade (wade.kallhoff@withcaldera.com) and ask to be added to the repo. Once he
confirms, open Terminal and paste the one-liner from step 2 again; it skips everything that is
already done.

**`command not found: claude`**
The `claude` command was installed but this Terminal window was opened before that. Close the
Terminal window (Cmd + Q) and open a new one, then try again. The desktop app is unaffected.

**"…cannot be opened because the developer cannot be verified" / Gatekeeper**
macOS sometimes blocks a freshly downloaded program. Open **System Settings > Privacy &
Security**, scroll down, and click **Open Anyway** next to the message about the blocked app,
then re-run the one-liner. This is rare with the official installers this script uses.

**The Command Line Tools dialog never appeared, or says "Can't install the software"**
Open the App Store, install any pending macOS updates, restart, and re-run the one-liner. If
it still fails, open Terminal and run `xcode-select --install` by hand to see Apple's message.

**Homebrew asked for a password and rejected it**
It wants your Mac login password (the one you use to unlock the screen), not your Apple ID or
Caldera password. Nothing is shown while you type. Press Enter once when done.

**`/delivery:doctor` does not appear in the Claude app**
Quit the Claude app completely (Cmd + Q) and reopen it; plugins are picked up when a new
session starts. If it still does not appear, type `claude` in a new Terminal window, then
`/plugin`, and check the **Installed** tab for `delivery@caldera`. If it is missing, run the
one-liner again.

**I want to see what would change before running it**
Paste this instead; it only reports `OK` / `MISSING` for each item and changes nothing:

```
curl -fsSL https://raw.githubusercontent.com/withcaldera/delivery-setup/main/bootstrap.sh | bash -s -- --check
```

**Something else**
Copy the last 20 lines from Terminal and send them to Wade. The script is safe to re-run as many
times as needed.
