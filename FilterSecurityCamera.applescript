using terms from application "Mail"
    on perform mail action with messages theMessages for rule theRule
        set homeDir to (system attribute "HOME")
        set workDir to homeDir & "/Downloads/.tmp"
        set queueFile to workDir & "/revisor.queue"
        set logFile to workDir & "/revisor.log"
        do shell script "mkdir -p " & quoted form of workDir & " >> " & quoted form of logFile & " 2>&1"

        tell application "Mail"
            repeat with eachMessage in theMessages
                set msgID to message id of eachMessage
                set mboxName to name of mailbox of eachMessage
                set accName to name of account of mailbox of eachMessage
                
                -- Append: message_id|mailbox_name|account_name
                set queueLine to msgID & "|" & mboxName & "|" & accName
                do shell script "echo " & quoted form of queueLine & " >> " & queueFile
            end repeat
        end tell
        
        -- Dynamically locate and trigger the worker inside the .scptd bundle
        set workerName to "FilterSecurityCameraWorker.sh"
        try
            tell me to set workerPath to POSIX path of (path to resource workerName)
            do shell script quoted form of workerPath & " >> " & quoted form of logFile & " 2>&1 &"
        on error errMsg
            display notification "Cannot find worker in bundle: " & errMsg with title "Revisor Error"
        end try
        
    end perform mail action with messages
end using terms from
