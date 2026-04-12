using terms from application "Mail"
    on perform mail action with messages theMessages for rule theRule
        tell application "Mail"
            repeat with eachMessage in theMessages
                try
                    -- Get the unique Message ID
                    set msgID to id of eachMessage
                    
                    -- Get the Account Name using the robust 'mailbox' path
                    -- This avoids the -1728 error in 'All Mail' or 'Smart Mailboxes'
                    set accName to name of account of mailbox of eachMessage
                    
                    -- Fire and Forget: 
                    -- We hand off the ID and Account Name to the bash script and exit immediately.
                    -- The '>' and '&' at the end ensure it runs in the background.
                    do shell script "$HOME/Library/Application Scripts/com.apple.mail/FilterSecurityCameraWorker.sh " & msgID & " " & (quoted form of accName) & " > /dev/null 2>&1 &"
                    
                on error errMsg
                    -- If the handoff fails, log it to a notification for debugging
                    display notification "Rule Error: " & errMsg with title "Revisor"
                end try
            end repeat
        end tell
    end perform mail action with messages
end using terms from