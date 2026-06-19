local IslandData = {}

IslandData.Islands = {
    ["Sam"] = Vector3.new(-1282.53, 218.00, -1347.59),
    ["Fisher"] = Vector3.new(-1689.73, 216.00, -320.37),
    ["SectorG9"] = Vector3.new(-2681.07, 216.00, -943.29),
    ["MarineFord"] = Vector3.new(-3310.71, 300.75, -3286.47),
    ["Purple Island"] = Vector3.new(-5273.88, 519.50, -7845.15),
    ["Water tower"] = Vector3.new(-233.99, 226.00, -1026.76),
    ["WindMills"] = Vector3.new(65.12, 224.00, -35.69),
    ["OneHouse"] = Vector3.new(720.87, 241.00, 1214.81),
    ["restaurant"] = Vector3.new(1954.35, 218.00, 610.74),
    ["KingCrab"] = Vector3.new(1215.75, 243.00, -268.88),
    ["CaveIsland"] = Vector3.new(2052.59, 491.00, -656.71),
    ["BigTree"] = Vector3.new(2051.62, 288.00, -1871.25),
    ["Krizma Island"] = Vector3.new(-1072.04, 361.00, 1677.36),
    ["Gun Island"] = Vector3.new(-1846.41, 222.00, 3402.44),
    ["Accient Island"] = Vector3.new(-2721.82, 252.69, 1153.06),
    ["C Island"] = Vector3.new(2953.90, 217.00, 1394.13),
    ["Bar Island"] = Vector3.new(1481.25, 263.90, 2117.69),
    ["Anna House"] = Vector3.new(1118.05, 217.20, 3353.08),
    ["Crocodile Land"] = Vector3.new(948.70, 392.59, 5014.60),
    ["Three Tree"] = Vector3.new(-5703.31, 216.00, 123.44),
    ["Hole Land"] = Vector3.new(-10913.88, 551.00, 5063.75),
    ["Many Land"] = Vector3.new(-9258.29, 216.00, -3025.81),
    ["Haki Land"] = Vector3.new(-1002.16, 4010.97, 10158.25),
    ["Vokun Land"] = Vector3.new(4685.26, 217.00, 4817.13),
    ["BigSnow"] = Vector3.new(6275.28, 487.00, -1829.30),
}

IslandData.ShopNPCs = {
    ["Sniper Shop"] = Vector3.new(-1843.3797607421875, 221.99998474121094, 3409.400634765625),
    ["Sword Shop"] = Vector3.new(1005.53515625, 223.99998474121094, -3337.915283203125),
    ["Strange Dealer"] = Vector3.new(1240.8421630859375, 224.20001220703125, -3240.296875),
}

IslandData.QuestNPCs = {
    ["Daily Quest"] = Vector3.new(-2606.061279296875, 253.69842529296875, 1087.8436279296875),
    ["Sam Quest"] = Vector3.new(-1303.5345458984375, 217.99998474121094, -1352.5908203125),
    ["Krizma Sword"] = Vector3.new(-1074.173828125, 360.999694824219, 1666.887084969375),
    ["Mode Position"] = Vector3.new(2053.41552734375, 497.69830322265625, -614.63305640625),
}

IslandData.MiscNPCs = {
    ["Stats Fruit Roll"] = Vector3.new(801.1287231445312, 230.37062072753906, 5354.083984375),
    ["Roll Stats Fruit"] = Vector3.new(801.3805541992188, 230.37062072753906, 5353.8662109375),
}

function IslandData:GetIslandNames()
    local names = {"None"}
    for name in pairs(self.Islands) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

function IslandData:GetShopNames()
    local names = {"None"}
    for name in pairs(self.ShopNPCs) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

function IslandData:GetQuestNames()
    local names = {"None"}
    for name in pairs(self.QuestNPCs) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

function IslandData:GetMiscNames()
    local names = {"None"}
    for name in pairs(self.MiscNPCs) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

return IslandData