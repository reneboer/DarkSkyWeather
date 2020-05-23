ABOUT = {
	NAME = "DarkSky Weather",
	VERSION = "1.8",
	DESCRIPTION = "DarkSky Weather plugin",
	AUTHOR = "Rene Boer"
}	
--[[

Alternative 1:
https://openweathermap.org/api


Version 0.1 2016-11-17 - Alpha version for testing
Version 0.2 2016-11-18 - Beta version for first AltUI App Store release
Version 0.3 2016-11-19 - Beta version with:
		automatic location setup by default - thanks @akbooer
		default icon fix - thanks @NikV
		state icons to reflect current weather - icons from icon8.com
Version 0.4 2016-11-26 - a few bug fixes and exposes more DarkSky variables - thanks @MikeYeager
Version 0.5 2019-03-23 - Added WindGust, uvIndex, Visibility
Version 0.7 2019-04-09 - Added Settings tab, Vera UI7 support, optimized request eliminating hourly data.
Version 0.8 2019-04-16 - Correction in trigger labels on .json file.
Version 0.9 2019-05-03 - Added display line selections.
Version 1.0 2019-05-08 - Optimize request removing response data we do not process.
						 Added selectable child devices. Inspired by akbooer Netatmo plugin. Thanks akbooer.
						 Changed all currently to start with Currently as prefix.
						 All variables use the Weather Service ID.
Version 1.2 2019-05-21 - Correction in D_DarkSkyWeather.json for new variables.
						 Settings variable type error fix.
Version 1.3 2019-05-21 - Correction in DisplayLine settings for new variables.
Version 1.4 2019-05-28 - Better DisplayLine update for multi variable child devices (wind,rain) as some could display previous pull data.
						 Added forecast LowTemp and forecast HighTemp.
						 Added ReportedUnits variable to show the units used for data.
Version 1.5 2020-03-06 - Added https protocol as it is no longer a value acceptable for API.
Version 1.6 2020-03-11 - Check for unsupported Vera models.
						 Code cleanup.
Version 1.7 2020-03-11 - Older Vera models user curl rather then http request.
Version 1.8 2020-05-23 - Added dewpoint child device.

Original author logread (aka LV999) up to version 0.4.

It is intended to capture and monitor select weather data
provided by DarkSky (formerly Forecast.io) under their general terms and conditions
available on the website https://darksky.net/dev/

It requires an API developer key that must be obtained from the website.

This program is free software: you can redistribute it and/or modify
it under the condition that it is for private or home usage and
this whole comment is reproduced in the source code file.
Commercial utilization is not authorized without the appropriate
written agreement from "reneboer", contact by PM on http://community.getvera.com/
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
--]]

-- plugin general variables
local https = require("ssl.https")
local ltn12 = require("ltn12")
local json = require("dkjson")

local SID_Weather 	= "urn:upnp-micasaverde-com:serviceId:Weather1"
local SID_Security 	= "urn:micasaverde-com:serviceId:SecuritySensor1"
local SID_Humid 	= "urn:micasaverde-com:serviceId:HumiditySensor1"
local SID_UV	 	= "urn:micasaverde-com:serviceId:LightSensor1"
local SID_HA	 	= "urn:micasaverde-com:serviceId:HaDevice1"
local SID_Baro 		= "urn:upnp-org:serviceId:BarometerSensor1"
local SID_Temp 		= "urn:upnp-org:serviceId:TemperatureSensor1"
local SID_Generic	= "urn:micasaverde-com:serviceId:GenericSensor1"
local SID_AltUI 	= "urn:upnp-org:serviceId:altui1"
local DS_urltemplate = "https://api.darksky.net/forecast/%s/%s,%s?lang=%s&units=%s&exclude=hourly,alerts"

local this_device = nil

