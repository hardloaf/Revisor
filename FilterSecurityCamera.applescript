using terms from application "Mail"
    on perform mail action with messages theMessages for rule theRule
        
        -- Revisor AppleScript entrypoint (compiled into Revisor.scptd).
        -- Locate the bundled worker script inside the script bundle's Resources folder.
        set workerName to "FilterSecurityCameraWorker.sh"
        try
            -- POSIX path of (path to resource "") is the Resources folder when running
            -- from a compiled script bundle. Build the full worker path from that folder.
            -- set resourceFolder to POSIX path of (path to resource "")
            set workerPath to POSIX path of (path to resource workerName)
        on error
            my appendLog("Cannot find " & workerName & " in bundle!")
            display notification "Cannot find " & workerName & " in bundle!" with title "Revisor Error"
            return
        end try
        
        my appendLog("AppleScript invoked. workerPath: " & workerPath)
        tell application "Mail"
            repeat with eachMessage in theMessages
                try
                    set msgID to message id of eachMessage
                    set accName to name of account of mailbox of eachMessage
                    
                    -- Construct the command
                    set cmd to quoted form of workerPath & " " & msgID & " " & (quoted form of accName) & " > /dev/null 2>&1 &"
                    my appendLog("Launching worker: " & cmd)
                    do shell script cmd
                    my appendLog("Launched worker for message " & msgID)
                    
                on error errMsg
                    my appendLog("Handoff failed: " & errMsg)
                    display notification "Handoff failed: " & errMsg with title "Revisor"
                end try
            end repeat
        end tell
    end perform mail action with messages

    on appendLog(msg)
        try
            -- Strict logging to /var/log/revisor.log only. If the script cannot write there
            -- the log attempt will be silently ignored.
            set logMsg to "[AppleScript] " & msg
            set shCmd to "sh -lc " & quoted form of ("ts=$(date +\"%Y-%m-%d %H:%M:%S%z\"); echo " & quoted form of logMsg & " >> /var/log/revisor.log 2>/dev/null")
            do shell script shCmd
        end try
    end appendLog
end using terms from
