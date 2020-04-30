local API = {
	Gui = {};
	Dialogue = {};
	Triggers = {};
	Player = {};
};

-- Roblox services
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local RunService = game:GetService("RunService");
local RemoteConnections = ReplicatedStorage:WaitForChild("DialogueMakerRemoteConnections");

local DefaultThemeName;
local SpeechBubbles = {};
local ClickDetectors = {};
local Events = {};

local DialogueSettings;
local NPC;
local RepsonseTemplate;

local RichTextAPI = require(script.RichText)

function API.Gui.GetDefaultThemeName()
	
	-- Check if the theme is in the cache
	if DefaultThemeName then
		return DefaultThemeName;
	end;
	
	-- Call up the server.
	return RemoteConnections.GetDefaultTheme:InvokeServer();
	
end;

function API.Gui.CreateNewDialogueGui(theme)
	
	local ThemeFolder = script.Parent.Themes;
	local DialogueGui;
	
	if theme and theme ~= "" then
		DialogueGui = ThemeFolder:FindFirstChild(theme);
		if not DialogueGui then
			warn("[Dialogue Maker] Can't find theme \""..theme.."\" in the Themes folder of the DialogueClientScript. Using default theme...");
		end;
	end;
	
	if not DialogueGui then
		DialogueGui = ThemeFolder:FindFirstChild(API.Gui.GetDefaultThemeName());
		if not DialogueGui then
			error("[Dialogue Maker] Default theme \""..API.GetDefaultThemeName().."\" couldn't be found in the themes folder.");
		end;
	end;
	
	return DialogueGui:Clone();
	
end;

function API.Triggers.AddSpeechBubble(npc, speechBubble)
	SpeechBubbles[npc] = speechBubble;
end;

function API.Triggers.CreateSpeechBubble(npc, properties)
	
	SpeechBubbles[npc] = Instance.new("BillboardGui");
	SpeechBubbles[npc].Name = "SpeechBubble";
	SpeechBubbles[npc].Active = true;
	SpeechBubbles[npc].LightInfluence = 0;
	SpeechBubbles[npc].ResetOnSpawn = false;
	SpeechBubbles[npc].Size = properties.SpeechBubbleSize;
	SpeechBubbles[npc].StudsOffset = properties.StudsOffset;
	SpeechBubbles[npc].Adornee = properties.SpeechBubblePart;
	
	local SpeechBubbleButton = Instance.new("ImageButton");
	SpeechBubbleButton.BackgroundTransparency = 1;
	SpeechBubbleButton.BorderSizePixel = 0;
	SpeechBubbleButton.Name = "SpeechBubbleButton";
	SpeechBubbleButton.Size = UDim2.new(1,0,1,0);
	SpeechBubbleButton.Image = properties.SpeechBubbleImage;
	SpeechBubbleButton.Parent = SpeechBubbles[npc];
	
	return SpeechBubbles[npc];
	
end;

function API.Triggers.DisableAllSpeechBubbles()
	for _, speechBubble in pairs(SpeechBubbles) do
		speechBubble.Enabled = false;
	end;
end;

function API.Triggers.EnableAllSpeechBubbles()
	for _, speechBubble in pairs(SpeechBubbles) do
		speechBubble.Enabled = true;
	end;
end;

function API.Triggers.AddClickDetector(npc, clickDetector)
	ClickDetectors[npc] = clickDetector;
end;

function API.Triggers.DisableAllClickDetectors()
	for _, clickDetector in pairs(ClickDetectors) do
		
		-- Keep track of the original parent
		local OriginalParentTag = Instance.new("ObjectValue");
		OriginalParentTag.Name = "OriginalParent"
		OriginalParentTag.Value = clickDetector.Parent;
		OriginalParentTag.Parent = clickDetector;
		
		clickDetector.Parent = nil;
		
	end;
end;

function API.Triggers.EnableAllClickDetectors()
	for _, clickDetector in pairs(ClickDetectors) do
		if clickDetector:FindFirstChild("OriginalParent") and clickDetector.OriginalParent:IsA("ObjectValue") and clickDetector.OriginalParent.Value then
			clickDetector.Parent = clickDetector.OriginalParent.Value;
			clickDetector.OriginalParent:Destroy();
		end;
	end;
end;

function API.Player.SetPlayer(player)
	API.Player.Player = player;
	API.Player.PlayerControls = require(player.PlayerScripts.PlayerModule):GetControls();
end;

function API.Player.FreezePlayer()
	API.Player.PlayerControls:Disable();
end;

function API.Player.UnfreezePlayer()
	API.Player.PlayerControls:Enable();
end;

function API.Dialogue.GoToDirectory(currentDirectory, targetPath)
	
	for index, directory in ipairs(targetPath) do
		if currentDirectory.Dialogue:FindFirstChild(directory) then
			currentDirectory = currentDirectory.Dialogue[directory];
		elseif currentDirectory.Responses:FindFirstChild(directory) then
			currentDirectory = currentDirectory.Responses[directory];
		elseif currentDirectory.Redirects:FindFirstChild(directory) then
			currentDirectory = currentDirectory.Redirects[directory];
		elseif currentDirectory:FindFirstChild(directory) then
			currentDirectory = currentDirectory[directory];
		end;
	end;
	
	return currentDirectory;
end;

function API.Dialogue.ReplaceVariablesWithValues(npc, text)
	
	for match in string.gmatch(text, "%[%/variable=([^%]]+)%]") do
				
		-- Get the match from the server
		local VariableValue = RemoteConnections.GetVariable:InvokeServer(npc, match);
		if VariableValue then
			text = text:gsub("%[%/variable=([^%]]+)%]",VariableValue);
		end;
		
	end;
	
	return text;
	