-- these are the configuration and their default values
local DS = { 
	Key = "",
	Latitude = "",
	Longitude = "",
	Period = 1800,	-- data refresh interval in seconds
	Units = "auto",
	DispLine1 = 1,
	DispLine2 = 2,
	ForecastDays = 2,
	ChildDev = "",
	RainSensor = 0,  -- Can support rain alarm for US,CA,UK (for NL we could use buienradar).
	Language = "en", -- default language
	ProviderName = "DarkSky (formerly Forecast.io)", -- added for reference to data source
	ProviderURL = "https://darksky.net/dev/",
	IconsProvider = "Thanks to icons8 at https://icons8.com",
	Documentation = "https://github.com/reneboer/DarkSkyWeather/wiki",
	LogLevel = 1,
	Version = ABOUT.VERSION
}

local static_Vars = "ProviderName, ProviderURL, IconsProvider, Documentation, Version"

-- this is the table used to map DarkSky output elements with the plugin serviceIds and variables
local VariablesMap = {
	currently = { 
		["apparentTemperature"] = {variable = "CurrentApparentTemperature", decimal = 1, childKey = "A", childID = nil},
		["cloudCover"] = {variable = "CurrentCloudCover", multiplier = 100, childKey = "C", childID = nil},
		["dewPoint"] = {variable = "CurrentDewPoint", decimal = 1, childKey = "D", initVal = 0, childID = nil},
		["humidity"] = {variable = "CurrentHumidity", multiplier = 100, decimal = 0, childKey = "H", childID = nil},
		["icon"] = {variable = "icon"},
		["ozone"] = {variable = "CurrentOzone", childKey = "O", childID = nil},
		["uvIndex"] = {variable = "CurrentuvIndex", childKey = "U", childID = nil},
		["visibility"] = {variable = "CurrentVisibility", decimal = 3, childKey = "V", childID = nil},
		["precipIntensity"] = {variable = "CurrentPrecipIntensity"},
		["precipProbability"] = {variable = "CurrentPrecipProbability", multiplier = 100, childKey = "R", childID = nil},
		["precipType"] = {variable = "CurrentPrecipType"},
		["pressure"] = {variable = "CurrentPressure", decimal = 0, childKey = "P", childID = nil},
		["summary"] = {variable = "CurrentConditions"},
		["temperature"] = {variable = "CurrentTemperature", decimal = 1, childKey = "T", childID = nil},
		["time"] = {variable = "LastUpdate"},
		["windBearing"] =  {variable = "CurrentWindBearing"},
		["windSpeed"] = {variable = "CurrentWindSpeed", decimal = 1, childKey = "W", childID = nil},
		["windGust"] = {variable = "CurrentWindGust", decimal = 1}
	},
	forecast = { 
		["pressure"] = {variable = "Pressure", decimal = 0},
		["summary"] = {variable = "Conditions"},
		["ozone"] = {variable = "Ozone"},
		["uvIndex"] = {variable = "uvIndex"},
		["uvIndexTime"] = {variable = "uvIndexTime"},
		["visibility"] = {variable = "Visibility", decimal = 3},
		["precipIntensity"] = {variable = "PrecipIntensity"},
		["precipIntensityMax"] = {variable = "PrecipIntensityMax"},
		["precipIntensityMaxTime"] = {variable = "PrecipIntensityMaxTime"},
		["precipProbability"] = {variable = "PrecipProbability", multiplier = 100},
		["precipType"] = {variable = "PrecipType"},
		["temperatureMax"] = {variable = "MaxTemp", decimal = 1},
		["temperatureMaxTime"] = {variable = "MaxTempTime", decimal = 1},
		["temperatureMin"] = {variable = "MinTemp", decimal = 1},
		["temperatureMinTime"] = {variable = "MinTempTime", decimal = 1},
		["temperatureHigh"] = {variable = "HighTemp", decimal = 1},
		["temperatureHighTime"] = {variable = "HighTempTime", decimal = 1},
		["temperatureLow"] = {variable = "LowTemp", decimal = 1},
		["temperatureLowTime"] = {variable = "LowTempTime", decimal = 1},
		["apparentTemperatureMax"] = {variable = "ApparentMaxTemp", decimal = 1},
		["apparentTemperatureMaxTime"] = {variable = "ApparentMaxTempTime", decimal = 1},
		["apparentTemperatureMin"] = {variable = "ApparentMinTemp", decimal = 1},
		["apparentTemperatureMinTime"] = {variable = "ApparentMinTempTime", decimal = 1},
		["icon"] = {variable = "Icon"},
		["cloudCover"] = {variable = "CloudCover", multiplier = 100},
		["dewPoint"] = {variable = "DewPoint", decimal = 1},
		["humidity"] = {variable = "Humidity", multiplier = 100, decimal = 0},
		["windBearing"] =  {variable = "WindBearing"},
		["windSpeed"] = {variable = "WindSpeed", decimal = 1},
		["windGust"] = {variable = "WindGust", decimal = 1},
		["windGustTime"] = {variable = "WindGustTime"}
	},
	daily_summary = {variable = "WeekConditions"},
	flags_units = {variable = "ReportedUnits"}
}
-- Mapping of data to display in ALTUI DisplayLines 1 & 2.
-- Keep definitions in sync with JS code.
local DisplayMap = {
	[1] = {{ prefix = "", var = "CurrentConditions" }},
	[2] = {{ prefix = "Pressure: ", var = "CurrentPressure"}},
	[3] = {{ prefix = "Last update: ", var = "LastUpdate" }},
    [4] = {{ prefix = "Wind: ", var = "CurrentWindSpeed" },{ prefix = "Gust: ", var = "CurrentWindGust" },{ prefix = "Bearing: ", var = "CurrentWindBearing" }},
    [5] = {{ prefix = "Ozone: ", var = "CurrentOzone" },{ prefix = "UV Index: ", var = "CurrentuvIndex" }},
    [6] = {{ prefix = "Current Temperature: ", var = "CurrentTemperature" }},
    [7] = {{ prefix = "Apparent Temperature: ", var = "ApparentTemperature" }},
    [8] = {{ prefix = "Current Cloud Cover: ", var = "CurrentCloudCover" }},
    [9] = {{ prefix = "Precip: ", var = "CurrentPrecipType" },{ prefix = "Prob.: ", var = "CurrentPrecipProbability" },{ prefix = "Intensity: ", var = "CurrentPrecipIntensity" }},
    [10] = {{ prefix = "Humidity: ", var = "CurrentHumidity" },{ prefix = "Dew Point: ", var = "CurrentDewPoint" }}
}
-- for writing to Luup variables, need serviceId and variable name for each sensor type
-- for creating child devices also need device xml filename
local SensorInfo = setmetatable (
  {	
    ['A'] = { deviceXML = "D_TemperatureSensor1.xml", serviceId = SID_Temp, variable = "CurrentTemperature", name="Apparent Temp."},
    ['D'] = { deviceXML = "D_TemperatureSensor1.xml", serviceId = SID_Temp, variable = "CurrentTemperature", name="Dewpoint"},
    ['T'] = { deviceXML = "D_TemperatureSensor1.xml", serviceId = SID_Temp, variable = "CurrentTemperature", name="Temperature"},
    ['H'] = { deviceXML = "D_HumiditySensor1.xml", serviceId = SID_Humid, variable = "CurrentLevel", name="Humidity"},
    ['U'] = { deviceXML = "D_LightSensor1.xml", deviceJSON = "D_UVSensor1.json", serviceId = SID_UV, variable = "CurrentLevel", name="UV Index"},
    ['P'] = { deviceXML = "D_DarkSkyMetric.xml", serviceId = SID_Generic, variable = "CurrentLevel", icon = 1 , name="Pressure"},
    ['O'] = { deviceXML = "D_DarkSkyMetric.xml", serviceId = SID_Generic, variable = "CurrentLevel", icon = 2 , name="Ozone"},
    ['V'] = { deviceXML = "D_DarkSkyMetric.xml", serviceId = SID_Generic, variable = "CurrentLevel", icon = 3 , name="Visibility"},
    ['W'] = { deviceXML = "D_DarkSkyMetric.xml", serviceId = SID_Generic, variable = "CurrentLevel", icon = 4 , name="Wind"},
    ['R'] = { deviceXML = "D_DarkSkyMetric.xml", serviceId = SID_Generic, variable = "CurrentLevel", icon = 5 , name="Precipitation"}
  },
  {__index = function ()  -- default for everything else
      return { deviceXML = "D_DarkSkyMetric.xml", serviceId = SID_Generic, variable = "CurrentLevel"} 
    end
  }
)


