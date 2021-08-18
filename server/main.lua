local Categories = {}
local Vehicles = {}
local shopLoading = true

Citizen.CreateThread(function()
    Categories = exports.ghmattimysql:executeSync("SELECT * FROM vehicle_categories ORDER BY label ASC")
    local vehicles = exports.ghmattimysql:executeSync("SELECT * FROM vehicles")
    for i = 1, #vehicles, 1 do
        local vehicle = vehicles[i]
        vehicle.loaded = false
        for j = 1, #Categories, 1 do
            if Categories[j].name == vehicle.category then
                vehicle.categoryLabel = Categories[j].label
                break
            end
        end
        if (vehicle.hash == "" or vehicle.hash == "0") then
            vehicle.hash = GetHashKey(vehicle.model)
            exports.ghmattimysql:execute("UPDATE vehicles SET hash = @hash WHERE model = @model",
                    {
                        ["@hash"] = vehicle.hash,
                        ["@model"] = vehicle.model
                    }
                )
        end
        Vehicles[tostring(vehicle.hash)] = vehicle
    end
    -- send information after db has loaded, making sure everyone gets vehicle information
    TriggerClientEvent("otaku_vehicleshop:sendCategories", -1, Categories)
    TriggerClientEvent("otaku_vehicleshop:sendVehicles", -1, Vehicles)
    shopLoading = false
end)

function RemoveOwnedVehicle(plate)
    exports.ghmattimysql:execute("DELETE FROM player_vehicles WHERE plate = @plate", { ["@plate"] = plate } )
end

RegisterServerEvent("otaku_vehicleshop:setVehicleOwned")
AddEventHandler("otaku_vehicleshop:setVehicleOwned", function(vehicleProps)
	local xPlayer = QBCore.Functions.GetPlayer(source)
	local vehicleName = Vehicles[tostring(vehicleProps.model)].name

	exports.ghmattimysql:execute('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (@license, @citizenid, @vehicle, @hash, @mods, @plate, @state)',
	{
		['@license'] = xPlayer.PlayerData.license,
		['@citizenid'] = xPlayer.PlayerData.citizenid,
		['@vehicle'] = string.lower(vehicleName),
		['@hash'] = GetHashKey(Vehicles[tostring(vehicleProps.model)].name),
		['@mods'] = json.encode(vehicleProps),
		['@plate'] = vehicleProps.plate,
		['@state'] = 0

	},
	function(rowsChanged)
		TriggerClientEvent('QBCore:Notify', -1, "A vehicle with plate: " .. vehicleProps.plate .. " now belongs to you!")
	end)
end)

RegisterServerEvent("otaku_vehicleshop:setVehicleOwnedPlayerId")
AddEventHandler(
	"otaku_vehicleshop:setVehicleOwnedPlayerId",
	function(playerId, vehicleProps)
		local xPlayer = QBCore.Functions.GetPlayer(playerId)

		exports.ghmattimysql:execute(
			"INSERT INTO owned_vehicles (owner, plate, vehicle, vehiclename) VALUES (@owner, @plate, @vehicle, @vehiclename)",
			{
				["@owner"] = xPlayer.identifier,
				["@plate"] = vehicleProps.plate,
				["@vehicle"] = json.encode(vehicleProps),
				["@vehiclename"] = Vehicles[tostring(vehicleProps.model)].name
			},
			function(rowsChanged)
				TriggerClientEvent(
					"QBCore:Notify",
					playerId,
					"Vehicle Registration",
					_U("vehicle_belongs", vehicleProps.plate),
					"fas fa-car",
					"green",
					3
				)
			end
		)
	end
)

RegisterServerEvent("otaku_vehicleshop:addToList")
AddEventHandler(
	"otaku_vehicleshop:addToList",
	function(target, model, plate)
		local xPlayer, xTarget = QBCore.Functions.GetPlayer(source), QBCore.Functions.GetPlayer(target)
		local dateNow = os.date("%Y-%m-%d %H:%M")

		if xPlayer.job.name ~= "cardealer" then
			print(("otaku_vehicleshop: %s attempted to add a sold vehicle to list!"):format(xPlayer.identifier))
			return
		end

		exports.ghmattimysql:execute(
			"INSERT INTO vehicle_sold (client, model, plate, soldby, date) VALUES (@client, @model, @plate, @soldby, @date)",
			{
				["@client"] = xTarget.getName(),
				["@model"] = model,
				["@plate"] = plate,
				["@soldby"] = xPlayer.getName(),
				["@date"] = dateNow
			}
		)
	end
)