end;

function API.Dialogue.PlaySound(gui, messageType)
	
	if gui:FindFirstChild("DialogueClickSound") and gui.DialogueClickSound:IsA("Sound") then
		
		if messageType == "Message" then
			gui.MessageClickSound:Play();
		elseif messageType == "Response" then
			gui.ResponseClickSound:Play();
		end;
		
	end;
	
end;

function API.Dialogue.ClearResponses(responseContainer)
	for _, response in ipairs(responseContainer:GetChildren()) do
		if not response:IsA("UIListLayout") then
			response:Destroy();
		end;
	end;
end;

function API.Dialogue.SetNPC(npc)
	NPC = npc;
end

function API.Dialogue.SetDialogueSettings(dialogueSettings)
	DialogueSettings = dialogueSettings;
end;

function API.Dialogue.SetResponseTemplate(responseTemplate)
	ResponseTemplate = responseTemplate;
end

local WaitingForPlayerResponse = false;

function API.Dialogue.RunAnimation(textContainer, textContent, currentDirectory, responsesEnabled, dialoguePriority)
	
	local NPCTalking = false;
	local NPCPaused = false;
	local Skipped = false;
	local Text;
	local PlayerResponse;
	local FinishingOverflow = false;
	local WaitingForOverflow = false;
	
	local function SetTextContainerEvent(container)
		Events.DialogueClicked = container.Parent.InputBegan:Connect(function(input)
			
			-- Make sure the player clicked the frame
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				
				if NPCTalking then
					
					if NPCPaused and not FinishingOverflow then
						
						FinishingOverflow = true;
						
						if textContainer.Parent:FindFirstChild("ClickToContinue") then
							if DialogueSettings.AllowPlayerToSkipDelay then
								textContainer.Parent.ClickToContinue.Visible = true;
							else
								textContainer.Parent.ClickToContinue.Visible = false;
							end;
						end;
							
						API.Dialogue.PlaySound(textContainer.Parent.Parent, "Message");
							
						NPCPaused = false;
						Text = RichTextAPI:ContinueOverflow(textContainer, Text);
						Text:Animate(true);
						
						if Text.Overflown then
							NPCPaused = true;
						else
							WaitingForOverflow = false;
						end;
						
						if textContainer.Parent:FindFirstChild("ClickToContinue") then
							textContainer.Parent.ClickToContinue.Visible = true;
						end;
						
						FinishingOverflow = false;
							
						return;
						
					end;
					
					-- Check settings set by the developer
					if DialogueSettings.AllowPlayerToSkipDelay then
						
						-- Replace the incomplete dialogue with the full text
						API.Dialogue.PlaySound(textContainer.Parent.Parent, "Message");
						Text:Show(false);
						NPCPaused = true;
						
					end;
					
				elseif #currentDirectory.Responses:GetChildren() == 0 then
					WaitingForPlayerResponse = false;
					Events.DialogueClicked:Disconnect();
				end;
				
			end;
			
		end);
	end;
	
	Text = RichTextAPI:New(
		textContainer, 
		textContent, {
			ContainerVerticalAlignment = Enum.VerticalAlignment.Top;
			AnimateStepTime = DialogueSettings.LetterDelay;
		},
		false);
		
	WaitingForPlayerResponse = true;
	NPCTalking = true;
			
	textContainer.Visible = true;
	
	SetTextContainerEvent(textContainer);
		
	Text:Animate(true);
		
	if Text.Overflown then
		NPCPaused = true;
		WaitingForOverflow = true;
	end;
	
	while WaitingForOverflow do
		RunService.Heartbeat:Wait();
	end;
	
	NPCTalking = false;
	
	if responsesEnabled and #currentDirectory.Responses:GetChildren() ~= 0 then
		
		local ResponseContainer = textContainer.Parent.ResponseContainer;
		
		-- Add response buttons
		for _, response in ipairs(currentDirectory.Responses:GetChildren()) do
			if RemoteConnections.PlayerPassesCondition:InvokeServer(NPC, response, response.Priority.Value) then
				local ResponseButton = ResponseTemplate:Clone();
				ResponseButton.Name = "Response";
				ResponseButton.Text = response.Message.Value;
				ResponseButton.Parent = ResponseContainer;
				ResponseButton.MouseButton1Click:Connect(function()
					
					API.Dialogue.PlaySound(textContainer.Parent.Parent, "Response")
					
					ResponseContainer.Visible = false;
					
					PlayerResponse = response;
					
					if response.HasAfterAction.Value then
						RemoteConnections.ExecuteAction:InvokeServer(NPC, response, "After");
					end;
					
					WaitingForPlayerResponse = false;
					
				end);
			end;
		end;
		
		ResponseContainer.CanvasSize = UDim2.new(0,ResponseContainer.CanvasSize.X,0,ResponseContainer.UIListLayout.AbsoluteContentSize.Y);
		ResponseContainer.Visible = true;
		
	elseif textContainer.Parent:FindFirstChild("ClickToContinue") then
		textContainer.Parent.ClickToContinue.Visible = true;
	end;
	
	while WaitingForPlayerResponse do
		RunService.Heartbeat:Wait();
	end;
	
	if PlayerResponse then
		return {Response = PlayerResponse};
	end;
	
	return {};
	
end;

function API.Dialogue.PlayerResponded(response)
	
	WaitingForPlayerResponse = false;
	
end;

return API;