---------------------------------------------------------------------------------------------
-- Utility functions
---------------------------------------------------------------------------------------------
local log
local var
local utils

-- API getting and setting variables and attributes from Vera more efficient.
local function varAPI()
	local def_sid, def_dev = '', 0
	
	local function _init(sid,dev)
		def_sid = sid
		def_dev = dev
	end
	
	-- Get variable value
	local function _get(name, sid, device)
		local value = luup.variable_get(sid or def_sid, name, tonumber(device or def_dev))
		return (value or '')
	end

	-- Get variable value as number type
	local function _getnum(name, sid, device)
		local value = luup.variable_get(sid or def_sid, name, tonumber(device or def_dev))
		local num = tonumber(value,10)
		return (num or 0)
	end
	
	-- Set variable value
	local function _set(name, value, sid, device)
		local sid = sid or def_sid
		local device = tonumber(device or def_dev)
		local old = luup.variable_get(sid, name, device)
		if (tostring(value) ~= tostring(old or '')) then 
			luup.variable_set(sid, name, value, device)
		end
	end

	-- create missing variable with default value or return existing
	local function _default(name, default, sid, device)
		local sid = sid or def_sid
		local device = tonumber(device or def_dev)
		local value = luup.variable_get(sid, name, device) 
		if (not value) then
			value = default	or ''
			luup.variable_set(sid, name, value, device)	
		end
		return value
	end
	
	-- Get an attribute value, try to return as number value if applicable
	local function _getattr(name, device)
		local value = luup.attr_get(name, tonumber(device or def_dev))
		local nv = tonumber(value,10)
		return (nv or value)
	end

	-- Set an attribute
	local function _setattr(name, value, device)
		local val = _getattr(name, device)
		if val ~= value then 
			luup.attr_set(name, value, tonumber(device or def_dev))
		end	
	end
	
	return {
		Get = _get,
		Set = _set,
		GetNumber = _getnum,
		Default = _default,
		GetAttribute = _getattr,
		SetAttribute = _setattr,
		Initialize = _init
	}
