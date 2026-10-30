-- Ambiente inicial. Se mantiene deliberadamente moderado para no perjudicar móviles.
local Lighting = game:GetService("Lighting")

Lighting.ClockTime = 1.5
Lighting.Brightness = 1.4
Lighting.ExposureCompensation = -0.15
Lighting.Ambient = Color3.fromRGB(35, 39, 48)
Lighting.OutdoorAmbient = Color3.fromRGB(18, 21, 29)
Lighting.GlobalShadows = true

local atmosphere = Lighting:FindFirstChild("NocturnaAtmosphere") or Instance.new("Atmosphere")
atmosphere.Name = "NocturnaAtmosphere"
atmosphere.Density = 0.28
atmosphere.Offset = 0.08
atmosphere.Color = Color3.fromRGB(155, 166, 190)
atmosphere.Decay = Color3.fromRGB(38, 43, 58)
atmosphere.Glare = 0.05
atmosphere.Haze = 1.2
atmosphere.Parent = Lighting

local color = Lighting:FindFirstChild("NocturnaColor") or Instance.new("ColorCorrectionEffect")
color.Name = "NocturnaColor"
color.Brightness = -0.04
color.Contrast = 0.16
color.Saturation = -0.22
color.TintColor = Color3.fromRGB(205, 215, 235)
color.Parent = Lighting
