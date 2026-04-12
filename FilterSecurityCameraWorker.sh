#!/bin/bash

# Arguments passed from AppleScript
MSG_ID=$1
ACCOUNT_NAME=$2
TEMP_DIR="$HOME/Downloads/.tmp/revisor_temp_$MSG_ID"
# Determine the directory this worker script lives in. When installed inside a script bundle
# this will be the bundle's Resources folder. Use that location to find the bundled tool.
WORKER_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_PATH="$$WORKER_DIR/FilterSecurityCamera"

# 1. Wait a moment for Mail to finish writing the database entry
sleep 2

# 2. Create a unique temp folder
mkdir -p "$TEMP_DIR"

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