end

-- API to handle basic logging and debug messaging
local function logAPI()
local def_level = 1
local def_prefix = ''
local def_name = 'log'
local def_debug = false
local def_file = false
local max_length = 100
local onOpenLuup = false
local taskHandle = -1

	local function _update(level)
		if level > 100 then
			def_file = true
			def_debug = true
			def_level = 10
		elseif level > 10 then
			def_debug = true
			def_file = false
			def_level = 10
		else
			def_file = false
			def_debug = false
			def_level = level
		end
	end	

	local function _init(prefix, level,onol)
		_update(level)
		def_prefix = prefix
		def_name = prefix:gsub(" ","")
		onOpenLuup = onol
	end	
	
	-- Build loggin string safely up to given lenght. If only one string given, then do not format because of length limitations.
	local function prot_format(ln,str,...)
		local msg = ""
		if arg[1] then 
			_, msg = pcall(string.format, str, unpack(arg))
		else 
			msg = str or "no text"
		end 
		if ln > 0 then
			return msg:sub(1,ln)
		else
			return msg
		end	
	end	
	local function _log(...) 
		if (def_level >= 10) then
			luup.log(def_prefix .. ": " .. prot_format(max_length,...), 50) 
		end	
	end	
	
	local function _info(...) 
		if (def_level >= 8) then
			luup.log(def_prefix .. "_info: " .. prot_format(max_length,...), 8) 
		end	
	end	

	local function _warning(...) 
		if (def_level >= 2) then
			luup.log(def_prefix .. "_warning: " .. prot_format(max_length,...), 2) 
		end	
	end	

	local function _error(...) 
		if (def_level >= 1) then
			luup.log(def_prefix .. "_error: " .. prot_format(max_length,...), 1) 
		end	
	end	

	local function _debug(...)
		if def_debug then
			luup.log(def_prefix .. "_debug: " .. prot_format(-1,...), 50) 
		end	
	end
	
	-- Write to file for detailed analysis
	local function _logfile(...)
		if def_file then
			local fh = io.open("/tmp/log/"..def_name..".log","a")
			local msg = prot_format(-1,...)
			fh:write(msg)
			fh:write("\n")
			fh:close()
		end	
	end
	
	local function _devmessage(devID, isError, timeout, ...)
		local message =  prot_format(60,...)
		local status = isError and 2 or 4
		-- Standard device message cannot be erased. Need to do a reload if message w/o timeout need to be removed. Rely on caller to trigger that.
		if onOpenLuup then
			taskHandle = luup.task(message, status, def_prefix, taskHandle)
			if timeout ~= 0 then
				luup.call_delay("logAPI_clearTask", timeout, "", false)
			else
				taskHandle = -1
			end
		else
			luup.device_message(devID, status, message, timeout, def_prefix)
		end	
	end
	
	local function logAPI_clearTask()
		luup.task("", 4, def_prefix, taskHandle)
		taskHandle = -1
	end
	_G.logAPI_clearTask = logAPI_clearTask
	
	
	return {
		Initialize = _init,
		Error = _error,
		Warning = _warning,
		Info = _info,
		Log = _log,
		Debug = _debug,
		Update = _update,
		LogFile = _logfile,
		DeviceMessage = _devmessage
	}
