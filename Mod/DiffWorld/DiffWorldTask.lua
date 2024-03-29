--[[
Title: Diff World Task
Author(s):  big, wxa
CreateDate: 2020.06.12
ModifyDate: 2021.08.09
Desc: DiffWorldTask
use the lib:
------------------------------------------------------------
local DiffWorldTask = NPL.load('(gl)Mod/DiffWorld/DiffWorldTask.lua')
------------------------------------------------------------
]]

-- bottles
local DiffWorldUI = NPL.load('./DiffWorldUI.lua')
local LocalServiceWorld = NPL.load("(gl)Mod/WorldShare/service/LocalService/LocalServiceWorld.lua")

-- libs
local BlockEngine = commonlib.gettable('MyCompany.Aries.Game.BlockEngine')
local CommandManager = commonlib.gettable('MyCompany.Aries.Game.CommandManager')
local SlashCommand = commonlib.gettable('MyCompany.Aries.SlashCommand.SlashCommand')
local lfs = commonlib.Files.GetLuaFileSystem()
local CommonLib = NPL.load('Mod/GeneralGameServerMod/CommonLib/CommonLib.lua')
local RPCVirtualConnection = NPL.load('Mod/GeneralGameServerMod/CommonLib/RPCVirtualConnection.lua')
local Desktop = commonlib.gettable('MyCompany.Aries.Creator.Game.Desktop')

-- service
local KeepworkServiceProject = NPL.load('(gl)Mod/WorldShare/service/KeepworkService/Project.lua')
local GitService = NPL.load('(gl)Mod/WorldShare/service/GitService.lua')
local LocalService = NPL.load('(gl)Mod/WorldShare/service/LocalService.lua')

local __rpc__ = commonlib.inherit(RPCVirtualConnection, {})
local __neuron_file__ = 'Mod/DiffWorld/DiffWorldTask.lua'
__rpc__:Property('RemoteNeuronFile', __neuron_file__) -- for client file
__rpc__:Property('LocalNeuronFile', __neuron_file__) -- for local file
CommonLib.AddPublicFile(__neuron_file__)
__rpc__:InitSingleton()

local DiffWorldTask = commonlib.inherit(commonlib.gettable('System.Core.ToolBase'), NPL.export())

local RegionSize = 512
local ChunkSize = 16

DiffWorldTask:Property('Local', true, 'IsLocal')

function DiffWorldTask:Register(...)
    __rpc__:Register(...)
end

function DiffWorldTask:Call(...)
    __rpc__:Call(...)
end

function DiffWorldTask:ctor()
    self:Reset()

    -- refresh data
    self:Register('DiffWorldRefreshRpc', function()
        self:Reset()
        self:StartClient()
    end)

    -- close client
    self:Register('DiffWorldCloseRpc', function()
        Desktop.ForceExit(false)
    end)

    -- Responsive compare world start
    self:Register('DiffWorldStartRpc', function(remote_regions)
        self:CompareRegion(remote_regions)

        return self.__regions__
    end)

    -- Responsive compare world finish
    self:Register('DiffWorldFinishRpc', function()
        self:DiffFinish(self.__diffs__)

        return self.__diffs__
    end)

    -- Response compare chunks information
    self:Register('DiffRegionChunkInfoRpc', function(data)
        return self:LoadRegionChunkInfo(
            self:GetRegion(data.region_key),
            data.chunk_generates
        )
    end)

    -- Response compare blocks
    self:Register('DiffRegionChunkBlockInfoRpc', function(data)
        local chunk = data.chunk

        local remoteBlocks = data.blocks
        local localBlocks = self:LoadRegionChunkBlockInfo(chunk)

        local regionKey = chunk.region_key
        local chunkKey = chunk.chunk_key

        local regions = self.__diffs__.__regions__

        local diffRegion = regions[regionKey] or {}
        regions[regionKey] = diffRegion

        local diffRegionChunk = diffRegion[chunkKey] or {}
        diffRegion[chunkKey] = diffRegionChunk

        -- compre blocks (local not exist and different block)
        for remoteBlockIndex, remoteBlock in pairs(remoteBlocks) do
            local localBlock = localBlocks[remoteBlockIndex]

            if not localBlock or
               localBlock.block_id ~= remoteBlock.block_id or
               localBlock.block_data ~= remoteBlock.block_data or
               localBlock.entity_data_md5 ~= remoteBlock.entity_data_md5 then

                local x, y, z = BlockEngine:FromSparseIndex(remoteBlockIndex)

                diffRegionChunk[remoteBlockIndex] = {
                    x = x,
                    y = y,
                    z = z,
                    remote_block_id = remoteBlock.block_id,
                    remote_block_data = remoteBlock.block_data,
                    remote_entity_data = remoteBlock.entity_data,
                    local_block_id = localBlock and localBlock.block_id,
                    local_block_data = localBlock and localBlock.block_data,
                    local_entity_data = localBlock and localBlock.entity_data,
                }
            end
        end

        -- compre blocks (remote not exist)
        for localBlockIndex, localBlock in pairs(localBlocks) do
            if not remoteBlocks[localBlockIndex] then
                local x, y, z = BlockEngine:FromSparseIndex(localBlockIndex)

                diffRegionChunk[localBlockIndex] = {
                    x = x,
                    y = y,
                    z = z,
                    local_block_id = localBlock.block_id,
                    local_block_data = localBlock.block_data,
                    local_entity_data = localBlock.entity_data,
                }
            end
        end

        return
    end)

    -- Set lead position
    self:Register('SetLeadRpc', function(block)
        if block and type(block) == 'table' then
            GameLogic.RunCommand(format('/goto %s %s %s', block.x, block.y, block.z))
        end
    end)