QBCore.Functions.CreateCallback(
	"otaku_vehicleshop:getCategories",
	function(source, cb)
		while shopLoading do
			Citizen.Wait(100)
		end

		cb(Categories)
	end
)

QBCore.Functions.CreateCallback(
	"otaku_vehicleshop:getVehicles",
	function(source, cb)
		while shopLoading do
			Citizen.Wait(100)
		end

		cb(Vehicles)
	end
)

function Round(value, numDecimalPlaces)
    if numDecimalPlaces then
        local power = 10^numDecimalPlaces
        return math.floor((value * power) + 0.5) / (power)
    else
        return math.floor(value + 0.5)
    end
end 

QBCore.Functions.CreateCallback(
	"otaku_vehicleshop:buyVehicle",
	function(source, cb, vehicleModel)
		local xPlayer = QBCore.Functions.GetPlayer(source)
		local vehicleData = nil

		for k, v in pairs(Vehicles) do
			if v.model == vehicleModel then
				vehicleData = v
				break
			end
		end

		if xPlayer.PlayerData.money["bank"] >= vehicleData.price then
			xPlayer.Functions.RemoveMoney("bank", vehicleData.price, "vehicle-bought-in-showroom")
			cb(true)
		else
			cb(false)
		end
	end
)

QBCore.Functions.CreateCallback(
	"otaku_vehicleshop:resellVehicle",
	function(source, cb, plate, model)
		local resellPrice = 0

		-- calculate the resell price
		for k, v in pairs(Vehicles) do
			if GetHashKey(v.model) == model then
				resellPrice = Round(v.price / 100 * Config.ResellPercentage)
				break
			end
		end

		if resellPrice == 0 then
			print(("otaku_vehicleshop: %s attempted to sell an unknown vehicle!"):format(GetPlayerIdentifiers(source)[1]))
			cb(false)
		end

		local xPlayer = QBCore.Functions.GetPlayer(source)

		exports.ghmattimysql.executeSync(
			"SELECT * FROM owned_vehicles WHERE owner = @owner AND @plate = plate",
			{
				["@owner"] = xPlayer.identifier,
				["@plate"] = plate
			},
			function(result)
				if result[1] then -- does the owner match?
					local vehicle = json.decode(result[1].vehicle)
					if vehicle.model == model then
						if vehicle.plate == plate then
							xPlayer.addAccountMoney("bank", resellPrice)
							RemoveOwnedVehicle(plate)

							cb(true)
						else
							print(("otaku_vehicleshop: %s attempted to sell an vehicle with plate mismatch!"):format(xPlayer.identifier))
							cb(false)
						end
					else
						print(("otaku_vehicleshop: %s attempted to sell an vehicle with model mismatch!"):format(xPlayer.identifier))
						cb(false)
					end
				else
					cb(false)
				end
			end
		)
	end
)

QBCore.Functions.CreateCallback("otaku_vehicleshop:isPlateTaken", function(source, cb, plate)
	exports.ghmattimysql.executeSync("SELECT * FROM owned_vehicles WHERE plate = @plate", { ["@plate"] = plate } ,function(result)
		cb(result[1] ~= nil)
	end)
end)

if Config.PoliceJob then
	QBCore.Functions.CreateCallback(
		"otaku_vehicleshop:retrieveJobVehicles",
		function(source, cb, type)
			local xPlayer = QBCore.Functions.GetPlayer(source)

			exports.ghmattimysql.executeSync(
				"SELECT * FROM owned_vehicles WHERE owner = @owner AND type = @type AND job = @job",
				{
					["@owner"] = xPlayer.identifier,
					["@type"] = type,
					["@job"] = xPlayer.job.name
				},
				function(result)
					cb(result)
				end
			)
		end
	)

	RegisterNetEvent("otaku_vehicleshop:setJobVehicleState")
	AddEventHandler(
		"otaku_vehicleshop:setJobVehicleState",
		function(plate, state)
			local xPlayer = QBCore.Functions.GetPlayer(source)

			exports.ghmattimysql:execute(
				"UPDATE owned_vehicles SET `stored` = @stored WHERE plate = @plate AND job = @job",
				{
					["@stored"] = state,
					["@plate"] = plate,
					["@job"] = xPlayer.job.name
				},
				function(rowsChanged)
					if rowsChanged == 0 then
						print(("[otaku_vehicleshop] [^3WARNING^7] %s exploited the garage!"):format(xPlayer.identifier))
					end
				end
			)
		end
	)
end
