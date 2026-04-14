#!/bin/bash

# Define paths
WORK_DIR="$HOME/Downloads/.tmp"
QUEUE_FILE="${WORK_DIR}/revisor.queue"
LOCK_FILE="${WORK_DIR}/revisor.lock"
LOG_FILE="${WORK_DIR}/revisor.log"

# Assuming classify_image is also inside the bundle's Resources folder alongside this script
DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_PATH="$DIR/FilterSecurityCamera"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

# 1. SINGLETON LOCK (macOS Native)
# shlock checks if a valid process holds the lock. If not, it creates it with our PID ($$).
if ! shlock -f "$LOCK_FILE" -p $$; then
    log "Already running, let the active daemon handle the queue"
    exit 0 # Already running, let the active daemon handle the queue
fi

# Ensure the lock file is removed whenever this script exits (success or error)
trap 'rm -f "$LOCK_FILE"' EXIT

log "Daemon Started."

# 2. TRANSACTIONAL QUEUE LOOP
while [ -s "$QUEUE_FILE" ]; do
    
    # Peek at the top line
    LINE=$(head -n 1 "$QUEUE_FILE")
    [ -z "$LINE" ] && break

    # Extract exactly what the AppleScript provided
    MSG_ID=$(echo "$LINE" | cut -d'|' -f1)
    MBOX_NAME=$(echo "$LINE" | cut -d'|' -f2)
    ACC_NAME=$(echo "$LINE" | cut -d'|' -f3)
    
    TEMP_DIR="$WORK_DIR/revisor_$MSG_ID"
    mkdir -p "$TEMP_DIR" >> "$LOG_FILE" 2>&1

    log "Extracting: $MSG_ID from $MBOX_NAME ($ACC_NAME)"

    # 3. MAILBOX-SPECIFIC EXTRACTION
    RESULT=$(osascript <<EOD
    tell application "Mail"
        try
            set targetID to "$MSG_ID"
            set theAccount to account "$ACC_NAME"
            set mboxName to "$MBOX_NAME"
            set theMailbox to missing value
            
            -- Attempt 1: Standard top-level lookup (e.g., INBOX)
            try
                set theMailbox to mailbox mboxName of theAccount
            on error
                -- Attempt 2: Gmail nested lookup (e.g., [Gmail]/All Mail)
                try
                    set theMailbox to mailbox mboxName of mailbox "[Gmail]" of theAccount
                on error
                    return "ERROR: Could not resolve hierarchy for mailbox " & mboxName
                end try
            end try
            
            -- Strict lookup using the provided mailbox
            set foundMessages to (every message of theMailbox whose message id is targetID)
            if (count of foundMessages) = 0 then return "NOT_FOUND"
            
            set theMessage to item 1 of foundMessages
            
            -- Save attachments
            set folderHFS to (POSIX file "$TEMP_DIR") as string
            set theAttachments to every mail attachment of theMessage
            repeat with eachAttachment in theAttachments
                save eachAttachment in file (folderHFS & (name of eachAttachment))
            end repeat
            
            return "SUCCESS"
        on error errMsg
            return "ERROR: " & errMsg
        end try
    end tell
EOD
)

    # 4. PROCESS RESULT
    if [ "$RESULT" == "SUCCESS" ]; then
        KEEP=false
        
        # Check files and run Vision tool
        if [ "$(ls -A "$TEMP_DIR")" ]; then
            for img in "$TEMP_DIR"/*; do
                log "Process $img"
                "$TOOL_PATH" -h "$img" >> "$LOG_FILE" 2>&1
                STATUS=$?
                if [ $STATUS -eq 0 ]; then
                    KEEP=true
                    log "Person found. Keeping."
                    break
                elif [ $STATUS -eq 1 ]; then
                    KEEP=false
                    log "No person. Trashing."
                else
                    KEEP=true
                    log "Tool status: $STATUS. Keeping."
                    break
                fi
            done
        fi

        # Trashing logic using the specific mailbox path
        if [ "$KEEP" = false ]; then
            osascript <<EOD  >> "$LOG_FILE" 2>&1
            tell application "Mail"
                set targetID to "$MSG_ID"
                set theAccount to account "$ACC_NAME"
                set mboxName to "$MBOX_NAME"
                set theMailbox to missing value
                
                -- Attempt 1: Standard top-level lookup (e.g., INBOX)
                try
                    set theMailbox to mailbox mboxName of theAccount
                on error
                    -- Attempt 2: Gmail nested lookup (e.g., [Gmail]/All Mail)
                    try
                        set theMailbox to mailbox mboxName of mailbox "[Gmail]" of theAccount
                    on error
                        return "ERROR: Could not resolve hierarchy for mailbox " & mboxName
                    end try
                end try
                
                -- Strict lookup using the provided mailbox
                set foundMessages to (every message of theMailbox whose message id is targetID)
                if (count of foundMessages) = 0 then return
                
                set theMessage to item 1 of foundMessages
                set read status of theMessage to true
                move theMessage to mailbox "Trash" of account "$ACC_NAME"
            end tell
EOD
        fi

        # TRANSACTION SUCCESS: Remove the item from the queue
        sed -i '' '1d' "$QUEUE_FILE"
        rm -rf "$TEMP_DIR"
        log "Finished processing line."

    elif [ "$RESULT" == "NOT_FOUND" ]; then
        log "Message not yet indexed in $MBOX_NAME. Backing off."
        rm -rf "$TEMP_DIR"
        exit 0 # Exit daemon; let the next Mail trigger retry this line
    else
        log "AppleScript Failure: $RESULT"
        # On hard failure, we pop the queue so it doesn't block forever
        sed -i '' '1d' "$QUEUE_FILE"
        rm -rf "$TEMP_DIR"
    fi

    # Small gap to prevent saturating Mail's event loop between queue items
    sleep 1
done

log "Daemon Exiting (Queue Empty)."