end

function DiffWorldTask:Reset()
    self.__regions__ = {}
    self.__diffs__ = {__regions__ = {}}
end

function DiffWorldTask:DownloadWorldById(pid, callback)
    if not callback or type(callback) ~= 'function' then
        return
    end

    local currentEnterWorld = GameLogic.GetFilters():apply_filters('store_get', 'world/currentEnterWorld')

    if not pid or type(pid) ~= 'number' then
        if currentEnterWorld and type(currentEnterWorld) == 'table' then
            pid = currentEnterWorld.kpProjectId
        end
    end

    KeepworkServiceProject:GetProject(pid, function(data, err)
        if not data or
           type(data) ~= 'table' or
           not data.name or
           not data.username or
           not data.world or
           not data.world.commitId then
            if callback and type(callback) == 'function' then
                callback(false)
            end

            return
        end

        Mod.WorldShare.MsgBox:Wait()

        LocalServiceWorld:DownLoadZipWorld(
            data.name,
            data.username,
            data.world.commitId,
            'temp/diff_world/',
            function(bSucceed)
                Mod.WorldShare.MsgBox:Close()

                callback(bSucceed, 'temp/diff_world/')
            end
        )
    end)
end

function DiffWorldTask:IsRemoteWorld()
    local world_directory = ParaWorld.GetWorldDirectory();
    return string.find(world_directory, "temp/diff_world/", 1, true);
end

function DiffWorldTask:GetRegion(key)
    self.__regions__[key] = self.__regions__[key] or {}
    return self.__regions__[key]
end

function DiffWorldTask:IsExistRegion(key)
    return self.__regions__[key] ~= nil;
end

function DiffWorldTask:UseSyncChunkMode()
    CommandManager:RunCommand("/property AsyncChunkMode false")
    CommandManager:RunCommand("/property UseAsyncLoadWorld false")
end

-- 获取所有区域信息
function DiffWorldTask:LoadAllRegionInfo()
    local directory = CommonLib.ToCanonicalFilePath(ParaWorld.GetWorldDirectory() .. '/blockWorld.lastsave')
    local entities = {}

    ParaIO.CreateDirectory(directory)

    for filename in lfs.dir(directory) do
        if string.match(filename, '%d+_%d+%.raw') then
            local region_x, region_z = string.match(filename, '(%d+)_(%d+)%.raw')
            local region_key = string.format('%s_%s', region_x, region_z)
            local region = self:GetRegion(region_key)

            region.region_key = region_key
            region.region_x = tonumber(region_x)
            region.region_z = tonumber(region_z)
            region.block_x = region.region_x * RegionSize
            region.block_z = region.region_z * RegionSize
            region.rawpath = CommonLib.ToCanonicalFilePath(directory .. '/' .. filename)
        elseif string.match(filename, '%d+_%d+%.region%.xml') then
            local region_key = string.match(filename, '(%d+_%d+)%.region%.xml')

            table.insert(
                entities,
                {
                    region_key = region_key,
                    xmlpath = CommonLib.ToCanonicalFilePath(directory .. '/' .. filename)
                }
            )
        end
    end

    for _, entity in ipairs(entities) do
        self:GetRegion(entity.region_key).xmlpath = entity.xmlpath
    end

    for _, region in pairs(self.__regions__) do
        region.rawmd5 = CommonLib.GetFileMD5(region.rawpath)
        region.xmlmd5 = CommonLib.GetFileMD5(region.xmlpath)
    end

    return self.__regions__