end 

-- API to handle some Util functions
local function utilsAPI()
local _UI5 = 5
local _UI6 = 6
local _UI7 = 7
local _UI8 = 8
local _OpenLuup = 99

  local function _init()
  end  

  -- See what system we are running on, some Vera or OpenLuup
  local function _getui()
    if (luup.attr_get("openLuup",0) ~= nil) then
      return _OpenLuup
    else
      return luup.version_major
    end
    return _UI7
  end
  
  local function _getmemoryused()
    return math.floor(collectgarbage "count")         -- app's own memory usage in kB
  end
  
  local function _setluupfailure(status,devID)
    if (luup.version_major < 7) then status = status ~= 0 end        -- fix UI5 status type
    luup.set_failure(status,devID)
  end

  -- Luup Reload function for UI5,6 and 7
  local function _luup_reload()
    if (luup.version_major < 6) then 
      luup.call_action("urn:micasaverde-com:serviceId:HomeAutomationGateway1", "Reload", {}, 0)
    else
      luup.reload()
    end
  end
  
  return {
    Initialize = _init,
    ReloadLuup = _luup_reload,
    GetMemoryUsed = _getmemoryused,
    SetLuupFailure = _setluupfailure,
    GetUI = _getui,
    IsUI5 = _UI5,
    IsUI6 = _UI6,
    IsUI7 = _UI7,
    IsUI8 = _UI8,
    IsOpenLuup = _OpenLuup
  }
end 

-- Need wrapper for Vera UI7.31 to set protocol. Sadly tls1.2 is not supported on the Lite.
local function HttpsGet(strURL)
	if (utils.GetUI() ~= utils.IsOpenLuup) and (not luup.model) then
		-- Older try to user curl
		local bdy,cde,hdrs = 1, 200, nil
		local p = io.popen("curl -k -s -m 15 -o - '" .. strURL .. "'")
		local result = p:read("*a")
		p:close()
		return bdy,cde,hdrs,result
	else
		-- Newer veras we can use http module
		local result = {}
		local bdy,cde,hdrs,stts = https.request{
			url = strURL, 
			method = 'GET',
			protocol = "any",
			options =  {"all", "no_sslv2", "no_sslv3"},
            verify = "none",
			sink=ltn12.sink.table(result)
		}
		return bdy,cde,hdrs,table.concat(result)
	end
end


