tell application "Mail"
	set selectedMessages to selection
	if (count of selectedMessages) is 0 then
		return "Please select an email first!"
	end if
	
	set theMessage to item 1 of selectedMessages
	set theID to id of theMessage
	
	-- Fix: Access the account through the mailbox hierarchy
	try
		set theAccountName to name of account of mailbox of theMessage
	on error
		-- Fallback if the above fails (sometimes happens in 'All Mail')
		set theAccountName to name of account of item 1 of accounts
		display notification "Could not determine account automatically. Using first account."
	end try
	
	return {theID, theAccountName}
end tell