end

function DiffWorldTask:LoadRegion(region)
    CommandManager:RunCommand('/loadregion %s %s %s', region.block_x, 5, region.block_z);
end

function DiffWorldTask:StartServer(ip, port)
    CommonLib.StartNetServer(ip, port)

    self:UseSyncChunkMode()
    self:Reset()
    self:LoadAllRegionInfo()

    -- server 端为Local数据
    self:SetLocal(true)
end

function DiffWorldTask:StartClient(ip, port)
    __rpc__:SetNid(CommonLib.AddNPLRuntimeAddress(ip, port))

    self:UseSyncChunkMode()
    self:Reset()
    self:LoadAllRegionInfo()
    self:SetLocal(false)

    local key, region, diff_regions = nil, nil, {}

    local function NextDiffRegionInfo()
        key, region = next(self.__regions__, key)

        if not region then
            return self:Call('DiffWorldFinishRpc', nil, function(data)
                self:DiffFinish(data)
            end)
        end 

        if region.is_equal_rawmd5 and region.is_equal_xmlmd5 then 
            -- 完全一致 比较下一个区域
            NextDiffRegionInfo()
        else
            -- entity 或 block 不同
            self:DiffRegionChunkInfo(region, function()
                -- 对比完成
                NextDiffRegionInfo()
            end)
        end
    end

    self:Call('DiffWorldStartRpc', self.__regions__, function(remoteRegions)
        -- compare twice
        self:CompareRegion(remoteRegions)

        NextDiffRegionInfo()
    end)
end

function DiffWorldTask:CompareRegion(regions)
    for key, data in pairs(regions) do
        local region = self.__regions__[key]

        if not region then
            region = self:GetRegion(key)
            commonlib.partialcopy(region, data)

            region.rawmd5 = nil
            region.xmlmd5 = nil
        end

        region.is_equal_rawmd5 = region.rawmd5 == data.rawmd5
        region.is_equal_xmlmd5 = region.xmlmd5 == data.xmlmd5
    end
end

-- compare chunk
function DiffWorldTask:DiffRegionChunkInfo(region, callback)
    local localChunks = self:LoadRegionChunkInfo(region)
    local remoteChunks = nil
    local chunkKey = nil
    local localChunk = nil

    local function NextDiffRegionChunkInfo()
        chunkKey, localChunk = next(localChunks, chunkKey)

        if not localChunk then
            if callback and type(callback) == 'function' then
                callback()
            end

            return
        end

        local remoteChunk = remoteChunks[chunkKey] or {}

        -- skip equal
        if localChunk.chunk_md5 == remoteChunk.chunk_md5 then
            NextDiffRegionChunkInfo()
        else
            self:DiffRegionChunkBlockInfo(localChunk, function()
                NextDiffRegionChunkInfo()
            end)
        end
    end

    -- 保证两个世界chunk生成是一致的
    local data = {
        region_key = region.region_key,
        chunk_generates = {}
    }

    for chunkKey, chunk in pairs(localChunks) do
        data.chunk_generates[chunkKey] = chunk.is_generate
    end

    self:Call('DiffRegionChunkInfoRpc', data, function(chunks)
        remoteChunks = chunks

        -- for compare
        for remoteChunkKey, remoteChunk in pairs(remoteChunks) do
            local localChunk = localChunks[remoteChunkKey]

            if not localChunk.is_generate and remoteChunk.is_generate then
                self:GenerateChunk(localChunk.chunk_x, localChunk.chunk_z)

                local chunkV = ParaTerrain.GetMapChunkData(localChunk.chunk_x, localChunk.chunk_z, false, 0xffff)
                localChunk.chunk_md5 = CommonLib.MD5(chunkV)
            end
        end

        NextDiffRegionChunkInfo()
    end)
end