-- processes and parses the DS data into device variables 
local function setvariables(varmap, value, prefix)
	if not prefix then prefix = "" end
	if varmap.pattern then value = string.gsub(value, varmap.pattern, "") end
	if varmap.multiplier then value = value * varmap.multiplier end
	if varmap.decimal then value = math.floor(value * 10^varmap.decimal + .5) / 10^varmap.decimal end
	var.Set(prefix..varmap.variable, value, varmap.serviceId)
	if varmap.childID then -- we update the child device as well
		local c = varmap.childKey
		var.Set(SensorInfo[c].variable, value, SensorInfo[c].serviceId, varmap.childID)
		-- Set display values for generic sensors
		if c == "W" then
			luup.call_delay("DS_UpdateMultiDataItem",2,c..varmap.childID)
		elseif c == "R" then
			-- Value is new PrecipProbability, when more than 1% display other than just dray
			if value > 1 then
				luup.call_delay("DS_UpdateMultiDataItem",2,c..varmap.childID)
			else
				var.Set("DisplayLine1", "No Precipitation expected", SID_AltUI, varmap.childID)
				var.Set("DisplayLine2", "", SID_AltUI, varmap.childID)
			end
		else
			var.Set("DisplayLine1", value, SID_AltUI, varmap.childID)
		end
	end
--[[
		if DS.RainSensor == 1 then
			-- the option of a virtual rain sensor is on, so we set the rain flags based on the trigger levels
			log.Debug("DEBUG: IntensityTrigger = %d - ProbabilityTrigger = %d", DS.PrecipIntensityTrigger, DS.PrecipProbabilityTrigger) 
			if key == "currently_precipIntensity" and tonumber(value) >= tonumber(DS.PrecipIntensityTrigger)
				then rain_intensity_trigger = tonumber(value) >= tonumber(DS.PrecipIntensityTrigger) 
			elseif key == "currently_precipProbability" and tonumber(value) >= tonumber(DS.PrecipProbabilityTrigger)
				then rain_probability_trigger = tonumber(value) >= tonumber(DS.PrecipProbabilityTrigger) end
			end
	end
]]
end

-- Update a multi data item with a slide delay so all parameters are updated
function DS_UpdateMultiDataItem(data)
	local sf,ss = string.format, string.sub
	
	local item = ss(data,1,1)
	local ID = tonumber(ss(data,2))
	if item == "W" then
		log.Debug("Updating wind data for child device "..ID)
		local ws = var.GetNumber("CurrentWindSpeed")
		local wg = var.GetNumber("CurrentWindGust")
		local wb = var.GetNumber("CurrentWindBearing")
		var.Set("DisplayLine1", sf("Speed %.1f, Gust %.1f ",ws,wg), SID_AltUI, ID)
		var.Set("DisplayLine2", sf("Bearing %d ",wb), SID_AltUI, ID)
	elseif item == "R" then
		log.Debug("Updating rain data for child device "..ID)
		local pp = var.GetNumber("CurrentPrecipProbability")
		local pi = var.GetNumber("CurrentPrecipIntensity")
		local pt = var.Get("CurrentPrecipType")
		var.Set("DisplayLine1", sf("Type %s ",pt), SID_AltUI, ID)
		var.Set("DisplayLine2", sf("Probability %d%%, Intensity %.2f",pp,pi), SID_AltUI, ID)
	end
end

-- Parse the DS json raw weather information hierarchy.
local function extractloop(datatable)
	-- Get the currently values we are interested in.
	local curTab = datatable.currently
	if curTab then
	    for tkey, value in pairs(VariablesMap.currently) do
	        if curTab[tkey] then
	            setvariables(value,curTab[tkey])
	        else
	            log.Debug("Currently key not found %s",tkey)
				var.Set(value.variable, "", value.serviceId)
	        end     
		end
    else
        log.Warning("No currently data")
	end
	-- Get the forecast data the user wants
	if DS.ForecastDays > 0 then
		for fd = 1, DS.ForecastDays do
			local prefix = ""
			if fd == 1 then
				prefix = "Today"
			elseif fd == 2 then	
				prefix = "Tomorrow"
			else
				prefix = "Forecast."..fd.."."
			end
			local curDay = datatable.daily.data[fd]
			if curDay then
				for tkey, value in pairs(VariablesMap.forecast) do
					if curDay[tkey] then
						setvariables(value,curDay[tkey],prefix)
					else
						log.Debug("Daily %d key %s not found",fd,tkey)
						var.Set(prefix..value.variable, "", value.serviceId)
					end     
				end
			else
				log.Warning("No daily data for day "..fd)
			end
		end
	else
		log.Debug("No forecast data configured")
	end
	-- Get daily summary data
	if datatable.daily.summary then
		setvariables(VariablesMap.daily_summary,datatable.daily.summary)
	end	
	-- Get units data
	if datatable.flags.units then
		setvariables(VariablesMap.flags_units,datatable.flags.units)
	end	
