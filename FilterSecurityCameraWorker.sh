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

# Logging target (strict): /var/log/revisor.log only. If not writable, logging is silent.
LOG_FILE="/var/log/revisor.log"

log() {
    ts="$(date +'%Y-%m-%d %H:%M:%S%z') $MSG_ID"
    # attempt to append to the log; suppress errors if file is not writable/doesn't exist
    echo "$ts [worker] $*" >> "$LOG_FILE" 2>/dev/null || true
}

log "Worker invoked. MSG_ID=$MSG_ID ACCOUNT_NAME=$ACCOUNT_NAME WORKER_DIR=$WORKER_DIR TOOL_PATH=$TOOL_PATH TEMP_DIR=$TEMP_DIR"

if [ ! -x "$TOOL_PATH" ]; then
    log "Warning: FilterSecurityCamera not found or not executable at $TOOL_PATH"
fi

mkdir -p "$TEMP_DIR"
# Allow the glob to expand to an empty list instead of the literal pattern
shopt -s nullglob

log "Created temp dir $TEMP_DIR"

MAX_RETRIES=3
RETRY_COUNT=0
SUCCESS=false

log "Starting attachment extraction for Message ID: $MSG_ID"

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    RETRY_COUNT=$((RETRY_COUNT + 1))

    # Run the osascript and capture exit status
    osascript <<EOD >> "$LOG_FILE" 2>&1
    tell application "Mail"
        try
            set theAccount to account "$ACCOUNT_NAME"
            -- set theMessage to first message of (mailbox "INBOX" of theAccount) whose message id is "$MSG_ID"
            repeat with theMailbox in mailboxes of theAccount
                try
                    set foundMessages to (every message of theMailbox whose message id is "$MSG_ID")
                    if (count of foundMessages) > 0 then
                        set theMessage to item 1 of foundMessages
                        exit repeat
                    end if
                end try
            end repeat
            set theAttachments to every mail attachment of theMessage
            
            -- Convert POSIX path to HFS path for Mail sandbox
            set folderHFS to (POSIX file "$TEMP_DIR") as string
            
            repeat with eachAttachment in theAttachments
                set attachmentName to name of eachAttachment
                set savePath to folderHFS & attachmentName
                save eachAttachment in file savePath
            end repeat
        on error errMsg
            -- If Mail fails, we exit with an error so Bash sees the failure
            error "AppleScript failed: " & errMsg
        end try
    end tell
EOD

    if [ $? -eq 0 ]; then
        log "Successfully saved attachments on attempt $RETRY_COUNT"
        SUCCESS=true
        break
    else
        log "Attempt $RETRY_COUNT failed. Retrying in 3s..."
        sleep 3
    fi
done

if [ "$SUCCESS" = false ]; then
    log "ERROR: Failed to save attachments after $MAX_RETRIES attempts. Exiting."
    rm -rf "$TEMP_DIR"
    exit 1
fi

count=$(ls -1 "$TEMP_DIR" 2>/dev/null | wc -l || true)
log "Attachment save complete. Files in $TEMP_DIR: $count"

DONT_MOVE=true
for img in "$TEMP_DIR"/*; do
    if [ -f "$img" ]; then
        log "Processing file $img"
        log "Running tool: $TOOL_PATH -h '$img'"
        "$TOOL_PATH" -h "$img" >>"$LOG_FILE" 2>&1
        status=$?
        log "Tool exit code $status for $img"
        if [ $status -eq 0 ]; then
            log "Match found in $img"
            DONT_MOVE=true
            break
        elif [ $status -eq 1 ]; then
            log "No match in $img"
            DONT_MOVE=false
        else
            log "Tool failed $img"
            DONT_MOVE=true
            break;
        fi
    fi
done

if [ "$DONT_MOVE" = false ]; then
    log "No person detected in any attachments; moving message to Trash"
    osascript <<EOD  >> "$LOG_FILE" 2>&1
    tell application "Mail"
        set theAccount to account "$ACCOUNT_NAME"
        -- set theMessage to first message of (mailbox "INBOX" of theAccount) whose message id is "$MSG_ID"
        repeat with theMailbox in mailboxes of theAccount
            try
                set foundMessages to (every message of theMailbox whose message id is "$MSG_ID")
                if (count of foundMessages) > 0 then
                    set theMessage to item 1 of foundMessages
                    exit repeat
                end if
            end try
        end repeat

        set read status of theMessage to true
        move theMessage to mailbox "Trash" of theAccount
    end tell
EOD
    if [ $? -eq 0 ]; then
        log "Message $MSG_ID moved to Trash"
    else
        log "Failed to move message $MSG_ID to Trash"
    fi
else
    log "Person detected; leaving message in mailbox"
fi

rm -rf "$TEMP_DIR"
log "Cleaned up temp dir $TEMP_DIR"
