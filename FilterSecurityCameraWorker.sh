#!/bin/bash

# Worker script invoked by the compiled AppleScript inside Revisor.scptd.
# Arguments: <message-id> <account-name>
#
# Behavior:
# 1) Save all attachments from the Mail message into a temporary folder
# 2) For each attachment, run the bundled FilterSecurityCamera binary (human-detection)
# 3) If no person is detected in any attachment, move the message to the Trash
#
# The script locates the bundled binary relative to this script's location so
# it works both in-repo and when installed inside the script bundle's Resources.
MSG_ID=$1
ACCOUNT_NAME=$2
TEMP_DIR="$HOME/Downloads/.tmp/revisor_temp_$MSG_ID"
# Resolve the directory this script lives in (bundle Resources folder when installed).
WORKER_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_PATH="$WORKER_DIR/FilterSecurityCamera"

# If the bundled tool is missing or not executable, warn and continue (no-op behavior).
if [ ! -x "$TOOL_PATH" ]; then
    echo "Warning: FilterSecurityCamera not found or not executable at $TOOL_PATH" >&2
fi

# 1. Wait a moment for Mail to finish writing the database entry
sleep 2

# 2. Create a unique temp folder
mkdir -p "$TEMP_DIR"
# Allow the glob to expand to an empty list instead of the literal pattern
shopt -s nullglob

# 3. Tell Mail to save attachments via osascript (backgrounded)
osascript <<EOD
tell application "Mail"
    set theAccount to account "$ACCOUNT_NAME"
    set theMessage to first message of (mailbox "INBOX" of theAccount) whose id is $MSG_ID
    set theAttachments to every mail attachment of theMessage
    
    -- Convert POSIX path to HFS path for Mail sandbox
    set folderHFS to (POSIX file "$TEMP_DIR") as string
    
    repeat with eachAttachment in theAttachments
        set attachmentName to name of eachAttachment
        set savePath to folderHFS & attachmentName
        save eachAttachment in file savePath -- Added 'file' keyword
    end repeat
end tell
EOD

# 4. Wait for files to actually appear (handled by the system)
sleep 2

# 5. Process the images
PERSON_FOUND=false
for img in "$TEMP_DIR"/*; do
    if [ -f "$img" ]; then
        if "$TOOL_PATH" -h "$img"; then
            PERSON_FOUND=true
            break
        fi
    fi
done

# 6. If no person was found, tell Mail to trash it
if [ "$PERSON_FOUND" = false ]; then
    osascript <<EOD
    tell application "Mail"
		set theAccount to account "$ACCOUNT_NAME"
		set theMessage to first message of (mailbox "INBOX" of theAccount) whose id is $MSG_ID
        set read status of theMessage to true
        move theMessage to mailbox "Trash" of theAccount
    end tell
EOD
fi

# 7. Clean up
rm -rf "$TEMP_DIR"