end

-- Build display line based on user preference
local function displayLine(linenum)
	local tc, ti = table.concat, table.insert
	local txtTab = {}
	local dispIdx = var.GetNumber("DispLine"..linenum)
	if dispIdx ~= 0 then
		for k,v in ipairs(DisplayMap[dispIdx]) do
			local val = var.Get(v.var,v.sid)
			if val ~= '' then
				if v.var == "LastUpdate" then
					val = os.date("%c",val)
				end
				ti(txtTab, v.prefix .. val)
			end    
		end
		if #txtTab ~= 0 then
			var.Set("DisplayLine"..linenum, tc(txtTab, ", "), SID_AltUI) 
		else
			log.Warning("No information found for DisplayLine"..linenum)
		end    
	else
		log.Warning("No configuration set for DisplayLine"..linenum)
	end
end

-- call the DarkSky API with our key and location parameters and processes the weather data json if success
local function DS_GetData()
	if DS.Key ~= "" then
		local url = string.format(DS_urltemplate, DS.Key, DS.Latitude, DS.Longitude, DS.Language, DS.Units)
		-- See if user wants forecast, if not eliminate daily from request
		if DS.ForecastDays == 0 then url = url .. ",daily" end
		-- If there is no rain sensor we do not need minutely data
		if DS.RainSensor == 0 then url = url .. ",minutely" end
		log.Debug("calling DarkSky API with url = %s", url)
		local wdata, retcode, headers, res = HttpsGet(url)
		local err = (retcode ~=200)
		if err then -- something wrong happpened (website down, wrong key or location)
			res = nil -- to do: better error handling ?
			log.Error("DarkSky API call failed with http code = %s", tostring(retcode))
		else
			log.Debug(res)
			res, err = json.decode(res)
			if not (err == 225) then
				extractloop(res)
				-- Update display for ALTUI
				displayLine(1)
				displayLine(2)
			else 
				log.Error("DarkSky API json decode error = %s", tostring(err)) 
			end
		end
		return err
	else
		var.Set("DisplayLine1", "Complete settings first.", SID_AltUI)
		log.Error("DarkSky API key is not yet specified.") 
		return 403
	end
end

-- check if device configuration parameters are current
local function check_param_updates()
local tvalue

	for key, value in pairs(DS) do
		tvalue = var.Get(key)
		if string.find(static_Vars, key) and tvalue ~= value then
			-- reset the static device variables to their build-in default in case new version changed these   
			tvalue = ""
		end  
		if tvalue == "" then
			if key == "Latitude" and value == "" then -- new set up, initialize latitude from controller info
				value = var.GetAttribute("latitude", 0)
				DS[key] = value
			end
			if key == "Longitude" and value == "" then -- new set up, initialize longitude from controller info
				value = var.GetAttribute("longitude", 0)
				DS[key] = value
			end
			var.Set(key, value) -- device newly created... need to initialize variables
		else
			-- Convert to numeric if applicable
			local nv = tonumber(tvalue,10)
			tvalue = (nv or tvalue)
			if tvalue ~= value then DS[key] = tvalue end
		end
	end
end

-- poll DarkSky Weather on a periodic basis
function Weather_delay_callback()
	check_param_updates()
	luup.call_delay ("Weather_delay_callback", DS["Period"])
	DS_GetData() -- get DarkSky data
end

