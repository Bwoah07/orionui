local _, ns = ...
local RC = ns.RC
if not RC then return end -- standalone RaidControl is enabled
local AutoInvite = RC:NewModule("AutoInvite", "AceEvent-3.0")

function AutoInvite:OnInitialize()
    self.db = RC.db.profile
end

function AutoInvite:OnEnable()
    self:RegisterEvent("CHAT_MSG_WHISPER")
end

function AutoInvite:CHAT_MSG_WHISPER(event, text, playerName, _, _, _, _, _, _, _, _, _, _, _)
    if not self.db.enableAutoInvite then return end
    if not text or not playerName then return end

    -- Check if we are the leader or have assist (or if group doesn't exist yet)
    if IsInGroup() and not UnitIsGroupLeader("player") and not UnitIsGroupAssistant("player") then
        return
    end

    local keyword = self.db.autoInviteKeyword or "inv"
    if string.lower(text) == string.lower(keyword) then
        -- Don't invite if we are already in a full 40-man raid
        if GetNumGroupMembers() >= 40 then return end

        local restriction = self.db.inviteRestriction or "Anyone"
        local canInvite = false

        if restriction == "Anyone" then
            canInvite = true
        elseif restriction == "Guild Only" then
            if IsInGuild() then
                if C_GuildInfo and C_GuildInfo.GuildRoster then
                    C_GuildInfo.GuildRoster()
                end
                for i = 1, GetNumGuildMembers() do
                    local name = GetGuildRosterInfo(i)
                    if name then
                        -- playerName usually includes realm, so strip realm for local players or match full string
                        local shortName = string.split("-", name)
                        local whisperShort = string.split("-", playerName)
                        if string.lower(name) == string.lower(playerName) or string.lower(shortName) == string.lower(whisperShort) then
                            canInvite = true
                            break
                        end
                    end
                end
            end
        elseif restriction == "Friends Only" then
            -- Standard Friends
            if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
                for i = 1, C_FriendList.GetNumFriends() do
                    local info = C_FriendList.GetFriendInfoByIndex(i)
                    if info and info.name then
                        local shortName = string.split("-", info.name)
                        local whisperShort = string.split("-", playerName)
                        if string.lower(info.name) == string.lower(playerName) or string.lower(shortName) == string.lower(whisperShort) then
                            canInvite = true
                            break
                        end
                    end
                end
            end

            -- Battle.net Friends
            if not canInvite and BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
                for i = 1, BNGetNumFriends() do
                    local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
                    if accountInfo and accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.characterName then
                        local bnetCharName = accountInfo.gameAccountInfo.characterName
                        local whisperShort = string.split("-", playerName)
                        if string.lower(bnetCharName) == string.lower(whisperShort) then
                            canInvite = true
                            break
                        end
                    end
                end
            end
        end

        if canInvite then
            RC:InviteGroupMember(playerName)
            if self.db.autoConvertKeywordInvites and not IsInRaid() and IsInGroup() and UnitIsGroupLeader("player") and C_PartyInfo and C_PartyInfo.ConvertToRaid then
                C_Timer.After(0.5, function()
                    if AutoInvite.db.autoConvertKeywordInvites and IsInGroup() and not IsInRaid() and UnitIsGroupLeader("player") then
                        local allowed = true
                        if C_PartyInfo.AllowedToDoPartyConversion then
                            local ok, result = pcall(C_PartyInfo.AllowedToDoPartyConversion, true)
                            allowed = ok and result == true
                        end
                        if allowed then
                            pcall(C_PartyInfo.ConvertToRaid)
                        end
                    end
                end)
            end
        end
    end
end