function DiffWorldTask:IsGenerateChunk(chunkX, chunkZ)
    local realChunk = GameLogic.GetWorld():GetChunk(chunkX, chunkZ, true)

    return  (realChunk and realChunk:GetTimeStamp() > 0) and true or false
end

function DiffWorldTask:GenerateChunk(chunkX, chunkZ)
    if self:IsGenerateChunk(chunkX, chunkZ) then
        return
    end

    local chunk = GameLogic.GetWorld():GetChunk(chunkX, chunkZ, true)

    GameLogic.GetBlockGenerator():GenerateChunk(chunk, chunkX, chunkZ, true)
end

function DiffWorldTask:LoadRegionChunkInfo(region, chunkGenerates)
    self:LoadRegion(region)

    local size = RegionSize / ChunkSize
    region.chunks = region.chunks or {}

    -- chunk is 16 * 16 * 256 cubic cylinder
    for i = 0, 31 do
        for j = 0, 31 do
            local chunkX = region.region_x * size + i
            local chunkZ = region.region_z * size + j
            local chunkKey = string.format('%s_%s', chunkX, chunkZ)

            if chunkGenerates and chunkGenerates[chunkKey] then
                self:GenerateChunk(chunkX, chunkZ)
            end

            local isGenerate = self:IsGenerateChunk(chunkX, chunkZ)
            local chunkV = isGenerate and ParaTerrain.GetMapChunkData(chunkX, chunkZ, false, 0xffff) or ''
            local chunkMd5 = CommonLib.MD5(chunkV)
            local chunk = region.chunks[chunkKey] or {}

            region.chunks[chunkKey] = chunk
            chunk.chunk_x = chunkX
            chunk.chunk_z = chunkZ
            chunk.chunk_md5 = chunkMd5
            chunk.chunk_key = chunkKey

            chunk.is_equal_rawmd5 = region.is_equal_rawmd5
            chunk.is_equal_xmlmd5 = region.is_equal_xmlmd5
            chunk.region_key = region.region_key
            chunk.is_generate = isGenerate
        end
    end

    return region.chunks
end

-- compare blocks
function DiffWorldTask:DiffRegionChunkBlockInfo(chunk, callback)
    local blocks = self:LoadRegionChunkBlockInfo(chunk)

    self:Call(
        'DiffRegionChunkBlockInfoRpc',
        {
            chunk = chunk,
            blocks = blocks
        },
        function()
            if callback and type(callback) == 'function' then
                callback()
            end

            return
        end
    )
end

function DiffWorldTask:LoadRegionChunkBlockInfo(chunk)
    local isEqualRawmd5 = chunk.is_equal_rawmd5
    local isEqualXmlmd5 = chunk.is_equal_xmlmd5
    local startX = chunk.chunk_x * ChunkSize
    local startY = chunk.chunk_z * ChunkSize
    local blocks = {}

    -- 16(x) * 16(z) * 256(y) blocks
    for i = 0, 15 do
        for j = 0, 15 do
            local x = startX + i
            local z = startY + j

            for y = -128, 128 do
                local index = BlockEngine:GetSparseIndex(x, y, z)
                local blockId, blockData, entityData = BlockEngine:GetBlockFull(x, y, z)

                
                -- 无实体数据且方块相同则不同步
                if blockId and blockId ~= 0 then
                    entityData = entityData and commonlib.serialize_compact(entityData)
                    local entityDataMd5 = entityData and CommonLib.MD5(entityData)

                    if not isEqualRawmd5 or entityData then
                        blocks[index] = {
                            block_id = blockId,
                            block_data = blockData,
                            entity_data = entityData,
                            entity_data_md5 = entityDataMd5,
                        }
                    end
                end
            end
        end
    end

    return blocks
end

function DiffWorldTask:DiffFinish(diffs)
    local isLocal = self:IsLocal()

    if not self:IsRemoteWorld() then
        if not DiffWorldUI.diffWorldTask then
            DiffWorldUI:Show(isLocal, diffs)
            DiffWorldUI.diffWorldTask = self
        else
            DiffWorldUI:RefreshDataCallback(isLocal, diffs)
        end
    end
end

function DiffWorldTask:OnClose()
    self:Call('DiffWorldCloseRpc', nil, function()
        self:Reset()
    end)
end

NPL.this(function()
    __rpc__:OnActivate(msg)
end)