-- creates/initializes and registers the default Temperature & Humidity children devices
-- and the optional virtual rain sensor child device
local function createchildren()
	local childSensors = var.Get("ChildDev")
	local makeChild = {}
	if childSensors ~= "" then
		log.Debug("Looking to create child sensor devices for %s", childSensors)
		childSensors = childSensors ..","
		-- Look at currently definitions for sensors that can have a child.
 	    for tkey, value in pairs(VariablesMap.currently) do
			for c in childSensors:gmatch("%w,") do			-- looking for individual (uppercase) letters followed by comma.
				c = c:sub(1,1)
				if value.childKey == c then
					makeChild[c] = tkey
					break
				end
			end
		end
	else
		log.Info("No child sensor devices to create.")
	end
	
	local children = luup.chdev.start(this_device)
	for c, tkey in pairs(makeChild) do
		local sensor = VariablesMap.currently[tkey]
		local sensorInfo = SensorInfo[c]
		log.Debug("Adding sensor type %s for %s", c, tkey)
		-- Make unique altid so we can handle multiple plugins installed
		local altid = 'DSW'..c..this_device
		local name = "DSW-"..(sensorInfo.name or sensor.variable)
		local vartable = {
			SID_HA..",HideDeleteButton=1",
			sensorInfo.serviceId..","..sensorInfo.variable.."=0"
		}
		-- Add icon var to variables if set
		if sensorInfo.icon then
			table.insert(vartable, SID_Weather..",IconSet="..sensorInfo.icon)
		end

		log.Debug("Child device id " .. altid .. " (" .. name .. ")")
		luup.chdev.append(
			this_device, 						-- parent (this device)
			children, 							-- pointer from above "start" call
			altid,								-- child Alt ID
			name,								-- child device description 
			"", 								-- serviceId (keep blank for UI7 restart avoidance)
			sensorInfo.deviceXML,				-- device file for given device
			"",									-- Implementation file
			table.concat(vartable,"\n"),		-- parameters to set 
			embed,								-- child devices can go in any room or not
			false)								-- child devices is not hidden
	end
	luup.chdev.sync(this_device, children)
			
	-- When all child sensors are there, configure them
	local needReload = false
	for deviceNo, d in pairs (luup.devices) do	-- pick up the child device numbers from their IDs
		if d.device_num_parent == this_device then
			local c = string.sub(d.id,4,4)	-- childKey is in altid
			local tkey = makeChild[string.sub(d.id,4,4)]
			if tkey then
				local sensor = VariablesMap.currently[tkey]
				sensor.childID = deviceNo
				local sJson = SensorInfo[c].deviceJSON
				if sJson then	-- Set specific JSON (for UV Index device)
					log.Debug("updating device_json to %s for device %s",sJson, deviceNo)
					if var.GetAttribute("device_json", deviceNo) ~= sJson then
						var.SetAttribute("device_json", sJson, deviceNo)
						-- We need to reload to make change effective
						needReload = true
					end	
				end
			end
		end
	end	
	if needReload then luup.reload() end
end

-- Update the log level.
function DS_SetLogLevel(logLevel)
	local level = tonumber(logLevel,10) or 1
	var.Set("LogLevel", level)
	log.Update(level)
end

-- device init sequence, called from the device implementation file
function init(lul_device)
	this_device = lul_device
	log = logAPI()
	var = varAPI()
	utils = utilsAPI()
	var.Initialize(SID_Weather, this_device)
	var.Default("LogLevel", 1)
	log.Initialize(ABOUT.NAME, var.GetNumber("LogLevel"), (utils.GetUI() == utils.IsOpenLuup or utils.GetUI() == utils.IsUI5))
	log.Info("device startup")
	-- Does no longer run on Lite and older models as tlsv1.2 is required
--	if (utils.GetUI() ~= utils.IsOpenLuup) and (not luup.model) then
--		var.Set("DisplayLine1", "Vera model not supported.", SID_AltUI)
--		utils.SetLuupFailure(0, this_device)
--		return false, "Plug-in is not supported on this Vera.", ABOUT.NAME
--	end
	check_param_updates()
	createchildren(this_device)
	-- See if user disabled plug-in 
	if var.GetAttribute("disabled") == 1 then
		log.Warning("Init: Plug-in version - DISABLED")
		var.Set("DisplayLine2", "Disabled. ", SID_AltUI)
		-- Still create any child devices so we do not loose configurations.
		utils.SetLuupFailure(0, PlugIn.THIS_DEVICE)
		return true, "Plug-in disabled attribute set", ABOUT.NAME
	end
	luup.call_delay ("Weather_delay_callback", 15)
	log.Info("device started")
	return true, "OK", ABOUT.NAME
end
