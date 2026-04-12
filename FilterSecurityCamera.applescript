using terms from application "Mail"
    on perform mail action with messages theMessages for rule theRule
        
        -- Revisor AppleScript entrypoint (compiled into Revisor.scptd).
        -- Locate the bundled worker script inside the script bundle's Resources folder.
        set workerName to "FilterSecurityCameraWorker.sh"
        try
            -- POSIX path of (path to resource "") is the Resources folder when running
            -- from a compiled script bundle. Build the full worker path from that folder.
            set resourceFolder to POSIX path of (path to resource "")
            set workerPath to resourceFolder & workerName
        on error
            display notification "Cannot find " & workerName & " in bundle!" with title "Revisor Error"
            return
        end try

        tell application "Mail"
            repeat with eachMessage in theMessages
                try
                    set msgID to id of eachMessage
                    set accName to name of account of mailbox of eachMessage
                    
                    -- Construct the command
                    set cmd to quoted form of workerPath & " " & msgID & " " & (quoted form of accName) & " > /dev/null 2>&1 &"
                    
                    do shell script cmd
                    
                on error errMsg
                    display notification "Handoff failed: " & errMsg with title "Revisor"
                end try
            end repeat
        end tell
    end perform mail action with messages
end using terms from
